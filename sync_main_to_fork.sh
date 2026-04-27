# 1. Switch to your main branch
git checkout main

# 2. Pull the latest changes from the original source
# Using --rebase ensures a clean, linear history
git pull --rebase upstream main

# 3. Update your GitHub fork so it matches your local main
git push origin main

# To clean that up and make sure your local code actually matches the new main you just pulled, run:
git submodule update --init --recursive