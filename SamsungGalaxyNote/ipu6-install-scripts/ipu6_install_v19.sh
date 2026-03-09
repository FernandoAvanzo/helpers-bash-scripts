#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[ipu6_install_v19] $*"; }
die(){ echo "[ipu6_install_v19][ERROR] $*" >&2; exit 1; }

# Optional: allow user to hand a known-good Jammy libstdc++6 .deb (>=13.2) URL
# Example: LIBSTDCXX_DEB_URL_OVERRIDE="https://.../libstdc++6_13.2.0-*_amd64.deb" sudo ./ipu6_install_v19.sh
LIBSTDCXX_DEB_URL_OVERRIDE="${LIBSTDCXX_DEB_URL_OVERRIDE:-}"

# --- 0. Quick environment & sanity checks ------------------------------------
KREL="$(uname -r)"
log "Kernel: $KREL"

# We only warn about IPU6 modules; do NOT abort if not visible in lsmod, because DKMS/late-load is fine.
if ! lsmod | grep -Eq 'intel_ipu6(_isys)?'; then
  log "WARNING: intel_ipu6 modules not visible in lsmod. If your dmesg shows IPU6 init OK, you can continue."
fi

# Basic tools
log "Installing base tools…"
apt-get update -y -o Acquire::Retries=3 >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl wget gnupg software-properties-common \
  gstreamer1.0-tools v4l-utils || true

# APT sanity: finish any half-done dpkg transactions
log "Sanity cleanup (apt/dpkg state)…"
dpkg --configure -a || true
apt-get -f install -y || true
apt-get autoremove -y || true
apt-get clean

# --- 1. HAL/userspace presence checks ----------------------------------------
# If icamerasrc & HAL were already installed successfully earlier, do not touch them.
HAL_PLUGIN="/usr/lib/libcamhal/plugins/ipu6epmtl.so"
ICAM_PKG_OK="no"
if command -v gst-inspect-1.0 >/dev/null 2>&1; then
  if dpkg -s gstreamer1.0-icamera >/dev/null 2>&1 && [ -e "$HAL_PLUGIN" ]; then
    ICAM_PKG_OK="yes"
    log "Intel HAL & icamerasrc already present; will not change them."
  fi
fi

if [ "$ICAM_PKG_OK" = "no" ]; then
  log "Ensuring Intel IPU6 OEM PPA is present & installing icamerasrc + HAL (no upgrades)…"
  add-apt-repository -y ppa:oem-solutions-group/intel-ipu6 || true
  apt-get update -y
  # Install ONLY if not present; avoid pulling newer lib stacks unnecessarily.
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    gstreamer1.0-icamera libcamhal-common libcamhal0 libcamhal-ipu6ep0 || true

  # Re-check
  if dpkg -s gstreamer1.0-icamera >/dev/null 2>&1 && [ -e "$HAL_PLUGIN" ]; then
    ICAM_PKG_OK="yes"
  else
    log "WARNING: Could not fully install icamerasrc/HAL from PPA. Continuing (you may already have them)."
  fi
fi

# --- 2. v4l2loopback (virtual camera) ----------------------------------------
# Useful later for browsers. Safe to (re)install; DKMS builds against your running kernel.
log "Ensuring v4l2loopback-dkms is installed for this kernel…"
DEBIAN_FRONTEND=noninteractive apt-get install -y v4l2loopback-dkms || true

# --- 3. Fix libstdc++: ensure GLIBCXX_3.4.32 is available ---------------------
LIBSTDCPP_SO="$(ldconfig -p | awk '/libstdc\+\+\.so\.6 \(/{print $NF; exit}')"
has_glibcxx() { strings "$1" 2>/dev/null | grep -q 'GLIBCXX_3\.4\.32'; }

if [ -n "$LIBSTDCPP_SO" ] && has_glibcxx "$LIBSTDCPP_SO"; then
  log "Your current libstdc++ already exports GLIBCXX_3.4.32. Skipping toolchain changes."
else
  log "GLIBCXX_3.4.32 not present. Installing a newer Jammy-compatible libstdc++6…"

  # Prefer Ubuntu toolchain PPAs first (cleanest), then optional manual override.
  add_ppa_once(){
    local PPA="$1"
    if ! grep -Rqs "$PPA" /etc/apt/sources.list.d /etc/apt/sources.list; then
      add-apt-repository -y "ppa:$PPA" || true
    fi
  }

  # Try both official Ubuntu toolchain PPAs (stable & test)
  add_ppa_once "ubuntu-toolchain-r/ppa"
  add_ppa_once "ubuntu-toolchain-r/test"
  apt-get update -y

  # Try to upgrade libstdc++6 (both arch to keep multi-arch consistent)
  DEBIAN_FRONTEND=noninteractive apt-get install -y libstdc++6 libstdc++6:i386 || true

  # Re-evaluate
  LIBSTDCPP_SO="$(ldconfig -p | awk '/libstdc\+\+\.so\.6 \(/{print $NF; exit}')"
  if [ -n "$LIBSTDCPP_SO" ] && has_glibcxx "$LIBSTDCPP_SO"; then
    log "Success: GLIBCXX_3.4.32 now exported by $(basename "$LIBSTDCPP_SO")."
  else
    if [ -n "$LIBSTDCXX_DEB_URL_OVERRIDE" ]; then
      log "Attempting manual override deb: $LIBSTDCXX_DEB_URL_OVERRIDE"
      tmpdeb="$(mktemp /tmp/libstdcxx6_XXXXXX.deb)"
      curl -fsSL "$LIBSTDCXX_DEB_URL_OVERRIDE" -o "$tmpdeb" || die "Failed fetching override .deb"
      dpkg -i "$tmpdeb" || apt-get -f install -y
      rm -f "$tmpdeb"
      ldconfig
    fi

    # Final check
    LIBSTDCPP_SO="$(ldconfig -p | awk '/libstdc\+\+\.so\.6 \(/{print $NF; exit}')"
    if [ -z "$LIBSTDCPP_SO" ] || ! has_glibcxx "$LIBSTDCPP_SO"; then
      die "libstdc++6 still lacks GLIBCXX_3.4.32. Supply LIBSTDCXX_DEB_URL_OVERRIDE for a Jammy-built libstdc++6 (>=13.2)."
    else
      log "Success via override: $(basename "$LIBSTDCPP_SO") exports GLIBCXX_3.4.32."
    fi
  fi
fi

# --- 4. Quick HAL smoke test --------------------------------------------------
log "Testing HAL with gst-inspect (expect no GLIBCXX error)…"
if ! gst-inspect-1.0 icamerasrc >/dev/null 2>&1; then
  # Show the first few lines of the error for context
  set +e
  gst-inspect-1.0 icamerasrc | head -n 20
  set -e
  die "icamerasrc still failing. Re-run and inspect above error lines."
fi

# --- 5. Optional: create a virtual /dev/video feed for apps -------------------
# We'll load v4l2loopback (if not loaded) and create /dev/video10 as a sink device.
# Then you can run, e.g.:
#   gst-launch-1.0 icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 \
#      ! videoconvert ! video/x-raw,format=YUY2 ! v4l2sink device=/dev/video10
if ! lsmod | grep -q v4l2loopback; then
  modprobe v4l2loopback exclusive_caps=1 max_buffers=4 devices=1 card_label="Virtual Camera"
fi

log "Done. Try:"
echo "  gst-launch-1.0 -v icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 \\"
echo "      ! videoconvert ! video/x-raw,format=YUY2 ! v4l2sink device=/dev/video10"
echo "Then select “Virtual Camera” in Zoom/Meet/etc."
