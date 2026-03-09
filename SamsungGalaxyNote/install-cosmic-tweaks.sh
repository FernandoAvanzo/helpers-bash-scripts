#!/usr/bin/env bash
set -Eeuo pipefail

APP_ID="dev.edfloreshz.CosmicTweaks"
FLATHUB_NAME="flathub"
FLATHUB_URL="https://flathub.org/repo/flathub.flatpakrepo"

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required but was not found."
  fi
}

install_flatpak() {
  if command -v flatpak >/dev/null 2>&1; then
    log "Flatpak is already installed."
    return 0
  fi

  require_sudo
  log "Flatpak was not found. Installing it with apt..."
  sudo apt update
  sudo apt install -y flatpak
}

ensure_flathub() {
  if flatpak remotes --columns=name | grep -Fxq "$FLATHUB_NAME"; then
    log "Flathub remote is already configured."
    return 0
  fi

  log "Adding Flathub remote for the current user..."
  flatpak remote-add --if-not-exists --user "$FLATHUB_NAME" "$FLATHUB_URL"
}

install_cosmic_tweaks() {
  if flatpak info --user "$APP_ID" >/dev/null 2>&1 || flatpak info "$APP_ID" >/dev/null 2>&1; then
    log "COSMIC Tweaks is already installed."
    return 0
  fi

  log "Installing COSMIC Tweaks from Flathub..."
  flatpak install -y --user "$FLATHUB_NAME" "$APP_ID"
}

desktop_hint() {
  cat <<'EOF'

Done.

You can now open COSMIC Tweaks in one of these ways:
  1. Press the Super key and search for: Tweaks
  2. Run in a terminal:
       flatpak run dev.edfloreshz.CosmicTweaks

Suggested next steps inside COSMIC Tweaks:
  - Panel / Dock: adjust position, transparency, spacing, and behavior
  - Color schemes: save or import themes
  - Layout presets / snapshots: try alternative desktop layouts safely

If you want to remove it later:
  flatpak uninstall dev.edfloreshz.CosmicTweaks
EOF
}

main() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    warn "Running as root is not required. The app will be installed for the root user if you continue."
    warn "It is usually better to run this script as your normal desktop user."
  fi

  if command -v hostnamectl >/dev/null 2>&1; then
    if hostnamectl 2>/dev/null | grep -Fq "Pop!_OS"; then
      log "Pop!_OS detected."
    else
      warn "This does not look like Pop!_OS. The script may still work on other Linux systems with Flatpak."
    fi
  fi

  install_flatpak
  ensure_flathub
  install_cosmic_tweaks
  desktop_hint
}

main "$@"
