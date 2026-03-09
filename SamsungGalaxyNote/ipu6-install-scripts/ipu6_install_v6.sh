#!/usr/bin/env bash
set -euo pipefail

log(){ echo -e "[ipu6_install_v6] $*"; }

require_root(){
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo $0"; exit 1
  fi
}

require_jammy(){
  . /etc/os-release
  if [[ "${VERSION_CODENAME:-}" != "jammy" ]]; then
    echo "This script targets 22.04 (Jammy). Detected: ${PRETTY_NAME:-unknown}. Abort."; exit 1
  fi
}

require_tools(){
  apt-get update -y
  apt-get install -y --no-install-recommends \
    apt-transport-https ca-certificates curl wget software-properties-common \
    linux-firmware v4l-utils libglib2.0-0
}

purge_conflicts(){
  log "Purging conflicting/out-of-tree IPU6/USBIO/IVSC stacks (ignore 'not installed' msgs)..."
  apt-get -y autopurge \
    'ivsc-*' 'intel-ivsc-*' 'usbio-*' 'linux-modules-*usbio*' \
    'linux-modules-ipu6-*' 'libspa-0.2-libcamera' \
    'lib*gcss*' 'lib*ia-*' 'lib*ipu6*' 'lib*ipu7*' || true

  # quarantine any stray OOT modules in the running kernel tree
  KVER="$(uname -r)"
  for d in /lib/modules/"$KVER"/updates/dkms /lib/modules/"$KVER"/extra; do
    if [[ -d "$d" ]]; then
      mkdir -p "$d".quarantine
      find "$d" -maxdepth 1 -type f -name '*ipu6*.ko*' -o -name '*usbio*.ko*' | while read -r f; do
        mv -f "$f" "$d".quarantine/ || true
      done
    fi
  done
}

install_hwe_with_ipu6(){
  log "Installing Jammy HWE kernel + IPU6 & USBIO module metas..."
  # HWE kernel meta (6.8 series on Jammy) + module metas that contain the drivers
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    linux-generic-hwe-22.04 \
    linux-modules-ipu6-generic-hwe-22.04 \
    linux-modules-usbio-generic-hwe-22.04

  # Record the just-installed HWE kernel version (latest 6.8.* generic)
  HWE_KVER="$(dpkg -l | awk '/^ii\s+linux-image-[0-9].*generic/{print $2" "$3}' \
    | sort -V | tail -n1 | awk '{print $1}' \
    | sed -E 's/linux-image-//')"

  if [[ -z "${HWE_KVER:-}" ]] || [[ ! -f "/boot/vmlinuz-$HWE_KVER" ]]; then
    echo "Could not determine installed HWE kernel version. Abort."; exit 1
  fi

  log "Installed kernel: $HWE_KVER"

  # Ensure initramfs exists for it
  update-initramfs -c -k "$HWE_KVER" || update-initramfs -u -k "$HWE_KVER"

  # On Pop!_OS use kernelstub to make a boot entry so systemd-boot can see it
  if command -v kernelstub >/dev/null 2>&1; then
    log "Registering HWE kernel with kernelstub (Pop!_OS boot manager)..."
    kernelstub -k "/boot/vmlinuz-$HWE_KVER" -i "/boot/initrd.img-$HWE_KVER" || true
  fi
}

ensure_firmware(){
  log "Checking IPU6 firmware..."
  # Meteor Lake (MTL) IPU6 firmware file name
  if [[ ! -f /lib/firmware/intel/ipu/ipu6epmtl_fw.bin ]]; then
    log "WARNING: /lib/firmware/intel/ipu/ipu6epmtl_fw.bin not found. Reinstalling linux-firmware..."
    apt-get install -y --reinstall linux-firmware
  fi
}

install_userspace(){
  log "Installing minimal user-space (libcamera tools + helpers)..."
  # Jammy's libcamera is old but OK for quick tests; we avoid gst auto-scan crashes by not installing -devs
  apt-get install -y libcamera-tools v4l-utils pipewire wireplumber xdg-desktop-portal xdg-desktop-portal-gnome
}

post_notes(){
  cat <<'EOF'

[ipu6_install_v6] Done. NEXT STEPS:

1) Reboot into the new kernel (HWE 6.8 series).
   - If your system shows a boot picker (systemd-boot), choose the new "Linux ... generic" entry.
   - If it boots straight through, the kernelstub step should have added it automatically.

2) After reboot, verify the drivers are present:
     uname -r
     lsmod | egrep 'ipu6|ivsc|usbio' || true
     modinfo intel_ipu6_psys | head
     ls /dev/video* 2>/dev/null

3) Quick camera smoke test (without GStreamer):
     cam -l
     cam -c 1 --stream

   If your app is V4L2-only, try LD_PRELOAD shim:
     apt-get install -y libspa-0.2-libcamera || true
     # or run libcamera-based apps directly.

4) If you ever want to roll back to the Pop kernel:
     sudo apt-get autopurge 'linux-image-6.8.*-generic' 'linux-headers-6.8.*-generic' \
                            linux-generic-hwe-22.04 linux-modules-ipu6-generic-hwe-22.04 \
                            linux-modules-usbio-generic-hwe-22.04
     sudo kernelstub --verbose   # to clean boot entries if needed

EOF
}

### main
require_root
require_jammy
log "Preflight..."
require_tools
purge_conflicts
ensure_firmware
install_hwe_with_ipu6
install_userspace
post_notes
