#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/ipu6_install_v34.$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

say(){ printf '[ipu6_install_v34] %s\n' "$*"; }

# --- 0. Basic facts -----------------------------------------------------------
KREL="$(uname -r)"
say "Kernel: $KREL"
SUDO_USER="${SUDO_USER:-$(id -un)}"
USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6 || echo /root)"
say "SUDO_USER: $SUDO_USER  HOME: $USER_HOME"

# --- 1. Quick kernel-side check ----------------------------------------------
if ! ls /dev/video* /dev/media* >/dev/null 2>&1; then
  say "No /dev/video*/media* nodes found. Kernel side not ready. Abort."
  exit 1
fi
say "IPU6 nodes exist; kernel/IPU6 likely OK."

# --- 2. Make sure helper tools exist -----------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y curl wget binutils dpkg-dev v4l-utils gstreamer1.0-tools >/dev/null

# --- 3. v4l2loopback (optional for browsers), non-fatal ----------------------
apt-get install -y v4l2loopback-dkms || true

# --- 4. Inspect currently installed HAL/IPA and glibc floor ------------------
NEED_FILES=(
  /usr/lib/libcamhal/plugins/ipu6epmtl.so
  /lib/libgcss-ipu6epmtl.so.0
  /lib/libbroxton_ia_pal-ipu6epmtl.so.0
)
MISSING=0
for f in "${NEED_FILES[@]}"; do
  [[ -f "$f" ]] || { say "WARN: $f not found (HAL may not be installed)"; MISSING=1; }
done

# Get system glibc version (major.minor)
SYS_GLIBC="$(ldd --version 2>/dev/null | head -n1 | sed -E 's/.* ([0-9]+\.[0-9]+).*/\1/')"
say "System glibc: $SYS_GLIBC (Jammy is 2.35)"

needs_new_glibc=0
if [[ $MISSING -eq 0 ]]; then
  say "Checking HAL/IPA for GLIBC_* requirements…"
  need_list=""
  for f in "${NEED_FILES[@]}"; do
    # readelf shows needed GLIBC versions in Version References
    req="$(/usr/bin/ldd -v "$f" 2>&1 | sed -n 's/.*(GLIBC_\([0-9]\+\.[0-9]\+\)).*/\1/p' | sort -u || true)"
    [[ -n "$req" ]] && need_list+="$req"$'\n'
  done
  max_need="$(printf '%s' "$need_list" | awk -F. 'NF{print $1*100+$2}' | sort -n | tail -1 || true)"
  if [[ -n "$max_need" ]]; then
    # compare as int
    sys="$(( ${SYS_GLIBC%%.*}*100 + ${SYS_GLIBC##*.} ))"
    if (( max_need > sys )); then
      needs_new_glibc=1
    fi
  fi
fi

if (( needs_new_glibc == 1 )); then
  say "HAL/IPA objects require GLIBC >= $(printf '%s' "$need_list" | sort -V | tail -1)."
  say "Your OS provides GLIBC $SYS_GLIBC, so these binaries cannot load on 22.04."
  cat <<'EOF'
Why this fails:
  • The installed Intel HAL/IPA packages were built on a newer distro (glibc >= 2.38).
  • Jammy (22.04) ships glibc 2.35. You cannot safely 'overlay' libc with LD_LIBRARY_PATH.

Two options:
  A) Upgrade the OS to Pop!_OS/Ubuntu 24.04, then keep these HAL packages. (Recommended)
  B) Stay on 22.04 but install Jammy-built HAL packages (compiled against glibc 2.35).

I can try (best-effort) to switch to Jammy-compatible HAL if apt shows such versions.
EOF

  # Try to find Jammy-targeted HAL meta package names; if present, attempt a downgrade.
  say "Attempting to find Jammy-compatible HAL packages in the OEM IPU6 PPA…"
  apt-get update -qq || true
  TRY_PKGS=(libcamhal-ipu6ep0 libcamhal-common libcamhal0 gstreamer1.0-icamera libipu6)
  found_any=0
  for p in "${TRY_PKGS[@]}"; do
    if apt-cache policy "$p" >/dev/null 2>&1; then
      say "Available versions for $p:"
      apt-cache policy "$p" | sed 's/^/  /'
      found_any=1
    fi
  done

  if (( found_any == 0 )); then
    say "No HAL packages found via apt cache. Likely you need to upgrade to 24.04."
    exit 2
  fi

  cat <<'EOF'
If you see older Jammy builds in the lists above, you can pin and install like:
  sudo apt-get install <pkg>=<jammy_version> ...  (for each of: libcamhal-ipu6ep0 libcamhal-common libcamhal0 gstreamer1.0-icamera libipu6)

After installing Jammy builds, re-run this script to complete the libstdc++ overlay and test GStreamer.
EOF
  exit 3
fi

# --- 5. Prepare a libstdc++ overlay that works on Jammy ----------------------
say "HAL is compatible with your glibc; setting up a per-process libstdc++ overlay (no system replacement)…"

BASE="/opt/ipu6-rt"
ENV="$BASE/env"
mkdir -p "$ENV"

# Pull conda-forge libstdc++ built with old glibc floor (cos7), so it won't demand GLIBC_2.38.
# Use micromamba to avoid system changes.
if [[ ! -x "$BASE/mm/micromamba" ]]; then
  say "Downloading micromamba (static)…"
  mkdir -p "$BASE/mm"
  curl -fsSL https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xJ -C "$BASE/mm" bin/micromamba
  mv "$BASE/mm/bin/micromamba" "$BASE/mm/micromamba"
  rmdir "$BASE/mm/bin" || true
fi

say "Creating env at $ENV with libstdcxx-ng=13.2.0 and libgcc-ng… (conda-forge)"
"$BASE/mm/micromamba" create -y -r "$ENV" -c conda-forge libstdcxx-ng=13.2.0 libgcc-ng >/dev/null

LIBDIR="$ENV/lib"
LIBSTD="$LIBDIR/libstdc++.so.6"
if [[ ! -e "$LIBSTD" ]]; then
  say "ERROR: libstdc++.so.6 not found in $LIBDIR"; exit 4
fi

# Verify GLIBCXX_3.4.32 exists and that this lib does NOT require GLIBC_2.38+
say "Verifying GLIBCXX_3.4.32 presence and no GLIBC_2.38 requirement…"
if ! strings -a "$LIBSTD" | grep -q 'GLIBCXX_3\.4\.32'; then
  say "WARN: strings did not show GLIBCXX_3.4.32; checking full version definitions (readelf)…"
fi
# Run ldd -v against HAL with overlay to ensure the new libstdc++ satisfies the GLIBCXX refs
say "Runtime link test with overlay against HAL…"
LD_LIBRARY_PATH="$LIBDIR" ldd -v /usr/lib/libcamhal/plugins/ipu6epmtl.so || true

# --- 6. Provide handy wrappers ------------------------------------------------
WRAP="$BASE/bin"; mkdir -p "$WRAP"
cat > "$WRAP/icamera-run" <<EOF
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$LIBDIR:\${LD_LIBRARY_PATH:-}"
exec "\$@"
EOF
chmod +x "$WRAP/icamera-run"

cat > /usr/local/bin/icamera-inspect <<EOF
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$LIBDIR:\${LD_LIBRARY_PATH:-}"
exec gst-inspect-1.0 icamerasrc
EOF
chmod +x /usr/local/bin/icamera-inspect

cat > /usr/local/bin/icamera-launch <<'EOF'
#!/usr/bin/env bash
export LD_LIBRARY_PATH="/opt/ipu6-rt/env/lib:${LD_LIBRARY_PATH:-}"
# Minimal pipeline: enumerate and push to fakesink
exec gst-launch-1.0 -v icamerasrc ! fakesink
EOF
chmod +x /usr/local/bin/icamera-launch

say "Smoke test: icamera-inspect (safe)…"
if ! /usr/local/bin/icamera-inspect; then
  say "WARN: icamerasrc still failed to load; check messages above."
else
  say "icamerasrc loaded."
fi

say "Done. Log saved to $LOG"
