#!/usr/bin/env bash
set -Eeuo pipefail

ME="[ipu6_install_v23]"
log(){ echo "${ME} $*"; }
warn(){ echo "${ME}[WARN] $*" >&2; }
err(){ echo "${ME}[ERROR] $*" >&2; exit 1; }

# --- constants
KVER="$(uname -r)"
OVERLAY_ROOT="/opt/ipu6-rt"
MAMBA_BIN="${OVERLAY_ROOT}/bin/micromamba"
ENV_PREFIX="${OVERLAY_ROOT}/env"
WRAPPER="/usr/local/bin/icamera-env"

log "Kernel: ${KVER}"
SUDO_USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
SUDO_HOME="$(getent passwd "$SUDO_USER_NAME" | cut -d: -f6 || echo /root)"
log "SUDO_USER: ${SUDO_USER_NAME}  HOME: ${SUDO_HOME}"

# --- 0) quick sanity: ipu6 nodes / messages
if ! ls /dev/video* >/dev/null 2>&1; then
  warn "No /dev/video* nodes visible. If this is a fresh boot, try: sudo dmesg | egrep -i 'ipu6|ov02c10|cse|authenticate' to confirm kernel side."
fi

# try to show the two well-known good lines you've seen
if ! dmesg | egrep -q 'intel-ipu6 .*Found supported sensor|CSE authenticate_run done' ; then
  warn "Didn't see expected IPU6 success lines in dmesg; you previously had them, so continuing."
fi

# --- 1) keep the good: v4l2loopback (for browsers)
log "Ensuring v4l2loopback-dkms is present and a device is loaded…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null || true
apt-get install -y v4l2loopback-dkms >/dev/null || true

# load a predictable virtual device (safe if already present)
if ! lsmod | grep -q '^v4l2loopback'; then
  modprobe v4l2loopback video_nr=10 card_label="Virtual Camera" exclusive_caps=1 || true
fi
# show it
if v4l2-ctl --list-devices 2>/dev/null | grep -q "Virtual Camera"; then
  log "v4l2loopback OK at /dev/video10"
else
  warn "v4l2loopback didn't enumerate yet; check dmesg if needed."
fi

# --- 2) HAL and icamerasrc: leave them as-is (you already installed from Intel PPA)
if ! gst-inspect-1.0 icamerasrc >/dev/null 2>&1; then
  warn "GStreamer 'icamerasrc' isn't inspectable yet (expected until we overlay libstdc++)."
fi

# --- 3) create a safe runtime overlay of libstdc++ with GLIBCXX_3.4.32
log "Preparing micromamba-based runtime overlay for libstdc++ (no system replacement)…"

mkdir -p "${OVERLAY_ROOT}/bin"

if [ ! -x "${MAMBA_BIN}" ]; then
  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' EXIT
  log "Downloading micromamba (static, Linux x86_64)…"
  # official micromamba delivery endpoint
  curl -fsSL https://micro.mamba.pm/api/micromamba/linux-64/latest -o "${TMPD}/micromamba.tar.bz2"
  tar -xjf "${TMPD}/micromamba.tar.bz2" -C "${TMPD}"
  install -m 0755 "${TMPD}/bin/micromamba" "${MAMBA_BIN}"
  rm -rf "$TMPD"
fi

# Create a tiny env holding just modern libstdc++
# Note: we pin to GCC 14 series; conda-forge Linux packages use an old glibc sysroot, so they run on Jammy.
if [ ! -d "${ENV_PREFIX}" ]; then
  log "Creating env at ${ENV_PREFIX} with libstdcxx-ng (GCC 14) and libgcc-ng…"
  "${MAMBA_BIN}" create -y -p "${ENV_PREFIX}" -c conda-forge libstdcxx-ng=14.* libgcc-ng >/dev/null
else
  log "Env already present at ${ENV_PREFIX}; leaving it."
fi

# find the library path in the env (usually ${ENV_PREFIX}/lib)
LIBDIR="$(dirname "$(readlink -f "${ENV_PREFIX}/lib/libstdc++.so.6")" || echo "${ENV_PREFIX}/lib")"
[ -f "${LIBDIR}/libstdc++.so.6" ] || err "Overlay libstdc++.so.6 not found in ${ENV_PREFIX}"

# verify the symbol we need
if ! strings "${LIBDIR}/libstdc++.so.6" | grep -q 'GLIBCXX_3\.4\.32'; then
  err "Overlay libstdc++ does not export GLIBCXX_3.4.32 (wrong version got installed)."
fi
log "Overlay libstdc++ exports GLIBCXX_3.4.32 ✔"

# --- 4) install a wrapper so only selected commands use the overlay
log "Installing ${WRAPPER} to launch camera apps with the overlay…"
cat > "${WRAPPER}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
OVER="${LIBDIR}"
export LD_LIBRARY_PATH="\${OVER}:\${LD_LIBRARY_PATH:-}"
exec "\$@"
EOF
chmod +x "${WRAPPER}"

# --- 5) helpful test scripts (do not auto-run to avoid surprises)
TEST_LIST="${OVERLAY_ROOT}/icamera-inspect.sh"
TEST_PREVIEW="${OVERLAY_ROOT}/icamera-preview.sh"
TEST_TO_V4L2="${OVERLAY_ROOT}/icamera-to-v4l2.sh"

cat > "${TEST_LIST}" <<'EOF'
#!/usr/bin/env bash
exec /usr/local/bin/icamera-env gst-inspect-1.0 icamerasrc
EOF
chmod +x "${TEST_LIST}"

cat > "${TEST_PREVIEW}" <<'EOF'
#!/usr/bin/env bash
# Basic live preview using the overlay
exec /usr/local/bin/icamera-env gst-launch-1.0 -v icamerasrc ! \
  video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! \
  videoconvert ! autovideosink
EOF
chmod +x "${TEST_PREVIEW}"

cat > "${TEST_TO_V4L2}" <<'EOF'
#!/usr/bin/env bash
# Feed the virtual /dev/video10 for browser use
sudo modprobe v4l2loopback video_nr=10 card_label="Virtual Camera" exclusive_caps=1 || true
exec /usr/local/bin/icamera-env gst-launch-1.0 icamerasrc ! \
  video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! \
  v4l2convert ! v4l2sink device=/dev/video10
EOF
chmod +x "${TEST_TO_V4L2}"

log "Done. Next steps:"
echo "  1) ${TEST_LIST}           # icamerasrc should list OK (no GLIBCXX error)."
echo "  2) ${TEST_PREVIEW}        # shows a live preview window."
echo "  3) ${TEST_TO_V4L2}        # then choose \"Virtual Camera\" in your browser/app."
