#!/usr/bin/env bash
set -euo pipefail

log() { printf "[ipu6_install_v7] %s\n" "$*"; }
die() { printf "[ipu6_install_v7] ERROR: %s\n" "$*" >&2; exit 1; }

require() {
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "Missing tool: $c"; done
}

require sudo apt awk sed grep cut sort uname dpkg apt-cache modinfo

log "Preflight..."
if ! grep -qs 'Ubuntu 22.04\|Pop!_OS 22.04' /etc/os-release; then
  die "This script targets Ubuntu/Pop!_OS 22.04 (Jammy)."
fi

log "Refreshing apt metadata..."
sudo apt-get update -y

log "Installing HWE kernel + IPU6 + USBIO metas (safe for NVIDIA via DKMS)..."
# These are the supported, per-kernel module metas on Jammy.
sudo apt-get install -y \
  linux-generic-hwe-22.04 \
  linux-modules-ipu6-generic-hwe-22.04 \
  linux-modules-usbio-generic-hwe-22.04 \
  v4l-utils libcamera-tools || die "apt install failed"

# Figure out exactly which HWE kernel image we just installed.
# We ask apt which real image 'linux-image-generic-hwe-22.04' depends on, then strip the prefix.
HWE_IMAGE_PKG="$(apt-cache depends linux-image-generic-hwe-22.04 | awk '/Depends: linux-image-[0-9]/{print $2}' | tail -n1 || true)"
[ -n "$HWE_IMAGE_PKG" ] || die "Could not resolve HWE image pkg via apt-cache."
HWE_KVER="${HWE_IMAGE_PKG#linux-image-}"

log "HWE kernel detected via meta: $HWE_KVER"

# Quick sanity: do the IPU6 & IVSC modules exist for that kernel?
if ! modinfo -k "$HWE_KVER" intel_ipu6_psys >/dev/null 2>&1; then
  log "WARN: intel_ipu6_psys not found for $HWE_KVER (module index not updated yet?). Running depmod..."
  sudo depmod -a "$HWE_KVER" || true
fi
if ! modinfo -k "$HWE_KVER" intel_ipu6_psys >/dev/null 2>&1; then
  log "WARN: intel_ipu6_psys still not found for $HWE_KVER. It will typically appear after reboot into $HWE_KVER."
else
  log "Found intel_ipu6_psys for $HWE_KVER."
fi

# IVSC / USBIO stack (module names differ by kernel generation; check common ones)
if modinfo -k "$HWE_KVER" ivsc >/dev/null 2>&1; then
  log "Found ivsc for $HWE_KVER."
else
  log "NOTE: 'ivsc' module not present in modinfo yet (OK if using updated USBIO stack)."
fi

# NVIDIA sanity (optional): check if the newly installed kernel has nvidia modules built by DKMS
if modinfo -k "$HWE_KVER" nvidia >/dev/null 2>&1; then
  log "NVIDIA DKMS present for $HWE_KVER."
else
  log "NOTE: NVIDIA DKMS module not found *yet* for $HWE_KVER. Usually DKMS builds during install; if not, it will build on next boot."
fi

cat <<EOF

[ipu6_install_v7] Done installing kernel + IPU6/USBIO bits.

Next steps:
  1) Reboot the system. It may boot the newest kernel ($HWE_KVER) by default.
     (Pop!_OS/systemd-boot users can select an older entry at boot if desired.)
  2) After booting into $HWE_KVER, verify the drivers loaded:
       dmesg | egrep -i 'ipu6|ivsc'
       lsmod | egrep 'intel_ipu6|ivsc'
       v4l2-ctl --list-devices
  3) Test capture:
       libcamera-hello   # or:
       gst-launch-1.0 libcamerasrc ! videoconvert ! autovideosink
  4) If the camera still isn't detected, ensure Secure Boot is off and retry.

This script does NOT force a new default kernel; it only installs the HWE stack.
Your NVIDIA driver is preserved via DKMS.

EOF
