#!/usr/bin/env bash
set -euo pipefail

NAME="ipu6_install_v40"
log(){ echo "[$NAME] $*"; }
fatal(){ echo "[$NAME][FATAL] $*" >&2; exit 1; }

MACHINE=ipu6-noble
ROOT=/var/lib/machines/$MACHINE
DIST=noble
PPA_LINE="deb https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu ${DIST} main"
# Launchpad PPA signing key for intel-ipu6 (fingerprint ends with A630CA96910990FF)
PPA_KEY_SHORT=A630CA96910990FF

log "Kernel: $(uname -r)"

# --- 0) Host sanity: we must have IPU6 /dev nodes already (kernel side OK) ---
if ! ls /dev/video* /dev/media* >/dev/null 2>&1; then
  log "WARN: did not see /dev/video* or /dev/media*; kernel IPU6 nodes missing?"
fi

# --- 1) Host packages we need for a container & video tools ---
log "Ensuring host packages (debootstrap, systemd-container, binutils, v4l-utils, gstreamer tools)…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq debootstrap systemd-container ca-certificates curl wget xz-utils \
  v4l2loopback-dkms v4l-utils gstreamer1.0-tools || true

# Provide a virtual camera on the host if not present
if ! modprobe -n v4l2loopback >/dev/null 2>&1; then
  fatal "v4l2loopback not available on this kernel."
fi
if ! lsmod | grep -q '^v4l2loopback'; then
  log "Loading v4l2loopback (video_nr=42)…"
  modprobe v4l2loopback exclusive_caps=1 video_nr=42 card_label="IPU6 Virtual Camera"
fi
if [ ! -e /dev/video42 ]; then
  fatal "Expected /dev/video42 not found after loading v4l2loopback."
fi
log "v4l2loopback ready at /dev/video42."

# --- 2) Create (or reuse) an Ubuntu 24.04 (Noble) rootfs for userspace camera stack ---
if [ ! -d "$ROOT" ] || [ ! -f "$ROOT/etc/os-release" ]; then
  log "Creating Noble rootfs at $ROOT (this may take a minute)…"
  debootstrap --arch=amd64 "$DIST" "$ROOT" http://archive.ubuntu.com/ubuntu
else
  log "Noble rootfs already exists, reusing."
fi

# Make sure container has DNS
install -Dm644 /etc/resolv.conf "$ROOT/etc/resolv.conf"

# --- 3) Configure apt sources & Intel IPU6 PPA inside the container ---
log "Configuring apt sources inside container…"
cat >"$ROOT/etc/apt/sources.list" <<EOF
deb http://archive.ubuntu.com/ubuntu ${DIST} main universe multiverse restricted
deb http://archive.ubuntu.com/ubuntu ${DIST}-updates main universe multiverse restricted
deb http://security.ubuntu.com/ubuntu ${DIST}-security main universe multiverse restricted
EOF

echo "$PPA_LINE" > "$ROOT/etc/apt/sources.list.d/intel-ipu6.list"

# Import the PPA signing key into the container’s trusted keyring
log "Importing Intel IPU6 PPA key inside container…"
mkdir -p "$ROOT/etc/apt/trusted.gpg.d"
# Use hkps keyserver and dearmor -> trusted.gpg.d
chroot "$ROOT" /bin/bash -c "apt-get update -qq || true; \
  apt-get install -y -qq gnupg ca-certificates curl >/dev/null 2>&1 || true"
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${PPA_KEY_SHORT}" \
  | chroot "$ROOT" /bin/bash -c "gpg --dearmor > /etc/apt/trusted.gpg.d/intel-ipu6.gpg"

# --- 4) Install the userspace camera stack inside the container ---
log "Installing IPU6 userspace & GStreamer inside the container…"
chroot "$ROOT" /bin/bash -c "apt-get update -qq"
# Note: v4l2sink is in plugins-good; install base + good + tools
chroot "$ROOT" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y \
  gstreamer1.0-icamera libcamhal-ipu6ep0 libcamhal0 libipu6 \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 libdrm2 libexpat1 \
  libv4l-0 gstreamer1.0-tools v4l-utils"

# --- 5) Provide wrappers to run pipelines in container with /dev bound to host ---
WRAP=/usr/local/bin/ipu6-container-run
log "Installing convenience wrapper: $WRAP"
cat >"$WRAP" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
ROOT=/var/lib/machines/ipu6-noble
# Bind /dev so the container sees the host cameras and the v4l2loopback device.
# Bind X11 socket if DISPLAY is set (for on-screen preview).
BINDS=(--bind=/dev --bind=/run --bind=/tmp)
if [ -n "${DISPLAY:-}" ] && [ -d /tmp/.X11-unix ]; then
  BINDS+=(--bind=/tmp/.X11-unix)
fi
exec systemd-nspawn -q -D "$ROOT" "${BINDS[@]}" /bin/bash -lc "$*"
EOS
chmod +x "$WRAP"

# Demo wrapper to feed the host virtual cam (/dev/video42) from inside the container
VCAM=/usr/local/bin/ipu6-feed-virtualcam
log "Installing demo: $VCAM"
cat >"$VCAM" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
CMD='gst-launch-1.0 icamerasrc ! video/x-raw,format=NV12,width=1280,height=720 ! queue ! v4l2sink device=/dev/video42 sync=false'
exec /usr/local/bin/ipu6-container-run "$CMD"
EOS
chmod +x "$VCAM"

# Quick self-checks
log "Self-check: container sees icamerasrc?"
/usr/local/bin/ipu6-container-run "gst-inspect-1.0 icamerasrc | head -n 5" || true

log "Done. Try:"
echo "  1) Preview on host X11 (allow local root temporarily):"
echo "     xhost +si:localuser:root && ipu6-container-run 'gst-launch-1.0 icamerasrc ! videoconvert ! xvimagesink -v'"
echo "     (then 'xhost -si:localuser:root' to revert)"
echo "  2) Create a virtual webcam for browsers:"
echo "     ipu6-feed-virtualcam"
