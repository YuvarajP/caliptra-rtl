#!/bin/bash
set -e # Stop if any command fails

# 1. Sync Main
echo "--- Syncing Main with Upstream ---"
git checkout main
git pull --rebase upstream main
git push origin main

# 2. Sync Feature Branch
echo "--- Syncing Feature Branch with Main ---"
git checkout yjpatil/iccm-lock-work
git rebase main
git submodule update --init --recursive

echo "--- Status ---"
git status
echo "Sync complete! Don't forget to 'git push --force' if needed."
