#!/usr/bin/env bash
# fix-ipu6-webcam.sh — Pop!_OS/Ubuntu IPU6 (Meteor Lake) webcam quick-fix
# - Installs/updates firmware for intel/ipu/ipu6epmtl_fw.bin
# - Adds the blob from Intel's repo if the package lacks it
# - Reloads the IPU6 driver (or asks to reboot)
# - Installs libcamera/PipeWire integration

set -euo pipefail

need_root() { [ "$EUID" -eq 0 ] || { echo "Please run as root: sudo $0"; exit 1; }; }
have() { command -v "$1" >/dev/null 2>&1; }

FW_REL_PATH="intel/ipu/ipu6epmtl_fw.bin"
FW_CANDIDATES=( "/lib/firmware/$FW_REL_PATH" "/usr/lib/firmware/$FW_REL_PATH" )
FW_URL="https://raw.githubusercontent.com/intel/ipu6-camera-bins/main/lib/firmware/${FW_REL_PATH}"
DISTRO_ID=$( . /etc/os-release; echo "${ID:-unknown}" )
DISTRO_VER=$( . /etc/os-release; echo "${VERSION_ID:-unknown}" )

need_root

echo "[i] Distro: $DISTRO_ID $DISTRO_VER"
if have apt; then
  echo "[i] Updating linux-firmware…"
  apt-get update -y
  apt-get install -y linux-firmware
else
  echo "[!] apt not found; this helper targets Pop!/Ubuntu. Continuing anyway…"
fi

have_fw() {
  for p in "${FW_CANDIDATES[@]}"; do [ -f "$p" ] && return 0; done
  return 1
}

if ! have_fw; then
  echo "[!] ${FW_REL_PATH} not found via package; fetching from Intel repo…"
  install -d /lib/firmware/intel/ipu
  if ! have wget; then apt-get install -y wget || true; fi
  wget -O "/lib/firmware/${FW_REL_PATH}" "${FW_URL}"
fi

echo "[i] Verifying firmware presence:"
for p in "${FW_CANDIDATES[@]}"; do [ -f "$p" ] && echo "  - OK: $p"; done

# Userspace bits (libcamera + PipeWire)
if have apt; then
  echo "[i] Installing libcamera/PipeWire pieces…"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    libcamera0 libcamera-tools libspa-0.2-libcamera pipewire wireplumber \
    xdg-desktop-portal xdg-desktop-portal-gtk || true
fi

# Refresh initramfs (harmless) and try to reload the driver
if have update-initramfs; then
  echo "[i] Updating initramfs (harmless, can be skipped)…"
  update-initramfs -u
fi

echo "[i] Reloading IPU6 driver if possible…"
modprobe -r intel-ipu6 2>/dev/null || true
if ! modprobe intel-ipu6 2>/dev/null; then
  echo "[!] Could not reload intel-ipu6 (it might be busy). A reboot is recommended."
fi

echo "[✓] Done. If the camera still doesn’t show up, reboot, then run:"
echo "    cam --list   # from libcamera-tools"
echo "    gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert ! autovideosink   # from gstreamer1.0-plugins-base"
