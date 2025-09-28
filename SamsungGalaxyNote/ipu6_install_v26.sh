#!/usr/bin/env bash
set -Eeuo pipefail

LOG="/var/log/ipu6_install_v26.$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log(){ echo "[ipu6_install_v26] $*"; }

SUDO_USER_NAME="${SUDO_USER:-$(id -un)}"
SUDO_HOME="$(getent passwd "$SUDO_USER_NAME" | cut -d: -f6)"

BASE="/opt/ipu6-rt"
MM="$BASE/mm/micromamba"
ENV="$BASE/env"              # conda env root
OVLLIB="$ENV/lib"            # conda lib dir (libstdc++.so.6 lives here)

log "Kernel: $(uname -r)"
log "SUDO_USER: $SUDO_USER_NAME  HOME: $SUDO_HOME"

# 0) sanity: we keep your working kernel/IPU6 state; do NOT touch it
if [[ -e /dev/media0 || -e /dev/video0 ]]; then
  log "/dev nodes exist; kernel/IPU6 likely OK."
else
  log "[WARN] IPU6 /dev nodes missing — kernel side may not be initialized; continuing anyway."
fi

# 1) base tools (minimal)
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
apt-get install -y --no-install-recommends ca-certificates curl wget gstreamer1.0-tools v4l-utils || true

# 2) v4l2loopback ensures a virtual camera exists (safe/no-op if already there)
log "Ensuring v4l2loopback-dkms is present…"
apt-get install -y --no-install-recommends v4l2loopback-dkms || true
if ! lsmod | grep -q v4l2loopback; then
  modprobe v4l2loopback devices=1 exclusive_caps=1 card_label="Virtual Camera" || true
fi
if ! v4l2-ctl --list-devices 2>/dev/null | grep -q "Virtual Camera"; then
  log "[WARN] v4l2loopback device not found; continuing (not required for direct preview)."
fi

# 3) Leave Intel HAL/icamerasrc as-is (you have them from the IPU6 PPA)
if dpkg -l | grep -q gstreamer1.0-icamera; then
  log "Intel HAL & icamerasrc already installed; not changing them."
else
  log "[WARN] Intel HAL/icamerasrc not detected by dpkg. If missing, see Ubuntu Intel MIPI camera guide."
fi

# 4) micromamba bootstrap (static tiny) + env with libstdcxx-ng=13.2.0
mkdir -p "$BASE/mm" "$ENV"

if [[ ! -x "$MM" ]]; then
  log "Downloading micromamba (static, linux-64)…"
  # documented here: https://mamba.readthedocs.io/en/latest/user_guide/micromamba.html
  # We avoid writing to $PWD; extract only the binary to $BASE/mm.
  tmpd="$(mktemp -d)"
  pushd "$tmpd" >/dev/null
  curl -fsSL "https://micro.mamba.pm/api/micromamba/linux-64/latest" | tar -xj "bin/micromamba"
  install -Dm755 "bin/micromamba" "$MM"
  popd >/dev/null
  rm -rf "$tmpd"
fi

log "Creating/updating env at $ENV with libstdcxx-ng=13.2.0 (and libgcc-ng)…"
"$MM" create -y -p "$ENV" -c conda-forge libstdcxx-ng=13.2.0 libgcc-ng >/dev/null

# 5) verify GLIBCXX_3.4.32 is present in the overlay libstdc++
SO="$OVLLIB/libstdc++.so.6"
if [[ ! -f "$SO" ]]; then
  log "[ERROR] $SO not found; micromamba env creation failed."
  exit 1
fi

if ! strings -a "$SO" | grep -q "GLIBCXX_3\.4\.32"; then
  log "[ERROR] Overlay libstdc++ does not export GLIBCXX_3.4.32. Refusing to proceed."
  log "       Check conda-forge connectivity or try rerun. (We purposely do not touch system libstdc++.)"
  exit 2
fi
log "Overlay libstdc++ exposes GLIBCXX_3.4.32 — good."

# 6) tiny wrappers that run GStreamer/hal with the overlay (no system library changes)
install -d /usr/local/bin

cat >/usr/local/bin/icamera-run <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
BASE="/opt/ipu6-rt"
ENV="$BASE/env"
OVLLIB="$ENV/lib"
# include HAL dirs just in case the loader wants to resolve them by rpath-less dlopen:
EXTRA="/usr/lib/libcamhal:/usr/lib/libcamhal/plugins"
export LD_LIBRARY_PATH="$OVLLIB:$EXTRA:${LD_LIBRARY_PATH:-}"
exec "$@"
EOF
chmod +x /usr/local/bin/icamera-run

cat >/usr/local/bin/gst-inspect-icamera <<'EOF'
#!/usr/bin/env bash
exec /usr/local/bin/icamera-run gst-inspect-1.0 icamerasrc
EOF
chmod +x /usr/local/bin/gst-inspect-icamera

cat >/usr/local/bin/gst-launch-icamera <<'EOF'
#!/usr/bin/env bash
# Basic preview pipeline (use autovideosink for on-screen test)
exec /usr/local/bin/icamera-run gst-launch-1.0 -v icamerasrc ! videoconvert ! autovideosink
EOF
chmod +x /usr/local/bin/gst-launch-icamera

log "Done. Try:  gst-inspect-icamera   and   gst-launch-icamera"
log "If you want to route into the virtual camera:  icamera-run gst-launch-1.0 icamerasrc ! videoconvert ! v4l2sink device=/dev/video10"
