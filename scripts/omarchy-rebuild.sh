#!/usr/bin/env bash
# Rebuild and reinstall Orcachy (Son's Orca fork) on this omarchy host.
#
# Scope: install deps + build the unpacked Linux app (--dir only — no AppImage/
# deb/rpm matrix, so a rebuild after a theme/UI change is minutes, not the full
# release build) + reinstall it under the names the app launcher and shell
# already expect (orca.desktop, ~/.local/bin/orca-ide).
#
# Does NOT touch:
#   - ~/.config/orca (phone pairing, relay keys, projects)
#   - app source (that is builder's lane)
#   - upstream (stablyai/orca); pulling upstream stays a manual `git fetch
#     upstream` + merge/rebase decision, never automated here.
#
# Env flags baked in on purpose (see config/electron-builder.config.cjs for why):
#   ORCA_LOCAL_SKIP_GLIBC_FLOOR=1   this host's glibc (2.44) is newer than the
#                                   upstream Ubuntu-20.04 redistribution floor;
#                                   irrelevant for a single-host local install.
#   ORCA_LOCAL_SKIP_AUTO_UPDATE=1   drop the `publish` block so electron-builder
#                                   never writes resources/app-update.yml --
#                                   the fork must not auto-update itself from
#                                   stablyai/orca's GitHub releases.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

INSTALL_DIR="$HOME/.local/share/orcachy"
DESKTOP_FILE="$HOME/.local/share/applications/orca.desktop"
ICON_PATH="$HOME/.local/share/icons/orca-ide.png"
CLI_LINK="$HOME/.local/bin/orca-ide"

log() { printf '[omarchy-rebuild] %s\n' "$1"; }

START_TS=$(date +%s)

log "pnpm install (root)"
mise exec -- pnpm install

if [ ! -d mobile/node_modules ]; then
  log "pnpm install (mobile workspace — first run only)"
  (cd mobile && mise exec -- pnpm install)
fi

log "building unpacked Linux app (build:unpack, no AppImage/deb/rpm)"
ORCA_LOCAL_SKIP_GLIBC_FLOOR=1 ORCA_LOCAL_SKIP_AUTO_UPDATE=1 \
  mise exec -- pnpm run build:unpack

if [ ! -x dist/linux-unpacked/orca-ide ]; then
  echo "[omarchy-rebuild] build failed: dist/linux-unpacked/orca-ide missing" >&2
  exit 1
fi

VERSION=$(dist/linux-unpacked/orca-ide --version 2>&1 | tail -1)
log "built version: $VERSION"

log "stopping any running Orcachy instance"
pkill -f "$INSTALL_DIR/orca-ide" 2>/dev/null || true
sleep 1

log "installing to $INSTALL_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$(dirname "$INSTALL_DIR")"
cp -a dist/linux-unpacked "$INSTALL_DIR"

mkdir -p "$(dirname "$CLI_LINK")"
ln -sf "$INSTALL_DIR/orca-ide" "$CLI_LINK"

mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Orcachy
Comment=Orcachy (Son's Orca fork)
Exec=$INSTALL_DIR/orca-ide %U
Icon=$ICON_PATH
Terminal=false
Categories=Development;
StartupWMClass=orca-ide
MimeType=x-scheme-handler/orca;
EOF

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))
log "done in ${ELAPSED}s. Installed: $INSTALL_DIR, launcher: $DESKTOP_FILE, CLI: $CLI_LINK"
log "orca-ide --version -> $VERSION"
