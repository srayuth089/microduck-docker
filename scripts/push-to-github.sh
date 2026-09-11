#!/usr/bin/env bash
# Create the GitHub repo under srayuth089 and push this directory to it.
#
# Run this yourself — it needs `gh` authenticated as the account that should
# OWN the repo. Check with: gh auth status
set -euo pipefail

OWNER="${OWNER:-srayuth089}"
REPO="${REPO:-microduck-docker}"
DESC="🦆 Microduck bipedal robot simulator in one Docker command — MuJoCo physics, pretrained RL policies and a 3D browser viewer. Made for STEM classrooms."

command -v gh >/dev/null || { echo "install gh: https://cli.github.com"; exit 1; }

who=$(gh api user -q .login)
if [ "$who" != "$OWNER" ]; then
  cat <<MSG
gh is authenticated as '$who', but this script targets '$OWNER'.

  gh auth login          # sign in as $OWNER
  gh auth switch --user $OWNER

Or push under the current account:  OWNER=$who $0
MSG
  exit 1
fi

[ -d .git ] || { git init -b main; }
git add -A
git diff --cached --quiet || git commit -m "microduck-docker: one-command Microduck simulator

Packages the Microduck simulator (MuJoCo physics, the official MJCF robot
model, pretrained ONNX policies, the CPU PPO trainer and the 3D browser
viewer) into a single multi-arch image, so a newcomer can watch and teach a
bipedal robot with one docker run and no local toolchain.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"

if gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  echo "▶ repo exists, pushing"
  git remote get-url origin >/dev/null 2>&1 || \
    git remote add origin "https://github.com/$OWNER/$REPO.git"
  git push -u origin main
else
  echo "▶ creating $OWNER/$REPO"
  gh repo create "$OWNER/$REPO" --public --source=. --remote=origin \
     --description "$DESC" --push
fi

gh repo edit "$OWNER/$REPO" --add-topic microduck --add-topic robotics \
  --add-topic docker --add-topic mujoco --add-topic reinforcement-learning \
  --add-topic simulation --add-topic stem-education --add-topic humanoid-robot \
  --add-topic sim2real 2>/dev/null || true

cat <<NEXT

✓ pushed to https://github.com/$OWNER/$REPO

Next, one-time, to enable publishing:
  1. Docker Hub → Account Settings → Personal access tokens → Read & Write
  2. gh secret set DOCKERHUB_TOKEN --repo $OWNER/$REPO
  3. Actions → "build & publish" → Run workflow
NEXT
