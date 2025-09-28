#!/usr/bin/env bash
set -Eeuo pipefail

LOG="/var/log/ipu6_install_v24.$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log(){ printf "[ipu6_install_v24] %s\n" "$*"; }
warn(){ printf "[ipu6_install_v24][WARN] %s\n" "$*" >&2; }
err(){ printf "[ipu6_install_v24][ERROR] %s\n" "$*" >&2; exit 1; }

KVER="$(uname -r)"
log "Kernel: $KVER"

# --- 0) Light sanity (keep previous good state) -------------------------------
# We do NOT touch kernel modules or HAL if they’re there.
# Your dmesg already shows IPU6 OK; we just warn if not visible.
if ! dmesg | grep -E "intel-ipu6.*Found supported sensor|CSE authenticate_run done" -q; then
  warn "Didn't spot the usual IPU6 success lines in dmesg; continuing because your /dev nodes exist."
fi

# Make sure v4l2loopback is available (already installed on your machine).
log "Ensuring v4l2loopback-dkms is present (no-op if already installed)…"
DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq v4l2loopback-dkms || true

# Don’t reinstall icamera/HAL if they exist (we keep the working parts).
if dpkg -l | grep -qE "gstreamer1.0-icamera|libcamhal"; then
  log "Intel HAL & icamerasrc already present; leaving them untouched."
else
  warn "Intel HAL/icamerasrc not found via dpkg. If needed later, follow the Ubuntu Intel MIPI guide."
fi

# --- 1) Build a libstdc++ **overlay** (no system replacement) -----------------
# Goal: provide GLIBCXX_3.4.32 for the Intel PAL library required by ipu6epmtl plugin.
# Strategy:
#   A) Try micromamba (conda-forge) with **pinned** libstdcxx-ng=13.2.0 and strict channels.
#   B) If A fails, fetch Ubuntu 24.04+ (noble) or 24.10 (oracular) libstdc++6 .deb from pool,
#      extract into /opt/ipu6-rt/lib and use via LD_LIBRARY_PATH.

BASE="/opt/ipu6-rt"
OLIB="$BASE/lib"
ENV="$BASE/env"
MM="$BASE/micromamba"

mkdir -p "$OLIB"

have_glibcxx32(){
  local so="$1"
  [[ -r "$so" ]] || return 1
  strings -a "$so" | grep -q "GLIBCXX_3.4.32"
}

pick_conda_lib(){
  # Find the first libstdc++.so.6 in env
  find "$ENV" -type f -name 'libstdc++.so.6*' -print -quit 2>/dev/null || true
}

conclude_overlay(){
  local so="$1"
  [[ -e "$so" ]] || return 1
  rm -f "$OLIB/libstdc++.so.6" "$OLIB"/libstdc++.so.6.*
  cp -av "$so" "$OLIB/"
  local base="$(basename "$so")"
  if [[ "$base" != "libstdc++.so.6" ]]; then
    ln -s "$base" "$OLIB/libstdc++.so.6"
  fi
  log "Overlay prepared at $OLIB ($(basename "$so"))."
  log "Overlay GLIBCXX versions available:"
  strings -a "$OLIB"/libstdc++.so.6* | grep -o "GLIBCXX_[0-9.]*" | sort -u | xargs echo
}

# A) micromamba exact pin (13.2.0) from conda-forge
log "Preparing micromamba overlay (conda-forge, libstdcxx-ng=13.2.0)…"
if [[ ! -x "$MM" ]]; then
  curl -fsSL https://micro.mamba.pm/api/micromamba/linux-64/latest -o "$BASE/mm.tar.bz2"
  mkdir -p "$BASE/mm"
  tar -xjf "$BASE/mm.tar.bz2" -C "$BASE/mm" --strip-components=1
  cp "$BASE/mm/bin/micromamba" "$MM"
  chmod +x "$MM"
fi

# Create/replace env cleanly
rm -rf "$ENV"
"$MM" create -y -p "$ENV" -c conda-forge --strict-channel-priority libstdcxx-ng=13.2.0 libgcc-ng=13.2.0 >/dev/null

CAND="$(pick_conda_lib || true)"
if [[ -n "${CAND:-}" ]] && have_glibcxx32 "$CAND"; then
  conclude_overlay "$CAND"
else
  warn "Conda libstdc++ did not expose GLIBCXX_3.4.32; trying Ubuntu pool fallback…"

  # B) fetch from Ubuntu pools (noble/oracular), parse the directory index for latest libstdc++6_*.deb
  fetch_from_pool(){
    local pool_url="$1"
    local tmpdir; tmpdir="$(mktemp -d)"
    log "Scanning $pool_url for libstdc++6…"
    if ! curl -fsSL "$pool_url" -o "$tmpdir/index.html"; then
      rm -rf "$tmpdir"; return 1
    fi
    local deb
    deb="$(grep -oE 'libstdc\+\+6_[^"]+amd64\.deb' "$tmpdir/index.html" | sort -V | tail -1 || true)"
    [[ -n "$deb" ]] || { rm -rf "$tmpdir"; return 1; }
    log "Found candidate: $deb"
    local url="$pool_url$deb"
    local debfile="/tmp/$deb"
    curl -fL "$url" -o "$debfile" || { rm -rf "$tmpdir"; return 1; }
    rm -rf "$BASE/overlay" && mkdir -p "$BASE/overlay"
    dpkg-deb -x "$debfile" "$BASE/overlay"
    local so
    so="$(find "$BASE/overlay/usr/lib/x86_64-linux-gnu" -maxdepth 1 -name 'libstdc++.so.6*' -type f -print -quit || true)"
    if [[ -n "$so" ]] && have_glibcxx32 "$so"; then
      conclude_overlay "$so"
      rm -rf "$tmpdir"
      return 0
    fi
    rm -rf "$tmpdir"; return 1
  }

  # Try gcc-14 first (Ubuntu 24.04+), then gcc-13
  POOL14="http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-14/"
  POOL13="http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-13/"
  if ! fetch_from_pool "$POOL14"; then
    warn "gcc-14 pool attempt failed; trying gcc-13 pool…"
    fetch_from_pool "$POOL13" || err "Could not obtain a libstdc++6 with GLIBCXX_3.4.32 from Ubuntu pools."
  fi
fi

# --- 2) Create wrappers to run icamera with the overlay -----------------------
WRAPDIR="/usr/local/bin"
mkdir -p "$WRAPDIR"

cat > "$WRAPDIR/icamera-preview" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
BASE="/opt/ipu6-rt"
export LD_LIBRARY_PATH="$BASE/lib:/usr/lib/libcamhal:/usr/lib:$LD_LIBRARY_PATH"
# Show a quick capability dump (helps debugging)
gst-inspect-1.0 icamerasrc | sed -n '1,40p' || true
# Try a 720p preview (autovideosink picks a sink; OK if it falls back to xvimagesink)
exec gst-launch-1.0 -v icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! videoconvert ! autovideosink
SH
chmod +x "$WRAPDIR/icamera-preview"

cat > "$WRAPDIR/icamera-to-virtual" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
BASE="/opt/ipu6-rt"
export LD_LIBRARY_PATH="$BASE/lib:/usr/lib/libcamhal:/usr/lib:$LD_LIBRARY_PATH"
# Ensure a loopback device exists (uses existing if already loaded)
if ! lsmod | grep -q v4l2loopback; then sudo modprobe v4l2loopback exclusive_caps=1 card_label="Virtual Camera"; fi
DEV="$(v4l2-ctl --list-devices 2>/dev/null | awk '/Virtual Camera/{getline; print $1; exit}')"
: "${DEV:=/dev/video10}"
echo "Streaming to $DEV … (Ctrl+C to stop)"
exec gst-launch-1.0 -v icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! videoconvert ! v4l2sink device="$DEV"
SH
chmod +x "$WRAPDIR/icamera-to-virtual"

log "Done. Use:
  • icamera-preview        # local preview using the overlay
  • icamera-to-virtual     # pipe to a /dev/video* loopback for browsers"

# A tiny postcheck: verify the overlay is actually used by the plugin
if command -v ldd >/dev/null; then
  log "Checking which libstdc++ icamerasrc will see under overlay:"
  LD_LIBRARY_PATH="$OLIB:/usr/lib/libcamhal:/usr/lib:$LD_LIBRARY_PATH" ldd /usr/lib/libcamhal/plugins/ipu6epmtl.so | grep -E 'libstdc\+\+|broxton|camhal' || true
fi
