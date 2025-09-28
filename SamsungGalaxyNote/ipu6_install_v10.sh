#!/usr/bin/env bash
set -euo pipefail

echo "[ipu6_install_v10] Preflight…"
if [[ $EUID -ne 0 ]]; then echo "Run as root (sudo)."; exit 1; fi

KREL="$(uname -r)"
need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  software-properties-common ca-certificates curl wget gnupg \
  build-essential pkg-config linux-headers-"$KREL" \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad v4l-utils

echo "[ipu6_install_v10] Ensure Intel IPU6 PPA present and userspace installed…"
# Intel IPU6 PPA (already in your logs, but ensure it's there)
if ! grep -Rqs "oem-solutions-group/intel-ipu6" /etc/apt/; then
  add-apt-repository -y ppa:oem-solutions-group/intel-ipu6
fi
apt-get update -y

# Core userspace from Intel stack. Names exist on the PPA; some may already be installed
# (Don't fail if a package is missing; try what's available.)
apt_install_soft() { apt-get install -y --no-install-recommends "$@" || true; }

apt_install_soft \
  ipu6-camera-bins \
  libcamhal-ipu6ep libcamhal-ipu6epmtl \
  libgcss-ipu6-0 libgcss-ipu6ep0 libgcss-ipu6epmtl0 \
  libia-aiq-ipu6-0 libia-isp-bxt-ipu6-0 libia-lard-ipu6-0 libia-log-ipu6-0 \
  libia-cca-ipu6-0 libia-nvm-ipu6-0 libia-emd-decoder-ipu6-0 \
  libcamera0 libcamera-tools libcamera-ipa 2>/dev/null || true

# GStreamer source plugin used by Intel HAL = icamerasrc
echo "[ipu6_install_v10] Installing icamerasrc (GStreamer) if available…"
apt_install_soft gstreamer1.0-icamerasrc

echo "[ipu6_install_v10] Verify kernel IPU6 modules…"
modprobe intel_ipu6 || true
modprobe intel_ipu6_isys || true
if ! lsmod | grep -q '^intel_ipu6'; then
  echo "IPU6 kernel modules not loaded. Check dmesg for IPU6 errors and verify firmware."
  exit 2
fi

echo "[ipu6_install_v10] Verify icamerasrc plugin…"
if ! gst-inspect-1.0 icamerasrc >/dev/null 2>&1; then
  echo "icamerasrc not found. This userspace is required for IPU6 on Ubuntu."
  echo "Check Intel PPA availability or install from source per Intel docs."
  exit 3
fi

echo "[ipu6_install_v10] Build & load v4l2loopback for ${KREL}…"
apt-get install -y dkms
# Always (re)install to ensure it matches current kernel
apt-get install -y v4l2loopback-dkms
depmod -a "$KREL" || true
modprobe -r v4l2loopback >/dev/null 2>&1 || true
modprobe v4l2loopback exclusive_caps=1 video_nr=42 card_label="Intel IPU6 (virtual)"
# confirm device
if [[ ! -e /dev/video42 ]]; then
  echo "Failed to create /dev/video42 from v4l2loopback"; exit 4
fi

echo "[ipu6_install_v10] Create systemd service to feed virtual camera via icamerasrc…"
cat >/etc/systemd/system/ipu6-virtualcam.service <<'EOF'
[Unit]
Description=Feed IPU6 frames into v4l2loopback (/dev/video42) via icamerasrc
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/gst-launch-1.0 -q \
  icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 \
  ! queue leaky=downstream max-size-buffers=4 \
  ! v4l2convert \
  ! video/x-raw,format=YUY2 \
  ! v4l2sink device=/dev/video42 sync=false
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ipu6-virtualcam.service

echo "[ipu6_install_v10] Sanity checks…"
sleep 1
v4l2-ctl --all -d /dev/video42 | sed -n '1,20p' || true

echo
echo "Done. In Chrome/Brave/Firefox, select the camera named: Intel IPU6 (virtual)"
echo "If the tab still can’t see a camera, close all browser windows and try again."
