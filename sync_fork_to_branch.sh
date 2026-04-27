#!/bin/bash

# Optional: Ensure you are on the right branch
git checkout yjpatil/iccm-lock-work

# 1. Fetch latest from your fork
echo "Fetching from origin..."
git fetch origin

# 2. Rebase the current branch on top of your fork's main
echo "Rebasing current branch on origin/main..."
git rebase origin/main

# 3. Clean up submodules to match the new state
echo "Updating submodules..."
git submodule update --init --recursive

echo "Done! Your branch is now synced with your fork's main."

# to commit your changes in the Branch
# git push origin yjpatil/iccm-lock-work --force-with-lease