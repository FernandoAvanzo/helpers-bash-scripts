#!/usr/bin/env bash
# ipu6_install_v25.sh
# Safe userspace fix for Intel IPU6 HAL (icamerasrc) on Pop!_OS 22.04 + custom 6.16 kernel.
# - Keeps your kernel-side success (from v7/v16).
# - Avoids system libstdc++ replacement; uses a per-process overlay from Ubuntu 24.04.
# - Leaves Intel OEM HAL/icamerasrc alone if already installed; installs minimal set if missing.

set -Eeuo pipefail

LOG="/var/log/ipu6_install_v25.$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

BLUE(){ echo -e "\e[34m$*\e[0m"; }
YEL(){  echo -e "\e[33m$*\e[0m"; }
RED(){  echo -e "\e[31m$*\e[0m"; }

KERNEL="$(uname -r)"
BLUE "[ipu6_install_v25] Kernel: $KERNEL"

# --- 0. Quick reality checks ---------------------------------------------------
if [ -e /dev/media0 ] || ls /dev/video* >/dev/null 2>&1; then
  YEL "[ipu6_install_v25] /dev nodes exist; kernel/IPU6 likely OK (you saw that in dmesg earlier)."
else
  YEL "[ipu6_install_v25] No /dev/media*/video* found. Kernel side might not be up — but continuing (userspace-only script)."
fi

# --- 1. Sanity cleanup (dpkg/apt, stale loopbacks) -----------------------------
BLUE "[ipu6_install_v25] Sanity cleanup (dpkg/apt, stale loopbacks)…"
apt-get update -y || true
apt-get -f install -y || true
dpkg --configure -a || true

# Remove zombie loopbacks if any
if lsmod | grep -q '^v4l2loopback'; then
  modprobe -r v4l2loopback || true
fi

# Tools we need
BLUE "[ipu6_install_v25] Installing base tools…"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl wget gnupg dpkg-dev binutils gstreamer1.0-tools v4l-utils || true

# --- 2. Ensure v4l2loopback (optional but handy for browsers) ------------------
BLUE "[ipu6_install_v25] Ensuring v4l2loopback-dkms is installed…"
DEBIAN_FRONTEND=noninteractive apt-get install -y v4l2loopback-dkms || true
# (Don't autoload; user may modprobe later with desired params)

# --- 3. Ensure Intel OEM HAL/icamerasrc present (no-op if already installed) ---
have_icamera=0
if gst-inspect-1.0 icamerasrc >/dev/null 2>&1; then
  have_icamera=1
fi

if [ "$have_icamera" -eq 0 ]; then
  YEL "[ipu6_install_v25] Intel HAL/icamerasrc not detected; attempting minimal install from Intel IPU6 PPA…"
  # PPA should already be present from your earlier runs; add if missing but do not fail if it's there.
  add-apt-repository -y ppa:oem-solutions-group/intel-ipu6 || true
  apt-get update -y || true
  # Install only the pieces that usually succeed; don't abort if resolver balks on some libs.
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    gstreamer1.0-icamera libcamhal0 libcamhal-common libcamhal-ipu6ep0 || true

  if gst-inspect-1.0 icamerasrc >/dev/null 2>&1; then
    BLUE "[ipu6_install_v25] icamerasrc now present."
  else
    YEL "[ipu6_install_v25] icamerasrc still not visible to GStreamer; we can continue with the overlay (you might already have it installed but not in path)."
  fi
else
  BLUE "[ipu6_install_v25] icamerasrc already present; leaving HAL as-is."
fi

# --- 4. Build a per-process libstdc++ overlay from Ubuntu 24.04 (Noble) -------
BASE="/opt/ipu6-rt"
OVER="$BASE/overlay"
BIN="$BASE/bin"
mkdir -p "$OVER" "$BIN"

has_glibcxx32() {
  # Returns 0 if the file exports GLIBCXX_3.4.32
  local so="$1"
  strings -a "$so" 2>/dev/null | grep -q 'GLIBCXX_3\.4\.32'
}

fetch_from_pool() {
  # Args: <pool-base-url> <regex> <outdir>
  local url="$1" regex="$2" out="$3"
  mkdir -p "$out"
  local index
  index="$(mktemp)"
  curl -fsSL "$url" -o "$index"
  # Pick the lexicographically latest matching .deb
  local rel="$(grep -Eo 'href="[^"]+"' "$index" | sed -E 's/^href="//; s/"$//' | grep -E "$regex" | sort -V | tail -n1 || true)"
  rm -f "$index"
  if [ -z "$rel" ]; then
    return 1
  fi
  BLUE "[pool] $rel"
  curl -fL "$url/$rel" -o "$out/$rel"
}

unpack_deb_into_overlay() {
  local deb="$1"
  dpkg-deb -x "$deb" "$OVER"
}

BLUE "[ipu6_install_v25] Fetching Noble libstdc++6 & libgcc-s1 from Ubuntu pool…"
POOL_GCC14="http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-14"
mkdir -p "$BASE/pool"
if ! fetch_from_pool "$POOL_GCC14" '^libstdc\+\+6_14\..*_amd64\.deb$' "$BASE/pool"; then
  RED "[ipu6_install_v25] Could not find libstdc++6 14.x in pool index."
  exit 1
fi
if ! fetch_from_pool "$POOL_GCC14" '^libgcc-s1_14\..*_amd64\.deb$' "$BASE/pool"; then
  YEL "[ipu6_install_v25] libgcc-s1 14.x not found; continuing (usually not needed for symbol versions)."
fi

for deb in "$BASE/pool"/*.deb; do
  BLUE "[ipu6_install_v25] Unpacking $(basename "$deb") into overlay…"
  unpack_deb_into_overlay "$deb"
done

# Verify the overlay actually has the right symbol version.
SO_CANDIDATES=()
while IFS= read -r -d '' f; do SO_CANDIDATES+=("$f"); done < <(find "$OVER" -type f -name 'libstdc++.so.6*' -print0)
if [ ${#SO_CANDIDATES[@]} -eq 0 ]; then
  RED "[ipu6_install_v25] No libstdc++.so.6 found in overlay; abort."
  exit 1
fi

OK=0
for so in "${SO_CANDIDATES[@]}"; do
  if has_glibcxx32 "$so"; then
    BLUE "[ipu6_install_v25] Verified $so exports GLIBCXX_3.4.32 ✔"
    OK=1
    break
  fi
done

if [ "$OK" -ne 1 ]; then
  RED "[ipu6_install_v25] Overlay libstdc++ still missing GLIBCXX_3.4.32. Abort."
  exit 1
fi

# --- 5. Create a wrapper to run things with the overlay ------------------------
WRAP="/usr/local/bin/icamera-run"
cat <<'EOS' | tee "$WRAP" >/dev/null
#!/usr/bin/env bash
set -Eeuo pipefail
OVER="/opt/ipu6-rt/overlay"
# Prefer both multi-arch spots, then existing LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$OVER/usr/lib/x86_64-linux-gnu:$OVER/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
exec "$@"
EOS
chmod +x "$WRAP"
BLUE "[ipu6_install_v25] Created wrapper: $WRAP"

# Optional convenience: small test helper
TESTWRAP="/usr/local/bin/icamera-inspect"
cat <<'EOS' | tee "$TESTWRAP" >/dev/null
#!/usr/bin/env bash
exec /usr/local/bin/icamera-run gst-inspect-1.0 icamerasrc "$@"
EOS
chmod +x "$TESTWRAP"

# --- 6. Friendly next steps ----------------------------------------------------
BLUE "[ipu6_install_v25] Done."
echo
cat <<'EONEXT'
Next steps to validate:
  1) Check that GStreamer now sees icamerasrc:
       icamera-inspect | head -n 20
  2) Try a live pipeline:
       icamera-run gst-launch-1.0 -v icamerasrc ! videoconvert ! autovideosink
  3) (Optional) Load a virtual camera for browsers:
       sudo modprobe v4l2loopback exclusive_caps=1 card_label="Virtual Camera"
       # Then forward frames into /dev/videoX using your relay pipeline (when you’re ready).

If icamerasrc STILL complains about GLIBCXX_3.4.32, run:
       strings -a /opt/ipu6-rt/overlay/usr/lib/x86_64-linux-gnu/libstdc++.so.6 | grep GLIBCXX
to confirm the symbol’s present (it should be).
EONEXT
