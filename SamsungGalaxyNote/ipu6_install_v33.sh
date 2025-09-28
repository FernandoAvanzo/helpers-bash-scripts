#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/ipu6_install_v33.$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log(){ echo "[ipu6_install_v33] $*"; }

OVERLAY="/opt/ipu6-rt/overlay/lib"
WRAPDIR="/usr/local/bin"
TMP="$(mktemp -d)"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT

log "Kernel: $(uname -r)"
log "Checking IPU6 nodes (kernel side)…"
if ! ls /dev/video* /dev/media* 1>/dev/null 2>&1; then
  log "No /dev/videoN or /dev/mediaN nodes; kernel/IPU6 not ready. Abort."
  exit 1
fi
log "OK: video/media nodes exist."

log "Installing base tools (curl, wget, binutils, dpkg-dev, v4l-utils, gstreamer1.0-tools)…"
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget binutils dpkg-dev v4l-utils gstreamer1.0-tools

log "Ensuring v4l2loopback-dkms is present (non-fatal if already)…"
DEBIAN_FRONTEND=noninteractive apt-get install -y v4l2loopback-dkms || true

# --- Build libstdc++ overlay from Ubuntu 24.04 (Noble) packages ---
mkdir -p "$OVERLAY"
log "Preparing overlay at $OVERLAY …"
# Fetch two .debs from Noble that carry the newer libstdc++/libgcc_s
UURL="http://archive.ubuntu.com/ubuntu/pool/main"
# Prefer GCC-14 builds from Noble (contain GLIBCXX_3.4.3x versions)
DEB_STD="$TMP/libstdc++6_14.2.0-4ubuntu2~24.04_amd64.deb"
DEB_GCC="$TMP/libgcc-s1_14.2.0-4ubuntu2~24.04_amd64.deb"

fetch(){  # url dest
  local url="$1" dest="$2"
  log "[pool] $(basename "$dest")"
  if ! curl -fsSL "$url" -o "$dest"; then
    log "[WARN] download failed: $url"
    return 1
  fi
}

fetch "$UURL/g/gcc-14/$(basename "$DEB_STD")" "$DEB_STD" || {
  log "[FALLBACK] Trying GCC-13 build from Noble…"
  DEB_STD="$TMP/libstdc++6_13.2.0-23ubuntu4_amd64.deb"
  fetch "$UURL/g/gcc-13/$(basename "$DEB_STD")" "$DEB_STD" || {
    log "[FATAL] Could not fetch any Noble libstdc++6 package."; exit 1; }
}

fetch "$UURL/g/gcc-14/$(basename "$DEB_GCC")" "$DEB_GCC" || {
  DEB_GCC="$TMP/libgcc-s1_13.2.0-23ubuntu4_amd64.deb"
  fetch "$UURL/g/gcc-13/$(basename "$DEB_GCC")" "$DEB_GCC" || {
    log "[FATAL] Could not fetch any Noble libgcc-s1 package."; exit 1; }
}

log "Extracting only the needed .so files into overlay (safe, path-agnostic)…"
U1="$TMP/u1"; U2="$TMP/u2"; mkdir -p "$U1" "$U2"
dpkg-deb -x "$DEB_STD" "$U1"
dpkg-deb -x "$DEB_GCC" "$U2"

# Helper: choose a real ELF shared object named libstdc++.so.6.*
choose_real_libstdcxx(){
  local root="$1"
  local cand
  while IFS= read -r cand; do
    # Skip python pretty-printers and anything not a shared object
    [[ "$cand" =~ \.py$ ]] && continue
    [[ "$cand" =~ -gdb\.py$ ]] && continue
    [[ "$cand" =~ \.a$ ]] && continue
    # Must be a 64-bit x86_64 ELF shared object
    if file -b "$cand" | grep -q 'ELF 64-bit LSB shared object, x86-64'; then
      echo "$cand"; return 0
    fi
  done < <(find "$root" -type f -name 'libstdc++.so.6.*' 2>/dev/null | sort -V)
  return 1
}

# Pick the correct .so from the extracted tree
STDCREAL="$(choose_real_libstdcxx "$U1/usr/lib" || true)"
[[ -z "${STDCREAL:-}" ]] && STDCREAL="$(choose_real_libstdcxx "$U1/lib" || true)"
if [[ -z "${STDCREAL:-}" ]]; then
  log "[FATAL] Could not locate a real libstdc++.so.6.* ELF in the .deb (avoiding *-gdb.py)."
  exit 1
fi

# And libgcc_s.so.1
GCCREAL="$(find "$U2" -type f -name 'libgcc_s.so.1' | head -n1 || true)"
if [[ -z "${GCCREAL:-}" ]]; then
  log "[FATAL] Could not locate libgcc_s.so.1 in Noble package."
  exit 1
fi

# Install into overlay
install -m 0755 -D "$STDCREAL" "$OVERLAY/$(basename "$STDCREAL")"
ln -sfn "$(basename "$STDCREAL")" "$OVERLAY/libstdc++.so.6"
install -m 0755 -D "$GCCREAL" "$OVERLAY/libgcc_s.so.1"

# Validate the overlay libs
log "Validating overlay libs…"
file "$OVERLAY/libstdc++.so.6"
if ! strings -a "$OVERLAY/libstdc++.so.6" | grep -q 'GLIBCXX_3\.4\.32'; then
  log "[WARN] strings did not show GLIBCXX_3.4.32; newer libstdc++ still usually contains earlier versions."
  log "      Proceeding to a runtime link test."
fi

# Runtime link test against the Intel HAL plugin (if present)
HAL="/usr/lib/libcamhal/plugins/ipu6epmtl.so"
if [[ -f "$HAL" ]]; then
  log "ldd -v HAL with overlay (expect GLIBCXX ref satisfied):"
  LD_LIBRARY_PATH="$OVERLAY" ldd -v "$HAL" || true
else
  log "[INFO] HAL plugin not found at $HAL; will still proceed. (icamerasrc will load it if installed)"
fi

# Wrappers to use the overlay without touching the system libstdc++
mkdir -p "$WRAPDIR"
cat > "$WRAPDIR/icamera-gst-inspect" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
OVER="/opt/ipu6-rt/overlay/lib"
export LD_LIBRARY_PATH="$OVER:${LD_LIBRARY_PATH-}"
exec gst-inspect-1.0 icamerasrc "$@"
EOF
chmod +x "$WRAPDIR/icamera-gst-inspect"

cat > "$WRAPDIR/icamera-gst-launch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
OVER="/opt/ipu6-rt/overlay/lib"
export LD_LIBRARY_PATH="$OVER:${LD_LIBRARY_PATH-}"
# Basic preview pipeline; adjust device selection via properties if needed
exec gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink
EOF
chmod +x "$WRAPDIR/icamera-gst-launch"

log "Smoke test: run gst-inspect with the overlay (this is read-only and safe)…"
if ! icamera-gst-inspect 2>&1 | tee /dev/stderr | grep -qi 'Factory Details'; then
  log "[WARN] icamerasrc still failed to load. Check for CamHAL messages above."
  log "      You can also try:  LD_LIBRARY_PATH=$OVERLAY gst-launch-1.0 icamerasrc ! fakesink -v"
else
  log "icamerasrc listed OK under the overlay."
fi

log "Done. Log saved to $LOG"
