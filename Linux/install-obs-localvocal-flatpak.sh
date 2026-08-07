#!/usr/bin/env bash
set -Eeuo pipefail

APP_ID="com.obsproject.Studio"
PLUGIN_ID="com.obsproject.Studio.Plugin.LocalVocal"
REPO_URL="https://github.com/locaal-ai/obs-localvocal.git"
WORKDIR="${WORKDIR:-$HOME/src/obs-localvocal}"
MANIFEST="./flatpak/com.obsproject.Studio.Plugin.LocalVocal.yaml"

log() {
  printf '\n[LocalVocal Installer] %s\n' "$*"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

if [[ "${EUID}" -eq 0 ]]; then
  die "Do not run this script as root. Run it as your normal user; it will use sudo only for APT packages."
fi

trap 'die "Command failed on line $LINENO."' ERR

log "Installing host dependencies with APT..."
sudo apt update
sudo apt install -y flatpak flatpak-builder git ca-certificates curl pciutils

log "Adding Flathub for the current user..."
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak_info_anywhere() {
  local id="$1"
  flatpak info --user "$id" >/dev/null 2>&1 || flatpak info --system "$id" >/dev/null 2>&1
}

log "Checking OBS Flatpak..."
if flatpak_info_anywhere "$APP_ID"; then
  log "OBS Flatpak is already installed."
else
  log "Installing OBS Studio Flatpak for this user..."
  flatpak install -y --user flathub "$APP_ID"
fi

log "Detecting GPU acceleration backend..."
if [[ -z "${ACCELERATION:-}" ]]; then
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    ACCELERATION="nvidia"
  elif lspci | grep -Eiq 'VGA|3D|Display' && lspci | grep -Eiq 'AMD|ATI|Radeon'; then
    ACCELERATION="amd"
  else
    ACCELERATION="generic"
  fi
fi
export ACCELERATION
log "Using ACCELERATION=${ACCELERATION}"

log "Cloning or updating LocalVocal source..."
mkdir -p "$(dirname "$WORKDIR")"

if [[ -d "$WORKDIR/.git" ]]; then
  git -C "$WORKDIR" fetch --all --tags
  git -C "$WORKDIR" pull --ff-only
else
  git clone "$REPO_URL" "$WORKDIR"
fi

cd "$WORKDIR"

if [[ ! -f "$MANIFEST" ]]; then
  die "Flatpak manifest not found at $WORKDIR/$MANIFEST. The project layout may have changed."
fi

log "Installing the SDK and SDK extensions declared by the Flatpak manifest..."

# Keep the installer synchronized with the project manifest.  The SDK is not
# necessarily KDE (and its branch changes over time), so do not hard-code a
# runtime or branch here.
SDK_REF="$(awk '$1 == "sdk:" { print $2; exit }' "$MANIFEST")"
if [[ -z "$SDK_REF" ]]; then
  die "Could not determine the Flatpak SDK from $MANIFEST."
fi

install_flatpak_ref() {
  local ref="$1"
  if flatpak_info_anywhere "$ref"; then
    log "$ref is already installed."
  else
    flatpak install -y --user flathub "$ref"
  fi
}

install_flatpak_ref "$SDK_REF"

# sdk-extensions are listed as YAML items below the sdk-extensions key.
while IFS= read -r extension; do
  [[ -n "$extension" ]] && install_flatpak_ref "${extension}//${SDK_REF##*//}"
done < <(
  awk '
    /^sdk-extensions:/ { in_extensions = 1; next }
    in_extensions && /^[^[:space:]-]/ { in_extensions = 0 }
    in_extensions && /^[[:space:]]*-[[:space:]]*org\./ {
      sub(/^[[:space:]]*-[[:space:]]*/, "")
      print
    }
  ' "$MANIFEST"
)

log "Building and installing LocalVocal Flatpak extension..."
chmod +x ./flatpak/build.sh
if ./flatpak/build.sh --disable-rofiles-fuse --force-clean --install build-dir "$MANIFEST"; then
  log "Installed through LocalVocal build.sh."
else
  log "build.sh install failed; trying user-local flatpak-builder install..."
  flatpak-builder --user --install --force-clean --disable-rofiles-fuse build-dir "$MANIFEST"
fi

log "Verifying installation..."
if flatpak list | grep -i "LocalVocal" >/dev/null 2>&1 || flatpak list | grep -i "$PLUGIN_ID" >/dev/null 2>&1; then
  log "LocalVocal appears in flatpak list."
else
  log "LocalVocal did not appear in flatpak list. It may still be installed as an extension; check OBS filters after restart."
fi

log "Done. Start OBS with:"
echo "flatpak run $APP_ID"

log "In OBS: Audio Mixer → gear on your mic/video source → Filters → + → LocalVocal Transcription."
