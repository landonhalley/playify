# Playify on Pterodactyl / Pelican

This folder contains an egg that installs Playify on a [Pterodactyl](https://pterodactyl.io) or [Pelican](https://pelican.dev) panel and keeps it up to date automatically.

| File | Purpose |
| :--- | :--- |
| `egg-playify.json` | The egg. Import this into your panel. |
| `install.sh` | Installation script (also embedded in the egg). Clones the repository into the server. |
| `update.sh` | Runs on every start. Pulls the latest commit from the configured repository/branch. |
| `boot.sh` | Runs after the update. Checks FFmpeg, sets up the Python virtualenv and dependencies, then starts the bot. |

## Import the egg

**Pelican:** Admin → Eggs → Import → upload `egg-playify.json` (or paste its raw URL: `https://raw.githubusercontent.com/landonhalley/playify/main/pterodactyl/egg-playify.json`).

**Pterodactyl:** Admin → Nests → pick (or create) a nest such as "Discord Bots" → Import Egg → upload `egg-playify.json`.

## Create the server

1. Create a new server with the **Playify** egg. The bot needs no port, but the panel requires an allocation, so give it any free one.
2. Fill in **Discord Bot Token** (required). Spotify and Genius keys are optional.
3. Recommended resources: 512 MB+ RAM, 2 GB+ disk.
4. Wait for the installation to finish, then press **Start**. The first start takes a minute or two while Python packages are installed. The panel shows the server as running once the bot logs `... is online.`

## Startup variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DISCORD_TOKEN` | *(empty)* | Your bot token. Required. |
| `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET` | *(empty)* | Optional Spotify API credentials. |
| `GENIUS_TOKEN` | *(empty)* | Optional Genius token for lyrics. |
| `AUTO_UPDATE` | `1` | Pull the latest version on every start. Set to `0` to stay on the installed version. |
| `ALWAYS_UPGRADE_PACKAGES` | `1` | Upgrade Python packages (yt-dlp, etc.) on every start. Set to `0` for faster boots; packages are then only installed when `requirements.txt` changes. |
| `GIT_REPO` | `https://github.com/landonhalley/playify` | Repository to install and update from (admin only). |
| `GIT_BRANCH` | `main` | Branch to track (admin only). |
| `GIT_USERNAME` / `GIT_TOKEN` | *(empty)* | Only needed for a private repository (admin only). |

## How updates work

On every start, `update.sh` fetches `GIT_BRANCH` from `GIT_REPO`. If there is a newer commit, the code is reset to it; otherwise the bot starts as is. If GitHub can't be reached, the bot starts on the version it already has.

Only files tracked by git get replaced. Your `.env`, `data/` (database, settings), `.venv/`, `bin/` and `logs/` are never touched. **Changes you make to tracked files (e.g. editing source code in the file manager) are overwritten on the next start.** To keep local changes, set `AUTO_UPDATE` to `0`.

To update right away, restart the server.

## Notes

* The panel runs the bot directly (`playify.py`), not the interactive TUI dashboard. Use the panel console and file manager instead.
* FFmpeg comes with the `parkervcp/yolks` Python images. If you use an image without it, `boot.sh` downloads a static build into `bin/`.
* If you switch the Docker image to a different Python version, the virtualenv is rebuilt automatically on the next start.
* `install.sh` is embedded in `egg-playify.json`. If you edit it, update the egg's `scripts.installation.script` too (or re-import the egg).
