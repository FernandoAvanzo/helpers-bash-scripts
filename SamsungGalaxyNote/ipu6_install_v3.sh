#!/usr/bin/env bash
set -euo pipefail

# ---- sanity ---------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0)"; exit 1
fi

echo "[1/8] Detecting conflicting DKMS/IPU6 packages..."
CONFLICT_PKGS=()
# Common out-of-tree packages that conflict with in-kernel IPU6 on 6.10+
for p in intel-ipu6-dkms ipu6-dkms libcamhal0 libcamhal-ipu6ep0 libcamhal-ipu6ep1 libcamera-v4l2 libcamera0.5 libspa-0.2-libcamera; do
  dpkg -l "$p" &>/dev/null && CONFLICT_PKGS+=("$p") || true
done

if ((${#CONFLICT_PKGS[@]})); then
  echo "  Found: ${CONFLICT_PKGS[*]}"
  apt-get -y purge "${CONFLICT_PKGS[@]}" || true
else
  echo "  No conflicting packages installed."
fi

echo "[2/8] Disabling suspicious camera-related PPAs (if any)..."
apt-get -y install ppa-purge >/dev/null 2>&1 || true
shopt -s nullglob
for f in /etc/apt/sources.list.d/*.list; do
  lc="$(tr '[:upper:]' '[:lower:]' < "$f")"
  if grep -Eiq '(intel-ipu6|libcamera|pipewire|sav|oem-solutions-group)' <<<"$lc"; then
    echo "  ppa-purge on $(basename "$f") ..."
    # Try ppa-purge if it is a Launchpad PPA; else just disable the file.
    if grep -qi 'launchpad.net' "$f"; then
      # Extract ppa:user/ppa-name form if present
      if grep -Eq 'ppa\.launchpadcontent\.net|launchpad\.net' "$f"; then
        # Best-effort parse; if it fails, fall back to disabling the file
        PPA_HINT="$(awk -F'/' '/^deb/ {for(i=1;i<=NF;i++) if($i ~ /launchpad/||$i ~ /ppa\.launchpadcontent/) print $(i+1)"/"$(i+2)}' "$f" | head -n1)"
        if [[ -n "${PPA_HINT:-}" ]]; then
          ppa-purge -y "ppa:${PPA_HINT}" || true
        fi
      fi
    fi
    # In any case, disable the file to stop the skew.
    sed -i 's/^[[:space:]]*deb/# disabled by fix-ipu6-pop.sh: &/g' "$f" || true
  fi
done
shopt -u nullglob

echo "[3/8] Refreshing APT and fixing broken state..."
apt-get update
apt-get -y -o Dpkg::Options::=--force-confnew --fix-broken install || true
apt-get -y autoremove --purge
apt-get -y autoclean

echo "[4/8] Ensure kernel firmware is current (Meteor Lake IPU6 firmware)..."
apt-get -y install linux-firmware
FW_DIR="/lib/firmware/intel/ipu"
mkdir -p "$FW_DIR"
if [[ ! -e "$FW_DIR/ipu6epmtl_fw.bin" && ! -e "$FW_DIR/ipu6epmtl_fw.bin.zst" ]]; then
  echo "  WARNING: ipu6epmtl_fw.bin is not present after linux-firmware update."
  echo "           On next boot, verify 'sudo dmesg | grep ipu6epmtl' shows firmware loaded."
fi

echo "[5/8] Install libcamera userspace + GStreamer plugin..."
# Use distro packages only to avoid version skew on Jammy/Pop!_OS 22.04
DEBS=(libcamera-tools libcamera-ipa gstreamer1.0-libcamera)
apt-get -y install "${DEBS[@]}"

echo "[6/8] Make sure the in-kernel modules will be used..."
# Unload any leftover OOT modules (ignore errors)
modprobe -r intel_ipu6_psys intel_ipu6_isys intel_ipu6 2>/dev/null || true

# Load in-tree modules (hyphens become underscores in modprobe)
modprobe intel-ipu6 || true
modprobe intel-ipu6-isys || true

echo "[7/8] Diagnostics:"
echo "  - Kernel IPU6 modules:"
lsmod | grep -E 'ipu6' || true
echo "  - Module origin (should be .../kernel/drivers/, NOT .../updates/dkms):"
modinfo intel-ipu6 2>/dev/null | awk -F: '/^filename/ {print $0}'
modinfo intel-ipu6-isys 2>/dev/null | awk -F: '/^filename/ {print $0}'

echo "[8/8] Quick libcamera sanity check:"
if command -v cam >/dev/null 2>&1; then
  cam -l || true
else
  echo "  'cam' tool not in PATH? (It is provided by libcamera-tools.)"
fi

echo
echo "NEXT STEPS:"
echo "  • Reboot now to ensure clean in-kernel IPU6 module load."
echo "  • After reboot, test:"
echo "      cam -l"
echo "      gst-launch-1.0 libcamerasrc ! videoconvert ! autovideosink"
echo
echo "If 'cam -l' shows a camera but apps still can't see it:"
echo "  • Ensure PipeWire + xdg-desktop-portal are present and up-to-date."
echo "    (Pop!_OS usually has them by default.)"
echo
echo "If 'cam -l' shows nothing, your specific sensor may need a newer libcamera IPA file."
echo "  Check /usr/share/libcamera/ipa/ipu6/ for your sensor YAML (e.g. ov02c10/hi556)."
echo
echo "Done."
