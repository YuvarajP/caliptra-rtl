# RISC-V Test Case with Custom Code in Different Memory Locations

## Step 1 — Write the test in C, place functions in specific sections

Use GCC section attributes to place functions into custom linker sections:

```c
// iccm_lock.c lines 47-49
void execute_first_pass_from_iccm  (void) __attribute__ ((aligned(4), section(".data_iccm0")));
void execute_second_pass_from_iccm (void) __attribute__ ((aligned(4), section(".data_iccm1")));
void execute_fatal_from_iccm       (void) __attribute__ ((aligned(4), section(".data_iccm2")));
```

## Step 2 — Call a function at a fixed memory address via function pointer

To call code that will be loaded at a known hardware address (e.g. ICCM base):

```c
// iccm_lock.c lines 55, 63, 111
uint32_t * ICCM      = (uint32_t *) RV_ICCM_SADR;   // 0x4000_0000
void (* iccm_fn)(void) = (void*) ICCM;
iccm_fn();                                            // jumps to 0x4000_0000
```

This only works after the code has been manually copied into ICCM (see Step 7).

## Step 3 — Define the memory layout in a custom linker script

`link.ld` controls where each section is placed:

- `.text` at `0x0` (iMem) — main program code, including `crt0`
- `.data` / `.bss` — stored in iMem (LMA), copied to DCCM `0x5002_0000` at runtime (VMA)
- `.data_iccm0/1/2` — stored in DCCM (LMA), intended to run from ICCM `0x4000_0000` (VMA)
- `.dccm` — lives directly in DCCM, VMA == LMA
- `STACK` — at the end of DCCM

LMA (Load Memory Address) = where the binary stores the data.
VMA (Virtual Memory Address) = where the CPU accesses it at runtime.

Reference: `src/integration/test_suites/libs/riscv_hw_if/link.ld`

## Step 4 — Compile and link with riscv-gcc

```bash
# build_commands.log line 1-5
riscv64-unknown-elf-gcc -mabi=ilp32 -march=rv32imc_zicsr_zifencei \
    -T link.ld -nostartfiles \
    -o iccm_lock.exe crt0.o iccm_lock.o caliptra_isr.o ...
```

All object files (including `crt0.o`) are linked into a single ELF binary `iccm_lock.exe`.
`crt0.o` is compiled from `crt0.s` and its `.text.init` section lands at address `0x0`.

## Step 5 — Extract per-region hex files with objcopy

```bash
# build_commands.log lines 6-16
objcopy -O verilog ... iccm_lock.exe program.hex   # iMem: .text (includes crt0), .data LMA, .bss LMA
objcopy -O verilog ... iccm_lock.exe dccm.hex      # DCCM: .dccm, .data_iccm0/1/2 staging copies
objcopy -O verilog ... iccm_lock.exe iccm.hex      # ICCM: .iccm (unused in this test)
objcopy -O verilog ... iccm_lock.exe mailbox.hex   # Mailbox: .mailbox
```

Each hex file covers exactly one memory region.

## Step 6 — Simulator preloads hex files into memory (readmemh)

Before releasing CPU reset, the SystemVerilog testbench loads each hex file:

```systemverilog
// caliptra_top_tb_services.sv lines 2646-2652
$readmemh("program.hex", imem_inst1.ram, ...);          // crt0 + .text → iMem at 0x0
$readmemh("dccm.hex",    dummy_dccm_preloader.ram, ...); // .data_iccm* staging → DCCM
$readmemh("iccm.hex",    dummy_iccm_preloader.ram, ...); // ICCM (empty here)
$readmemh("mailbox.hex", dummy_mbox_preloader.ram, ...); // Mailbox
```

No CPU involvement — the simulator writes directly into the memory models.

## Step 7 — CPU reset: crt0 runs at PC=0x0 before main()

On reset the CPU PC = `0x0`, which is `_start` in `crt0.s`:

```
_start (crt0.s):
  1. CSR / MRAC setup
  2. Copy .data  from iMem (LMA) → DCCM 0x5002_0000 (VMA)   [crt0.s lines 60-70]
  3. Copy .bss   from iMem (LMA) → DCCM (after .data)        [crt0.s lines 72-83]
  4. Set stack pointer (STACK symbol from link.ld)            [crt0.s line 87]
  5. call main()                                              [crt0.s line 89]
```

Reference: `src/integration/test_suites/libs/riscv_hw_if/crt0.s`

## Step 8 — main() manually copies code section from DCCM to ICCM

The `.data_iccm*` sections are already in DCCM (loaded by the simulator in Step 6).
`main()` copies them into ICCM before executing via the function pointer:

```c
// iccm_lock.c lines 96-101
code_word = (uint32_t *) &iccm_code0_start;  // source: DCCM staging area
while (code_word < (uint32_t *) &iccm_code0_end) {
    *iccm_dest++ = *code_word++;             // dest: ICCM at 0x4000_0000
}
iccm_fn();  // now safe to jump to 0x4000_0000
```

## Full memory journey summary

```
Build:
  crt0.s + iccm_lock.c  →  iccm_lock.exe  →  program.hex, dccm.hex, iccm.hex, mailbox.hex

Simulator (before reset):
  program.hex  →  iMem  (0x0000_0000)   crt0 + .text + .data LMA + .bss LMA
  dccm.hex     →  DCCM  (0x5000_0000)   .dccm + .data_iccm0/1/2 staging

CPU reset → PC = 0x0:
  crt0: iMem (.data LMA)   ──copy──▶  DCCM (0x5002_0000)
  crt0: iMem (.bss  LMA)   ──copy──▶  DCCM (after .data)
  crt0: call main()

main():
  DCCM (.data_iccm0)  ──copy──▶  ICCM (0x4000_0000)
  iccm_fn()  →  executes from ICCM
```


  So there are three categories of tests:

  1. Tests with NO custom .ld (e.g. smoke_test_sha256, fw_test_lms*)

  Use the shared link.ld from libs/riscv_hw_if/. These tests are simple — all code runs from iMem, data goes to DCCM 0x5002_0000. No ICCM usage.

  2. Tests with a custom .ld (e.g. smoke_test_ras, iccm_lock)

  Same structure as the shared link.ld but with tweaks — e.g. smoke_test_ras.ld uses DCCM 0x5001_0000 instead of 0x5002_0000, or places all .rodata into .dccm directly instead of
  .data.

  3. FMC/RT tests (e.g. caliptra_fmc.ld, caliptra_rt.ld)

  Completely different layout — .text is placed in ICCM directly (VMA=LMA=0x4000_0000), not in iMem. These represent real firmware that ROM loads into ICCM before handing off control.

  ---
  Key distinction from iccm_lock

  In iccm_lock, code is placed in .data_iccm* sections and manually copied to ICCM at runtime by the test itself (to test the locking mechanism). In FMC/RT tests, .text is placed
  directly at ICCM VMA and loaded there by ROM as part of normal boot flow — no manual copy needed.