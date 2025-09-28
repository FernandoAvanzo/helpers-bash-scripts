#!/usr/bin/env bash
set -euo pipefail

echo "[0/7] Pre-flight..."
if ! grep -q "Pop!_OS 22.04" /etc/os-release; then
  echo "This script is tuned for Pop!_OS 22.04 (Jammy base). Exiting."; exit 1
fi
KVER="$(uname -r)"
echo "Kernel: $KVER"

echo "[1/7] Remove conflicting PPAs & packages (savoury1 etc.)..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ppa-purge || true
for ppa in savoury1/ffmpeg4 savoury1/multimedia savoury1/backports; do
  if [ -e "/etc/apt/sources.list.d/${ppa//\//-}-ubuntu-*.list" ]; then
    echo "  - ppa-purge ppa:$ppa"
    ppa-purge -y "ppa:$ppa" || true
  fi
done
# Also disable any .list that mentions savoury1 or ipu6 dev PPAs:
grep -rilE 'savoury1|oem-solutions-group|intel-ipu6|intel-ipu7' /etc/apt/sources.list.d/ 2>/dev/null \
  | xargs -r -I{} bash -c 'echo "# disabled by ipu6_webcam_fix_v4" >> "{}"; mv "{}" "{}.disabled"'

echo "[2/7] Purge out-of-tree IPU6/IVSC/USBIO stacks (if any) and clean leftovers..."
# Purge known dkms & HAL/plugin packages if present
PKGS=(
  intel-ipu6-dkms intel-ivsc-dkms usbio-dkms libcamhal* icamerasrc* intel-mipi* linux-modules-ipu6*
  gstreamer1.0-libcamera libspa-0.2-libcamera
)
DEBIAN_FRONTEND=noninteractive apt-get purge -y "${PKGS[@]}" 2>/dev/null || true
# Remove any stray .ko from dkms/updates trees for current kernel
find "/lib/modules/$KVER" -type f \
  \( -name 'intel_ipu6*.ko*' -o -name 'ipu6*.ko*' -o -name 'ov02c10*.ko*' -o -name 'ivsc*.ko*' -o -name 'usbio*.ko*' \) \
  -path "*/updates/*" -print -delete || true
depmod -a "$KVER"

echo "[3/7] Make sure the official firmware & base multimedia stack are in place..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  linux-firmware v4l-utils
FWM=/lib/firmware/intel/ipu/ipu6epmtl_fw.bin
if [ -f "$FWM" ]; then
  echo "  - Found IPU6 MTL firmware: $FWM"
else
  echo "  ! WARNING: $FWM not found. Your linux-firmware may be too old."
  echo "    On Pop!_OS this file should exist; re-check linux-firmware afterwards."
fi

echo "[4/7] Install libcamera tooling from Jammy repos (no PPAs)..."
# libcamera-tools provides 'cam' and 'qcam' on Jammy
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  libcamera-tools libcamera0 gstreamer1.0-plugins-bad pipewire wireplumber \
  xdg-desktop-portal xdg-desktop-portal-gnome || true

# Try libcamera-v4l2 if available on your repo; if not, continue
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libcamera-v4l2 || true

echo "[5/7] Ensure we only ever load in-kernel IPU6"
# Rebuild initramfs for all kernels to flush any stale OOT modules that might be bundled
update-initramfs -u -k all
# Proactively unload any stale modules now (ignore errors if not loaded)
modprobe -r intel_ipu6_psys intel_ipu6_isys intel_ipu6 2>/dev/null || true

echo "[6/7] Create a 'libcamerify' helper (V4L2 compatibility via LD_PRELOAD) ..."
# Some apps only speak V4L2. libcamera’s V4L2 compat can be preloaded.
WRAP=/usr/local/bin/libcamerify
LIBPATH="$(ldconfig -p 2>/dev/null | awk '/libcamera/ && /v4l2.*compat.*\.so/ {print $NF; exit}')"
if [ -z "$LIBPATH" ]; then
  # Try common paths
  for p in /usr/lib/x86_64-linux-gnu/libcamera/v4l2-compat.so \
  /usr/lib64/libcamera/v4l2-compat.so ; do
    [ -f "$p" ] && LIBPATH="$p" && break
  done
fi
cat > "$WRAP" <<EOF
#!/usr/bin/env bash
set -euo pipefail
LIB="\${LIBCAMERA_V4L2_COMPAT:-$LIBPATH}"
if [ ! -f "\$LIB" ]; then
  echo "libcamerify: libcamera V4L2 compat library not found. Try running 'cam -l' to verify camera first." >&2
  exec "\$@"
else
  export LD_PRELOAD="\$LIB:\${LD_PRELOAD-}"
  exec "\$@"
fi
EOF
chmod +x "$WRAP"
[ -n "$LIBPATH" ] && echo "  - libcamerify will use: $LIBPATH" || echo "  - libcamerify installed (will no-op if compat lib not present)."

echo "[7/7] Restart user services (PipeWire/portal), then quick sanity checks..."
loginctl enable-linger "$SUDO_USER" >/dev/null 2>&1 || true
systemctl --user daemon-reload || true
systemctl --user restart wireplumber pipewire xdg-desktop-portal xdg-desktop-portal-gnome || true

echo
echo "Done. Now try:"
echo "  1) cam -l                      # list detected cameras"
echo "  2) cam -c 1 --stream           # quick preview from first camera"
echo "If your browser/app is V4L2-only, try:"
echo "  libcamerify cheese             # or: libcamerify firefox"
echo
echo "If 'cam -l' shows nothing, run:"
echo "  journalctl -b -k | egrep -i 'ipu6|ov02c10|ivsc|vsc|intel'"
echo
