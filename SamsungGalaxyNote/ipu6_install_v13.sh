#!/usr/bin/env bash
set -euo pipefail

echo "[ipu6_install_v13] Kernel: $(uname -r)"

need_root() { [ "$EUID" -eq 0 ] || { echo "Run as root (sudo)"; exit 1; }; }
need_root

# --- Robust IPU6 presence check (don’t abort if lsmod is empty) ---
has_ipu6=0
if [ -e /sys/module/intel_ipu6 ] || [ -e /sys/module/intel_ipu6_isys ]; then
  has_ipu6=1
elif dmesg | grep -qi 'intel-ipu6'; then
  has_ipu6=1
elif v4l2-ctl --list-devices 2>/dev/null | grep -q '^ipu6'; then
  has_ipu6=1
fi

if [ "$has_ipu6" -eq 0 ]; then
  echo "[ipu6_install_v13] Warning: Could not confirm IPU6 from sysfs/dmesg/v4l2 yet."
  echo "Continuing anyway (driver may load on first use)."
fi

# --- APT pre-reqs ---
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg software-properties-common \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad v4l-utils

# --- Ensure Intel IPU6 PPA is configured ---
if ! grep -Rqs "oem-solutions-group/intel-ipu6" /etc/apt/sources.list /etc/apt/sources.list.d; then
  add-apt-repository -y ppa:oem-solutions-group/intel-ipu6  # dev PPA; used intentionally
fi
apt-get update

# --- Install Intel IPU6 userspace & helpers (from that PPA) ---
# Package names as published by the PPA: gst-plugins-icamera, ipu6-camera-hal, ipu6-camera-bins, v4l2-relayd
apt-get install -y --no-install-recommends \
  ipu6-camera-bins ipu6-camera-hal gst-plugins-icamera v4l2-relayd

# --- v4l2loopback (builds for your current kernel via DKMS) ---
apt-get install -y v4l2loopback-dkms
# Persistent options for browsers (see v4l2loopback docs)
install -Dm0644 /dev/stdin /etc/modprobe.d/v4l2loopback.conf <<'EOF'
# Create one virtual UVC device that Chrome/Firefox accept
options v4l2loopback video_nr=42 card_label="IPU6 Virtual Camera" exclusive_caps=1 max_buffers=32
EOF

# (Re)load loopback with our options
modprobe -r v4l2loopback 2>/dev/null || true
modprobe v4l2loopback || { echo "[ipu6_install_v13] ERROR: v4l2loopback failed to load"; exit 1; }

# --- Systemd service: feed IPU6 -> loopback with icamerasrc ---
# icamerasrc is the GStreamer source from Intel’s icamera plugin (gst-plugins-icamera).
# Docs & examples are in Intel’s repo. We'll output NV12 1280x720@30 which browsers handle fine.
# Refs: ipu6-camera-hal README and icamerasrc README.
install -Dm0644 /dev/stdin /etc/systemd/system/ipu6-virtualcam.service <<'EOF'
[Unit]
Description=IPU6 → v4l2loopback (icamerasrc pipeline)
After=multi-user.target

[Service]
Type=simple
# Try sensor-id=0 (typical single-sensor laptops). Adjust width/height if needed.
ExecStart=/usr/bin/gst-launch-1.0 -e icamerasrc sensor-id=0 ! \
  video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! \
  queue ! videoconvert ! queue ! v4l2sink device=/dev/video42 sync=false
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ipu6-virtualcam.service

echo
echo "[ipu6_install_v13] Done."
echo "Test the pieces:"
echo "  - gst-inspect-1.0 icamerasrc        # plugin present?"
echo "  - v4l2-ctl --all -d /dev/video42     # loopback exists?"
echo "  - In Chrome/Firefox, select 'IPU6 Virtual Camera'."
echo
echo "If the service fails, check logs: sudo journalctl -u ipu6-virtualcam -b"
