#!/bin/bash
# Playify - Pterodactyl / Pelican installation script.
# Runs once inside the installer container (as root) with the server's files
# mounted at /mnt/server. Python dependencies are installed on first boot by
# pterodactyl/boot.sh, using the Python version of the selected Docker image.

set -e

apt-get update -qq
apt-get install -y -qq --no-install-recommends git ca-certificates curl > /dev/null

mkdir -p /mnt/server
cd /mnt/server

REPO="${GIT_REPO:-https://github.com/landonhalley/playify}"
BRANCH="${GIT_BRANCH:-main}"
[[ "$REPO" != *.git ]] && REPO="${REPO}.git"

CLONE_URL="$REPO"
if [[ -n "${GIT_TOKEN:-}" ]]; then
    CLONE_URL="https://${GIT_USERNAME:-git}:${GIT_TOKEN}@${REPO#https://}"
fi

echo "Installing Playify from ${REPO%.git} (branch: ${BRANCH})"

if [[ -d .git ]]; then
    echo "Existing installation found, updating it in place..."
    git remote set-url origin "$REPO"
    git -c credential.helper= fetch --depth 1 "$CLONE_URL" "$BRANCH"
    git checkout --force -B "$BRANCH" FETCH_HEAD
    git reset --hard FETCH_HEAD
else
    # Clone into a temp dir and copy over, so a reinstall onto a non-empty
    # server keeps user files such as .env and data/.
    TMP="$(mktemp -d)"
    git -c credential.helper= clone --depth 1 --branch "$BRANCH" "$CLONE_URL" "$TMP/playify"
    git -C "$TMP/playify" remote set-url origin "$REPO"
    cp -a "$TMP/playify/." /mnt/server/
    rm -rf "$TMP"
fi

mkdir -p data bin
chmod +x pterodactyl/*.sh 2>/dev/null || true

echo "Playify installed at commit $(git rev-parse --short HEAD)."
echo "Set your Discord token under Startup and start the server."
