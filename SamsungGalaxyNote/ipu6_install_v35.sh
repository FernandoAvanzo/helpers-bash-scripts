#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/ipu6_install_v35.$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log(){ echo "[ipu6_install_v35] $*"; }

# --- 0. Context --------------------------------------------------------------
KERNEL="$(uname -r)"
SUDO_USER="${SUDO_USER:-$(id -un)}"
USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6 || echo /home/$SUDO_USER)"
log "Kernel: $KERNEL"
log "SUDO_USER: $SUDO_USER  HOME: $USER_HOME"

# --- 1. Make sure kernel side is present (you already had it) ----------------
have_nodes=0
if ls /dev/video* >/dev/null 2>&1; then have_nodes=1; fi
if [[ $have_nodes -eq 1 ]]; then
  log "OK: video/media nodes exist (kernel/IPU6 likely OK)."
else
  log "WARN: No /dev/video* nodes. Reboot into the kernel that loads IPU6 modules and try again."
fi

# --- 2. Base tooling, v4l2loopback ------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
apt-get install -y --no-install-recommends \
  curl wget binutils dpkg-dev v4l-utils gstreamer1.0-tools || true

log "Ensuring v4l2loopback-dkms is present (non-fatal if already)…"
apt-get install -y v4l2loopback-dkms || true

# --- 3. Diagnose GLIBC (system) and GLIBC required by HAL/IPA ----------------
glibc_ver="$(/usr/bin/ldd --version 2>/dev/null | head -n1 | sed -E 's/.* //')"
log "System glibc: ${glibc_ver}"

needs_new_glibc=0
need_list=""

# Known HAL/IPA/Plugin locations from the Intel PPA
candidates=(
  "/usr/lib/libcamhal/plugins/ipu6epmtl.so"
  "/usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgsticamerasrc.so"
  "/lib/libgcss-ipu6epmtl.so.0"
  "/lib/libbroxton_ia_pal-ipu6epmtl.so.0"
  "/lib/libia_aiq-ipu6epmtl.so.0"
  "/lib/libia_cca-ipu6epmtl.so.0"
  "/lib/libia_aiqb_parser-ipu6epmtl.so.0"
  "/lib/libia_cmc_parser-ipu6epmtl.so.0"
  "/lib/libia_dvs-ipu6epmtl.so.0"
  "/lib/libia_ltm-ipu6epmtl.so.0"
  "/lib/libia_mkn-ipu6epmtl.so.0"
  "/lib/libia_coordinate-ipu6epmtl.so.0"
)

max_req="2.0"
have_any=0
for so in "${candidates[@]}"; do
  [[ -f "$so" ]] || continue
  have_any=1
  # Extract GLIBC_* version refs from .gnu.version{,_d} sections
  reqs=$(readelf -V "$so" 2>/dev/null | awk '/GLIBC_[0-9]+\.[0-9]+/ {print $1}' | sed 's/.*GLIBC_/GLIBC_/g' | sort -u)
  if [[ -n "$reqs" ]]; then
    # find the highest GLIBC_*.*
    hi=$(echo "$reqs" | sed 's/GLIBC_//' | sort -t. -k1,1n -k2,2n | tail -n1)
    # compare with system glibc
    sys="${glibc_ver}"
    # normalize
    need_major="${hi%%.*}"; need_minor="${hi##*.}"
    sys_major="${sys%%.*}"; sys_minor="${sys##*.}"
    # numeric compare
    if (( need_major > sys_major )) || { (( need_major == sys_major )) && (( need_minor > sys_minor )); }; then
      needs_new_glibc=1
      need_list+="$so requires GLIBC_${hi} (system is ${glibc_ver})"$'\n'
      # track max
      max_req="$hi"
    fi
  fi
done

if (( have_any == 0 )); then
  log "Note: HAL/IPA libraries not found on disk; skipping GLIBC check for them."
fi

# --- 4. If HAL/IPA need newer glibc than this OS, stop (no risky hacks) ------
if (( needs_new_glibc == 1 )); then
  echo
  echo "HAL/IPA were built for newer glibc than your OS provides:"
  echo "----- offenders (require > GLIBC_${glibc_ver}) -----"
  echo -n "$need_list"
  echo "----------------------------------------------------"
  echo "This cannot be fixed with LD_LIBRARY_PATH or a libstdc++ overlay."
  echo
  cat <<'MSG'
Two safe choices:
  A) Upgrade the OS to Ubuntu/Pop!_OS 24.04 (glibc 2.39). Then the current Intel HAL loads.
  B) Stay on 22.04 but install Jammy-built HAL/IPA that target glibc 2.35.

This script will NOT replace libc. If you want me to try an APT downgrade
to older HAL builds (only if the PPA still publishes Jammy-compatible ones),
re-run with:   sudo GLIBC_DOWNGRADE_OK=1 ./ipu6_install_v35.sh
MSG

  if [[ "${GLIBC_DOWNGRADE_OK:-0}" != "1" ]]; then
    exit 3
  fi
fi

# --- 5. Optional: attempt HAL downgrade to Jammy-compatible builds -----------
# We only attempt if user explicitly asked for it.
if [[ "${GLIBC_DOWNGRADE_OK:-0}" == "1" ]]; then
  log "Attempting to locate Jammy-compatible HAL/IPA versions via APT…"
  apt-get update -y || true
  pkgs=(libcamhal-ipu6ep0 libcamhal-common libcamhal0 gstreamer1.0-icamera libipu6)
  for p in "${pkgs[@]}"; do
    log "Versions available for $p:"
    apt-cache policy "$p" || true
  done
  echo
  echo "If you see older Jammy builds above, you can pin and install, e.g.:"
  echo "  sudo apt-get install libcamhal-ipu6ep0=<version> libcamhal-common=<version> libcamhal0=<version> gstreamer1.0-icamera=<version> libipu6=<version>"
  echo
  echo "No automatic downgrade performed (PPA contents are volatile)."
  exit 4
fi

# --- 6. libstdc++ overlay (safe; fixes GLIBCXX_3.4.32 if needed) -------------
OVER="/opt/ipu6-rt/overlay/lib"
mkdir -p "$OVER"
tmpd="$(mktemp -d)"
log "Preparing libstdc++/libgcc overlay (Noble pool -> these files are fine on Jammy; they do NOT replace libc)…"
# pull only .so from pool, extract with dpkg-deb -x (safer than ar/xz juggling)
curl -fsSL -o "$tmpd/libstdc++.deb" http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-14/libstdc++6_14.2.0-4ubuntu2~24.04_amd64.deb
curl -fsSL -o "$tmpd/libgccs1.deb"  http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-14/libgcc-s1_14.2.0-4ubuntu2~24.04_amd64.deb
dpkg-deb -x "$tmpd/libstdc++.deb" "$tmpd/u1"
dpkg-deb -x "$tmpd/libgccs1.deb"  "$tmpd/u2"
cp -av "$tmpd/u1"/usr/lib/x86_64-linux-gnu/libstdc++.so.6* "$OVER"/
cp -av "$tmpd/u2"/lib/x86_64-linux-gnu/libgcc_s.so.1       "$OVER"/
ln -sf libstdc++.so.6* "$OVER/libstdc++.so.6" || true

# quick report
echo; log "Overlay contains:"
ls -l "$OVER" || true

# --- 7. Create test wrappers -------------------------------------------------
BIN="/usr/local/bin"
mkdir -p "$BIN"
cat > "$BIN/icamera-inspect" <<'EOF'
#!/usr/bin/env bash
export LD_LIBRARY_PATH=/opt/ipu6-rt/overlay/lib${LD_LIBRARY_PATH+:$LD_LIBRARY_PATH}
exec gst-inspect-1.0 icamerasrc "$@"
EOF
cat > "$BIN/icamera-launch" <<'EOF'
#!/usr/bin/env bash
export LD_LIBRARY_PATH=/opt/ipu6-rt/overlay/lib${LD_LIBRARY_PATH+:$LD_LIBRARY_PATH}
exec gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink -v
EOF
chmod +x "$BIN/icamera-inspect" "$BIN/icamera-launch"
log "Wrappers installed: icamera-inspect, icamera-launch"

# --- 8. Smoke test (won’t fix glibc mismatch, only GLIBCXX) -----------------
log "Smoke test: icamera-inspect (safe)…"
if ! "$BIN/icamera-inspect" >/dev/null 2>&1; then
  log "Note: icamerasrc still failed to load — check for GLIBC_* messages above."
else
  log "icamerasrc was inspected successfully."
fi

echo
log "Done. Log saved to $LOG"
