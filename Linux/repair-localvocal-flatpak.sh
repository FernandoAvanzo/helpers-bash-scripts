#!/usr/bin/env bash
set -Eeuo pipefail

echo "[1/6] Closing OBS..."
flatpak kill com.obsproject.Studio 2>/dev/null || true
pkill -f obs 2>/dev/null || true

echo "[2/6] Installing required tools..."
sudo apt update
sudo apt install -y flatpak flatpak-builder git ca-certificates

echo "[3/6] Ensuring OBS Flatpak is installed for this user..."
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y --user flathub com.obsproject.Studio
flatpak install -y --user flathub org.kde.Sdk//6.8

echo "[4/6] Getting LocalVocal source..."
mkdir -p "$HOME/src"
if [[ -d "$HOME/src/obs-localvocal/.git" ]]; then
  git -C "$HOME/src/obs-localvocal" pull --ff-only || true
else
  git clone https://github.com/locaal-ai/obs-localvocal.git "$HOME/src/obs-localvocal"
fi

cd "$HOME/src/obs-localvocal"

echo "[5/6] Reinstalling LocalVocal as a user Flatpak extension..."
export ACCELERATION=generic
flatpak-builder \
  --user \
  --install \
  --force-clean \
  build-dir \
  ./flatpak/com.obsproject.Studio.Plugin.LocalVocal.yaml

echo "[6/6] Checking extension visibility inside OBS sandbox..."
flatpak list --columns=application,branch,installation | grep -Ei 'obsproject|localvocal|kde' || true

echo
echo "Plugin files visible inside OBS sandbox:"
flatpak run --command=sh com.obsproject.Studio -c \
  'find /app/plugins -maxdepth 6 \( -iname "*local*" -o -iname "*vocal*" \) -print' || true

echo
echo "Now start OBS with:"
echo "flatpak run com.obsproject.Studio"
