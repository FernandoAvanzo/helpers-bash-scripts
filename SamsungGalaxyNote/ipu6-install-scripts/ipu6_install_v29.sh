#!/usr/bin/env bash
# ipu6_install_v29.sh
set -euo pipefail

LOG="/var/log/ipu6_install_v29.$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log(){ printf "[ipu6_install_v29] %s\n" "$*"; }

OVERLAY_ROOT="/opt/ipu6-rt"
OVERLAY_LIB="$OVERLAY_ROOT/overlay/usr/lib/x86_64-linux-gnu"
WRAP_DIR="/usr/local/bin"

need() { command -v "$1" >/dev/null 2>&1 || apt-get update && apt-get install -y "$1"; }

has_glibcxx_32() { strings -a "$1" 2>/dev/null | grep -q 'GLIBCXX_3\.4\.32'; }

ensure_tools(){
  log "Kernel: $(uname -r)"
  log "Installing base tools (curl, wget, binutils, dpkg-dev, v4l-utils, gstreamer1.0-tools)…"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget binutils dpkg-dev v4l-utils gstreamer1.0-tools
}

ensure_loopback(){
  log "Ensuring v4l2loopback-dkms is present (non-fatal if already)…"
  DEBIAN_FRONTEND=noninteractive apt-get install -y v4l2loopback-dkms || true
}

prepare_overlay(){
  log "Preparing overlay at $OVERLAY_ROOT/overlay …"
  mkdir -p "$OVERLAY_LIB"
}

try_local_candidates(){
  log "Searching local bundled libstdc++ candidates (Chrome, Steam, vendor apps)…"
  local found=""

  # Typical locations: Chrome bundles, Steam runtimes, vendor apps under /opt
  mapfile -t CANDS < <(find /opt /usr/local /usr/lib -maxdepth 6 -type f -name 'libstdc++.so.6*' 2>/dev/null || true)

  for so in "${CANDS[@]:-}"; do
    if has_glibcxx_32 "$so"; then
      log "Found suitable libstdc++ with GLIBCXX_3.4.32: $so"
      install -Dm0644 "$so" "$OVERLAY_LIB/libstdc++.so.6"
      # Try to bring a matching libgcc_s if colocated
      local dir; dir="$(dirname "$so")"
      if [[ -f "$dir/libgcc_s.so.1" ]]; then
        install -Dm0644 "$dir/libgcc_s.so.1" "$OVERLAY_LIB/libgcc_s.so.1"
      fi
      found="yes"
      break
    fi
  done

  [[ -n "$found" ]]
}

fetch_debian_rt(){
  log "Fetching Debian (testing/unstable) libstdc++6 & libgcc-s1 into overlay…"
  # Prefer GCC 14 from trixie/sid (has newer GLIBCXX symbols, covers 3.4.32)
  local base="http://deb.debian.org/debian/pool/main"
  local deb1="$base/g/gcc-14/libstdc++6_14.2.0-19_amd64.deb"
  local deb2="$base/g/gcc-14/libgcc-s1_14.2.0-19_amd64.deb"

  mkdir -p "$OVERLAY_ROOT/tmp"
  curl -fL "$deb2" -o "$OVERLAY_ROOT/tmp/libgcc-s1.deb"
  curl -fL "$deb1" -o "$OVERLAY_ROOT/tmp/libstdc++6.deb"

  dpkg-deb -x "$OVERLAY_ROOT/tmp/libgcc-s1.deb" "$OVERLAY_ROOT/overlay"
  dpkg-deb -x "$OVERLAY_ROOT/tmp/libstdc++6.deb" "$OVERLAY_ROOT/overlay"

  if [[ ! -f "$OVERLAY_LIB/libstdc++.so.6" ]]; then
    # Jam some symlink if Debian puts it as .so.6.x.x only
    local real
    real="$(ls -1 "$OVERLAY_LIB"/libstdc++.so.6.* 2>/dev/null | head -n1 || true)"
    [[ -n "$real" ]] && ln -sf "$(basename "$real")" "$OVERLAY_LIB/libstdc++.so.6"
  fi

  if [[ -f "$OVERLAY_LIB/libstdc++.so.6" ]] && has_glibcxx_32 "$OVERLAY_LIB/libstdc++.so.6"; then
    log "Overlay libstdc++ exports GLIBCXX_3.4.32 (OK)."
    return 0
  else
    log "[ERROR] Overlay libstdc++ still lacks GLIBCXX_3.4.32 after Debian fetch."
    return 1
  fi
}

make_wrappers(){
  log "Creating wrappers that use the overlay (LD_LIBRARY_PATH) …"
  install -d "$WRAP_DIR"

  cat > "$WRAP_DIR/gst-inspect-ipu6" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
OVER="/opt/ipu6-rt/overlay/usr/lib/x86_64-linux-gnu"
export LD_LIBRARY_PATH="$OVER${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec gst-inspect-1.0 icamerasrc "$@"
EOF

  cat > "$WRAP_DIR/gst-launch-ipu6" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
OVER="/opt/ipu6-rt/overlay/usr/lib/x86_64-linux-gnu"
export LD_LIBRARY_PATH="$OVER${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec gst-launch-1.0 "$@"
EOF

  chmod +x "$WRAP_DIR/gst-inspect-ipu6" "$WRAP_DIR/gst-launch-ipu6"
}

post_hints(){
  log "Done. Test with:"
  echo "  gst-inspect-ipu6 | head -n 20"
  echo "  gst-launch-ipu6 -v icamerasrc ! videoconvert ! autovideosink"
  echo
  echo "If you need a virtual device for browsers:"
  echo "  sudo modprobe v4l2loopback devices=1 exclusive_caps=1 card_label=\"Virtual Camera\""
  echo "  gst-launch-ipu6 -v icamerasrc ! video/x-raw,format=YUY2,width=1280,height=720 ! v4l2sink device=/dev/video10"
}

### MAIN
ensure_tools
ensure_loopback
prepare_overlay

if try_local_candidates; then
  log "Using local vendor-bundled libstdc++ for overlay."
elif fetch_debian_rt; then
  log "Using Debian runtime libs for overlay."
else
  log "[FATAL] Could not obtain a libstdc++ that exports GLIBCXX_3.4.32."
  exit 1
fi

make_wrappers
post_hints
