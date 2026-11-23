#!/bin/bash
# Playify - Pterodactyl / Pelican auto-updater.
#
# Runs on every server start (before boot.sh). If AUTO_UPDATE=1, it fetches
# GIT_BRANCH from GIT_REPO and hard-resets the code to the latest commit.
# Untracked / git-ignored files (.env, data/, .venv/, bin/, logs/) are never
# touched, so settings, the database and installed packages survive updates.
# Any failure here is non-fatal: the bot simply starts on the current version.

cd /home/container || exit 0

log() { echo -e "\033[1;36m[Playify]\033[0m $*"; }
warn() { echo -e "\033[1;33m[Playify]\033[0m $*"; }

if [[ "${AUTO_UPDATE:-1}" != "1" ]]; then
    log "Auto-update disabled, skipping update check."
    exit 0
fi

if [[ ! -d .git ]]; then
    warn "No git repository found, cannot auto-update. Reinstall the server from the panel to enable updates."
    exit 0
fi

REPO="${GIT_REPO:-https://github.com/landonhalley/playify}"
BRANCH="${GIT_BRANCH:-main}"
[[ "$REPO" != *.git ]] && REPO="${REPO}.git"

# Inject credentials for private forks (never printed).
FETCH_URL="$REPO"
if [[ -n "${GIT_TOKEN:-}" ]]; then
    FETCH_URL="https://${GIT_USERNAME:-git}:${GIT_TOKEN}@${REPO#https://}"
fi

# Keep the stored remote in sync with the panel variable (without the token).
git remote set-url origin "$REPO" 2>/dev/null || git remote add origin "$REPO"

log "Checking ${REPO%.git} (${BRANCH}) for updates..."
if ! git -c credential.helper= fetch --quiet --depth 1 "$FETCH_URL" "$BRANCH" 2>/dev/null; then
    warn "Could not reach the repository. Starting the currently installed version."
    exit 0
fi

LOCAL="$(git rev-parse HEAD 2>/dev/null || echo none)"
REMOTE="$(git rev-parse FETCH_HEAD)"

if [[ "$LOCAL" == "$REMOTE" ]]; then
    log "Already up to date (${LOCAL:0:7})."
    exit 0
fi

log "Update found: ${LOCAL:0:7} -> ${REMOTE:0:7} ($(git log -1 --format=%s FETCH_HEAD 2>/dev/null))"
if git checkout --quiet --force -B "$BRANCH" FETCH_HEAD && git reset --quiet --hard FETCH_HEAD; then
    log "Updated to ${REMOTE:0:7}."
else
    warn "Update failed, starting the currently installed version."
fi
