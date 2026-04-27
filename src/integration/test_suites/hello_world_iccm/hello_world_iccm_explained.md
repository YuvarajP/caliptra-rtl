# hello_world_iccm — Deep Dive

## Purpose

This test verifies that code can be **copied from DCCM into ICCM** at runtime and then
**executed from ICCM**. The `printf` function has two addresses: it lives in DCCM initially
(LMA — Load Memory Address), but is linked to run at the ICCM base address
(VMA — Virtual Memory Address).

---

## Memory Layout (from `link.ld`)

| Section        | LMA (stored at)             | VMA (runs at)          |
|----------------|-----------------------------|------------------------|
| `.text`        | `0x0`                       | `0x0` (ROM)            |
| `.dccm`        | `0x5002xxxx`                | `0x5002xxxx` (DCCM)    |
| `.data_iccm0`  | right after `.dccm` in DCCM | `0x40000000` (ICCM)    |

The linker script places `.data_iccm0` in DCCM at its LMA, but assigns it a VMA of
`0x40000000` (the ICCM base, `RV_ICCM_SADR`):

```
.data_iccm0 0x40000000 : AT(iccm_code0_start) { KEEP(*(.data_iccm0)) ... }
```

The `printf` function is defined inside `.data_iccm0`, so the linker assigns it the address
`0x40000000`. The test is responsible for copying the code to that address before calling it.

---

## Step-by-step Execution

### 1. Enable caches in MRAC

```asm
li x1, 0xaaaaaaaa
csrw 0x7c0, x1
```

Writes to the **MRAC** (Memory Region Attribute Control) CSR, marking all memory regions as
cacheable.

> **What is a CSR?**
> CSR (Control and Status Register) is a bank of registers built directly into the CPU core.
> They are accessed via dedicated instructions (`csrw`, `csrr`) using a 12-bit address encoded
> in the instruction itself — no memory bus involved. This is different from MMIO (Memory-Mapped
> I/O), which uses regular load/store instructions (`lw`, `sw`, `sb`) that travel over the data
> bus to a specific address in the address space.
>
> | | CSR | MMIO |
> |---|---|---|
> | Access instruction | `csrw`/`csrr` | `lw`/`sw`/`sb` |
> | Where it lives | Inside the CPU | External address space |
> | Goes over data bus | No | Yes |
> | Typical use | CPU control knobs | Peripherals, STDOUT, hardware registers |

---

### 2. Initialize interrupts

```asm
call init_interrupts
```

Sets up the VeeR EL2 interrupt infrastructure:
- Disables global interrupts (`mstatus.MIE`) before touching the PIC
- Sets `mtvec` to the vectored interrupt table with mode=1 (vectored)
- Configures VeeR's PIC (Programmable Interrupt Controller) — priorities, enables, gateway controls
- Enables interrupts for all Caliptra peripherals at the MMIO level
- Re-enables global interrupts

> **Where is `init_interrupts` implemented?**
> It is **not** in the `.s` file and not declared with `.extern`. It is defined in the shared
> library at `libs/caliptra_isr/caliptra_isr.c:166`.
>
> **How does the linker find it?**
> The Makefile (`tools/scripts/Makefile`) checks whether `caliptra_isr.h` exists in the test
> directory. If it does, `caliptra_isr.o` is added to the link step:
> ```makefile
> ifeq (0,$(shell test -e $(TEST_DIR)/caliptra_isr.h && echo $$?))
>     OFILES += caliptra_isr.o
> endif
> ```
> `caliptra_isr.o` is compiled from `libs/caliptra_isr/caliptra_isr.c`, found via `VPATH`.
> So the *presence* of `caliptra_isr.h` in the test directory acts as the signal — not a
> `#include` in the `.s` file.
>
> **What about `.extern`?**
> `.extern` means a symbol is defined in *another source file*, not necessarily the linker
> script. It is optional and informational in most assemblers — the linker resolves any
> undefined symbol the same way regardless. In this file, `.extern` is only used for
> `iccm_code0_start` and `iccm_code0_end`, which happen to be defined in the linker script.
> `init_interrupts` has no `.extern` declaration at all — the assembler just leaves a
> relocation entry for the linker to fill in.

---

### 3. Disable write-back coalescing

```asm
li  x3, 4
csrw mfdc, x3     // mfdc = CSR 0x7f9
```

`li x3, 4` sets bit 2. The RTL (`el2_dec_tlu_ctl.sv`) maps that bit to:
```sv
assign dec_tlu_wb_coalescing_disable = mfdc[2];
```

**What is write-back coalescing?**
VeeR EL2's store buffer can merge consecutive stores to adjacent addresses into a single wider
transaction before committing to memory. For normal RAM this is a performance win, but the ICCM
controller expects individual word-aligned 32-bit writes. If coalescing is enabled, the store
buffer might merge two adjacent `sw` instructions into a 64-bit transaction that the ICCM
controller cannot handle, resulting in corrupted instructions.

Disabling it here ensures each `sw` in the copy loop produces exactly one 32-bit write to ICCM.

---

### 4. Set up copy pointers

```asm
li  x3, RV_ICCM_SADR      // x3 = 0x40000000 — destination (ICCM, where printf will run)
la  x4, iccm_code0_start   // x4 = LMA of printf code, packed right after .dccm in DCCM
la  x5, iccm_code0_end     // x5 = end of source
```

`iccm_code0_start` and `iccm_code0_end` are symbols defined in the linker script that mark
the boundaries of the `.data_iccm0` section's LMA region in DCCM.

---

### 5. Copy `printf` from DCCM to ICCM

```asm
load:
    lw  x6, 0(x4)    // load word from DCCM
    sw  x6, 0(x3)    // store word to ICCM
    addi x4, x4, 4
    addi x3, x3, 4
    bltu x4, x5, load
```

Word-by-word copy of the `printf` function body from its DCCM staging area into ICCM at
`0x40000000`.

---

### 6. Fence and call printf

```asm
fence.i
call printf
```

**`fence.i`** flushes the instruction cache, ensuring the CPU fetches the newly written ICCM
instructions rather than stale cache lines. Without it, the CPU might execute garbage.

**`call printf`** expands to two instructions:
```asm
auipc ra, %pcrel_hi(printf)        // ra = PC + upper bits of offset to 0x40000000
jalr  ra, %pcrel_lo(printf)(ra)    // ra = PC+4 (saved), then PC = 0x40000000
```

The `jalr` instruction does two things simultaneously:
1. Computes the jump target from the current `ra` value
2. Writes `PC+4` (the address of the next instruction, i.e., `_finish`) into `ra`

This is why `ra` ends up pointing to `_finish` after `call printf` fires.

> **Why not just `j 0x40000000`?**
> A plain jump (`j 0x40000000` expands to `jal x0, ...`) discards the return address by
> writing to `x0`. Both land at `0x40000000`, but when `printf` executes `ret` at the end,
> it reads `ra` to determine where to return. With `call`, `ra` = `_finish` so execution
> correctly continues there. With `j`, `ra` still holds the return address from
> `call init_interrupts`, so `ret` jumps back into the middle of the init path and
> `_finish` is never reached — the testbench never sees `0xFF` and simulation hangs.

---

### 7. `printf` executes from ICCM

```asm
printf:               // Running at 0x40000000 in ICCM
    li x3, STDOUT
    la x4, hw_data    // hw_data string lives in .dccm
loop:
    lb x5, 0(x4)
    sb x5, 0(x3)      // write each byte to STDOUT MMIO
    addi x4, x4, 1
    bnez x5, loop     // until null terminator
    ret               // jalr x0, ra, 0  →  jumps to _finish
```

Prints the string byte-by-byte to the STDOUT MMIO register. The string `hw_data` lives in
`.dccm` and is accessed by address — the CPU has no problem reading DCCM data from code
running in ICCM.

---

### 8. Signal test completion

```asm
_finish:
    li x3, STDOUT
    addi x5, x0, 0xff
    sb x5, 0(x3)          // 0xFF on STDOUT tells the testbench to end simulation
    beq x0, x0, _finish   // spin forever
```

Writing `0xFF` to the STDOUT MMIO address is the convention used by the Caliptra testbench
to detect test completion and terminate the simulation.

---

## Build flow summary

```
hello_world_iccm.s
    │
    ├── preprocessed by riscv64-unknown-elf-cpp (expands #include "caliptra_defines.h")
    ├── assembled to hello_world_iccm.o
    │
caliptra_isr.h present in test dir
    │
    └── Makefile adds caliptra_isr.o (from libs/caliptra_isr/caliptra_isr.c)
    │
    ┌─────────────────┐
    │  LINK STEP      │   hello_world_iccm.o + caliptra_isr.o + ...
    │  using link.ld  │   → hello_world_iccm.exe
    └─────────────────┘
    │
    ├── program.hex   (ROM image, .text only, padded to 96KiB)
    └── dccm.hex      (.dccm + .data_iccm0 LMA region, loaded into DCCM at sim start)
```

The testbench preloads `program.hex` into ROM and `dccm.hex` into DCCM before releasing the
CPU from reset. The CPU then runs from ROM, copies `printf` from DCCM into ICCM, and executes it.
