# ICCM Lock Test Description

## Overview

**Purpose:** Verify that the ICCM (Instruction Closely-Coupled Memory) write-lock mechanism works correctly — once locked, writes to ICCM are blocked and trigger an NMI.

---

## Memory Layout

```
ROM (0x00000000)       - main() runs here initially
ICCM (0x40000000)      - target for code execution
DCCM (0x50020000+)     - staging area for code to be copied
  ├── .data            - normal data
  ├── iccm_code0       - execute_first_pass_from_iccm()  [binary blob]
  ├── iccm_code1       - execute_second_pass_from_iccm() [binary blob]
  └── iccm_code2       - execute_fatal_from_iccm()       [binary blob]
```

The three ICCM functions are compiled into DCCM (as LMA), with VMA at 0x40000000. They are designed to be **copied into ICCM and executed there**.

---

## Test Flow (Two Passes via Core Reset)

### Pass 1

```
main()
  │
  ├─ ICCM_LOCK == 0? ✓ (assert it's not already locked)
  │
  ├─ Copy iccm_code0 (DCCM:50020880) → ICCM (40000000)
  │
  ├─ Execute from ICCM → execute_first_pass_from_iccm()
  │     └─ Increments persistent_exec_cnt (in DCCM, survives reset)
  │     └─ Returns to main()
  │
  ├─ Lock ICCM: write SOC_IFC_INTERNAL_ICCM_LOCK = 1
  │
  ├─ Try to unlock: write ICCM_LOCK = 0  → should FAIL (stays locked)
  │
  ├─ Test DCCM read/write still works while ICCM locked ✓
  │
  ├─ Read back ICCM, compare with iccm_code0 source ✓
  │
  ├─ Copy iccm_code2 (fatal code) → ICCM  ← WRITE TO LOCKED ICCM!
  │     └─ AHB error response → triggers NMI
  │
  └─ NMI handler (execute_first_pass_from_iccm runs as NMI vector)
        └─ persistent_nmi_expected == 1 ✓
        └─ Set persistent_is_second_pass = 1
        └─ Trigger core reset → restart from main()
```

### Pass 2 (after core reset)

```
main()
  │
  ├─ persistent_is_second_pass == 1, so copy iccm_code1 → ICCM
  │
  ├─ Execute from ICCM → execute_second_pass_from_iccm()
  │     └─ Returns to main() (does NOT increment persistent_exec_cnt)
  │
  ├─ Check persistent_exec_cnt <= 1 ✓ (iccm_code0 didn't run again)
  │
  ├─ Lock ICCM again, verify unlock still fails
  │
  ├─ Test DCCM access again
  │
  ├─ Copy iccm_code2 (fatal code) → ICCM ← WRITE TO LOCKED ICCM again!
  │     └─ AHB error → NMI
  │
  └─ NMI handler (execute_second_pass_from_iccm runs as NMI vector)
        └─ persistent_is_second_pass == 1 ✓
        └─ SEND_STDOUT_CTRL(0xff) → TESTCASE PASSED ✓
```

---

## What Each Code Section Tests

| Section | Function | Purpose |
|---------|----------|---------|
| `iccm_code0` | `execute_first_pass_from_iccm` | Normal execution + NMI handler for pass 1 |
| `iccm_code1` | `execute_second_pass_from_iccm` | Normal execution + NMI handler for pass 2 |
| `iccm_code2` | `execute_fatal_from_iccm` | **Should never execute** — used purely to trigger NMI when copied to locked ICCM |

---

## Key Assertions Being Verified

1. **ICCM_LOCK starts clear** on boot
2. **ICCM is writable** before lock
3. **ICCM_LOCK cannot be cleared** by software once set (only reset clears it)
4. **DCCM remains writable** while ICCM is locked (no collateral damage)
5. **Write to locked ICCM generates NMI** (AHB error propagation)
6. **ICCM retains correct content** after locking (reads still work)
7. **Core reset clears ICCM_LOCK** (pass 2 can write ICCM again)
8. **iccm_code0 does not execute during pass 2** (content was overwritten with iccm_code1)

---

## Build Note

The `.data_iccm0/1/2` sections must use `KEEP()` in the linker script
(`src/integration/test_suites/libs/riscv_hw_if/link.ld`) to prevent the
linker's `--gc-sections` from stripping them. These sections are accessed
via function pointers, so the linker cannot trace the references statically.
