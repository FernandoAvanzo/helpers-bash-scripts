#!/usr/bin/env bash
set -euo pipefail

log(){ printf "[ipu6_install_v11] %s\n" "$*"; }

# ---- Preflight ---------------------------------------------------------------
if [[ $(id -u) -ne 0 ]]; then
  echo "Run as root (sudo)."; exit 1
fi

KVER="$(uname -r)"
log "Kernel: $KVER"

# Required headers for DKMS/v4l2loopback
if ! dpkg -s "linux-headers-$(uname -r)" >/dev/null 2>&1; then
  log "Installing headers for $(uname -r)…"
  apt-get update -y
  apt-get install -y "linux-headers-$(uname -r)"
fi

# Minimal tools
apt-get update -y
apt-get install -y ca-certificates curl gnupg software-properties-common \
  build-essential pkg-config git meson ninja-build cmake \
  python3 python3-pip python3-jinja2 python3-yaml \
  libglib2.0-dev libyaml-dev libgnutls28-dev libevent-dev \
  libudev-dev libunwind-dev libdw-dev libdrm-dev \
  libexif-dev libtiff5-dev libjpeg-dev \
  gstreamer1.0-tools gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  v4l-utils

# ---- Verify kernel IPU6 is present ------------------------------------------
if ! lsmod | grep -Eq '(^| )intel_ipu6( |$)'; then
  # Try loading the modules in case they were not autoloaded
  modprobe intel_ipu6 || true
fi

if ! lsmod | grep -Eq '(^| )intel_ipu6( |$)'; then
  log "IPU6 kernel modules not loaded. Please ensure your kernel has IPU6 built. Abort."
  exit 1
fi

# ---- Intel IPU6 HAL / Binaries (firmware & libs) ----------------------------
# Use Intel's PPA if present; otherwise assume you previously installed it.
# (On Pop!_OS Jammy this PPA exists; if it's already added, apt will be a no-op.)
add-apt-repository -y ppa:oem-solutions-group/intel-ipu6 || true
apt-get update -y
apt-get install -y \
  ipu6-camera-bins || true  # name may vary; if absent, we proceed with existing install

# ---- Build libcamera (Intel fork with IPU6 pipeline) -------------------------
WORKDIR="/usr/local/src/ipu6"
install -d "$WORKDIR"
cd "$WORKDIR"

if [[ ! -d libcamera ]]; then
  log "Cloning Intel libcamera (with IPU6 pipeline)…"
  git clone https://github.com/intel/libcamera.git
fi

cd libcamera
# Use default branch from Intel fork which includes IPU6 pipeline
log "Configuring libcamera build…"
meson setup build \
  -Dpipelines=ipu6 \
  -Dgstreamer=enabled \
  -Dv4l2=true \
  -Dtest=false \
  -Ddocumentation=false || meson setup --reconfigure build \
  -Dpipelines=ipu6 -Dgstreamer=enabled -Dv4l2=true -Dtest=false -Ddocumentation=false

log "Building libcamera… (this can take a while)"
ninja -C build
log "Installing libcamera to /usr/local"
ninja -C build install
ldconfig

# Quick smoke test: do we have libcamerasrc plugin now?
if ! gst-inspect-1.0 libcamerasrc >/dev/null 2>&1; then
  # ---- Fallback: build Intel icamerasrc plugin ------------------------------
  cd "$WORKDIR"
  if [[ ! -d icamerasrc ]]; then
    log "Cloning Intel icamerasrc (fallback GStreamer source)…"
    git clone https://github.com/intel/icamerasrc.git
  fi
  cd icamerasrc
  meson setup build || meson setup --reconfigure build
  ninja -C build
  ninja -C build install
  ldconfig
fi

# ---- v4l2loopback (virtual camera for browser) ------------------------------
# Try packaged DKMS first
if ! modinfo v4l2loopback >/dev/null 2>&1; then
  log "Installing v4l2loopback-dkms…"
  apt-get install -y v4l2loopback-dkms || true
fi

# If still missing, build from source (works with any kernel as long as headers are present)
if ! modinfo v4l2loopback >/dev/null 2>&1; then
  cd "$WORKDIR"
  if [[ ! -d v4l2loopback ]]; then
    log "Cloning v4l2loopback…"
    git clone https://github.com/umlaeute/v4l2loopback.git
  fi
  cd v4l2loopback
  make
  make install
  depmod -a
fi

# Autoload at boot with friendly name (one device)
install -Dm644 /dev/stdin /etc/modules-load.d/v4l2loopback.conf <<'EOF'
v4l2loopback
EOF

install -Dm644 /dev/stdin /etc/modprobe.d/v4l2loopback.conf <<'EOF'
options v4l2loopback devices=1 video_nr=42 card_label="IPU6 Virtual Camera" exclusive_caps=1
EOF

modprobe -r v4l2loopback 2>/dev/null || true
modprobe v4l2loopback devices=1 video_nr=42 card_label="IPU6 Virtual Camera" exclusive_caps=1

# ---- Helper launcher: stream libcamera -> /dev/video42 ----------------------
install -Dm755 /dev/stdin /usr/local/bin/start-ipu6-virtualcam <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Pick a reasonable default format; adjust if needed
# Try libcamerasrc first, fallback to icamerasrc if missing
if gst-inspect-1.0 libcamerasrc >/dev/null 2>&1; then
  SRC="libcamerasrc ! video/x-raw,width=1280,height=720,framerate=30/1"
else
  SRC="icamerasrc ! video/x-raw,width=1280,height=720,framerate=30/1"
fi
exec gst-launch-1.0 -v $SRC ! videoconvert ! v4l2sink device=/dev/video42 sync=false
EOF

# systemd user service so you can start/stop easily
install -Dm644 /dev/stdin /etc/systemd/user/ipu6-virtualcam.service <<'EOF'
[Unit]
Description=Feed IPU6 camera into /dev/video42 via GStreamer
After=graphical-session.target

[Service]
ExecStart=/usr/local/bin/start-ipu6-virtualcam
Restart=on-failure

[Install]
WantedBy=default.target
EOF

log "Enabling user service (run as your normal user): systemctl --user enable --now ipu6-virtualcam.service"
log "All done. Reboot recommended. Then run:  libcamera-hello -t 2000  (for a quick test)"
