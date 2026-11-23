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
REQ_SHA="$(sha256sum requirements.txt | cut -d' ' -f1)"
if [[ "${ALWAYS_UPGRADE_PACKAGES:-1}" == "1" ]]; then
    log "Installing / upgrading Python dependencies..."
    "$VENV/bin/pip" install -q --upgrade pip wheel
    "$VENV/bin/pip" install -q --upgrade -r requirements.txt || { err "pip install failed."; exit 1; }
    echo "$REQ_SHA" > "$VENV/.requirements.sha"
elif [[ "$(cat "$VENV/.requirements.sha" 2>/dev/null)" != "$REQ_SHA" ]]; then
    log "requirements.txt changed, installing Python dependencies..."
    "$VENV/bin/pip" install -q --upgrade pip wheel
    "$VENV/bin/pip" install -q -r requirements.txt || { err "pip install failed."; exit 1; }
    echo "$REQ_SHA" > "$VENV/.requirements.sha"
else
    log "Python dependencies are up to date."
fi

# --- 4. Launch ---------------------------------------------------------------
mkdir -p data
log "Version: $(git rev-parse --short HEAD 2>/dev/null || echo unknown) | Python ${PY_VER} | $(ffmpeg -version 2>/dev/null | head -n1 || echo 'ffmpeg missing')"
log "Starting bot..."
exec "$VENV/bin/python" playify.py
