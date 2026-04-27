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

By default, the repository you clone is named `origin`. You only need to add the `upstream` source to track the original project.

```bash
# Add upstream chipsalliance repo
git remote add upstream git@github.com:chipsalliance/caliptra-rtl.git
```

**Verify:**
```bash
git remote -v
# origin    git@github.com:YuvarajP/caliptra-rtl.git (fetch)
# origin    git@github.com:YuvarajP/caliptra-rtl.git (push)
# upstream  git@github.com:chipsalliance/caliptra-rtl.git (fetch)
# upstream  git@github.com:chipsalliance/caliptra-rtl.git (push)
```

### 3. Checkout your work branch

```bash
git checkout yjpatil/iccm-lock-work
# Ensure all submodules are synchronized to this branch's state
git submodule update --init --recursive
```

## Using Automation Scripts

To simplify the sync process, ensure your scripts are executable:
`chmod +x sync_main_to_fork.sh sync_fork_to_branch.sh`

### Sync Fork Main with Upstream
Run this while on the `main` branch to pull the latest from `chipsalliance` into your fork:
```bash
./sync_main_to_fork.sh
```

### Sync Feature Branch with Fork Main
Run this while on your feature branch to rebase your work on top of your latest fork-main:
```bash
./sync_fork_to_branch.sh
```

## Ongoing Manual Workflow

### Push changes to your fork
```bash
git push origin yjpatil/iccm-lock-work
```

### Manual Sync with Upstream
```bash
git fetch upstream
git rebase upstream/main
git submodule update --init --recursive
git push origin yjpatil/iccm-lock-work --force-with-lease
```

### Create a new branch inheriting current work
```bash
git checkout yjpatil/iccm-lock-work
git checkout -b yjpatil/new-feature
```

## Troubleshooting
**Dirty Submodules:** If `git status` shows `modified: submodules/adams-bridge (new commits)` after a pull or checkout, always run:
`git submodule update --init --recursive`
