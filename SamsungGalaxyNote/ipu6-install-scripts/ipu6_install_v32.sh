#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/ipu6_install_v32.$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log() { printf '[ipu6_install_v32] %s\n' "$*"; }

OVERLAY="/opt/ipu6-rt/overlay/lib"
WRAPDIR="/usr/local/bin"

log "Kernel: $(uname -r)"

# 0) Quick kernel-side sanity: IPU6 video/media nodes exist?
log "Checking IPU6 nodes (kernel side)…"
if ls /dev/video* /dev/media* >/dev/null 2>&1; then
  log "OK: video/media nodes exist."
else
  log "WARN: no /dev/video* or /dev/media* found; kernel side may not be up."
fi

# 1) Base tools and v4l utilities (idempotent)
log "Installing base tools (curl, wget, binutils, dpkg-dev, v4l-utils, gstreamer1.0-tools)…"
apt-get update -y || true
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl wget binutils dpkg-dev v4l-utils gstreamer1.0-tools || true

# 2) Ensure v4l2loopback (idempotent)
log "Ensuring v4l2loopback-dkms is present (non-fatal if already)…"
DEBIAN_FRONTEND=noninteractive apt-get install -y v4l2loopback-dkms || true

# 3) Prepare overlay
log "Preparing overlay at $OVERLAY …"
mkdir -p "$OVERLAY"
chmod 755 /opt/ipu6-rt /opt/ipu6-rt/overlay "$OVERLAY"

# 4) Try to reuse a vendor-bundled libstdc++ (Chrome/Steam/etc.) first
log "Searching local bundled libstdc++ candidates (Chrome, Steam)…"
FOUND_STDCPP=""
for CAND in \
/usr/lib/chromium-browser/lib/libstdc++.so.6 \
/opt/google/chrome/lib/libstdc++.so.6 \
"$HOME/.local/share/Steam/ubuntu12_64/steam-runtime/usr/lib/x86_64-linux-gnu/libstdc++.so.6" \
"$HOME/.steam/steam/ubuntu12_64/steam-runtime/usr/lib/x86_64-linux-gnu/libstdc++.so.6" \
/opt/*/libstdc++.so.6; do
  [[ -f "$CAND" ]] || continue
  if strings "$CAND" 2>/dev/null | grep -q 'GLIBCXX_3\.4\.32'; then
    FOUND_STDCPP="$CAND"
    break
  fi
done

if [[ -n "$FOUND_STDCPP" ]]; then
  log "Found suitable local libstdc++ at: $FOUND_STDCPP"
  install -m 0644 "$FOUND_STDCPP" "$OVERLAY/libstdc++.so.6"
else
  # 5) Fetch Ubuntu Noble (24.04) libgcc-s1 & libstdc++6 and extract
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  # Prefer current Noble point release; adjust if mirrors rename. Two candidates:
  U_LIBGCC="http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-14/libgcc-s1_14.2.0-4ubuntu2~24.04_amd64.deb"
  U_LIBSTD="http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-14/libstdc++6_14.2.0-4ubuntu2~24.04_amd64.deb"

  log "Downloading libgcc-s1 and libstdc++6 (Ubuntu 24.04) into $TMP…"
  (cd "$TMP" && wget -q "$U_LIBGCC" -O libgcc.deb && wget -q "$U_LIBSTD" -O libstdcxx.deb)

  log "Extracting only the needed .so files into overlay (path-agnostic)…"
  mkdir -p "$TMP/u1" "$TMP/u2"
  dpkg-deb -x "$TMP/libgcc.deb"   "$TMP/u1"
  dpkg-deb -x "$TMP/libstdcxx.deb" "$TMP/u2"

  # Find real files regardless of lib/ vs usr/lib location
  GCCCAND="$(find "$TMP/u1" -type f -name 'libgcc_s.so.1' | head -n1 || true)"
  STDCREAL="$(find "$TMP/u2" -type f -name 'libstdc++.so.6.*' | sort -V | tail -n1 || true)"
  if [[ -z "$GCCCAND" || -z "$STDCREAL" ]]; then
    echo "[ipu6_install_v32][FATAL] Could not locate shared objects inside the .debs." >&2
    exit 1
  fi

  install -m 0644 "$GCCCAND"  "$OVERLAY/libgcc_s.so.1"
  install -m 0644 "$STDCREAL" "$OVERLAY/$(basename "$STDCREAL")"
  ln -sf "$(basename "$STDCREAL")" "$OVERLAY/libstdc++.so.6"
fi

# 6) Quick symbol sanity (best-effort): should show GLIBCXX_3.4.32
if strings "$OVERLAY/libstdc++.so.6" 2>/dev/null | grep -q 'GLIBCXX_3\.4\.32'; then
  log "Overlay libstdc++ exports GLIBCXX_3.4.32 ✓"
else
  log "WARN: overlay libstdc++ did not reveal GLIBCXX_3.4.32 via strings; still proceeding to runtime test."
fi

# 7) Wrappers that prefer the overlay without touching system libs
mkdir -p "$WRAPDIR"
cat > "$WRAPDIR/gst-inspect-icamera" <<'EOF'
#!/usr/bin/env bash
export LD_LIBRARY_PATH="/opt/ipu6-rt/overlay/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec gst-inspect-1.0 icamerasrc "$@"
EOF
chmod +x "$WRAPDIR/gst-inspect-icamera"

cat > "$WRAPDIR/gst-launch-icamera" <<'EOF'
#!/usr/bin/env bash
export LD_LIBRARY_PATH="/opt/ipu6-rt/overlay/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec gst-launch-1.0 "$@"
EOF
chmod +x "$WRAPDIR/gst-launch-icamera"

cat > "$WRAPDIR/icamera-to-loopback" <<'EOF'
#!/usr/bin/env bash
# Creates a virtual /dev/video10 and feeds icamerasrc into it (Ctrl+C to stop).
set -euo pipefail
sudo modprobe v4l2loopback devices=1 exclusive_caps=1 card_label="Virtual Camera" || true
export LD_LIBRARY_PATH="/opt/ipu6-rt/overlay/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# Try a conservative caps set; adjust width/height/framerate as needed.
exec gst-launch-1.0 -e icamerasrc ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! v4l2convert ! v4l2sink device=/dev/video10
EOF
chmod +x "$WRAPDIR/icamera-to-loopback"

# 8) Smoke test: can we at least load icamerasrc’s factory with the overlay?
log "Smoke test: gst-inspect-icamera (this used to fail with GLIBCXX error)…"
if "$WRAPDIR/gst-inspect-icamera" | head -n 1; then
  log "gst-inspect-icamera ran; overlay likely correct."
  log "Tip: run 'icamera-to-loopback' to publish the camera to /dev/video10 for browsers."
else
  log "WARN: gst-inspect-icamera still failed; check the output above."
fi

log "Done. Log saved to $LOG"
