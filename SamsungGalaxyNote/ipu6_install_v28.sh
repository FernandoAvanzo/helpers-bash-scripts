#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/ipu6_install_v28.$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log(){ echo "[ipu6_install_v28] $*"; }

# 0) Basics and locations
OVERLAY=/opt/ipu6-rt/overlay
OLIB="$OVERLAY/lib"
BIN=/usr/local/bin
mkdir -p "$OLIB" "$BIN"

log "Kernel: $(uname -r)"
log "Checking IPU6 nodes (kernel side)…"
if ! ls /dev/video* /dev/media* 1>/dev/null 2>&1; then
  log "No /dev/video* or /dev/media* nodes. Kernel/IPU6 not active. Abort."
  exit 1
fi
log "OK: video/media nodes exist."

log "Base tools…"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl wget gstreamer1.0-tools v4l-utils binutils xz-utils

log "Ensure v4l2loopback-dkms is present (non-fatal if already)…"
DEBIAN_FRONTEND=noninteractive apt-get install -y v4l2loopback-dkms || true

# 1) Fetch exact GCC 13.2 runtime from Ubuntu pool
TMPD=$(mktemp -d)
cleanup(){ rm -rf "$TMPD"; }
trap cleanup EXIT

# Jammy-compatible GCC-13.2 runtime from Ubuntu pool (no PPA required)
LIBSTD_URL="http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-13/libstdc++6_13.2.0-4ubuntu3_amd64.deb"
LIBGCC_URL="http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-13/libgcc-s1_13.2.0-4ubuntu3_amd64.deb"

log "Downloading libgcc-s1 and libstdc++6 13.2.0 from Ubuntu pool…"
wget -qO "$TMPD/libgcc.deb" "$LIBGCC_URL"
wget -qO "$TMPD/libstdc++.deb" "$LIBSTD_URL"

log "Unpacking into overlay: $OLIB"
pushd "$TMPD" >/dev/null
ar x libgcc.deb  && tar -xf data.tar.* || true
ar x libstdc++.deb && tar -xf data.tar.* || true
popd >/dev/null

# Copy only the runtime .so files we need
find "$TMPD" -type f \( -name "libgcc_s.so*" -o -name "libstdc++.so*" \) -exec cp -av {} "$OLIB"/ \;

# Keep sane symlinks in overlay
pushd "$OLIB" >/dev/null
# point libstdc++.so.6 -> highest real soname present
if [ -f libstdc++.so.6.0.32 ]; then
  ln -sf libstdc++.so.6.0.32 libstdc++.so.6
fi
if [ -f libgcc_s.so.1 ]; then
  ln -sf libgcc_s.so.1 libgcc_s.so
fi
popd >/dev/null

# 2) Verify GLIBCXX_3.4.32 actually exists in the overlay
log "Verifying GLIBCXX_3.4.32 in overlay libstdc++…"
if ! strings -a "$OLIB/libstdc++.so.6" | grep -q "GLIBCXX_3\.4\.32"; then
  log "[ERROR] Overlay libstdc++ does not export GLIBCXX_3.4.32."
  log "        Check network and that files came from the Ubuntu pool above."
  exit 1
fi
log "OK: overlay libstdc++ exports GLIBCXX_3.4.32."

# 3) Create wrappers so only camera tools use the overlay
make_wrapper(){
  local name="$1"; shift
  local target="$*"
  cat > "$BIN/$name" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
OLIB="/opt/ipu6-rt/overlay/lib"
# Also include system lib dirs so HAL/IA-PAL in /lib keep resolving
export LD_LIBRARY_PATH="$OLIB:/lib/x86_64-linux-gnu:/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
exec "$@"
EOF
  chmod +x "$BIN/$name"
}

log "Creating wrappers in $BIN …"
make_wrapper icamera-env /usr/bin/env
make_wrapper gst-inspect-icamera /usr/bin/gst-inspect-1.0
make_wrapper gst-launch-icamera /usr/bin/gst-launch-1.0

# 4) Tiny helper to show if the HAL now resolves
cat > "$BIN/ipu6-hal-ldd" <<'EOF'
#!/usr/bin/env bash
set -e
OLIB="/opt/ipu6-rt/overlay/lib"
export LD_LIBRARY_PATH="$OLIB:/lib/x86_64-linux-gnu:/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
ldd /usr/lib/libcamhal/plugins/ipu6epmtl.so || true
ldd /lib/libbroxton_ia_pal-ipu6epmtl.so.0 || true
EOF
chmod +x "$BIN/ipu6-hal-ldd"

log "Done. Next steps (run as your normal user):"
cat <<'EONEXT'
  # 1) Check HAL resolves with the overlay:
     sudo ipu6-hal-ldd

  # 2) Probe the plugin:
     gst-inspect-icamera icamerasrc | head -n 30

  # 3) Try a simple capture (window):
     gst-launch-icamera -v icamerasrc ! videoconvert ! autovideosink

  # 4) If you need a virtual cam for browsers later, load v4l2loopback like:
     sudo modprobe v4l2loopback exclusive_caps=1 video_nr=10 card_label="Virtual Camera"
EONEXT
