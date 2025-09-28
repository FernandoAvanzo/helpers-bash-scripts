#!/usr/bin/env bash
set -euo pipefail

log(){ printf "[ipu6_install_v30] %s\n" "$*"; }

# --- 0) Non-destructive sanity ------------------------------------------------
KVER="$(uname -r)"
log "Kernel: $KVER"
if ! ls /dev/video* >/dev/null 2>&1; then
  log "[WARN] No /dev/video* found. Kernel side may not be up; continuing anyway."
fi

# --- 1) Base tools (non-invasive) --------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq curl wget xz-utils binutils gstreamer1.0-tools v4l-utils >/dev/null

# --- 2) v4l2loopback present is OK (no-op if already) ------------------------
apt-get install -y -qq v4l2loopback-dkms >/dev/null || true

# --- 3) Prepare overlay root --------------------------------------------------
ROOT="/opt/ipu6-rt"
OLIB="$ROOT/overlay/lib"
MMBIN="$ROOT/mm/bin/micromamba"
ENV="$ROOT/env"
mkdir -p "$OLIB"
mkdir -p "$(dirname "$MMBIN")"

# --- 4) Fetch micromamba (static) if missing ---------------------------------
if [ ! -x "$MMBIN" ]; then
  log "Downloading micromamba (static)…"
  TMP=$(mktemp -d)
  curl -fsSL "https://micro.mamba.pm/api/micromamba/linux-64/latest" -o "$TMP/mm.tar.bz2"
  tar -xjf "$TMP/mm.tar.bz2" -C "$TMP"
  # find the binary inside the tarball (layout may vary slightly over time)
  MMB=$(find "$TMP" -type f -path "*/bin/micromamba" | head -n1)
  install -Dm755 "$MMB" "$MMBIN"
  rm -rf "$TMP"
fi

# --- 5) Create/refresh env with EXACT GCC 13.2 runtime -----------------------
log "Creating env at $ENV with libstdcxx-ng=13.2.0 and libgcc-ng=13.2.0 (conda-forge)…"
/usr/bin/env -i "$MMBIN" create -y -p "$ENV" -c conda-forge \
  libstdcxx-ng=13.2.0 libgcc-ng=13.2.0 >/dev/null

# --- 6) Stage libraries into overlay and verify symbol -----------------------
# Copy libstdc++ and libgcc_s from the env into our overlay
find "$ENV" -name "libstdc++.so.6*" -exec cp -av "{}" "$OLIB"/ \; >/dev/null
find "$ENV" -name "libgcc_s.so.1"     -exec cp -av "{}" "$OLIB"/ \; >/dev/null

# Ensure we have the real .so and a friendly soname symlink if needed
REAL=$(ls "$OLIB"/libstdc++.so.6.* 2>/dev/null | head -n1 || true)
if [ -n "${REAL:-}" ]; then
  ln -sf "$(basename "$REAL")" "$OLIB/libstdc++.so.6"
fi

# Verify GLIBCXX_3.4.32 exists
if ! strings -a "$OLIB/libstdc++.so.6" | grep -q 'GLIBCXX_3\.4\.32'; then
  log "[ERROR] Overlay libstdc++ does NOT export GLIBCXX_3.4.32."
  log "        Trying a secondary install with libstdcxx-ng=14.1 (should include older symbols too)…"
  "$MMBIN" install -y -p "$ENV" -c conda-forge libstdcxx-ng=14.1.0 libgcc-ng >/dev/null
  find "$ENV" -name "libstdc++.so.6*" -exec cp -av "{}" "$OLIB"/ \; >/dev/null
  find "$ENV" -name "libgcc_s.so.1"     -exec cp -av "{}" "$OLIB"/ \; >/dev/null
  REAL=$(ls "$OLIB"/libstdc++.so.6.* 2>/dev/null | head -n1 || true)
  [ -n "${REAL:-}" ] && ln -sf "$(basename "$REAL")" "$OLIB/libstdc++.so.6"
fi

if ! strings -a "$OLIB/libstdc++.so.6" | grep -q 'GLIBCXX_3\.4\.32'; then
  log "[FATAL] Still missing GLIBCXX_3.4.32 in overlay libstdc++. Aborting."
  exit 1
fi
log "Overlay exports GLIBCXX_3.4.32 — good."

# --- 7) Helper wrappers (per-process LD_LIBRARY_PATH only) -------------------
install -Dm755 /dev/stdin /usr/local/bin/ipu6-env-run <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export LD_LIBRARY_PATH="/opt/ipu6-rt/overlay/lib${LD_LIBRARY_PATH+:$LD_LIBRARY_PATH}"
exec "$@"
EOF

install -Dm755 /dev/stdin /usr/local/bin/icamera-inspect <<'EOF'
#!/usr/bin/env bash
exec /usr/local/bin/ipu6-env-run gst-inspect-1.0 icamerasrc
EOF

install -Dm755 /dev/stdin /usr/local/bin/icamera-preview <<'EOF'
#!/usr/bin/env bash
# Simple preview. Use Ctrl+C to exit.
exec /usr/local/bin/ipu6-env-run gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink
EOF

install -Dm755 /dev/stdin /usr/local/bin/icamera-bridge <<'EOF'
#!/usr/bin/env bash
# Feed the hardware camera into a v4l2loopback device (default /dev/video10) for browsers.
DEV="${1:-/dev/video10}"
# Ensure the loopback exists
sudo modprobe v4l2loopback devices=1 video_nr="${DEV##*/video}" exclusive_caps=1 card_label="Virtual Camera" || true
exec /usr/local/bin/ipu6-env-run gst-launch-1.0 icamerasrc ! videoconvert ! v4l2sink device="$DEV"
EOF

log "Done. Try:"
echo "  icamera-inspect"
echo "  icamera-preview"
echo "  icamera-bridge   # to create a browser-visible virtual camera"
