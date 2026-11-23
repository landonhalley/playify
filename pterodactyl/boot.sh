#!/bin/bash
# Playify - Pterodactyl / Pelican boot script.
#
# Run by the egg's startup command *after* the git auto-update step, so the
# freshly pulled version of this script is always the one that executes.
# Responsibilities: make sure FFmpeg is available, keep the Python virtualenv
# and dependencies in sync with requirements.txt, then launch the bot.

set -uo pipefail
cd /home/container || exit 1

export PYTHONUNBUFFERED=1
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1

log() { echo -e "\033[1;36m[Playify]\033[0m $*"; }
err() { echo -e "\033[1;31m[Playify]\033[0m $*" >&2; }

# --- 1. Basic configuration check -------------------------------------------
if [[ -z "${DISCORD_TOKEN:-}" ]]; then
    err "DISCORD_TOKEN is empty. Set it in the panel under Startup -> Discord Bot Token."
    exit 1
fi

# --- 2. FFmpeg ----------------------------------------------------------------
# Most Python yolk images ship ffmpeg. If the selected image does not, download
# a static build into ./bin once and put it on PATH.
mkdir -p bin
export PATH="/home/container/bin:${PATH}"
if ! command -v ffmpeg >/dev/null 2>&1; then
    case "$(uname -m)" in
        x86_64)  FF_ARCH="amd64" ;;
        aarch64) FF_ARCH="arm64" ;;
        *)       FF_ARCH="" ;;
    esac
    if [[ -n "$FF_ARCH" ]]; then
        log "FFmpeg not found in image, downloading a static build (${FF_ARCH})..."
        tmp="$(mktemp -d)"
        if curl -fsSL "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${FF_ARCH}-static.tar.xz" -o "$tmp/ffmpeg.tar.xz" \
            && tar -xJf "$tmp/ffmpeg.tar.xz" -C "$tmp"; then
            cp "$tmp"/ffmpeg-*-static/ffmpeg "$tmp"/ffmpeg-*-static/ffprobe bin/ && chmod +x bin/ffmpeg bin/ffprobe
            log "FFmpeg installed to ./bin"
        else
            err "Could not download FFmpeg. Playback will fail until ffmpeg is available."
        fi
        rm -rf "$tmp"
    else
        err "FFmpeg not found and no static build is available for $(uname -m)."
    fi
fi

# --- 3. Python virtualenv + dependencies -------------------------------------
PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')"
VENV=".venv"

# Rebuild the venv if it is missing/broken or the Docker image's Python changed.
if [[ ! -x "$VENV/bin/python" ]] || [[ "$(cat "$VENV/.python-version" 2>/dev/null)" != "$PY_VER" ]]; then
    log "Creating Python ${PY_VER} virtual environment..."
    rm -rf "$VENV"
    python3 -m venv "$VENV" || { err "Failed to create virtualenv."; exit 1; }
    echo "$PY_VER" > "$VENV/.python-version"
    rm -f "$VENV/.requirements.sha"
fi

# Only reinstall when requirements.txt changed (keeps boots fast), unless the
# admin asked for packages to always be upgraded (picks up yt-dlp fixes).
# Downloads are retried generously because some hosts have flaky connections.
PIP_OPTS=(-q --retries 5 --timeout 30)
if "$VENV/bin/pip" install --help 2>/dev/null | grep -q -- "--resume-retries"; then
    PIP_OPTS+=(--resume-retries 20)
fi

pip_install() {
    local attempt
    for attempt in 1 2; do
        "$VENV/bin/pip" install "${PIP_OPTS[@]}" "$@" && return 0
        if [[ "$attempt" -lt 2 ]]; then
            err "pip install failed (attempt ${attempt}/2), retrying in 5s..."
            sleep 5
        fi
    done
    return 1
}

REQ_SHA="$(sha256sum requirements.txt | cut -d' ' -f1)"
INSTALLED_SHA="$(cat "$VENV/.requirements.sha" 2>/dev/null)"

if [[ "${ALWAYS_UPGRADE_PACKAGES:-1}" == "1" || "$INSTALLED_SHA" != "$REQ_SHA" ]]; then
    log "Installing / upgrading Python dependencies..."
    pip_install --upgrade pip wheel || true
    if pip_install --upgrade -r requirements.txt; then
        echo "$REQ_SHA" > "$VENV/.requirements.sha"
    elif [[ -n "$INSTALLED_SHA" ]]; then
        # A previous install worked: start on the packages we already have
        # rather than taking the bot offline over a network hiccup.
        err "Could not upgrade dependencies (network issue?). Starting with the currently installed packages."
    else
        err "Could not install dependencies and none are installed yet. Check the server's network and restart."
        exit 1
    fi
else
    log "Python dependencies are up to date."
fi

# --- 4. Launch ---------------------------------------------------------------
mkdir -p data
log "Version: $(git rev-parse --short HEAD 2>/dev/null || echo unknown) | Python ${PY_VER} | $(ffmpeg -version 2>/dev/null | head -n1 || echo 'ffmpeg missing')"
log "Starting bot..."
exec "$VENV/bin/python" playify.py
