# Review Instructions for ICCM Lock Work

To review or test this branch, follow the steps below to pull the code into your local environment.

### 1. Add the Remote Fork
If you haven't already, add my fork as a remote repository:
```bash
git remote add yuvaraj git@github.com:YuvarajP/caliptra-rtl.git
git fetch yuvaraj
```

### 2. Check Out the Branch
Create a local tracking branch from my fork:
```bash
git checkout -b yjpatil/iccm-lock-work yuvaraj/yjpatil/iccm-lock-work
git submodule update --init --recursive
```

### 3. Syncing Latest Changes
I frequently rebase this branch against `upstream/main` to keep the history clean. If I have pushed updates and your local branch has diverged, use these commands to reset to my latest version:
```bash
git fetch yuvaraj
git reset --hard yuvaraj/yjpatil/iccm-lock-work
git submodule update --init --recursive
```

---
**Note:** The `git submodule update` command is critical to ensure the `adams-bridge` and other submodules match the commit pointers in this branch.
