# Memory Loading in the iccm_lock Test

## Overview of the build outputs

The build produces four `.hex` files, each loaded into a separate memory region by the simulator before the CPU starts:

| File | Loaded into | Contents |
|---|---|---|
| `program.hex` | iMem (`0x0000_0000`) | `.text`, `.eh_frame`, `.data` (LMA), `.bss` (LMA) |
| `dccm.hex` | DCCM (`0x5000_0000`) | `.dccm`, `.data_iccm0/1/2` (staging copies) |
| `iccm.hex` | ICCM (`0x4000_0000`) | `.iccm` (unused in this test) |
| `mailbox.hex` | Mailbox | `.mailbox` (unused in this test) |

---

## LMA vs VMA

**VMA (Virtual Memory Address)** — the address the program uses at runtime. When C code accesses a variable, the CPU uses the VMA.

**LMA (Load Memory Address)** — the address where the data is physically stored in the binary/ROM image at startup.

They differ when data needs to live in writable RAM at runtime but must be stored in non-volatile ROM/flash. Someone has to copy the bytes from LMA → VMA before the program uses them.

In `link.ld`, the `AT(lma)` syntax expresses this:
```ld
_data_vma_start = 0x50020000;
.data _data_vma_start : AT(_data_lma_start) { ... }
```
This tells the linker: store `.data` at `_data_lma_start` in the output file (in iMem), but the program will access it at `0x50020000` (in DCCM) at runtime.

---

## Three memory regions and two copy mechanisms

### What the simulator loads (no CPU involved)

The simulator pre-populates memories from the `.hex` files before the CPU starts executing. The `.data_iccm0/1/2` sections are already in DCCM when the CPU wakes up — the simulator put them there via `dccm.hex`.

### Copy 1 — crt0, before `main()`

`crt0.s` copies `.data` and `.bss` from their **LMA in iMem → VMA in DCCM** (`0x5002_0000`).

```asm
la t0, _data_lma_start   // source: ROM (iMem)
la t1, _data_lma_end
la t2, _data_vma_start   // dest:   0x50020000 in DCCM
data_cp_loop:
    lw t3, 0(t0)
    sw t3, 0(t2)
    addi t0, t0, 4
    addi t2, t2, 4
    bltu t0, t1, data_cp_loop
```

This is standard C runtime init — without it, global/static variables in C would be uninitialized or point at ROM (unwritable). crt0 touches **nothing** related to ICCM.

### Copy 2 — `iccm_lock.c` `main()` (manual)

The test manually copies `.data_iccm0` (or `1`) from **DCCM staging area → ICCM**:

```c
code_word = (uint32_t *) &iccm_code0_start; // already in DCCM via dccm.hex
while (code_word < (uint32_t *) &iccm_code0_end) {
    *iccm_dest++ = *code_word++;            // write into ICCM at 0x4000_0000
}
```

This is the core of the test: writing code into ICCM, locking it, and verifying that subsequent writes trigger an NMI.

---

## Who calls crt0?

Nobody in C code calls crt0. The CPU jumps to it automatically at reset.

- `link.ld` sets `ENTRY(_start)` — the entry point of the ELF binary.
- `crt0.s` places `_start` in `.text.init` at address `0x0`.
- The VeeR EL2 core's reset vector is `0x0`, so the CPU begins executing `_start` on power-on/reset.

### Full boot call chain

```
Hardware reset
  → PC = 0x0
  → _start (crt0.s)              ← CPU wakes up here, no explicit call
      → MRAC / CSR setup
      → iMem (.data LMA) ──copy──▶ DCCM (0x5002_0000)
      → iMem (.bss  LMA) ──copy──▶ DCCM (after .data)
      → set stack pointer (STACK symbol from link.ld)
      → call main()
          → DCCM (.data_iccm0) ──copy──▶ ICCM (0x4000_0000)
          → iccm_fn()   ← jumps into ICCM and executes
```

---

## Full memory journey for `.data_iccm0`

```
Build time:
  iccm_lock.c  →  .data_iccm0 section (VMA=0x4000_0000, LMA=in DCCM)

Simulator loads:
  dccm.hex  ──▶  DCCM (LMA address)    ← .data_iccm0 lands here

CPU (crt0):
  No action on .data_iccm* — crt0 only handles .data/.bss

CPU (main):
  DCCM (iccm_code0_start) ──▶ ICCM (0x4000_0000)   ← manual copy in iccm_lock.c
  iccm_fn()  ← function pointer to 0x4000_0000, executes from ICCM
```
