#!/usr/bin/env bash
set -euo pipefail

echo "[ipu6_install_v8] Preflight…"
if [[ $EUID -ne 0 ]]; then echo "Please run with sudo"; exit 1; fi

# 1) Sanity: we expect intel_ipu6 modules to exist already
if ! lsmod | grep -q 'intel_ipu6'; then
  echo "intel_ipu6 modules not loaded; kernel side not ready. Abort."; exit 1
fi

# 2) Stop the libcamera GStreamer plugin from crashing gst-plugin-scan
echo "[ipu6_install_v8] Removing mismatched GStreamer libcamera plugin (harmless if absent)…"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get remove -y gstreamer1.0-libcamera || true

# 3) Intel IPU6 PPA (userspace stack)
echo "[ipu6_install_v8] Ensuring Intel IPU6 PPA is present…"
if ! grep -Rqs "oem-solutions-group/intel-ipu6" /etc/apt/sources.list.d /etc/apt/sources.list; then
  apt-get install -y software-properties-common
  add-apt-repository -y ppa:oem-solutions-group/intel-ipu6
fi
apt-get update -y

# 4) Find the right package names on Jammy and install them
echo "[ipu6_install_v8] Installing IPU6 userspace (HAL, binaries, icamerasrc, relay + loopback)…"
set +e
# Candidates vary a bit by build; we detect what exists and install it.
PKGS=()
for p in ipu6-camera-bins ipu6-camera-hal gstreamer1.0-icamerasrc gstreamer-plugins-icamerasrc v4l2-relayd v4l2loopback-dkms; do
  if apt-cache show "$p" >/dev/null 2>&1; then PKGS+=("$p"); fi
done
# HAL/icam libs sometimes use "libcamhal-…" names – grab whatever exists
for p in $(apt-cache search -n 'libcamhal.*ipu6' | awk '{print $1}'); do PKGS+=("$p"); done
set -e

if [[ ${#PKGS[@]} -eq 0 ]]; then
  echo "Could not find any IPU6 userspace packages in the PPA. Abort."
  exit 1
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKGS[@]}"

# 5) udev permission for udmabuf (non-root camera use)
echo "[ipu6_install_v8] Installing udev rule for udmabuf…"
install -d -m 0755 /etc/udev/rules.d
cat >/etc/udev/rules.d/90-udmabuf.rules <<'EOF'
KERNEL=="udmabuf*", GROUP="video", MODE="0660"
EOF
udevadm control --reload && udevadm trigger

# 6) Create a V4L2 relay device now (one-off, survives until reboot)
echo "[ipu6_install_v8] Loading v4l2loopback (ICamera Relay)…"
modprobe v4l2loopback devices=1 exclusive_caps=1 card_label="ICamera Relay" || true

echo
echo "[ipu6_install_v8] Done."
echo "Next step (manual test):"
echo "  1) Close all apps that might use the camera."
echo "  2) Run this in a terminal (shows a live preview *and* fills /dev/video-relay):"
echo "     gst-launch-1.0 -v icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! tee name=t \\"
echo "        t. ! queue ! videoconvert ! autovideosink sync=false \\"
echo "        t. ! queue ! v4l2convert ! v4l2sink device=/dev/video-relay sync=false"
echo
echo "  3) With that pipeline running, open Chrome/Firefox and pick the device named “ICamera Relay”."
echo
echo "If that works, you can later switch to the persistent service:"
echo "  systemctl enable --now v4l2-relayd@icam-relay.service   # if the package provides the template"
echo "  (or keep using the simple gst-launch line above)."
