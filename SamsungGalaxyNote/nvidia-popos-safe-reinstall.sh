#!/usr/bin/env bash
# nvidia-popos-safe-reinstall.sh
#
# Safe-ish NVIDIA driver rollback/reinstall helper for Pop!_OS.
# Designed for DKMS/package-manager failures where stale NVIDIA modules
# or half-configured packages block a clean reinstall.
#
# What it does:
#   1. Captures a recovery snapshot (package list, configs, logs).
#   2. Purges the current NVIDIA driver stack.
#   3. Removes stale DKMS trees and leftover nvidia*.ko* files.
#   4. Repairs apt/dpkg state.
#   5. Reinstalls the proprietary NVIDIA stack via system76-driver-nvidia.
#   6. Runs post-checks.
#   7. Attempts a best-effort rollback if something fails.
#
# IMPORTANT:
# - Run this from a TTY or SSH session, not from a GUI terminal.
# - A reboot is strongly recommended after a successful run.
# - The rollback is best-effort, not transactional.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"

DEFAULT_INSTALL_PACKAGE="system76-driver-nvidia"
WORKDIR_BASE="/var/backups/nvidia-driver-reinstall"

ASSUME_YES=0
DRY_RUN=0
AUTO_ROLLBACK=1
ALLOW_SECURE_BOOT=0
INSTALL_PACKAGE="$DEFAULT_INSTALL_PACKAGE"
ROLLBACK_DIR=""

WORKDIR=""
LOGFILE=""
RUNNING_KERNEL="$(uname -r)"
ROLLBACK_IN_PROGRESS=0

declare -a KERNELS=()
declare -a DRIVER_PACKAGES=()
declare -a PREV_DRIVER_PACKAGES=()
declare -a PREV_DRIVER_PACKAGES_WITH_VERSIONS=()

usage() {
  cat <<'EOF'
Usage:
  sudo ./nvidia-popos-safe-reinstall.sh [options]

Options:
  --yes                      Run non-interactively where possible.
  --dry-run                  Print what would be done without changing the system.
  --install-package PKG      Package to install after cleanup.
                             Default: system76-driver-nvidia
  --allow-secure-boot        Continue even if Secure Boot appears enabled.
                             Not recommended on Pop!_OS for this workflow.
  --no-auto-rollback         Do not attempt automatic best-effort rollback on failure.
  --rollback DIR             Restore from a previous snapshot directory.
  -h, --help                 Show this help.

Examples:
  sudo ./nvidia-popos-safe-reinstall.sh --yes
  sudo ./nvidia-popos-safe-reinstall.sh --yes --dry-run
  sudo ./nvidia-popos-safe-reinstall.sh --rollback /var/backups/nvidia-driver-reinstall/20260310-120000
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

cleanup_temp() {
  :
}

on_exit() {
  cleanup_temp || true
  if [[ -n "${WORKDIR:-}" ]]; then
    log "Snapshot/log directory: $WORKDIR"
  fi
}

restore_configs_from_backup() {
  local dir="$1"
  local archive="$dir/backups/config-files.tar"
  if [[ -f "$archive" ]]; then
    log "Restoring backed up NVIDIA-related configuration files."
    if (( ! DRY_RUN )); then
      tar -xpf "$archive" -C / || true
    fi
  fi
}

repair_apt_state() {
  log "Repairing apt/dpkg state."
  run apt-get clean
  run_shell 'rm -rf /var/lib/apt/lists/*'
  run apt-get update
  run dpkg --configure -a
  run apt-get -y install -f
  run apt-get -y full-upgrade
  run apt-get -y autoremove --purge
}

best_effort_restart_initramfs() {
  if command -v update-initramfs >/dev/null 2>&1; then
    run update-initramfs -u -k all || true
  fi
}

perform_rollback() {
  local dir="${1:-$WORKDIR}"
  [[ -n "$dir" && -d "$dir" ]] || {
    warn "Rollback requested, but snapshot directory is missing."
    return 1
  }

  ROLLBACK_IN_PROGRESS=1
  log "Starting best-effort rollback from: $dir"

  restore_configs_from_backup "$dir"

  repair_apt_state || true

  local versions_file="$dir/state/previous-driver-packages-with-versions.txt"
  local names_file="$dir/state/previous-driver-packages.txt"
  local -a pkgs=()

  if [[ -f "$versions_file" ]] && [[ -s "$versions_file" ]]; then
    mapfile -t pkgs < "$versions_file"
    if (( ${#pkgs[@]} > 0 )); then
      log "Attempting rollback using previously installed package versions."
      if ! run apt-get -y install "${pkgs[@]}"; then
        warn "Version-locked rollback failed; trying package names only."
      fi
    fi
  fi

  if [[ -f "$names_file" ]] && [[ -s "$names_file" ]]; then
    mapfile -t pkgs < "$names_file"
    if (( ${#pkgs[@]} > 0 )); then
      run apt-get -y install "${pkgs[@]}" || true
    fi
  fi

  repair_apt_state || true
  best_effort_restart_initramfs || true

  log "Rollback attempt finished. A reboot is recommended."
}

on_err() {
  local line="$1"
  local exit_code="$2"
  trap - ERR
  warn "Script failed at line $line with exit code $exit_code."

  if (( AUTO_ROLLBACK )) && (( ! ROLLBACK_IN_PROGRESS )) && [[ -n "${WORKDIR:-}" ]] && [[ -d "${WORKDIR:-}" ]]; then
    warn "Attempting automatic best-effort rollback."
    perform_rollback "$WORKDIR" || true
  fi

  exit "$exit_code"
}

trap 'on_err "$LINENO" "$?"' ERR
trap on_exit EXIT

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
      --install-package)
        shift
        [[ $# -gt 0 ]] || die "--install-package requires a value."
        INSTALL_PACKAGE="$1"
        ;;
      --allow-secure-boot)
        ALLOW_SECURE_BOOT=1
        ;;
      --no-auto-rollback)
        AUTO_ROLLBACK=0
        ;;
      --rollback)
        shift
        [[ $# -gt 0 ]] || die "--rollback requires a directory."
        ROLLBACK_DIR="$1"
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
  for cmd in apt-get apt-cache dpkg dpkg-query lspci modprobe modinfo depmod grep awk sed tar find sort uname; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} > 0 )); then
    die "Missing required commands: ${missing[*]}"
  fi
}

check_pop_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != "pop" && "${NAME:-}" != *"Pop!_OS"* ]]; then
      warn "This does not look like Pop!_OS. The script is tuned for Pop!_OS and System76 packaging."
    fi
  else
    warn "Cannot read /etc/os-release; continuing carefully."
  fi
}

check_not_running_inside_gui_terminal() {
  if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    die "You appear to be running this from a GUI session. Switch to a TTY (for example Ctrl+Alt+F3) or SSH and run it again."
  fi
}

check_nvidia_hardware() {
  if ! lspci -nnk | grep -Eiq '(^|[[:space:]])(VGA|3D|Display).*(NVIDIA)|NVIDIA'; then
    die "No NVIDIA GPU was detected by lspci."
  fi
}

check_secure_boot() {
  if command -v mokutil >/dev/null 2>&1; then
    local sb_state
    sb_state="$(mokutil --sb-state 2>/dev/null || true)"
    if grep -qi 'enabled' <<<"$sb_state"; then
      if (( ALLOW_SECURE_BOOT )); then
        warn "Secure Boot appears enabled. Continuing because --allow-secure-boot was supplied."
      else
        die "Secure Boot appears enabled. On Pop!_OS, disable Secure Boot for this NVIDIA reinstall workflow, or rerun with --allow-secure-boot if you knowingly manage your own signing."
      fi
    fi
  fi
}

gather_kernels() {
  mapfile -t KERNELS < <(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)
  if (( ${#KERNELS[@]} == 0 )); then
    die "No installed kernels were found under /lib/modules."
  fi
}

check_disk_space() {
  local mountpoint min_mb avail_mb
  while read -r mountpoint min_mb; do
    if mountpoint -q "$mountpoint" 2>/dev/null || [[ "$mountpoint" == "/" ]]; then
      avail_mb="$(df -Pm "$mountpoint" | awk 'NR==2 {print $4}')"
      if [[ -n "$avail_mb" ]] && [[ "$avail_mb" =~ ^[0-9]+$ ]] && (( avail_mb < min_mb )); then
        warn "Low free space on $mountpoint: ${avail_mb}MB available (recommended minimum ${min_mb}MB)."
      fi
    fi
  done <<'EOF'
/ 2048
/boot 512
/boot/efi 128
EOF
}

collect_driver_package_lists() {
  local pkg
  mapfile -t PREV_DRIVER_PACKAGES_WITH_VERSIONS < <(
    dpkg-query -W -f='${Package}=${Version}\n' 2>/dev/null | while IFS= read -r pkg; do
      case "$pkg" in
        nvidia-cuda-*|cuda-*|libcudnn*|libcublas*|nsight-*|libnvidia-container*|nvidia-container-*|nvidia-docker*)
          ;;
        nvidia-*|libnvidia-*|xserver-xorg-video-nvidia*|linux-*-nvidia*|system76-driver-nvidia=*)
          printf '%s\n' "$pkg"
          ;;
      esac
    done | sort -u
  )

  PREV_DRIVER_PACKAGES=()
  if (( ${#PREV_DRIVER_PACKAGES_WITH_VERSIONS[@]} > 0 )); then
    local entry
    for entry in "${PREV_DRIVER_PACKAGES_WITH_VERSIONS[@]}"; do
      PREV_DRIVER_PACKAGES+=("${entry%%=*}")
    done
  fi

  DRIVER_PACKAGES=("${PREV_DRIVER_PACKAGES[@]}")
}

create_snapshot_dir() {
  local ts
  ts="$(date '+%Y%m%d-%H%M%S')"
  WORKDIR="$WORKDIR_BASE/$ts"
  LOGFILE="$WORKDIR/run.log"
  mkdir -p "$WORKDIR/state" "$WORKDIR/backups"
  touch "$LOGFILE"
  log "Created snapshot directory: $WORKDIR"
}

capture_state() {
  log "Capturing pre-change state."

  printf '%s\n' "$SCRIPT_VERSION" > "$WORKDIR/state/script-version.txt"
  printf '%s\n' "$INSTALL_PACKAGE" > "$WORKDIR/state/requested-install-package.txt"
  printf '%s\n' "$RUNNING_KERNEL" > "$WORKDIR/state/running-kernel.txt"
  printf '%s\n' "${KERNELS[@]}" > "$WORKDIR/state/installed-kernels.txt"

  collect_driver_package_lists
  printf '%s\n' "${PREV_DRIVER_PACKAGES[@]:-}" > "$WORKDIR/state/previous-driver-packages.txt"
  printf '%s\n' "${PREV_DRIVER_PACKAGES_WITH_VERSIONS[@]:-}" > "$WORKDIR/state/previous-driver-packages-with-versions.txt"

  apt-mark showmanual > "$WORKDIR/state/apt-manual.txt" || true
  dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' > "$WORKDIR/state/dpkg-status.tsv" || true
  dkms status > "$WORKDIR/state/dkms-status-before.txt" 2>&1 || true
  apt-mark showhold > "$WORKDIR/state/apt-holds-before.txt" 2>&1 || true
  lspci -nnk > "$WORKDIR/state/lspci-nnk.txt" 2>&1 || true
  lsmod > "$WORKDIR/state/lsmod-before.txt" 2>&1 || true
  modprobe -c | grep -i nvidia > "$WORKDIR/state/modprobe-nvidia-before.txt" 2>&1 || true
  journalctl -k -b --no-pager > "$WORKDIR/state/kernel-journal-before.txt" 2>&1 || true

  local -a backup_paths=()
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] && backup_paths+=("$path")
  done < <(find /etc/modprobe.d /etc/X11 /usr/share/X11/xorg.conf.d -maxdepth 2 -type f \( -iname '*nvidia*' -o -name 'xorg.conf' \) 2>/dev/null | sort -u)

  if (( ${#backup_paths[@]} > 0 )); then
    tar -cpf "$WORKDIR/backups/config-files.tar" --absolute-names "${backup_paths[@]}" || true
  fi
}

verify_install_package_available() {
  if ! apt-cache show "$INSTALL_PACKAGE" >/dev/null 2>&1; then
    die "The requested install package '$INSTALL_PACKAGE' is not available in the current apt sources."
  fi
}

stop_nvidia_userspace_if_possible() {
  # Keep this conservative. We do not try to stop a GUI session that launched us.
  # We do stop display-manager if it is active and we are not inside a GUI terminal.
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet display-manager.service; then
      log "Stopping display-manager.service to reduce driver-in-use conflicts."
      run systemctl stop display-manager.service || true
    fi
  fi
}

purge_driver_stack() {
  log "Purging currently installed NVIDIA driver packages."
  if (( ${#DRIVER_PACKAGES[@]} > 0 )); then
    run apt-get -y purge "${DRIVER_PACKAGES[@]}"
  else
    warn "No installed NVIDIA driver packages were detected by the package filter; continuing with stale-file cleanup."
  fi

  # Follow System76's general cleanup pattern after a purge.
  run apt-get -y autoremove --purge
  run apt-get clean
}

clean_dkms_trees() {
  log "Removing stale DKMS trees for NVIDIA."
  if command -v dkms >/dev/null 2>&1; then
    local line ver
    while IFS= read -r line; do
      [[ "$line" =~ ^nvidia/([^,[:space:]]+) ]] || continue
      ver="${BASH_REMATCH[1]}"
      run dkms remove -m nvidia -v "$ver" --all || true
    done < <(dkms status 2>/dev/null || true)
  fi

  local dir
  for dir in /var/lib/dkms/nvidia /var/lib/dkms/nvidia-* /usr/src/nvidia-*; do
    [[ -e "$dir" ]] || continue
    run rm -rf -- "$dir"
  done
}

remove_stale_nvidia_module_files() {
  log "Removing leftover nvidia*.ko* files from installed kernels."
  local k kdir removed_any file
  for k in "${KERNELS[@]}"; do
    removed_any=0
    for kdir in "/lib/modules/$k/updates/dkms" "/lib/modules/$k/updates" "/lib/modules/$k/extra"; do
      [[ -d "$kdir" ]] || continue
      while IFS= read -r -d '' file; do
        log "Removing stale module file: $file"
        if (( ! DRY_RUN )); then
          rm -f -- "$file"
        fi
        removed_any=1
      done < <(find "$kdir" -maxdepth 1 -type f -name 'nvidia*.ko*' -print0 2>/dev/null || true)
    done
    if (( removed_any )); then
      run depmod -a "$k" || true
    fi
  done
}

ensure_current_kernel_headers_present() {
  local build_dir="/lib/modules/$RUNNING_KERNEL/build"
  if [[ -e "$build_dir" ]]; then
    return 0
  fi

  warn "Kernel headers for the running kernel appear missing. Attempting to install them."
  run apt-get -y install "linux-headers-$RUNNING_KERNEL" || warn "Could not install linux-headers-$RUNNING_KERNEL automatically."
}

reinstall_driver_stack() {
  log "Installing proprietary NVIDIA driver stack using: $INSTALL_PACKAGE"
  verify_install_package_available
  run apt-get update
  run dpkg --configure -a
  run apt-get -y install -f
  run apt-get -y full-upgrade
  ensure_current_kernel_headers_present
  run apt-get -y install "$INSTALL_PACKAGE"

  if command -v dkms >/dev/null 2>&1; then
    run dkms autoinstall || true
  fi

  best_effort_restart_initramfs
}

post_checks() {
  log "Running post-install checks."

  if dpkg --audit 2>/dev/null | grep -Eiq 'nvidia|system76-driver-nvidia'; then
    die "dpkg still reports NVIDIA-related packages in an unconfigured/broken state."
  fi

  modinfo -k "$RUNNING_KERNEL" nvidia >/dev/null 2>&1 || die "modinfo could not find the nvidia module for the running kernel $RUNNING_KERNEL."

  dkms status > "$WORKDIR/state/dkms-status-after.txt" 2>&1 || true
  lsmod > "$WORKDIR/state/lsmod-after.txt" 2>&1 || true
  journalctl -k -b --no-pager > "$WORKDIR/state/kernel-journal-after.txt" 2>&1 || true

  if command -v modprobe >/dev/null 2>&1; then
    if ! modprobe nvidia >/dev/null 2>&1; then
      warn "modprobe nvidia did not succeed immediately. This can happen until reboot, or if Secure Boot/signing policy blocks unsigned modules."
    fi
  fi

  if command -v nvidia-smi >/dev/null 2>&1; then
    if ! nvidia-smi > "$WORKDIR/state/nvidia-smi-after.txt" 2>&1; then
      warn "nvidia-smi did not succeed immediately. Reboot first, then retest."
    fi
  else
    warn "nvidia-smi is not present in PATH after installation."
  fi

  log "Post-checks passed. A reboot is strongly recommended."
}

main_reinstall() {
  require_root
  require_commands
  check_pop_os
  check_not_running_inside_gui_terminal
  check_nvidia_hardware
  check_secure_boot
  gather_kernels
  check_disk_space
  create_snapshot_dir
  capture_state

  if ! confirm "Proceed with NVIDIA driver purge/cleanup/reinstall?"; then
    die "Aborted by user."
  fi

  stop_nvidia_userspace_if_possible
  purge_driver_stack
  clean_dkms_trees
  remove_stale_nvidia_module_files
  repair_apt_state
  reinstall_driver_stack
  post_checks
}

main_rollback() {
  require_root
  require_commands
  [[ -n "$ROLLBACK_DIR" ]] || die "No rollback directory was provided."
  [[ -d "$ROLLBACK_DIR" ]] || die "Rollback directory does not exist: $ROLLBACK_DIR"

  WORKDIR="$ROLLBACK_DIR"
  LOGFILE="$WORKDIR/run.log"
  touch "$LOGFILE" 2>/dev/null || true

  perform_rollback "$ROLLBACK_DIR"
}

main() {
  parse_args "$@"

  export DEBIAN_FRONTEND=noninteractive

  if [[ -n "$ROLLBACK_DIR" ]]; then
    main_rollback
  else
    main_reinstall
  fi
}

main "$@"
