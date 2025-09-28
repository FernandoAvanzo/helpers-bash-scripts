#!/usr/bin/env bash
set -Eeuo pipefail

tag="[ipu6_install_v14]"
say(){ echo "$tag $*"; }
die(){ echo "$tag ERROR: $*" >&2; exit 1; }

# ---------- preflight ----------
KVER="$(uname -r)"
say "Kernel: $KVER"

if ! command -v add-apt-repository >/dev/null; then
  apt-get update
  apt-get install -y software-properties-common || die "install software-properties-common"
fi

# ---------- repo: Intel IPU6 OEM PPA (Jammy) ----------
if ! grep -Rqs "oem-solutions-group/intel-ipu6" /etc/apt/sources.list /etc/apt/sources.list.d; then
  say "Adding Intel IPU6 OEM PPA…"
  add-apt-repository -y ppa:oem-solutions-group/intel-ipu6 || die "add PPA"
fi
apt-get update

# ---------- cleanup of previous failed runs ----------
say "Sanity cleanup (diversions, half-configured pkgs, stale loopback)…"
systemctl stop ipu6-vcam.service 2>/dev/null || true
systemctl disable ipu6-vcam.service 2>/dev/null || true
modprobe -r v4l2loopback 2>/dev/null || true

# long-standing diversion sometimes left by older stacks
if dpkg-divert --list 2>/dev/null | grep -q "/etc/modprobe.d/v4l2-relayd.conf"; then
  say "Removing old dpkg-divert for v4l2-relayd.conf…"
  dpkg-divert --remove /etc/modprobe.d/v4l2-relayd.conf --rename || true
fi
rm -f /etc/modprobe.d/v4l2-relayd.conf || true

# Recover from any broken states
apt-get -y -f install || true
dpkg --configure -a || true
apt-get update

# Optional purge of stale/broken OEM stack bits
# (safe if absent; avoids “already installed but not configured” traps)
apt-get -y purge gstreamer1.0-icamera gst-plugins-icamera \
  libcamhal-ipu6epmtl0 libcamhal-ipu6ep0 libcamhal0 libcamhal-common \
  libipu6 libipu6ep libipu6epmtl libgcss-ipu6-0 libgcss-ipu6ep0 2>/dev/null || true
apt-get -y -f install || true
dpkg --configure -a || true
apt-get update

# ---------- install runtime pieces ----------
say "Installing v4l2loopback (virtual camera)…"
apt-get install -y --no-install-recommends v4l2loopback-dkms || die "v4l2loopback-dkms install failed"

say "Installing Intel IPU6 OEM userspace (HAL + icamerasrc)…"
PKGS_COMMON="libcamhal-common libcamhal0 libipu6 libgcss-ipu6-0"
# Detect Meteor Lake (MTL) from dmesg, fallback to generic
HAL="libcamhal-ipu6ep0"
if dmesg | grep -qE "intel_vpu .*MTL"; then HAL="libcamhal-ipu6epmtl0"; fi

# Try primary plugin name for Jammy PPA
if ! apt-get install -y --no-install-recommends ${PKGS_COMMON} "${HAL}" gstreamer1.0-icamera; then
  say "Falling back to alternate plugin name…"
  apt-get install -y --no-install-recommends ${PKGS_COMMON} "${HAL}" gst-plugins-icamera || die "HAL/plugin packages not available from PPA"
fi

# ---------- load loopback now ----------
say "Loading v4l2loopback module…"
modprobe v4l2loopback video_nr=42 card_label="IPU6 Virtual Camera" exclusive_caps=1 || die "modprobe v4l2loopback"

# ---------- systemd bridge service (icamerasrc -> v4l2loopback) ----------
say "Creating systemd service to feed the virtual camera…"
cat >/etc/systemd/system/ipu6-vcam.service <<'EOF'
[Unit]
Description=Bridge Intel IPU6 (icamerasrc) to /dev/video42 (v4l2loopback) for browsers
After=multi-user.target
Wants=graphical.target

[Service]
Type=simple
# Conservative 720p30 NV12; adjust if needed
ExecStart=/usr/bin/gst-launch-1.0 -q icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! videoconvert ! v4l2sink device=/dev/video42 sync=false
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ipu6-vcam.service || true

say "Done."
echo
say "Quick checks:"
echo "  1) v4l2-ctl --list-devices              # should show \"IPU6 Virtual Camera\" on /dev/video42"
echo "  2) journalctl -u ipu6-vcam -b --no-pager # look for runtime errors (e.g., missing PSYS)"
echo "  3) gst-launch-1.0 -v icamerasrc ! autovideosink   # local preview test"
echo
say "If the service errors mentioning PSYS, test once with Ubuntu HWE kernel (6.8) where IPU6 ISYS/PSYS is known-good."
