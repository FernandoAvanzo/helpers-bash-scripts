#!/usr/bin/env bash
# shellcheck disable=SC2012
# Remove IPU6 stack and restore previous system state
set -euo pipefail

find_backup_dir() {
    local backup_dir
    backup_dir=$(find /opt/ipu6-bkp/ -maxdepth 1 -name "ipu6-backup-*" -type d -printf '%T@ %p\n' 2>/dev/null |
                sort -nr | head -n1 | cut -d' ' -f2-)
    echo "$backup_dir"
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

validate_backup() {
    local backup_dir="$1"
    [[ -n "$backup_dir" && -d "$backup_dir" ]] || die "No valid backup directory found"
    log "Using backup directory: $backup_dir"
}

safe_remove() {
    local target="$1"
    if [[ -e "$target" ]]; then
        rm -rf "$target" && log "Removed: $target" || log "Failed to remove: $target"
    fi
}

main() {
    [[ $EUID -eq 0 ]] || die "Run as root"
    
    local backup_dir
    backup_dir=$(find_backup_dir)
    validate_backup "$backup_dir"
    
    echo "==> Uninstalling DKMS module"
    if dkms status ipu6-drivers 2>/dev/null | grep -q "installed"; then
        dkms remove -m ipu6-drivers -v 0.0.0 --all || log "DKMS removal failed"
    fi
    safe_remove "/usr/src/ipu6-drivers-0.0.0"
    
    echo "==> Removing HAL, plugin and libs"
    safe_remove "/usr/lib/libipu*"
    safe_remove "/usr/lib/gstreamer-1.0/libicamerasrc*.so"
    safe_remove "/usr/include/ipu6"
    ldconfig
    
    echo "==> Restoring firmware (if backup exists)"
    if [[ -d "$backup_dir/fw" ]]; then
      rm -rf /lib/firmware/intel/ipu
      cp -a "$backup_dir/fw"/* /lib/firmware/intel/ && log "Firmware restored"
    else
      safe_remove "/lib/firmware/intel/ipu"
      log "No backup found - IPU firmware removed"
    fi
    
    echo "==> Cleaning working directories"
    safe_remove "/opt/ipu6"
    
    echo "==> Updating initramfs and depmod"
    update-initramfs -u || log "initramfs update failed"
    depmod -a || log "depmod failed"
    
    echo "Rollback finished – reboot recommended."
}

main "$@"
