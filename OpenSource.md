# 1. Create the repo on GitHub (visit github.com/new)
#    Name: Tickr
#    Visibility: Public
#    Do NOT add README/license/gitignore (we have them)

# 2. Add remote and push
git remote add origin https://github.com/YOUR_USERNAME/Tickr.git
git push -u origin main

# 3. Update README — replace YOUR_USERNAME with your actual GitHub username
#    in the download badge and release link, then:
git add README.md && git commit -m "Update GitHub username in README" && git push

# 4. Create first release (triggers GitHub Action to build DMG)
git tag v1.0.0
git push origin v1.0.0

# 5. The GitHub Action will:
#    - Build the app
#    - Create Tickr.dmg
#    - Publish it as a GitHub Release
#    - The README download link will work automatically
