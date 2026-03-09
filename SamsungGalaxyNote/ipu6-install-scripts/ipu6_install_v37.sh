#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/ipu6_install_v37.$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

die(){ echo "[FATAL] $*" >&2; exit 1; }
log(){ echo "[ipu6_install_v37] $*"; }

# --- 0. Basics ---------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Run as root (sudo)."

log "Kernel: $(uname -r)"
glibc_ver=$(ldd --version | awk 'NR==1{print $NF}')
log "Host glibc: $glibc_ver"

# --- 1. Verify IPU6 kernel side is up ---------------------------------------
log "Checking IPU6 nodes (kernel side)…"
if ! ls /dev/video* /dev/media* 2>/dev/null | grep -Eq '/dev/video|/dev/media'; then
  die "No /dev/video* or /dev/media* nodes found. Your IPU6 kernel modules aren't active."
fi
log "OK: video/media nodes exist."

# --- 2. Ensure v4l2loopback on host -----------------------------------------
log "Ensuring v4l2loopback-dkms is installed…"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq v4l2loopback-dkms v4l-utils gstreamer1.0-tools

# load a predictable virtual device at /dev/video10
if ! lsmod | grep -q v4l2loopback; then
  modprobe v4l2loopback exclusive_caps=1 card_label="Intel-MIPI-Loopback" video_nr=10 || true
fi
# If loaded without our options, reload with them
if ! v4l2-ctl --list-devices 2>/dev/null | grep -q "Intel-MIPI-Loopback"; then
  rmmod v4l2loopback 2>/dev/null || true
  modprobe v4l2loopback exclusive_caps=1 card_label="Intel-MIPI-Loopback" video_nr=10
fi
log "v4l2loopback ready at /dev/video10."

# --- 3. If host glibc >= 2.38, you could run everything natively ------------
need_container=1
dpkg --compare-versions "$glibc_ver" ge 2.38 && need_container=0

# --- 4. Container path (recommended on 22.04) --------------------------------
ROOT=/var/lib/ipu6-noble
if [[ $need_container -eq 1 ]]; then
  log "Host glibc < 2.38 -> using a minimal Ubuntu 24.04 (Noble) container runtime."

  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq debootstrap systemd-container ca-certificates curl wget

  if [[ ! -e "$ROOT"/bin/bash ]]; then
    log "Bootstrapping Noble rootfs at $ROOT (this is small and quick)…"
    debootstrap --variant=minbase noble "$ROOT" http://archive.ubuntu.com/ubuntu || die "debootstrap failed"
  else
    log "Noble rootfs already exists, reusing."
  fi

  # Ensure networking in the chroot
  cp -f /etc/resolv.conf "$ROOT/etc/resolv.conf"

  # Base apt sources for Noble
  cat > "$ROOT/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe multiverse restricted
deb http://archive.ubuntu.com/ubuntu noble-updates main universe multiverse restricted
deb http://archive.ubuntu.com/ubuntu noble-security main universe multiverse restricted
EOF

  # Add Intel IPU6 PPA (jammy pocket) to the container (the PPA publishes only jammy)
  mkdir -p "$ROOT/etc/apt/sources.list.d"
  echo "deb http://ppa.launchpad.net/oem-solutions-group/intel-ipu6/ubuntu jammy main" \
    > "$ROOT/etc/apt/sources.list.d/intel-ipu6.list"

  # Add the PPA key inside the container (copy from host if present, else fetch)
  if [[ -f /etc/apt/trusted.gpg.d/oem-solutions-group-ubuntu-intel-ipu6.gpg ]]; then
    cp /etc/apt/trusted.gpg.d/oem-solutions-group-ubuntu-intel-ipu6.gpg \
      "$ROOT/etc/apt/trusted.gpg.d/"
  else
    chroot "$ROOT" bash -c '
      apt-get update -qq || true
      apt-get install -y -qq gnupg
      # Key fingerprint from Launchpad page
      apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 23CBDB455F3792D18EF17E63A630CA96910990FF
    '
  fi

  log "Installing IPU6 userspace and GStreamer inside the container…"
  chroot "$ROOT" bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    # Base GStreamer + icamerasrc; let noble satisfy deps (glibc 2.39)
    apt-get install -y -qq \
      gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-tools \
      gstreamer1.0-icamera libcamhal-ipu6ep0 libcamhal-common libcamhal0 libipu6
  ' || die "IPU6 userspace install inside container failed (check PPA state)."

  # Create a runner that pushes frames from container to host /dev/video10
  WRAP=/usr/local/bin/ipu6-container-webcam
  cat > "$WRAP" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT=/var/lib/ipu6-noble
# Ensure the loopback device exists on host
if [[ ! -e /dev/video10 ]]; then
  echo "Missing /dev/video10 on host; load v4l2loopback first." >&2
  exit 1
fi
# Run gst inside the container with host devices bound
exec systemd-nspawn -q \
  -D "$ROOT" \
  --bind=/dev \
  --bind=/run/udev \
  --bind=/sys \
  --bind=/proc \
  --bind-ro=/lib/firmware \
  --machine=ipu6-noble \
  /usr/bin/env -i \
    PATH="/usr/sbin:/usr/bin:/bin" \
    GST_PLUGIN_SYSTEM_PATH_1_0="/usr/lib/x86_64-linux-gnu/gstreamer-1.0" \
    LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu" \
    gst-launch-1.0 -v icamerasrc ! \
      video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! \
      videoconvert ! v4l2sink device=/dev/video10
EOF
  chmod +x "$WRAP"
  log "Created runner: $WRAP"

  log "Usage:"
  echo "  sudo ipu6-container-webcam"
  echo "Then pick \"Intel-MIPI-Loopback\" (/dev/video10) in apps."

else
  # (If you had upgraded to 24.04 host, the native path would be used here.)
  log "Host glibc >= 2.38 — container not strictly required; you could apt install the IPU6 userspace natively."
fi

log "Done. Log saved to $LOG"
