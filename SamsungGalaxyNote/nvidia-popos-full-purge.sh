#!/usr/bin/env bash
# nvidia-popos-full-purge.sh
#
# Purpose:
#   Force a clean NVIDIA package + DKMS + module purge on Pop!_OS / Ubuntu-family
#   systems that are stuck in a broken NVIDIA DKMS state because stale module
#   files remain on disk and keep causing postinst failures.
#
# What it does:
#   1. Captures a snapshot of package + kernel + dkms state.
#   2. Finds and purges all NVIDIA-related packages it can safely identify.
#   3. Force-purges remaining half-installed NVIDIA packages via dpkg.
#   4. Removes stale DKMS trees and NVIDIA source trees.
#   5. Removes stale nvidia*.ko* files from every installed kernel.
#   6. Rebuilds depmod and initramfs.
#   7. Verifies packages, DKMS state, and on-disk modules are gone.
#
# Notes:
# - Run from a TTY or SSH session, not from a graphical terminal.
# - This script is intentionally aggressive.
# - It does NOT reinstall drivers. Reinstall afterward with:
#       sudo apt update
#       sudo apt full-upgrade
#       sudo apt install system76-driver-nvidia

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"
WORKDIR_BASE="/var/backups/nvidia-full-purge"

ASSUME_YES=0
DRY_RUN=0
ALLOW_GUI=0

WORKDIR=""
LOGFILE=""
RUNNING_KERNEL="$(uname -r)"

declare -a KERNELS=()
declare -a NVIDIA_PACKAGES=()
declare -a NVIDIA_STATUS_LINES=()

usage() {
  cat <<'EOF'
Usage:
  sudo ./nvidia-popos-full-purge.sh [options]

Options:
  --yes              Non-interactive mode where possible.
  --dry-run          Print actions without changing the system.
  --allow-gui        Allow running from a graphical session. Not recommended.
  -h, --help         Show help.

Examples:
  sudo ./nvidia-popos-full-purge.sh --dry-run --yes
  sudo ./nvidia-popos-full-purge.sh --yes
EOF
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  local msg="$*"
  if [[ -n "${LOGFILE:-}" ]]; then
    printf '[%s] %s\n' "$(timestamp)" "$msg" | tee -a "$LOGFILE" >&2
  else
    printf '[%s] %s\n' "$(timestamp)" "$msg" >&2
  fi
}

warn() {
  log "WARNING: $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

confirm() {
  local prompt="$1"
  if (( ASSUME_YES )); then
    log "$prompt -> yes"
    return 0
  fi
  read -r -p "$prompt [y/N]: " reply
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

run() {
  log "+ $*"
  if (( DRY_RUN )); then
    return 0
  fi
  "$@"
}

run_shell() {
  local cmd="$1"
  log "+ bash -c '$cmd'"
  if (( DRY_RUN )); then
    return 0
  fi
  bash -c "$cmd"
}

trap_exit() {
  if [[ -n "${WORKDIR:-}" ]]; then
    log "Log and snapshot directory: $WORKDIR"
  fi
}

trap 'trap_exit' EXIT

require_root() {
  [[ "$EUID" -eq 0 ]] || die "Run this script as root."
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes)
        ASSUME_YES=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --allow-gui)
        ALLOW_GUI=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
}

require_commands() {
  local missing=()
  local cmd
  for cmd in apt-get apt-cache dpkg dpkg-query dkms find grep awk sed tar sort uname depmod update-initramfs lspci lsmod; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} > 0 )); then
    die "Missing required commands: ${missing[*]}"
  fi
}

check_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    log "Detected OS: ${PRETTY_NAME:-unknown}"
    case "${ID:-}" in
      pop|ubuntu)
        ;;
      *)
        warn "This script was tuned for Pop!_OS / Ubuntu-family systems."
        ;;
    esac
  fi
}

check_gui_session() {
  if (( ! ALLOW_GUI )) && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    die "Graphical session detected. Switch to a TTY or SSH and rerun, or use --allow-gui."
  fi
}

check_nvidia_hardware() {
  if lspci -nnk | grep -Eiq '(VGA|3D|Display).*(NVIDIA)|NVIDIA'; then
    log "NVIDIA GPU detected."
  else
    warn "No NVIDIA GPU was detected by lspci. Continuing because cleanup may still be needed."
  fi
}

gather_kernels() {
  mapfile -t KERNELS < <(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)
  (( ${#KERNELS[@]} > 0 )) || die "No installed kernels found under /lib/modules."
}

create_snapshot_dir() {
  local ts
  ts="$(date '+%Y%m%d-%H%M%S')"
  WORKDIR="$WORKDIR_BASE/$ts"
  LOGFILE="$WORKDIR/run.log"
  mkdir -p "$WORKDIR/state" "$WORKDIR/backups"
  touch "$LOGFILE"
  log "Created work directory: $WORKDIR"
}

capture_state() {
  log "Capturing current system state."
  printf '%s\n' "$SCRIPT_VERSION" > "$WORKDIR/state/script-version.txt"
  printf '%s\n' "$RUNNING_KERNEL" > "$WORKDIR/state/running-kernel.txt"
  printf '%s\n' "${KERNELS[@]}" > "$WORKDIR/state/installed-kernels.txt"

  dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' > "$WORKDIR/state/dpkg-status.tsv" || true
  apt-mark showmanual > "$WORKDIR/state/apt-manual.txt" || true
  apt-mark showhold > "$WORKDIR/state/apt-holds.txt" || true
  dkms status > "$WORKDIR/state/dkms-status-before.txt" 2>&1 || true
  lspci -nnk > "$WORKDIR/state/lspci-nnk.txt" 2>&1 || true
  lsmod > "$WORKDIR/state/lsmod-before.txt" 2>&1 || true
  find /lib/modules -type f \( -name 'nvidia*.ko' -o -name 'nvidia*.ko.zst' -o -name 'nvidia*.ko.xz' \) \
    | sort > "$WORKDIR/state/nvidia-module-files-before.txt" 2>/dev/null || true

  tar -cpf "$WORKDIR/backups/etc-modprobe-and-x11.tar" \
    /etc/modprobe.d /etc/X11 /usr/share/X11/xorg.conf.d 2>/dev/null || true
}

collect_nvidia_packages() {
  log "Collecting NVIDIA-related packages."

  mapfile -t NVIDIA_PACKAGES < <(
    dpkg-query -W -f='${Package}\n' 2>/dev/null | awk '
      BEGIN { IGNORECASE=1 }
      /^nvidia/ { print; next }
      /^libnvidia/ { print; next }
      /^xserver-xorg-video-nvidia/ { print; next }
      /^system76-driver-nvidia$/ { print; next }
      /^linux-(modules|objects)-nvidia/ { print; next }
      /^cuda/ { print; next }
      /^libcudnn/ { print; next }
      /^libcublas/ { print; next }
      /^nsight/ { print; next }
      /^nvidia-container/ { print; next }
      /^libnvidia-container/ { print; next }
      /^nvidia-docker/ { print; next }
    ' | sort -u
  )

  mapfile -t NVIDIA_STATUS_LINES < <(
    dpkg-query -W -f='${db:Status-Abbrev}\t${Package}\t${Version}\n' 2>/dev/null | awk '
      BEGIN { IGNORECASE=1 }
      $2 ~ /^nvidia/ ||
      $2 ~ /^libnvidia/ ||
      $2 ~ /^xserver-xorg-video-nvidia/ ||
      $2 ~ /^system76-driver-nvidia$/ ||
      $2 ~ /^linux-(modules|objects)-nvidia/ ||
      $2 ~ /^cuda/ ||
      $2 ~ /^libcudnn/ ||
      $2 ~ /^libcublas/ ||
      $2 ~ /^nsight/ ||
      $2 ~ /^nvidia-container/ ||
      $2 ~ /^libnvidia-container/ ||
      $2 ~ /^nvidia-docker/ { print }
    '
  )

  printf '%s\n' "${NVIDIA_PACKAGES[@]:-}" > "$WORKDIR/state/nvidia-packages-detected.txt"
  printf '%s\n' "${NVIDIA_STATUS_LINES[@]:-}" > "$WORKDIR/state/nvidia-package-status-before.txt"

  if (( ${#NVIDIA_PACKAGES[@]} == 0 )); then
    warn "No NVIDIA-related packages were detected in dpkg."
  else
    log "Detected ${#NVIDIA_PACKAGES[@]} NVIDIA-related packages."
  fi
}

stop_display_manager_if_present() {
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet display-manager.service; then
      log "Stopping display-manager.service to reduce driver-in-use issues."
      run systemctl stop display-manager.service || true
    fi
  fi
}

unhold_nvidia_packages() {
  local held
  mapfile -t held < <(apt-mark showhold 2>/dev/null | grep -Ei '^(nvidia|libnvidia|xserver-xorg-video-nvidia|system76-driver-nvidia|linux-(modules|objects)-nvidia|cuda|libcudnn|libcublas|nsight|nvidia-container|libnvidia-container|nvidia-docker)' || true)
  if (( ${#held[@]} > 0 )); then
    log "Removing apt holds from NVIDIA-related packages."
    run apt-mark unhold "${held[@]}" || true
  fi
}

apt_purge_nvidia_packages() {
  if (( ${#NVIDIA_PACKAGES[@]} > 0 )); then
    log "Purging NVIDIA-related packages with apt."
    run apt-get -y purge "${NVIDIA_PACKAGES[@]}" || true
  fi

  run apt-get -y autoremove --purge || true
  run apt-get clean || true
}

force_purge_leftover_packages() {
  log "Looking for leftover half-installed NVIDIA-related packages."
  local -a leftovers=()
  mapfile -t leftovers < <(
    dpkg-query -W -f='${db:Status-Abbrev}\t${Package}\n' 2>/dev/null | awk '
      BEGIN { IGNORECASE=1 }
      ($2 ~ /^nvidia/ ||
       $2 ~ /^libnvidia/ ||
       $2 ~ /^xserver-xorg-video-nvidia/ ||
       $2 ~ /^system76-driver-nvidia$/ ||
       $2 ~ /^linux-(modules|objects)-nvidia/ ||
       $2 ~ /^cuda/ ||
       $2 ~ /^libcudnn/ ||
       $2 ~ /^libcublas/ ||
       $2 ~ /^nsight/ ||
       $2 ~ /^nvidia-container/ ||
       $2 ~ /^libnvidia-container/ ||
       $2 ~ /^nvidia-docker/) { print $2 }
    ' | sort -u
  )

  if (( ${#leftovers[@]} > 0 )); then
    log "Force-purging remaining NVIDIA-related packages with dpkg."
    local pkg
    for pkg in "${leftovers[@]}"; do
      run dpkg --purge --force-all "$pkg" || true
    done
  fi
}

remove_nvidia_dkms_trees() {
  log "Removing NVIDIA DKMS trees and source trees."
  local path
  for path in /var/lib/dkms/nvidia /var/lib/dkms/nvidia-* /usr/src/nvidia-* /usr/src/nvidia_open-* /usr/src/nvidia-open-*; do
    [[ -e "$path" ]] || continue
    run rm -rf -- "$path"
  done
}

remove_nvidia_module_files() {
  log "Removing stale NVIDIA module files from installed kernels."
  local k kdir file removed
  for k in "${KERNELS[@]}"; do
    removed=0
    for kdir in "/lib/modules/$k/updates/dkms" "/lib/modules/$k/updates" "/lib/modules/$k/extra" "/lib/modules/$k/kernel/drivers/video"; do
      [[ -d "$kdir" ]] || continue
      while IFS= read -r -d '' file; do
        log "Removing $file"
        if (( ! DRY_RUN )); then
          rm -f -- "$file"
        fi
        removed=1
      done < <(find "$kdir" -maxdepth 2 -type f \( -name 'nvidia*.ko' -o -name 'nvidia*.ko.zst' -o -name 'nvidia*.ko.xz' \) -print0 2>/dev/null || true)
    done

    if (( removed )); then
      run depmod -a "$k" || true
    fi
  done
}

remove_residual_config_files() {
  log "Removing common NVIDIA residual config files."
  local f
  for f in \
    /etc/modprobe.d/nvidia*.conf \
    /etc/modprobe.d/*nvidia*.conf \
    /lib/modprobe.d/nvidia*.conf \
    /etc/X11/xorg.conf \
    /etc/X11/xorg.conf.d/10-nvidia*.conf \
    /usr/share/X11/xorg.conf.d/10-nvidia*.conf
  do
    compgen -G "$f" >/dev/null || continue
    run_shell "rm -f -- $f"
  done
}

repair_package_state() {
  log "Repairing dpkg/apt state after purge."
  run dpkg --configure -a || true
  run apt-get -y install -f || true
  run apt-get -y autoremove --purge || true
  run apt-get clean || true
}

rebuild_initramfs_and_depmod() {
  log "Rebuilding depmod for all kernels."
  local k
  for k in "${KERNELS[@]}"; do
    run depmod -a "$k" || true
  done

  log "Rebuilding initramfs."
  run update-initramfs -u -k all || true
}

post_check_packages_removed() {
  log "Checking that NVIDIA-related packages are gone."
  local remaining
  remaining="$(
    dpkg-query -W -f='${db:Status-Abbrev}\t${Package}\t${Version}\n' 2>/dev/null | awk '
      BEGIN { IGNORECASE=1 }
      $2 ~ /^nvidia/ ||
      $2 ~ /^libnvidia/ ||
      $2 ~ /^xserver-xorg-video-nvidia/ ||
      $2 ~ /^system76-driver-nvidia$/ ||
      $2 ~ /^linux-(modules|objects)-nvidia/ ||
      $2 ~ /^cuda/ ||
      $2 ~ /^libcudnn/ ||
      $2 ~ /^libcublas/ ||
      $2 ~ /^nsight/ ||
      $2 ~ /^nvidia-container/ ||
      $2 ~ /^libnvidia-container/ ||
      $2 ~ /^nvidia-docker/ { print }
    '
  )"

  printf '%s\n' "$remaining" > "$WORKDIR/state/nvidia-package-status-after.txt"

  if [[ -n "$remaining" ]]; then
    warn "Some NVIDIA-related packages still appear in dpkg state:"
    printf '%s\n' "$remaining" | tee -a "$LOGFILE" >&2
  else
    log "No NVIDIA-related packages remain in dpkg."
  fi
}

post_check_dkms_removed() {
  log "Checking that NVIDIA DKMS entries are gone."
  local dk
  dk="$(dkms status 2>/dev/null | grep -i '^nvidia/' || true)"
  printf '%s\n' "$dk" > "$WORKDIR/state/dkms-status-after.txt"
  if [[ -n "$dk" ]]; then
    warn "NVIDIA DKMS entries still exist:"
    printf '%s\n' "$dk" | tee -a "$LOGFILE" >&2
  else
    log "No NVIDIA DKMS entries remain."
  fi
}

post_check_module_files_removed() {
  log "Checking that NVIDIA kernel module files are gone."
  local files
  files="$(find /lib/modules -type f \( -name 'nvidia*.ko' -o -name 'nvidia*.ko.zst' -o -name 'nvidia*.ko.xz' \) | sort || true)"
  printf '%s\n' "$files" > "$WORKDIR/state/nvidia-module-files-after.txt"
  if [[ -n "$files" ]]; then
    warn "NVIDIA module files still exist on disk:"
    printf '%s\n' "$files" | tee -a "$LOGFILE" >&2
  else
    log "No NVIDIA module files remain under /lib/modules."
  fi
}

post_check_loaded_modules() {
  log "Checking loaded NVIDIA modules."
  local mods
  mods="$(lsmod | awk 'tolower($1) ~ /^nvidia/ { print }' || true)"
  printf '%s\n' "$mods" > "$WORKDIR/state/lsmod-after.txt"
  if [[ -n "$mods" ]]; then
    warn "NVIDIA modules are still loaded in the running kernel:"
    printf '%s\n' "$mods" | tee -a "$LOGFILE" >&2
    warn "A reboot may be needed before reinstall."
  else
    log "No loaded NVIDIA modules remain."
  fi
}

final_summary() {
  local problems=0

  [[ -s "$WORKDIR/state/nvidia-package-status-after.txt" ]] && grep -q '[^[:space:]]' "$WORKDIR/state/nvidia-package-status-after.txt" && ((problems+=1))
  [[ -s "$WORKDIR/state/dkms-status-after.txt" ]] && grep -q '[^[:space:]]' "$WORKDIR/state/dkms-status-after.txt" && ((problems+=1))
  [[ -s "$WORKDIR/state/nvidia-module-files-after.txt" ]] && grep -q '[^[:space:]]' "$WORKDIR/state/nvidia-module-files-after.txt" && ((problems+=1))

  if (( problems == 0 )); then
    log "Purge completed cleanly."
    log "Next steps:"
    log "  1. Reboot."
    log "  2. Run: sudo apt update && sudo apt full-upgrade"
    log "  3. Reinstall proprietary driver with: sudo apt install system76-driver-nvidia"
  else
    warn "Purge completed, but residual NVIDIA state remains. Review:"
    warn "  $WORKDIR/state/nvidia-package-status-after.txt"
    warn "  $WORKDIR/state/dkms-status-after.txt"
    warn "  $WORKDIR/state/nvidia-module-files-after.txt"
    warn "A reboot is still recommended before further repair work."
  fi
}

main() {
  parse_args "$@"
  require_root
  require_commands
  check_os
  check_gui_session
  check_nvidia_hardware
  gather_kernels
  create_snapshot_dir
  capture_state
  collect_nvidia_packages

  cat >&2 <<EOF
About to aggressively purge NVIDIA-related packages and stale kernel modules.

This may remove:
  - NVIDIA proprietary/open driver packages
  - DKMS trees and source trees
  - leftover nvidia*.ko* files from installed kernels
  - common NVIDIA Xorg/modprobe config files

Snapshot/log directory:
  $WORKDIR
EOF

  confirm "Continue?" || die "Aborted by user."

  stop_display_manager_if_present
  unhold_nvidia_packages
  apt_purge_nvidia_packages
  force_purge_leftover_packages
  remove_nvidia_dkms_trees
  remove_nvidia_module_files
  remove_residual_config_files
  repair_package_state
  rebuild_initramfs_and_depmod
  post_check_packages_removed
  post_check_dkms_removed
  post_check_module_files_removed
  post_check_loaded_modules
  final_summary
}

main "$@"
