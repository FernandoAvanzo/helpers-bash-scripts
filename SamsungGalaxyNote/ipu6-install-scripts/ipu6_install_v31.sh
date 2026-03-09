#!/usr/bin/env bash
set -Eeuo pipefail

LOG_TAG="[ipu6_install_v31]"
log(){ echo "$LOG_TAG $*"; }
die(){ echo "$LOG_TAG [ERROR] $*" >&2; exit 1; }

# --- 0) Basic info ------------------------------------------------------------
KERNEL="$(uname -r)"
SUDO_USER_NAME="${SUDO_USER:-root}"
HOME_DIR="$(getent passwd "${SUDO_USER_NAME}" | cut -d: -f6 || echo /root)"
log "Kernel: $KERNEL"
log "SUDO_USER: $SUDO_USER_NAME  HOME: $HOME_DIR"

# --- 1) Sanity: IPU6 nodes present? (Kernel side OK) --------------------------
if ! ls /dev/video* /dev/media* >/dev/null 2>&1; then
  die "No /dev/video* or /dev/media* nodes found. Reboot into the kernel where IPU6 loads (your 6.16.x did)."
fi
log "IPU6 video/media nodes exist; kernel/IPU6 looks OK."

# --- 2) Tools we rely on ------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -qq || true
apt-get install -y -qq \
  curl wget ca-certificates binutils dpkg-dev gstreamer1.0-tools v4l-utils || true

command -v readelf >/dev/null 2>&1 || apt-get install -y -qq binutils >/dev/null 2>&1 || true
command -v objdump >/dev/null 2>&1 || apt-get install -y -qq binutils >/dev/null 2>&1 || true

# --- 3) v4l2loopback for browser compatibility --------------------------------
log "Ensuring v4l2loopback-dkms is present (non-fatal if already)…"
apt-get install -y -qq v4l2loopback-dkms || true
# Don't force-load here; we’ll provide a helper that modprobes with nice params.

# --- 4) Build a per-process libstdc++ overlay (no system replacement) ---------
OVERLAY="/opt/ipu6-rt/overlay"
LIBDIR="$OVERLAY/lib"
WORK="/tmp/ipu6rt.$$"
mkdir -p "$LIBDIR" "$WORK"
trap 'rm -rf "$WORK"' EXIT

# We’ll use Ubuntu Noble’s runtime (exports 3.4.32 and newer).
STD_DEB_URL="http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-14/libstdc++6_14.2.0-4ubuntu2~24.04_amd64.deb"
GCC_DEB_URL="http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-14/libgcc-s1_14.2.0-4ubuntu2~24.04_amd64.deb"

log "Downloading libgcc-s1 & libstdc++6 (Ubuntu 24.04)…"
curl -fsSL "$GCC_DEB_URL" -o "$WORK/libgcc.deb"
curl -fsSL "$STD_DEB_URL" -o "$WORK/libstdc.deb"

log "Extracting only the needed .so files into overlay…"
rm -rf "$WORK/u1" "$WORK/u2"
dpkg-deb -x "$WORK/libgcc.deb" "$WORK/u1"
dpkg-deb -x "$WORK/libstdc.deb" "$WORK/u2"

# Copy the exact shared libs
cp -f "$WORK/u1"/lib/x86_64-linux-gnu/libgcc_s.so.1 "$LIBDIR/"
cp -f "$WORK/u2"/usr/lib/x86_64-linux-gnu/libstdc++.so.6.* "$LIBDIR/"
# Create the soname symlink if needed
STD_REAL="$(basename "$(ls -1 "$LIBDIR"/libstdc++.so.6.* | sort -V | tail -n1)")"
ln -sf "$STD_REAL" "$LIBDIR/libstdc++.so.6"

# --- 5) Validate (using proper ELF introspection, not strings) ----------------
log "Checking the overlay libstdc++ version table for GLIBCXX_3.4.32…"
if objdump -T "$LIBDIR/libstdc++.so.6" | grep -q 'GLIBCXX_3\.4\.32'; then
  log "Overlay exports GLIBCXX_3.4.32 ✓"
else
  # Some builds hide it from objdump -T; try readelf --version-info as well.
  if readelf --version-info "$LIBDIR/libstdc++.so.6" 2>/dev/null | grep -q 'Name: GLIBCXX_3\.4\.32'; then
    log "Overlay exports GLIBCXX_3.4.32 (readelf) ✓"
  else
    echo
    echo "$LOG_TAG [WARN] Could not *see* GLIBCXX_3.4.32 in symbol tables."
    echo "$LOG_TAG        That check can be misleading on some builds. We’ll continue,"
    echo "$LOG_TAG        and rely on LD_PRELOAD to satisfy the HAL at runtime."
    echo
  fi
fi

# --- 6) Create robust wrappers that force the overlay into processes ----------
# master wrapper
RUN_WRAPPER="/usr/local/bin/icamera-run"
cat <<'EOF' > "$RUN_WRAPPER"
#!/usr/bin/env bash
set -Eeuo pipefail
OVER="/opt/ipu6-rt/overlay/lib"

# Ensure our overlay is first in search path
export LD_LIBRARY_PATH="${OVER}:${LD_LIBRARY_PATH:-}"

# Force our C++ runtime even if RUNPATH is set in vendor libs
if [ -f "${OVER}/libstdc++.so.6" ]; then
  if [ -n "${LD_PRELOAD:-}" ]; then
    export LD_PRELOAD="${OVER}/libstdc++.so.6:${LD_PRELOAD}"
  else
    export LD_PRELOAD="${OVER}/libstdc++.so.6"
  fi
fi

exec "$@"
EOF
chmod +x "$RUN_WRAPPER"

# gst convenience wrappers
for WRAP in gst-inspect-icamera gst-launch-icamera ; do
  cat <<'EOF' > "/usr/local/bin/${WRAP}"
#!/usr/bin/env bash
exec /usr/local/bin/icamera-run ${0%-icamera} "$@"
EOF
  chmod +x "/usr/local/bin/${WRAP}"
done

# quick loopback feeder (so browsers can see "Virtual Camera")
FEED="/usr/local/bin/start-icamera-vcam"
cat <<'EOF' > "$FEED"
#!/usr/bin/env bash
set -Eeuo pipefail
VCAM="${VCAM:-/dev/video10}"
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
FPS="${FPS:-30}"

# Make sure loopback exists
if ! lsmod | grep -q '^v4l2loopback'; then
  modprobe v4l2loopback card_label="Virtual Camera" exclusive_caps=1 video_nr="${VCAM#/dev/video}" || true
fi

# Run the pipeline through our overlay
exec /usr/local/bin/icamera-run \
  gst-launch-1.0 -v \
    icamerasrc ! video/x-raw,format=NV12,width=${WIDTH},height=${HEIGHT},framerate=${FPS}/1 \
    ! v4l2sink device="${VCAM}"
EOF
chmod +x "$FEED"

echo
log "Done. Overlay & wrappers are ready."

cat <<'NEXT'

Quick tests (use these exact wrappers so the overlay is active):

  1) Inspect plugin:
       sudo -u "$SUDO_USER" icamera-run gst-inspect-1.0 icamerasrc | head -n 20

     If you previously saw:
       /lib/x86_64-linux-gnu/libstdc++.so.6: version `GLIBCXX_3.4.32' not found
     That should be gone now.

  2) Smoke test a pipeline (no window):
       sudo -u "$SUDO_USER" icamera-run gst-launch-1.0 -v icamerasrc num-buffers=30 ! fakesink

  3) Feed a virtual camera for browsers:
       sudo -u "$SUDO_USER" start-icamera-vcam
     Then in Chrome/Firefox pick "Virtual Camera".

Notes:
- We didn’t touch your system libstdc++; the newer runtime is used only when you run via icamera-run wrappers.
- If a browser doesn’t pick frames, keep the feeder running and reselect the device. Some web apps probe formats slowly.

NEXT
