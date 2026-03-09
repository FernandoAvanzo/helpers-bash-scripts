#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/ipu6_install_v27.$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log(){ echo "[ipu6_install_v27] $*"; }

OVERLAY_BASE="/opt/ipu6-rt"
OVERLAY_LIB="$OVERLAY_BASE/overlay/lib"
WRAP_BIN="/usr/local/bin"

mkdir -p "$OVERLAY_LIB"

log "Kernel: $(uname -r)"
log "SUDO_USER: ${SUDO_USER:-$(id -un)}  HOME: ${HOME:-/root}"

# 0) Sanity: your kernel side is already fine; leave HAL/icamerasrc alone.
log "Checking for IPU6 character/media devices (kernel side)…"
if ls /dev/video* /dev/media* >/dev/null 2>&1; then
  log "IPU6 devices exist; kernel/IPU6 likely OK."
else
  log "[WARN] No /dev/video*/media* found. The rest of this script just prepares userspace."
fi

# 1) v4l2loopback (kept, safe no-op if installed)
log "Ensuring v4l2loopback-dkms is present…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -o=Dpkg::Use-Pty=0 >/dev/null || true
apt-get install -y -o=Dpkg::Use-Pty=0 v4l2loopback-dkms || true

# 2) Prepare a clean overlay dir
log "Preparing overlay at $OVERLAY_LIB …"
rm -f "$OVERLAY_LIB"/libstdc++.so.6* "$OVERLAY_LIB"/libgcc_s.so.1 || true

have_glibcxx() {
  local so="$1"
  [[ -r "$so" ]] || return 1
  strings -a -- "$so" | grep -q 'GLIBCXX_3\.4\.32'
}

pick_and_copy() {
  local src="$1" base dst
  base="$(basename "$src")"
  dst="$OVERLAY_LIB/$base"
  install -m 0644 -T -- "$src" "$dst"
  # If this is the SONAME versioned file, also update the symlink
  if [[ "$base" == libstdc++.so.6.* ]]; then
    ln -sf "$base" "$OVERLAY_LIB/libstdc++.so.6"
  fi
  if [[ "$base" == libgcc_s.so.1 ]]; then
    : # nothing else to do
  fi
}

# 3) Try system-provided bundled runtimes first (Chrome/Steam), then fall back to Noble packages.
log "Searching local bundled libstdc++ candidates (Chrome, Steam)…"
CANDIDATES=()

# Google Chrome often bundles a newer libstdc++
CANDIDATES+=(/opt/google/chrome/libstdc++.so.6)

# Steam runtimes (use SUDO_USER’s home if present)
USR="${SUDO_USER:-}"
if [[ -n "$USR" ]]; then
  USER_HOME="$(getent passwd "$USR" | cut -d: -f6)"
  CANDIDATES+=("$USER_HOME/.local/share/Steam/ubuntu12_64/steam-runtime/usr/lib/x86_64-linux-gnu/libstdc++.so.6")
  CANDIDATES+=("$USER_HOME/.local/share/Steam/ubuntu12_32/steam-runtime/usr/lib/x86_64-linux-gnu/libstdc++.so.6")
  # Newer Steam Linux Runtimes:
  CANDIDATES+=("$USER_HOME/.local/share/Steam/steamapps/common/SteamLinuxRuntime_sniper/pressure-vessel/share/steamruntime/usr/lib/x86_64-linux-gnu/libstdc++.so.6")
fi

FOUND_LOCAL=""
for so in "${CANDIDATES[@]}"; do
  if [[ -r "$so" ]] && have_glibcxx "$so"; then
    log "Found suitable libstdc++ with GLIBCXX_3.4.32 at: $so"
    pick_and_copy "$so"
    FOUND_LOCAL="yes"
    break
  fi
done

if [[ -z "$FOUND_LOCAL" ]]; then
  log "No suitable local libstdc++ found. Fetching Ubuntu 24.04 (Noble) packages into overlay…"
  TMPD="$(mktemp -d)"
  pushd "$TMPD" >/dev/null

  # Try a short list of known-good nobles; we’ll stop at first that verifies.
  DEBS=(
    "http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-13/libstdc++6_13.2.0-23ubuntu4_amd64.deb"
    "http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-14/libstdc++6_14.2.0-4ubuntu2~24.04_amd64.deb"
  )
  # Always pair with libgcc_s, but any contemporary one is fine
  LIBGCC="http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-14/libgcc-s1_14.2.0-4ubuntu2~24.04_amd64.deb"

  wget -q "$LIBGCC" -O libgcc.deb || true
  if [[ -s libgcc.deb ]]; then
    dpkg-deb -x libgcc.deb x && \
      cp -f x/lib/x86_64-linux-gnu/libgcc_s.so.1 "$OVERLAY_LIB/" || true
  fi

  OK=""
  for url in "${DEBS[@]}"; do
    log "[pool] $(basename "$url")"
    wget -q "$url" -O libstdcxx.deb || { log "[WARN] download failed: $url"; continue; }
    rm -rf x && dpkg-deb -x libstdcxx.deb x || { log "[WARN] dpkg-deb -x failed"; continue; }

    # Find the real SONAME file (libstdc++.so.6.0.xx)
    real=(x/usr/lib/x86_64-linux-gnu/libstdc++.so.6.*)
    if [[ -r "${real[0]}" ]]; then
      pick_and_copy "${real[0]}"
      if have_glibcxx "${real[0]}"; then
        OK="yes"
        break
      else
        log "[WARN] That candidate does not export GLIBCXX_3.4.32, trying next…"
        rm -f "$OVERLAY_LIB"/libstdc++.so.6*
      fi
    else
      log "[WARN] Couldn’t locate extracted libstdc++ in that .deb"
    fi
  done

  popd >/dev/null
  rm -rf "$TMPD"

  if [[ -z "$OK" ]]; then
    log "[ERROR] Could not obtain a libstdc++ with GLIBCXX_3.4.32 from Ubuntu pool."
    log "        You can still point the wrappers to any vendor-bundled libstdc++ that has it."
    exit 1
  fi
fi

# 4) Verify overlay exports the needed symbol
REAL_SO="$(readlink -f "$OVERLAY_LIB/libstdc++.so.6")"
if ! have_glibcxx "$REAL_SO"; then
  log "[ERROR] Overlay libstdc++ at $REAL_SO still missing GLIBCXX_3.4.32. Abort."
  exit 1
fi
log "Overlay OK: $REAL_SO exports GLIBCXX_3.4.32"

# 5) Create lightweight wrappers so you don’t have to remember LD_LIBRARY_PATH
install -m 0755 /dev/stdin "$WRAP_BIN/ipu6-run" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
OL="/opt/ipu6-rt/overlay/lib"
export LD_LIBRARY_PATH="${OL}:${LD_LIBRARY_PATH-}"
exec "$@"
EOF

install -m 0755 /dev/stdin "$WRAP_BIN/ipu6-gst" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
OL="/opt/ipu6-rt/overlay/lib"
export LD_LIBRARY_PATH="${OL}:${LD_LIBRARY_PATH-}"
# Let GStreamer find icamerasrc in the standard plugin dir
exec gst-launch-1.0 -v icamerasrc ! videoconvert ! autovideosink
EOF

log "Wrappers installed:"
log "  • ipu6-run <any_command>"
log "  • ipu6-gst   (quick camera smoke test)"

# 6) (Optional) Load v4l2loopback now (safe if already loaded)
if ! lsmod | grep -q '^v4l2loopback'; then
  log "Loading v4l2loopback kernel module…"
  modprobe v4l2loopback exclusive_caps=1 card_label="Virtual Camera" devices=1 || true
fi

# 7) Brief next steps
log "All set. Try:"
echo "    ipu6-run gst-inspect-1.0 icamerasrc | head"
echo "    ipu6-gst"
