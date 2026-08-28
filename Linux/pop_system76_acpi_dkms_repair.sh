#!/usr/bin/env bash
# pop_system76_acpi_dkms_repair.sh
#
# Purpose:
#   Repair Pop!_OS package-manager failures caused by DKMS refusing to install
#   system76_acpi for a new kernel because an in-tree system76_acpi module already exists.
#
# Default mode is DRY RUN. Use --apply to modify the system.
#
# Recommended first run:
#   bash pop_system76_acpi_dkms_repair.sh
#
# Apply the recommended fix for non-System76 hardware / kernels that already ship system76_acpi:
#   bash pop_system76_acpi_dkms_repair.sh --apply --mode purge-dkms
#
# Fallback, only if you intentionally want DKMS to override the kernel module:
#   bash pop_system76_acpi_dkms_repair.sh --apply --mode force-dkms
#
# Rollback/savepoint:
#   Each --apply run creates /var/backups/pop-dkms-repair/<timestamp>/
#   with logs, package state, dkms state, selected config backups, and a rollback.sh helper.

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM_NAME="$(basename "$0")"
APPLY=0
MODE="purge-dkms"
ENABLE_FLATPAK=1
ALLOW_CRITICAL_REMOVAL=0
SAVE_ROOT="/var/backups/pop-dkms-repair"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SAVEPOINT="${SAVE_ROOT}/${TIMESTAMP}"
LOG="${SAVEPOINT}/repair.log"

usage() {
  cat <<'USAGE'
Usage:
  pop_system76_acpi_dkms_repair.sh [options]

Options:
  --apply                      Actually change the system. Without this, the script is a dry run.
  --mode purge-dkms            Recommended: remove system76-acpi-dkms if safe, then repair dpkg/apt.
  --mode force-dkms            Fallback: force DKMS to install system76_acpi over the in-tree module.
  --no-flatpak                 Skip Flatpak update/repair.
  --allow-critical-removal     Do not abort if apt simulation shows critical packages would be removed.
  -h, --help                   Show this help.

Examples:
  bash pop_system76_acpi_dkms_repair.sh
  bash pop_system76_acpi_dkms_repair.sh --apply --mode purge-dkms
  bash pop_system76_acpi_dkms_repair.sh --apply --mode force-dkms
USAGE
}

log() {
  local msg="$*"
  printf '[%s] %s\n' "$(date '+%F %T')" "$msg" | tee -a "$LOG" >&2
}

die() {
  log "ERROR: $*"
  log "Savepoint/logs: $SAVEPOINT"
  exit 1
}

on_error() {
  local rc=$?
  log "ERROR: command failed with exit code ${rc}: ${BASH_COMMAND}"
  log "Review ${LOG}. If this was an --apply run, see ${SAVEPOINT}/rollback.sh."
  exit "$rc"
}
trap on_error ERR

parse_args() {
  while (($#)); do
    case "$1" in
      --apply) APPLY=1 ;;
      --mode)
        shift || die "--mode requires an argument"
        MODE="${1:-}"
        case "$MODE" in
          purge-dkms|force-dkms) ;;
          *) die "Unsupported mode: $MODE" ;;
        esac
        ;;
      --no-flatpak) ENABLE_FLATPAK=0 ;;
      --allow-critical-removal) ALLOW_CRITICAL_REMOVAL=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift || true
  done
}

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -E bash "$0" "$@"
    fi
    die "Run as root or install sudo."
  fi
}

run() {
  log "+ $*"
  if ((APPLY)); then
    "$@" 2>&1 | tee -a "$LOG"
  else
    log "[dry-run] skipped: $*"
  fi
}

run_may_fail() {
  log "+ $*"
  if ((APPLY)); then
    set +e
    "$@" 2>&1 | tee -a "$LOG"
    local rc=${PIPESTATUS[0]}
    set -e
    if ((rc != 0)); then
      log "Non-fatal command returned ${rc}: $*"
    fi
    return 0
  else
    log "[dry-run] skipped: $*"
  fi
}

capture() {
  local name="$1"
  shift
  log "Capturing ${name}"
  {
    printf '### %s\n' "$name"
    printf '$ %q ' "$@"; printf '\n\n'
    "$@" || true
  } >"${SAVEPOINT}/${name}.txt" 2>&1
}

backup_path() {
  local path="$1"
  local label="$2"
  if [[ -e "$path" ]]; then
    log "Backing up ${path} -> backups/${label}.tar"
    mkdir -p "${SAVEPOINT}/backups"
    tar -cpf "${SAVEPOINT}/backups/${label}.tar" -C "$(dirname "$path")" "$(basename "$path")"
  else
    log "Backup skipped; not found: ${path}"
  fi
}

write_rollback_helper() {
  cat >"${SAVEPOINT}/rollback.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=\$'\n\t'
SP="${SAVEPOINT}"

if [[ \${EUID} -ne 0 ]]; then
  exec sudo -E bash "\$0" "\$@"
fi

echo "Rollback helper for savepoint: \${SP}"
echo "This restores selected saved config/state references and attempts to reinstall system76-acpi-dkms."
echo "It cannot guarantee a full OS snapshot rollback. Use your filesystem snapshot/Timeshift backup if available."
read -r -p "Continue? [y/N] " ans
[[ "\${ans}" == "y" || "\${ans}" == "Y" ]] || exit 0

if [[ -f "\${SP}/backups/etc_apt.tar" ]]; then
  tar -xpf "\${SP}/backups/etc_apt.tar" -C /etc
  echo "Restored /etc/apt from savepoint."
fi

if [[ -f "\${SP}/backups/etc_kernel.tar" ]]; then
  tar -xpf "\${SP}/backups/etc_kernel.tar" -C /etc
  echo "Restored /etc/kernel from savepoint."
fi

if [[ -f "\${SP}/backups/var_lib_dkms_system76_acpi.tar" ]]; then
  mkdir -p /var/lib/dkms
  tar -xpf "\${SP}/backups/var_lib_dkms_system76_acpi.tar" -C /var/lib/dkms
  echo "Restored /var/lib/dkms/system76_acpi from savepoint."
fi

apt-get update -m || true
apt-get install -y system76-acpi-dkms || true
dkms autoinstall || true
dpkg --configure -a || true
apt-get -f install -y || true

echo "Rollback helper finished. Review dpkg/apt output before rebooting."
EOF
  chmod 700 "${SAVEPOINT}/rollback.sh"
}

init_savepoint() {
  mkdir -p "$SAVEPOINT"
  chmod 700 "$SAVEPOINT"
  : > "$LOG"
  chmod 600 "$LOG"
  log "Program: $PROGRAM_NAME"
  log "Mode: $MODE"
  log "Apply: $APPLY"
  log "Savepoint: $SAVEPOINT"

  capture "os-release" cat /etc/os-release
  capture "uname" uname -a
  capture "hostnamectl" hostnamectl
  capture "df-h" df -h
  capture "apt-policy-linux" bash -c "apt-cache policy linux-system76 linux-generic linux-headers-generic system76-acpi-dkms system76-dkms system76-io-dkms 2>/dev/null"
  capture "dpkg-kernel-packages" bash -c "dpkg-query -W -f='\${binary:Package}\t\${Version}\t\${db:Status-Abbrev}\n' 'linux-*' 'system76-*' 2>/dev/null | sort"
  capture "dpkg-audit" dpkg --audit
  capture "dkms-status" dkms status
  capture "apt-sources-list" bash -c "find /etc/apt -maxdepth 3 -type f \( -name '*.list' -o -name '*.sources' \) -print -exec sed -n '1,220p' {} \;"
  capture "flatpak-list" bash -c "command -v flatpak >/dev/null 2>&1 && flatpak list --app --runtime || true"

  backup_path "/etc/apt" "etc_apt"
  backup_path "/etc/kernel" "etc_kernel"
  backup_path "/var/lib/dpkg/status" "var_lib_dpkg_status"
  backup_path "/var/lib/apt/extended_states" "var_lib_apt_extended_states"
  backup_path "/var/lib/dkms/system76_acpi" "var_lib_dkms_system76_acpi"

  dpkg --get-selections >"${SAVEPOINT}/dpkg-selections.txt" || true
  apt-mark showmanual >"${SAVEPOINT}/apt-manual.txt" || true
  write_rollback_helper
}

critical_removal_guard() {
  local sim="${SAVEPOINT}/apt-purge-system76-acpi-dkms.simulation.txt"
  log "Simulating apt purge for system76-acpi-dkms"
  set +e
  apt-get -s purge system76-acpi-dkms >"$sim" 2>&1
  local rc=$?
  set -e
  cat "$sim" | tee -a "$LOG" >/dev/null
  if ((rc != 0)); then
    die "apt purge simulation failed. See $sim"
  fi

  if grep -Eq '^Remv (pop-desktop|linux-system76|linux-generic|linux-headers-generic|linux-image-generic|system76-driver-nvidia|nvidia-driver|nvidia-dkms|system76-driver)' "$sim"; then
    if ((ALLOW_CRITICAL_REMOVAL)); then
      log "WARNING: critical package removal detected, but --allow-critical-removal was provided."
    else
      die "apt would remove critical Pop!/kernel/NVIDIA packages. Not purging. Try --mode force-dkms or inspect $sim."
    fi
  fi
}

installed_pkg() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -q 'install ok installed'
}

latest_system76_acpi_dkms_version() {
  find /var/lib/dkms/system76_acpi -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n 1
}

all_kernel_dirs() {
  find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -E '^[0-9].*generic$' | sort -V
}

repair_with_purge() {
  log "Strategy: purge system76-acpi-dkms, keep kernel in-tree system76_acpi module, then repair dpkg/apt."

  if installed_pkg "system76-acpi-dkms"; then
    critical_removal_guard

    local versions=()
    mapfile -t versions < <(find /var/lib/dkms/system76_acpi -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V || true)
    for version in "${versions[@]}"; do
      [[ -n "$version" ]] || continue
      run_may_fail dkms remove -m system76_acpi -v "$version" --all
    done

    run apt-get purge -y system76-acpi-dkms
  else
    log "system76-acpi-dkms is not installed; skipping purge."
  fi

  run apt-get clean
  run apt-get update -m
  run dpkg --configure -a
  run apt-get -f install -y
  run apt-get full-upgrade -y
  run apt-get autoremove --purge -y
  run apt-get clean
}

repair_with_force_dkms() {
  log "Strategy: force DKMS installation of system76_acpi over any in-tree module."

  local version
  version="$(latest_system76_acpi_dkms_version || true)"
  [[ -n "$version" ]] || die "No system76_acpi version found under /var/lib/dkms/system76_acpi. Install/reinstall system76-acpi-dkms or use --mode purge-dkms."

  local kernels=()
  mapfile -t kernels < <(all_kernel_dirs || true)
  ((${#kernels[@]} > 0)) || die "No generic kernels found under /lib/modules."

  for kernel in "${kernels[@]}"; do
    if [[ -d "/lib/modules/${kernel}/build" ]]; then
      run_may_fail dkms build -m system76_acpi -v "$version" -k "$kernel" --force
      run dkms install -m system76_acpi -v "$version" -k "$kernel" --force
    else
      log "Skipping ${kernel}; missing /lib/modules/${kernel}/build headers link."
    fi
  done

  run apt-get clean
  run apt-get update -m
  run dpkg --configure -a
  run apt-get -f install -y
  run apt-get full-upgrade -y
  run apt-get autoremove --purge -y
  run apt-get clean
}

flatpak_maintenance() {
  ((ENABLE_FLATPAK)) || { log "Flatpak maintenance disabled."; return 0; }
  command -v flatpak >/dev/null 2>&1 || { log "flatpak command not found; skipping."; return 0; }

  local target_user="${SUDO_USER:-}"
  if [[ -n "$target_user" && "$target_user" != "root" ]] && id "$target_user" >/dev/null 2>&1; then
    run_may_fail runuser -u "$target_user" -- flatpak repair --user -y
    run_may_fail runuser -u "$target_user" -- flatpak update -y
    run_may_fail runuser -u "$target_user" -- flatpak uninstall --unused -y
  else
    run_may_fail flatpak repair --user -y
    run_may_fail flatpak update -y
    run_may_fail flatpak uninstall --unused -y
  fi
}

post_checks() {
  capture "post-dpkg-audit" dpkg --audit
  capture "post-dkms-status" dkms status
  capture "post-apt-simulate-upgrade" bash -c "apt-get -s full-upgrade | sed -n '1,220p'"
  log "Post-checks saved in $SAVEPOINT"
}

main() {
  parse_args "$@"
  require_root "$@"
  init_savepoint

  if ((APPLY == 0)); then
    log "DRY RUN ONLY. Re-run with --apply after reviewing the savepoint."
  fi

  case "$MODE" in
    purge-dkms) repair_with_purge ;;
    force-dkms) repair_with_force_dkms ;;
  esac

  flatpak_maintenance
  post_checks

  log "Finished. Savepoint: $SAVEPOINT"
  if ((APPLY)); then
    log "Reboot after verifying: sudo reboot"
  else
    log "No changes were made because --apply was not provided."
  fi
}

main "$@"
