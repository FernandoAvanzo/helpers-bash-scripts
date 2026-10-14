#!/usr/bin/env bash
# Diagnose or interactively repair a Pop!_OS NVIDIA driver/library mismatch.
# Package changes require the explicit --repair option; reboot is always manual.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"
readonly DRIVER_METAPACKAGE="system76-driver-nvidia"
REPAIR=false

usage() {
  cat <<USAGE
Usage: ${SCRIPT_NAME} [--repair] [--help]

  --repair  Update APT metadata, simulate upgrades, and (after confirmation)
            repair package state and reinstall ${DRIVER_METAPACKAGE}.
  --help    Show this help.

Without --repair, the script only prints diagnostics. It never reboots.
USAGE
}

log() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

confirm() {
  local prompt=$1 answer
  [[ -t 0 ]] || die "Interactive confirmation is required; run this from a terminal."
  read -r -p "${prompt} [y/N] " answer
  [[ ${answer,,} == "y" || ${answer,,} == "yes" ]]
}

run() {
  log "Running: $*"
  "$@"
}

show_diagnostics() {
  log "Operating system"
  if [[ -r /etc/os-release ]]; then
    sed -n -e 's/^PRETTY_NAME=/  /p' /etc/os-release
  else
    log "/etc/os-release is unavailable"
  fi

  log "Kernel: $(uname -r)"
  log "NVIDIA tools and loaded module"
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi || true
  else
    log "nvidia-smi is not installed or not on PATH"
  fi
  if [[ -r /proc/driver/nvidia/version ]]; then
    cat /proc/driver/nvidia/version
  else
    log "No readable /proc/driver/nvidia/version (module may not be loaded)"
  fi
  if command -v modinfo >/dev/null 2>&1; then
    modinfo -F version nvidia 2>&1 || true
  fi

  log "Installed NVIDIA/System76 packages"
  if command -v dpkg-query >/dev/null 2>&1; then
    dpkg-query -W -f='  ${binary:Package}\t${Version}\t${db:Status-Status}\n' \
      'nvidia-*' 'libnvidia-*' 'system76-driver-nvidia' 2>/dev/null || true
  fi

  log "APT candidate for ${DRIVER_METAPACKAGE}"
  if command -v apt-cache >/dev/null 2>&1; then
    apt-cache policy "${DRIVER_METAPACKAGE}" 2>/dev/null || true
  fi

  if command -v mokutil >/dev/null 2>&1; then
    mokutil --sb-state 2>/dev/null || true
  fi
}

main() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --repair) REPAIR=true ;;
      --help|-h) usage; return 0 ;;
      *) usage >&2; die "Unknown option: ${arg}" ;;
    esac
  done

  [[ -r /etc/os-release ]] || die "Cannot identify the operating system."
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == "pop" || ${ID_LIKE:-} == *"pop"* ]] || \
    die "This script is intended for Pop!_OS (detected ID=${ID:-unknown})."

  show_diagnostics

  if [[ ${REPAIR} != true ]]; then
    log "Diagnostic mode only. If this is a recent driver update, reboot first."
    log "For package repair, review the report and rerun with --repair."
    return 0
  fi

  [[ ${EUID} -eq 0 ]] && die "Do not run the script as root; it uses sudo for package operations."
  command -v sudo >/dev/null 2>&1 || die "sudo is required."
  command -v apt-get >/dev/null 2>&1 || die "apt-get is required."
  command -v apt-cache >/dev/null 2>&1 || die "apt-cache is required."

  log "This will update APT metadata, repair interrupted package configuration,"
  log "simulate a full upgrade, and reinstall ${DRIVER_METAPACKAGE} if confirmed."
  log "The full upgrade may update packages beyond NVIDIA. Review its simulation."
  confirm "Continue with APT metadata refresh and simulation?" || {
    log "Cancelled; no package changes were made."
    return 0
  }

  run sudo apt-get update
  run sudo dpkg --configure -a
  run sudo apt-get --fix-broken install

  log "APT full-upgrade simulation follows. Review removals and proposed changes."
  sudo apt-get --simulate full-upgrade

  confirm "Apply the full-upgrade transaction shown above?" || {
    log "Cancelled before full-upgrade; reinstall was not attempted."
    return 0
  }
  run sudo apt-get full-upgrade

  confirm "Reinstall ${DRIVER_METAPACKAGE} from configured repositories?" || {
    log "Upgrade completed; metapackage reinstall skipped."
    log "Reboot manually, then check nvidia-smi."
    return 0
  }
  run sudo apt-get install --reinstall "${DRIVER_METAPACKAGE}"

  log "Package operations completed. Reboot manually to load the matching kernel module:"
  log "  sudo reboot"
  log "After reboot, verify with nvidia-smi and /proc/driver/nvidia/version."
}

main "$@"
