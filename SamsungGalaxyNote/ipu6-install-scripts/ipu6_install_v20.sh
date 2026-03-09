#!/usr/bin/env bash
# ipu6_install_v20.sh
# Pop!_OS 22.04 (Jammy base) + Kernel 6.16.x on Samsung Galaxy Book 3 (960XGL / MTL)
# Goal: keep working kernel IPU6 drivers, ensure Intel HAL + icamerasrc, provide GLIBCXX_3.4.32 via overlay only for camera processes.

set -Eeuo pipefail

LOG=/var/log/ipu6_install_v20.$(date +%F-%H%M%S).log
exec > >(tee -a "$LOG") 2>&1

log()  { printf "[ipu6_install_v20] %s\n" "$*"; }
warn() { printf "[ipu6_install_v20][WARN] %s\n" "$*" >&2; }
err()  { printf "[ipu6_install_v20][ERROR] %s\n" "$*" >&2; exit 1; }

trap 'err "Script failed at line $LINENO. See $LOG"' ERR

KREL="$(uname -r)"
log "Kernel: $KREL"

# ---------- helpers ----------
have_pkg() { dpkg -s "$1" >/dev/null 2>&1; }
have_bin() { command -v "$1" >/dev/null 2>&1; }
has_symbol_in() { local so="$1" sym="$2"; strings -a "$so" 2>/dev/null | grep -q "$sym"; }

# ---------- 0. Sanity cleanup ----------
log "Sanity cleanup (dpkg/apt)…"
dpkg --configure -a || true
DEBIAN_FRONTEND=noninteractive apt-get -f install -y || true
apt-get update -y || true

# ---------- 1. Base tools ----------
log "Installing base tools…"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl wget gnupg software-properties-common \
  gstreamer1.0-tools v4l-utils gzip || true

# ---------- 2. Verify IPU6 kernel side (don’t abort if absent) ----------
if lsmod | grep -q '^intel_ipu6'; then
  log "IPU6 kernel modules are loaded."
else
  if [ -e /dev/media0 ] || dmesg | grep -q 'intel-ipu6 .*Connected 1 cameras'; then
    warn "intel_ipu6 not in lsmod, but nodes/messages exist. Continuing."
  else
    warn "intel_ipu6 modules not seen. If this kernel normally loads them, continue; otherwise reboot the kernel that does."
  fi
fi

# ---------- 3. Ensure Intel HAL + icamerasrc from OEM PPA (names that exist on Jammy) ----------
if ! have_pkg gstreamer1.0-icamera || ! have_pkg libcamhal0; then
  log "Adding Intel IPU6 OEM PPA (if missing) and installing HAL + icamerasrc…"
  add-apt-repository -y ppa:oem-solutions-group/intel-ipu6 || true
  apt-get update -y || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    gstreamer1.0-icamera libcamhal0 libcamhal-common libcamhal-ipu6ep0 || true
else
  log "Intel HAL & icamerasrc already present; not changing them."
fi

# ---------- 4. v4l2loopback for a virtual camera ----------
log "Ensuring v4l2loopback-dkms is installed and module loaded…"
DEBIAN_FRONTEND=noninteractive apt-get install -y v4l2loopback-dkms || true
# Reload with sane defaults (video10, label Virtual Camera, exclusive caps for browsers)
modprobe -r v4l2loopback 2>/dev/null || true
modprobe v4l2loopback video_nr=10 card_label="Virtual Camera" exclusive_caps=1 2>/dev/null || true

# ---------- 5. libstdc++ overlay with GLIBCXX_3.4.32 (no system replacement) ----------
OVERLAY=/opt/ipu6-stdc++-overlay
TARGET_SO="$OVERLAY/usr/lib/x86_64-linux-gnu/libstdc++.so.6"
SYMBOL="GLIBCXX_3.4.32"

# Check system libstdc++ first
SYS_SO="$(ldconfig -p | awk '/libstdc\+\+\.so\.6 \(/{print $NF; exit}' || true)"
if [ -n "${SYS_SO:-}" ] && has_symbol_in "$SYS_SO" "$SYMBOL"; then
  log "System libstdc++ already provides $SYMBOL."
else
  if [ -f "$TARGET_SO" ] && has_symbol_in "$TARGET_SO" "$SYMBOL"; then
    log "Overlay libstdc++ already present with $SYMBOL."
  else
    log "Building libstdc++ overlay (Jammy build from Ubuntu Toolchain PPA)…"
    add-apt-repository -y ppa:ubuntu-toolchain-r/test || true
    apt-get update -y || true

    mkdir -p /tmp/ipu6-stdcpp && cd /tmp/ipu6-stdcpp
    # Pull the Packages index and find the newest libstdc++6 .deb for jammy/amd64
    BASE="https://ppa.launchpadcontent.net/ubuntu-toolchain-r/test/ubuntu"
    PKGZ="$BASE/dists/jammy/main/binary-amd64/Packages.gz"
    curl -fsSL "$PKGZ" -o Packages.gz
    gunzip -f Packages.gz
    DEB_PATH="$(awk '
      $1=="Package:" && $2=="libstdc++6"{hit=1}
      hit && $1=="Filename:"{print $2; exit}
    ' Packages || true)"

    if [ -z "${DEB_PATH:-}" ]; then
      err "Could not locate libstdc++6 in the Toolchain PPA Packages file."
    fi

    DEB_URL="$BASE/$DEB_PATH"
    log "Downloading $DEB_URL"
    curl -fsSL "$DEB_URL" -o libstdcpp.deb

    log "Extracting into overlay: $OVERLAY"
    rm -rf "$OVERLAY"
    mkdir -p "$OVERLAY"
    dpkg -x libstdcpp.deb "$OVERLAY"

    if [ ! -f "$TARGET_SO" ] || ! has_symbol_in "$TARGET_SO" "$SYMBOL"; then
      err "Overlay libstdc++ still missing $SYMBOL. Aborting."
    fi
    log "Overlay libstdc++ exports $SYMBOL."
  fi
fi

# ---------- 6. Small wrappers to always load the overlay ----------
ENV_WRAPPER=/usr/local/bin/icamera-env
cat > "$ENV_WRAPPER" <<'EOS'
#!/usr/bin/env bash
OVERLAY=/opt/ipu6-stdc++-overlay/usr/lib/x86_64-linux-gnu
export LD_LIBRARY_PATH="${OVERLAY}:${LD_LIBRARY_PATH:-}"
exec "$@"
EOS
chmod +x "$ENV_WRAPPER"

PREVIEW=/usr/local/bin/icamera-preview
cat > "$PREVIEW" <<'EOS'
#!/usr/bin/env bash
# Live preview from Intel IPU6 via icamerasrc
# Usage: sudo icamera-preview [width height framerate sensor_id]
W=${1:-1280}; H=${2:-720}; F=${3:-30}; SID=${4:-0}
OVERLAY=/opt/ipu6-stdc++-overlay/usr/lib/x86_64-linux-gnu
export LD_LIBRARY_PATH="${OVERLAY}:${LD_LIBRARY_PATH:-}"
exec gst-launch-1.0 -v icamerasrc sensor_id=${SID} ! video/x-raw,format=NV12,width=${W},height=${H},framerate=${F}/1 ! \
    v4l2convert ! autovideosink sync=false
EOS
chmod +x "$PREVIEW"

VIRT=/usr/local/bin/icamera-virtcam
cat > "$VIRT" <<'EOS'
#!/usr/bin/env bash
# Feed IPU6 into v4l2loopback (/dev/video10) for browsers
# Usage: sudo icamera-virtcam [width height framerate sensor_id device]
W=${1:-1280}; H=${2:-720}; F=${3:-30}; SID=${4:-0}; DEV=${5:-/dev/video10}
OVERLAY=/opt/ipu6-stdc++-overlay/usr/lib/x86_64-linux-gnu
export LD_LIBRARY_PATH="${OVERLAY}:${LD_LIBRARY_PATH:-}"
exec gst-launch-1.0 -v icamerasrc sensor_id=${SID} ! video/x-raw,format=NV12,width=${W},height=${H},framerate=${F}/1 ! \
    v4l2convert ! v4l2sink device=${DEV} sync=false
EOS
chmod +x "$VIRT"

log "Done."
log "Next steps:"
log "  1) icamera-env gst-inspect-1.0 icamerasrc | head"
log "  2) icamera-preview          # live window"
log "  3) icamera-virtcam          # fills /dev/video10 for browsers"
