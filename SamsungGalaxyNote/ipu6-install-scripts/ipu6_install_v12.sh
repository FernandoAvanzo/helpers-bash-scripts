#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[ipu6_install_v12] $*"; }

# 0) Preconditions: kernel modules present (you already have them)
log "Kernel: $(uname -r)"
if ! lsmod | grep -qE '(^| )intel_ipu6(_isys)?( |$)'; then
  log "intel_ipu6 modules not loaded. Please reboot into the kernel where they load (your 6.16 does). Abort."
  exit 1
fi

# 1) Repos: make sure Intel IPU6 PPA is present (userspace HAL/bins live here)
if ! grep -Rqs "oem-solutions-group/intel-ipu6" /etc/apt/sources.list.d /etc/apt/sources.list; then
  log "Adding Intel IPU6 PPA…"
  add-apt-repository -y ppa:oem-solutions-group/intel-ipu6
fi

log "Refreshing APT…"
apt-get update -y

# 2) Install Intel HAL + binaries (pick MTL variants if available)
log "Installing Intel IPU6 HAL + binaries…"
# always try the common binary blob package
APT_PKGS=(ipu6-camera-bins)

# add whichever HAL libs exist on this distro (mtl first, then generic/ep)
mapfile -t HALS < <(apt-cache search -n '^libcamhal-ipu6.*' \
  | awk '{print $1}' | sort -u)
if ((${#HALS[@]})); then
  # Prefer mtl variants if present
  for p in "${HALS[@]}"; do
    if [[ "$p" =~ mtl ]]; then APT_PKGS+=("$p"); fi
  done
  # If nothing mtl-like appended, add generic ones
  if ((${#APT_PKGS[@]}==1)); then
    APT_PKGS+=("${HALS[@]}")
  fi
fi

# it’s okay if some names don’t exist; apt will ignore unknowns below
apt-get install -y --no-install-recommends "${APT_PKGS[@]}" || true

# 3) Ensure GStreamer dev/runtime (from Pop!_OS repos) – no libcamera here
log "Installing GStreamer dev/runtime…"
apt-get install -y --no-install-recommends \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  meson ninja-build build-essential pkg-config git

# 4) Build & install icamerasrc (Intel’s plugin)
ICAMERA_DIR=/usr/local/src/icamerasrc
if [[ ! -d $ICAMERA_DIR ]]; then
  log "Cloning icamerasrc…"
  git clone --depth=1 -b icamerasrc_slim_api https://github.com/intel/icamerasrc "$ICAMERA_DIR"
fi
log "Building icamerasrc…"
cd "$ICAMERA_DIR"
meson setup --wipe build -Dprefix=/usr
ninja -C build
ninja -C build install

# 5) v4l2loopback (DKMS or source fallback)
log "Installing v4l2loopback (DKMS)…"
if ! apt-get install -y --no-install-recommends v4l2loopback-dkms; then
  log "DKMS package missing; building v4l2loopback from source…"
  cd /usr/local/src
  if [[ ! -d v4l2loopback ]]; then
    git clone --depth=1 https://github.com/umlaeute/v4l2loopback.git
  fi
  cd v4l2loopback
  make
  make install
  depmod -a
fi

# load (or reload) the loopback with browser-friendly options
log "Loading v4l2loopback kernel module…"
modprobe -r v4l2loopback 2>/dev/null || true
modprobe v4l2loopback video_nr=42 card_label="Intel IPU6 Virtual Camera" exclusive_caps=1

# 6) Systemd service to feed the virtual camera from icamerasrc
SERVICE=/etc/systemd/system/ipu6-virtualcam.service
cat > "$SERVICE" <<'EOF'
[Unit]
Description=Intel IPU6 -> v4l2loopback virtual camera
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/gst-launch-1.0 -v icamerasrc ! \
  video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! \
  videoconvert ! video/x-raw,format=YUY2 ! \
  v4l2sink device=/dev/video42 sync=false
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ipu6-virtualcam.service || true

log "Done."
log "Check with:  v4l2-ctl --device=/dev/video42 --all  and  gst-device-monitor-1.0 | grep -A5 'Intel IPU6 Virtual Camera'"
log "In Chrome/Edge: settings -> Camera -> pick “Intel IPU6 Virtual Camera”."
