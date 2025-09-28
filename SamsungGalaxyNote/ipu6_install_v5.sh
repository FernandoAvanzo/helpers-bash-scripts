#!/usr/bin/env bash
set -euo pipefail

ME="$(basename "$0")"
USER_NAME="${SUDO_USER:-$USER}"
KVER="$(uname -r)"
DKMS_UPDATES_DIR="/lib/modules/${KVER}/updates/dkms"
BACKUP_DIR="/var/backups/ipu6-dkms-backup-$(date +%Y%m%d-%H%M%S)"
EXTRA_DIR="/lib/modules/${KVER}/extra"
LOG(){ echo -e "[$ME] $*"; }

require_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

LOG "Preflight checks..."
require_cmd apt
require_cmd modprobe
require_cmd tee
require_cmd sed
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root."; exit 1; }

# 0) Make sure firmware & headers are present
LOG "Ensuring firmware and headers are installed..."
apt-get update -y
apt-get install -y linux-firmware linux-headers-"${KVER}" build-essential git pkg-config \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad

# 1) Remove/neutralize out-of-tree IPU6/IVSC DKMS stacks
LOG "Purging likely conflicting DKMS/IPU6 packages (if present)..."
# Known package names across OEM/PPAs (best-effort; ignore missing)
apt-get purge -y -o Dpkg::Options::=--force-confnew \
  intel-ipu6-dkms ivsc-driver ivsc-dkms intel-ivsc-driver usbio-driver usbio-dkms \
  linux-modules-ipu6-generic-hwe-22.04 linux-modules-ipu6-generic-hwe-24.04 \
  linux-modules-ipu6 linux-modules-ipu6-* || true

# Also remove any stale DKMS module instances
if command -v dkms >/dev/null 2>&1; then
  dkms status | awk -F, '/ipu6|ivsc|usbio/ {print $1}' | while read -r mod; do
    LOG "Removing DKMS module: $mod"
    dkms remove "$mod" --all || true
  done
fi

# 2) Keep sensor drivers but disable ONLY the OOT IPU6 core modules
if [[ -d "$DKMS_UPDATES_DIR" ]]; then
  mkdir -p "$BACKUP_DIR"
  LOG "Scanning $DKMS_UPDATES_DIR for OOT IPU6 core modules to quarantine..."
  shopt -s nullglob
  for ko in "$DKMS_UPDATES_DIR"/intel_ipu6*.ko* "$DKMS_UPDATES_DIR"/ipu_bridge*.ko*; do
    [[ -e "$ko" ]] || continue
    bn="$(basename "$ko")"
    LOG " - quarantining $bn"
    mv -f "$ko" "$BACKUP_DIR"/
  done
  depmod -a
fi

# 3) Make sure the in-kernel IPU6 stack can load
LOG "Loading in-kernel IPU6 core (should NOT be tagged OE in lsmod)..."
modprobe -r intel_ipu6_psys intel_ipu6_isys intel_ipu6 2>/dev/null || true
modprobe intel_ipu6 || true
modprobe intel_ipu6_isys || true
modprobe intel_ipu6_psys || true

# 4) Install Intel userspace (icamerasrc / HAL) from Intel IPU6 PPA (userspace only)
LOG "Adding Intel IPU6 userspace PPA and installing ipu6-camera-bins..."
if ! apt-cache policy | grep -q "oem-solutions-group/intel-ipu6"; then
  apt-get install -y software-properties-common
  add-apt-repository -y ppa:oem-solutions-group/intel-ipu6
fi
apt-get update -y
apt-get install -y ipu6-camera-bins

# 5) Ensure v4l2loopback is available for V4L2-only applications
LOG "Installing v4l2loopback-dkms and configuring a loopback /dev/video..."
apt-get install -y v4l2loopback-dkms
mkdir -p /etc/modprobe.d
cat >/etc/modprobe.d/v4l2loopback.conf <<'EOF'
# Create one loopback node, label it clearly, and allow multiple readers
options v4l2loopback devices=1 video_nr=20 card_label="IPU6 Relay Camera" exclusive_caps=0
EOF
modprobe -r v4l2loopback 2>/dev/null || true
modprobe v4l2loopback || true

# 6) Ensure the ov02c10 sensor driver exists and can load
mkdir -p "$EXTRA_DIR"
if ! modinfo ov02c10 >/dev/null 2>&1; then
  LOG "ov02c10 module not found in this kernel. Building ONLY the sensor from Intel ipu6-drivers..."
  TMPDIR="$(mktemp -d)"
  pushd "$TMPDIR" >/dev/null
  git clone --depth=1 https://github.com/intel/ipu6-drivers.git
  cd ipu6-drivers
  # Build only the i2c sensor subtree; we avoid installing any ipu6 core .ko
  make -C /lib/modules/"$KVER"/build M="$(pwd)"/drivers/media/i2c modules
  # Copy just ov02c10.ko if it was produced
  if [[ -f drivers/media/i2c/ov02c10.ko ]]; then
    cp -f drivers/media/i2c/ov02c10.ko "$EXTRA_DIR"/
    LOG "Installed ov02c10.ko into $EXTRA_DIR"
  else
    LOG "WARNING: ov02c10.ko did not build; proceeding without it."
  fi
  popd >/dev/null
  rm -rf "$TMPDIR"
  depmod -a
fi

# Try to load the sensor (ignore failure if model differs)
modprobe ov02c10 2>/dev/null || true

# 7) Create a user service that relays icamerasrc into the loopback node for legacy apps/browsers
LOG "Creating a user systemd unit to relay icamerasrc -> /dev/video20 via GStreamer..."
UNIT_DIR="/home/${USER_NAME}/.config/systemd/user"
mkdir -p "$UNIT_DIR"

cat >"$UNIT_DIR/ipu6-icamera-relay.service" <<'EOF'
[Unit]
Description=IPU6 icamerasrc relay to v4l2loopback (/dev/video20)
After=graphical-session.target pipewire.service
Wants=graphical-session.target

[Service]
Type=simple
Environment=GST_VAAPI_ALL_DRIVERS=1
# Try 1280x720 NV12 @30; adjust if needed
ExecStart=/usr/bin/gst-launch-1.0 -v icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! queue ! v4l2sink device=/dev/video20 sync=false
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

# Enable & start for the login user
loginctl enable-linger "$USER_NAME" >/dev/null 2>&1 || true
sudo -u "$USER_NAME" XDG_RUNTIME_DIR="/run/user/$(id -u "$USER_NAME")" systemctl --user daemon-reload || true
sudo -u "$USER_NAME" XDG_RUNTIME_DIR="/run/user/$(id -u "$USER_NAME")" systemctl --user enable --now ipu6-icamera-relay.service || true

# 8) Quick hints
LOG "Done."
echo
echo "Now try (as your normal user):"
echo "  - Test the HAL directly:  GST_DEBUG=2 gst-launch-1.0 icamerasrc ! autovideosink"
echo "  - Check loopback node:    v4l2-ctl --list-devices | grep -A1 'IPU6 Relay Camera'"
echo "  - In apps, pick:          'IPU6 Relay Camera' (/dev/video20)"
echo
echo "If nothing shows, capture kernel logs:"
echo "  journalctl -b -k | egrep -i 'ipu6|ov02c10|icamera|v4l2|ivsc|intel'"
