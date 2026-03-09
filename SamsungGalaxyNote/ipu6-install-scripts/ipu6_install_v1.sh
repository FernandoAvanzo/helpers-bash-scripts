#!/usr/bin/env bash
# -------------------------------------------------------------------------
#  Intel IPU-6 / IPU-6E webcam stack installer      (Galaxy Book4 Ultra)
#  Pop!_OS 22.04 · kernel ≥ 6.10                    2025-06-29 · v1.7
# -------------------------------------------------------------------------
#  • Pulls/up-dates Intel’s four upstream repos
#  • Builds DKMS driver, installs firmware & user-space HAL
#  • GStreamer ≥ 1.23 auto-upgrade via Savoury1 PPA
#  • Idempotent – safe to re-run; DEBUG=1 prints every command
# -------------------------------------------------------------------------
set -Eeuo pipefail
[[ "${DEBUG:-}" == "1" ]] && set -x
trap 'echo >&2 "❌  aborted at line $LINENO"; exit 1' ERR

# ---------- paths ---------------------------------------------------------
STACK_DIR=/opt/ipu6
BACKUP_DIR=/opt/ipu6-backup-$(date +%F-%H%M)
IPU_FW_DIR=/lib/firmware/intel/ipu
DRV_NAME=ipu6-drivers
DRV_VER=0.0.0
SRC_DIR=/usr/src/${DRV_NAME}-${DRV_VER}
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }

# ---------- 0.  make sure GStreamer ≥ 1.23 --------------------------------
need_gst() { pkg-config --exists gstreamer-1.0 && pkg-config --atleast-version=1.23 gstreamer-1.0; }
if ! need_gst; then
  echo "==> Enabling Savoury1 multimedia PPA (GStreamer 1.24.x)"
  apt install -y software-properties-common
  add-apt-repository -y ppa:savoury1/multimedia
  apt update && apt full-upgrade -y
fi

# ---------- 1.  build dependencies ---------------------------------------
echo "==> Installing build dependencies"
apt install -y dkms build-essential git cmake ninja-build meson \
  linux-headers-$(uname -r) libexpat1-dev automake libtool libdrm-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-vaapi \
  libva-dev libva-drm2 pkg-config

# ---------- 2.  clone / update the repos ---------------------------------
echo "==> Fetching Intel sources"
mkdir -p "$STACK_DIR" && cd "$STACK_DIR"

clone() {
  local url=$1 branch=${2:-} dir; dir=$(basename "${url%.git}")

  if [[ -d $dir/.git ]]; then
    git -C "$dir" pull --rebase --quiet
  else
    git clone --depth 1 --quiet "$url" "$dir"
  fi

  if [[ -n $branch ]]; then
    if git -C "$dir" ls-remote --heads origin "$branch" &>/dev/null; then
      echo "      → $dir : switching to $branch"
      git -C "$dir" fetch --depth 1 --quiet origin "$branch"
      git -C "$dir" checkout --quiet -B "$branch" FETCH_HEAD
    else
      echo "⚠️   $dir : branch '$branch' not found – using default"
    fi
  fi
}

clone https://github.com/intel/ipu6-drivers.git
clone https://github.com/intel/ipu6-camera-bins.git
clone https://github.com/intel/ipu6-camera-hal.git
clone https://github.com/intel/icamerasrc.git icamerasrc_slim_api   # falls back gracefully if deleted

# ---------- 3.  DKMS driver ----------------------------------------------
echo "==> DKMS: $DRV_NAME $DRV_VER"
if dkms status | grep -qE "^$DRV_NAME, $DRV_VER"; then
  dkms build -m "$DRV_NAME" -v "$DRV_VER" || {
    dkms remove -m "$DRV_NAME" -v "$DRV_VER" --all
    rm -rf "$SRC_DIR"
  }
fi
if ! dkms status | grep -qE "^$DRV_NAME, $DRV_VER"; then
  [[ -d $SRC_DIR ]] || cp -a ipu6-drivers "$SRC_DIR"
  dkms add -m "$DRV_NAME" -v "$DRV_VER"
fi
dkms build   -m "$DRV_NAME" -v "$DRV_VER"
dkms install -m "$DRV_NAME" -v "$DRV_VER" --force

# ---------- 4.  firmware & proprietary libs ------------------------------
echo "==> Installing IPU firmware"
mkdir -p "$BACKUP_DIR"
[[ -d $IPU_FW_DIR ]] && cp -a "$IPU_FW_DIR" "$BACKUP_DIR/" || true
mkdir -p "$IPU_FW_DIR"

find ipu6-camera-bins -type f -name '*_fw.bin' -print0 |
while IFS= read -r -d '' src; do
  dst="$IPU_FW_DIR/$(basename "$src")"
  [[ -e $dst ]] && continue           # skip duplicates
  install -m 644 "$src" "$dst"
done

pushd ipu6-camera-bins/lib >/dev/null
for lib in lib*.so.*; do ln -sf "$lib" "${lib%.*}"; done
cp -P lib* /usr/lib/
popd >/dev/null
ldconfig

# ---------- 5.  camera-HAL -----------------------------------------------
echo "==> Building camera HAL"
cd ipu6-camera-hal
rm -rf build && mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DIPU_VERSIONS="ipu6;ipu6ep;ipu6epmtl" \
      -DUSE_PG_LITE_PIPE=ON ..
make -j"$(nproc)"
make install

# ---------- 6.  icamerasrc plugin ----------------------------------------
echo "==> Building icamerasrc"
cd "$STACK_DIR/icamerasrc"
export CHROME_SLIM_CAMHAL=ON
./autogen.sh
./configure --prefix=/usr --enable-gstdrmformat=yes
make -j"$(nproc)"
make install
ldconfig

# ---------- 7.  done ------------------------------------------------------
echo -e "\n✅  IPU-6 stack installed."
echo "🔄  Reboot, then test with:"
echo "     gst-launch-1.0 icamerasrc ! videoconvert ! autovideosink"
