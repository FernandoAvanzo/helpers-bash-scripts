#!/usr/bin/env bash
set -Eeuo pipefail

# ipu6_install_v39.sh — Run Intel IPU6 userspace in an Ubuntu 24.04 container on a 22.04 host.
# It avoids all GLIBC_2.38+ breakage on Jammy by isolating userspace in a Noble rootfs.

ROOT="/var/lib/ipu6rt/noble-rootfs"
MACH="ipu6rt"
VLOOP_DEV="/dev/video10"    # v4l2loopback device (already present on your system)
LOG="/var/log/ipu6_install_v39.$(date +%Y%m%d-%H%M%S).log"

say(){ printf '[ipu6_install_v39] %s\n' "$*" | tee -a "$LOG" ; }
die(){ printf '[ipu6_install_v39][FATAL] %s\n' "$*" | tee -a "$LOG" ; exit 1; }

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root (sudo)."; }

require_root
say "Kernel: $(uname -r)"

# 0) Quick sanity: make sure IPU6 /dev nodes are present on the host
if ! ls /dev/video* /dev/media* 1>/dev/null 2>&1; then
  say "[WARN] No /dev/video* or /dev/media* found. IPU6 kernel side may not be loaded."
  say "       You previously had them, so continue — but check dmesg if this persists."
else
  say "OK: video/media nodes exist."
fi

# 1) Make sure host has the tooling & v4l2loopback
say "Ensuring host packages (debootstrap, systemd-container, v4l2loopback, tools)…" | tee -a "$LOG"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >>"$LOG" 2>&1 || true
apt-get install -y debootstrap systemd-container ca-certificates curl wget \
  gstreamer1.0-tools v4l-utils v4l2loopback-dkms >>"$LOG" 2>&1

# 2) Ensure v4l2loopback device exists
if [[ ! -e "$VLOOP_DEV" ]]; then
  say "Creating v4l2loopback device at $VLOOP_DEV…"
  modprobe v4l2loopback devices=1 video_nr=10 card_label="Virtual Camera" exclusive_caps=1 || true
  sleep 1
  [[ -e "$VLOOP_DEV" ]] || die "v4l2loopback failed to create $VLOOP_DEV"
else
  say "v4l2loopback ready at $VLOOP_DEV."
fi

# 3) Bootstrap (or reuse) a minimal Noble rootfs
if [[ ! -f "$ROOT/etc/os-release" ]]; then
  say "Bootstrapping Ubuntu 24.04 (Noble) rootfs at $ROOT…"
  mkdir -p "$ROOT"
  debootstrap --variant=minbase noble "$ROOT" http://archive.ubuntu.com/ubuntu >>"$LOG" 2>&1
  # basic networking & apt
  cp -f /etc/resolv.conf "$ROOT/etc/resolv.conf"
  cat >"$ROOT/etc/apt/sources.list.d/ubuntu-noble.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
deb http://security.ubuntu.com/ubuntu noble-security main universe
EOF
else
  say "Noble rootfs already exists, reusing."
fi

# 4) Add Intel IPU6 PPA for NOBLE (not jammy) and import key(s) inside the container
say "Configuring IPU6 PPA (noble) and importing keys inside the container…"
mkdir -p "$ROOT/etc/apt/sources.list.d" "$ROOT/etc/apt/trusted.gpg.d" "$ROOT/host-share"
cat >"$ROOT/etc/apt/sources.list.d/intel-ipu6-noble.list" <<'EOF'
deb https://ppa.launchpadcontent.net/oem-solutions-group/intel-ipu6/ubuntu noble main
EOF

# If host already has the PPA key, copy it; otherwise fetch from keyserver.
if [[ -f /etc/apt/trusted.gpg.d/oem-solutions-group-ubuntu-intel-ipu6.gpg ]]; then
  cp -f /etc/apt/trusted.gpg.d/oem-solutions-group-ubuntu-intel-ipu6.gpg \
    "$ROOT/etc/apt/trusted.gpg.d/intel-ipu6.gpg"
else
  chroot "$ROOT" bash -lc "
    set -Eeuo pipefail
    apt-get update -y || true
    apt-get install -y --no-install-recommends gpg ca-certificates curl >/dev/null
    curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x23CBDB455F3792D18EF17E63A630CA96910990FF' \
      | gpg --dearmor >/etc/apt/trusted.gpg.d/intel-ipu6.gpg
  " >>"$LOG" 2>&1 || die "Failed to import intel-ipu6 PPA key into container"
fi

# 5) Install IPU6 userspace (Noble builds) inside the container
say "Installing IPU6 userspace & GStreamer inside the container…"
systemd-nspawn -D "$ROOT" --machine="$MACH" --setenv=DEBIAN_FRONTEND=noninteractive \
  --bind=/dev --bind=/run/udev \
  bash -lc "set -Eeuo pipefail
    apt-get update -y
    apt-get install -y --no-install-recommends \
      ipu6-camera-hal ipu6-camera-bins gst-plugins-icamera \
      gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good v4l-utils
  " >>"$LOG" 2>&1 || die "Container install failed (check PPA state and network)."

# 6) Drop helper that runs the camera → v4l2loopback bridge *inside* the container
say "Installing helper pipeline inside the container…"
cat >"$ROOT/usr/local/bin/ipu6-bridge.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
DEVICE="${1:-/dev/video10}"
# Try a conservative caps set that most browsers accept; adjust if needed.
# We convert whatever icamerasrc produces into a v4l2sink-compatible stream.
gst-launch-1.0 -v \
  icamerasrc ! \
  videoconvert ! video/x-raw,format=YUY2,width=1280,height=720,framerate=30/1 ! \
  v4l2sink device="$DEVICE" sync=false max-buffers=2 drop=true
EOS
chmod +x "$ROOT/usr/local/bin/ipu6-bridge.sh"

# 7) Host-side wrappers to run/inspect quickly
say "Creating host wrappers: /usr/local/bin/ipu6cam-start and ipu6cam-inspect"
cat >/usr/local/bin/ipu6cam-start <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
systemd-nspawn -q -D "$ROOT" --machine="$MACH" --bind=/dev --bind=/run/udev \\
  bash -lc "/usr/local/bin/ipu6-bridge.sh '$VLOOP_DEV'"
EOF
chmod +x /usr/local/bin/ipu6cam-start

cat >/usr/local/bin/ipu6cam-inspect <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
systemd-nspawn -q -D /var/lib/ipu6rt/noble-rootfs --machine=ipu6rt --bind=/dev --bind=/run/udev \
  bash -lc "GST_DEBUG=icamerasrc:3 gst-inspect-1.0 icamerasrc || true"
EOF
chmod +x /usr/local/bin/ipu6cam-inspect

say "Done. Try:  ipu6cam-inspect   (should enumerate sensors via HAL)"
say "Then:       ipu6cam-start     (fills $VLOOP_DEV; open it in a host app)"
say "Log: $LOG"
