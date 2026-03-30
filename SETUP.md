# Reproducing This Environment on a New Machine

## Prerequisites

- Git installed
- SSH key added to your GitHub account (`YuvarajP`)
- `gh` CLI installed and authenticated (`gh auth login`)

## Steps

### 1. Clone your fork

```bash
git clone git@github.com:YuvarajP/caliptra-rtl.git
cd caliptra-rtl
```

### 2. Set up remotes

```bash
# rename origin to myfork (your fork)
git remote rename origin myfork

# add upstream chipsalliance repo as origin
git remote add origin git@github.com:chipsalliance/caliptra-rtl.git
```

Verify:
```bash
git remote -v
# myfork  git@github.com:YuvarajP/caliptra-rtl.git (fetch)
# myfork  git@github.com:YuvarajP/caliptra-rtl.git (push)
# origin  git@github.com:chipsalliance/caliptra-rtl.git (fetch)
# origin  git@github.com:chipsalliance/caliptra-rtl.git (push)
```

### 3. Checkout your work branch

```bash
git checkout yjpatil/iccm-lock-work
```

## Ongoing Workflow

### Push changes to your fork
```bash
git push myfork yjpatil/iccm-lock-work
```

### Sync with upstream
```bash
git fetch origin
git rebase origin/main
git push myfork --force-with-lease
```

### Create a new branch inheriting current work
```bash
git checkout yjpatil/iccm-lock-work
git checkout -b yjpatil/new-feature
```
