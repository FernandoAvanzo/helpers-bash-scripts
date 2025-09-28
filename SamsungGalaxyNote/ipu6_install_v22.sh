#!/usr/bin/env bash
set -euo pipefail

LOG_DIR=/var/log
LOG_FILE="$LOG_DIR/ipu6_install_v22.$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[ipu6_install_v22] $*"; }
warn(){ echo "[ipu6_install_v22][WARN] $*" >&2; }
err() { echo "[ipu6_install_v22][ERROR] $*" >&2; exit 1; }

# --- 0. Context ---------------------------------------------------------------
KERNEL="$(uname -r)"
SUDO_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6 2>/dev/null || echo /root)"
log "Kernel: $KERNEL"
log "SUDO_USER: ${SUDO_USER:-root}  HOME: $SUDO_HOME"

# --- 1. Quick kernel/IPU6 health check ---------------------------------------
# We don't bail just because lsmod is quiet; Pop!_OS can build these in-tree.
have_nodes=0
if [ -e /dev/media0 ] || ls /dev/video* >/dev/null 2>&1; then have_nodes=1; fi
if dmesg | grep -qE "intel-ipu6 .*Connected [1-9] cameras|CSE authenticate_run done"; then
  log "IPU6 in dmesg looks good (sensor detected/authenticated)."
else
  warn "Didn't see IPU6 success lines in dmesg; things may still be okay if nodes exist."
fi
if [ "$have_nodes" -eq 0 ]; then
  warn "No /dev/media* or /dev/video* nodes visible. Are you booted into the working kernel (your 6.16.x)?"
fi

# --- 2. Base tools and v4l2loopback ------------------------------------------
log "Installing base tools…"
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg wget gstreamer1.0-tools v4l-utils || true

log "Ensuring v4l2loopback-dkms is present…"
DEBIAN_FRONTEND=noninteractive apt-get install -y v4l2loopback-dkms || true
modprobe v4l2loopback devices=1 exclusive_caps=1 card_label="Virtual Camera" || true

# --- 3. HAL/icamerasrc sanity (leave as-is if already installed) -------------
if dpkg -l | grep -qE 'gstreamer1.0-icamera|libcamhal-ipu6ep0'; then
  log "Intel HAL & icamerasrc already installed; leaving them untouched."
else
  warn "Intel HAL/icamerasrc not detected from PPA. If needed, install from PPA later; kernel side already works."
fi

# --- 4. Build a per-process libstdc++ overlay (no system replacements) -------
OVERLAY=/opt/ipu6-stdcpp-overlay
BIN_DIR=/usr/local/bin
mkdir -p "$OVERLAY" "$BIN_DIR"

need_sym="GLIBCXX_3.4.32"
log "Searching this system for a libstdc++.so.6 that exports $need_sym … (this may take a moment)"

# Candidate directories (system + common vendor runtimes)
CANDIDATE_DIRS=(
  /lib/x86_64-linux-gnu
  /usr/lib/x86_64-linux-gnu
  /usr/local/lib
  /opt/google/chrome
  /opt/chromium
  /opt/brave.com/brave
  /opt/microsoft/edge
  /snap/chromium/current/usr/lib/x86_64-linux-gnu
  "$SUDO_HOME/.steam/steam/ubuntu12_64"
  "$SUDO_HOME/.local/share/Steam/ubuntu12_64"
  "$SUDO_HOME/.steam/steam/steamapps/common/SteamLinuxRuntime_sniper"
  "$SUDO_HOME/.steam/steam/steamapps/common/SteamLinuxRuntime_soldier"
)
found_lib=""

for d in "${CANDIDATE_DIRS[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r -d '' f; do
    if strings -a "$f" 2>/dev/null | grep -q "$need_sym"; then
      found_lib="$f"
      break
    fi
  done < <(find "$d" -maxdepth 2 -type f -name "libstdc++.so.6*" -print0 2>/dev/null || true)
  [ -n "$found_lib" ] && break
done

if [ -z "$found_lib" ]; then
  err "Couldn't find any local libstdc++.so.6 with $need_sym.
Hints:
  • If you have Steam installed, make sure you've launched it at least once (it populates ~/.local/share/Steam/ubuntu12_64).
  • Some vendor apps under /opt/* bundle their own libstdc++; installing one may provide the needed symbol.
  • We intentionally avoid replacing your system libstdc++; this overlay is per-process only (via LD_LIBRARY_PATH)."
fi

log "Using candidate: $found_lib"
rm -f "$OVERLAY/libstdc++.so.6" "$OVERLAY"/libstdc++.so.6.*
# Prefer to symlink (so updates follow the source)
ln -sf "$found_lib" "$OVERLAY/libstdc++.so.6"

# --- 5. Drop wrappers that run with the overlay ------------------------------
cat > "$BIN_DIR/ipu6-gst-inspect" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
OVERLAY=/opt/ipu6-stdcpp-overlay
export LD_LIBRARY_PATH="$OVERLAY${LD_LIBRARY_PATH+:$LD_LIBRARY_PATH}"
exec gst-inspect-1.0 icamerasrc "$@"
EOF
chmod +x "$BIN_DIR/ipu6-gst-inspect"

cat > "$BIN_DIR/ipu6-gst-preview" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
OVERLAY=/opt/ipu6-stdcpp-overlay
export LD_LIBRARY_PATH="$OVERLAY${LD_LIBRARY_PATH+:$LD_LIBRARY_PATH}"
# Try a simple preview; tweak caps later once HAL initializes
exec gst-launch-1.0 -v icamerasrc ! videoconvert ! autovideosink
EOF
chmod +x "$BIN_DIR/ipu6-gst-preview"

# --- 6. Smoke test -----------------------------------------------------------
log "Testing icamerasrc initialization using the overlay…"
set +e
OUT="$(LD_LIBRARY_PATH="$OVERLAY${LD_LIBRARY_PATH+:$LD_LIBRARY_PATH}" \
  gst-inspect-1.0 icamerasrc 2>&1)"
rc=$?
set -e

if echo "$OUT" | grep -q "$need_sym"; then
  err "Even with the overlay, loader still complains about $need_sym. The candidate libstdc++ is not suitable."
fi

if echo "$OUT" | grep -q "failed to open library: .*ipu6epmtl.so"; then
  err "HAL plugin still didn't load; check that libcamhal-ipu6ep0 and its deps are installed from Intel IPU6 PPA."
fi

if [ $rc -ne 0 ]; then
  warn "gst-inspect exit code: $rc"
fi

log "Success: icamerasrc is discoverable without GLIBCXX errors."
log "Next steps:"
echo "  1) Run:     ipu6-gst-preview         # live preview"
echo "  2) If you need a /dev/video* for browsers:"
echo "       a) modprobe v4l2loopback devices=1 exclusive_caps=1 card_label='Virtual Camera'"
echo "       b) (optional) Use a pipeline like:"
echo "          env LD_LIBRARY_PATH=$OVERLAY \\
              gst-launch-1.0 -v icamerasrc ! videoconvert ! v4l2sink device=/dev/video10"
log "All done."
