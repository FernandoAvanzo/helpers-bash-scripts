#!/usr/bin/env bash
# pop_system76_acpi_dkms_repair.sh
#
# Purpose:
#   Repair Pop!_OS package-manager failures caused by DKMS refusing to install
#   system76_acpi when the target kernel already contains an in-tree
#   system76_acpi.ko(.zst) module.
#
# What v2 fixes:
#   - Skips DKMS' internal "original_module" directory; it is not a DKMS version.
#   - Makes non-fatal DKMS cleanup truly non-fatal under set -Eeuo pipefail.
#   - Handles a half-completed v1 run where the DKMS module was removed but the
#     Debian package was not purged yet.
#
# Default mode is dry-run. Use --apply to modify the system.
#
# Recommended:
#   bash pop_system76_acpi_dkms_repair_v2.sh
#   bash pop_system76_acpi_dkms_repair_v2.sh --apply --mode purge-dkms
#
# Fallback:
#   bash pop_system76_acpi_dkms_repair_v2.sh --apply --mode force-dkms
#
# Savepoints:
#   /var/backups/pop-dkms-repair-v2/<timestamp>/

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM_NAME="$(basename "$0")"
APPLY=0
MODE="purge-dkms"
ENABLE_FLATPAK=1
ENABLE_AUTOREMOVE=0
ALLOW_CRITICAL_REMOVAL=0
QUARANTINE_STALE_DKMS=1
SAVE_ROOT="/var/backups/pop-dkms-repair-v2"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SAVEPOINT="${SAVE_ROOT}/${TIMESTAMP}"
LOG="${SAVEPOINT}/repair.log"
CMD_COUNTER=0

usage() {
  cat <<'USAGE'
Usage:
  pop_system76_acpi_dkms_repair.sh [options]

Options:
  --apply                      Actually change the system. Without this, dry-run only.
  --mode purge-dkms            Recommended: purge system76-acpi-dkms, then repair dpkg/apt.
  --mode force-dkms            Fallback: force DKMS install over the in-tree module.
  --no-flatpak                 Skip Flatpak repair/update.
  --autoremove                 Remove packages APT marks as no longer required (opt-in).
  --no-quarantine              Do not move stale /var/lib/dkms/system76_acpi after purge.
  --allow-critical-removal     Continue even if apt simulation says critical packages are removed.
  -h, --help                   Show this help.

Examples:
  bash pop_system76_acpi_dkms_repair.sh
  bash pop_system76_acpi_dkms_repair.sh --apply --mode purge-dkms
  bash pop_system76_acpi_dkms_repair.sh --apply --mode purge-dkms --no-flatpak
  bash pop_system76_acpi_dkms_repair.sh --apply --mode force-dkms
USAGE
}

ensure_log_target() {
  mkdir -p "$SAVEPOINT"
  chmod 700 "$SAVEPOINT"
  if [[ ! -e "$LOG" ]]; then
    : > "$LOG"
    chmod 600 "$LOG"
  fi
}

log() {
  local msg="$*"
  local line
  line="$(printf '[%s] %s\n' "$(date '+%F %T')" "$msg")"
  if [[ -d "$SAVEPOINT" ]]; then
    printf '%s\n' "$line" | tee -a "$LOG" >&2
  else
    printf '%s\n' "$line" >&2
  fi
}

die() {
  log "ERROR: $*"
  log "Savepoint/logs: $SAVEPOINT"
  exit 1
}

on_error() {
  local rc=$?
  log "ERROR: unexpected failure, exit code ${rc}: ${BASH_COMMAND}"
  log "Review ${LOG}. If this was an --apply run, see ${SAVEPOINT}/rollback.sh."
  exit "$rc"
}
trap on_error ERR

cmd_string() {
  printf '%q ' "$@"
}

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
    --no-quarantine) QUARANTINE_STALE_DKMS=0 ;;
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

run_logged() {
  local fatal="$1"
  shift

  local cmd
  cmd="$(cmd_string "$@")"
  log "+ ${cmd}"

  if ((APPLY == 0)); then
    log "[dry-run] skipped: ${cmd}"
    return 0
  fi

  CMD_COUNTER=$((CMD_COUNTER + 1))
  local outfile="${SAVEPOINT}/cmd-${CMD_COUNTER}.log"

  set +e
  "$@" >"$outfile" 2>&1
  local rc=$?
  set -e

  cat "$outfile" >> "$LOG"
  cat "$outfile"

  if ((rc != 0)); then
    if [[ "$fatal" == "fatal" ]]; then
      die "command failed with exit code ${rc}: ${cmd}"
    fi
    log "Non-fatal command returned ${rc}: ${cmd}"
    return 0
  fi

  return 0
}

run() {
  run_logged fatal "$@"
}

run_optional() {
  # ERR traps are independent of errexit.  Temporarily disable the trap while
  # running an explicitly optional command so its failure is recorded by
  # run_logged instead of aborting the whole script.
  trap - ERR
  run_logged optional "$@"
  local rc=$?
  trap on_error ERR
  return "$rc"
}

capture() {
  local name="$1"
  shift
  log "Capturing ${name}"
  {
    printf '### %s\n' "$name"
    printf '$ '
    printf '%q ' "$@"
    printf '\n\n'
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
echo "It is not a full filesystem snapshot rollback."
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

if [[ -d "\${SP}/quarantine/system76_acpi" && ! -e /var/lib/dkms/system76_acpi ]]; then
  mkdir -p /var/lib/dkms
  cp -a "\${SP}/quarantine/system76_acpi" /var/lib/dkms/system76_acpi
  echo "Copied quarantined /var/lib/dkms/system76_acpi back into place."
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
  ensure_log_target
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

dpkg_has_record() {
  dpkg-query -W -f='${db:Status-Abbrev}\n' "$1" >/dev/null 2>&1
}

pkg_is_active_or_configured() {
  local state
  state="$(dpkg-query -W -f='${db:Status-Abbrev}\n' "$1" 2>/dev/null || true)"
  [[ "$state" =~ ^(i|r?c) ]]
}

pkg_is_installedish() {
  local status
  status="$(dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null || true)"
  [[ "$status" == install\ ok\ installed || "$status" == install\ ok\ half-configured || "$status" == install\ ok\ unpacked || "$status" == install\ ok\ half-installed ]]
}

critical_removal_guard() {
  local sim="${SAVEPOINT}/apt-purge-system76-acpi-dkms.simulation.txt"
  log "Simulating apt purge for system76-acpi-dkms"

  set +e
  apt-get -s purge system76-acpi-dkms >"$sim" 2>&1
  local rc=$?
  set -e

  cat "$sim" >> "$LOG"
  cat "$sim"

  if ((rc != 0)); then
    die "apt purge simulation failed. See $sim"
  fi

  # apt-get -s uses "Remv" for some versions and "Purg" when purge is
  # requested.  Check both; otherwise a dangerous dependency cascade can
  # pass this guard unnoticed.
  # system76-driver and system76-driver-nvidia depend on system76-acpi-dkms;
  # their removal is the expected metapackage consequence of purge mode. Do
  # not classify those two packages as critical: with autoremove disabled,
  # their payload packages remain installed. Protect the kernel, desktop, and
  # NVIDIA driver packages themselves.
  if grep -Eq '^(Remv|Purg) (pop-desktop|linux-system76|linux-generic|linux-headers-generic|linux-image-generic|nvidia-driver|nvidia-dkms)' "$sim"; then
    if ((ALLOW_CRITICAL_REMOVAL)); then
      log "WARNING: critical package removal detected, but --allow-critical-removal was provided."
    else
      die "apt would remove critical Pop!/kernel/NVIDIA packages. Not purging. Try --mode force-dkms or inspect $sim."
    fi
  fi

  if grep -Eq '^(Remv|Purg) system76-driver(-nvidia)?([: ]|$)' "$sim"; then
    log "APT will remove dependent System76 driver metapackages; this is expected in purge-dkms mode."
  fi
}

discover_system76_acpi_dkms_versions() {
  local root="/var/lib/dkms/system76_acpi"
  [[ -d "$root" ]] || return 0

  while IFS= read -r path; do
    local version
    version="$(basename "$path")"

    # DKMS stores displaced in-tree modules here. It is not a module version.
    case "$version" in
    original_module|.*|source|build|kernel-*|collisions)
      continue
      ;;
    esac

    # Real DKMS versions normally have a source symlink, dkms.conf, or build dir.
    if [[ -e "$path/source" || -f "$path/dkms.conf" || -d "$path/build" ]]; then
      printf '%s\n' "$version"
    fi
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -V)
}

latest_system76_acpi_dkms_version() {
  discover_system76_acpi_dkms_versions | sort -V | tail -n 1
}

all_kernel_dirs() {
  find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -E '^[0-9].*generic$' | sort -V || true
}

quarantine_stale_dkms_tree() {
  ((QUARANTINE_STALE_DKMS)) || { log "Stale DKMS quarantine disabled."; return 0; }
  local root="/var/lib/dkms/system76_acpi"
  [[ -d "$root" ]] || return 0

  if pkg_is_installedish "system76-acpi-dkms"; then
    log "Not quarantining ${root}; system76-acpi-dkms still appears installed."
    return 0
  fi

  local valid_versions=()
  mapfile -t valid_versions < <(discover_system76_acpi_dkms_versions || true)
  if ((${#valid_versions[@]} > 0)); then
    log "Not quarantining ${root}; valid DKMS version dirs remain: ${valid_versions[*]}"
    return 0
  fi

  log "Quarantining stale DKMS tree ${root}; no valid system76_acpi DKMS versions remain."
  if ((APPLY)); then
    mkdir -p "${SAVEPOINT}/quarantine"
    mv "$root" "${SAVEPOINT}/quarantine/system76_acpi"
  else
    log "[dry-run] skipped: mv ${root} ${SAVEPOINT}/quarantine/system76_acpi"
  fi
}

repair_package_manager() {
  run apt-get clean
  run apt-get update -m
  run dpkg --configure -a
  run apt-get -f install -y
  run dpkg --configure -a
  run apt-get full-upgrade -y
  if ((ENABLE_AUTOREMOVE)); then
    run apt-get autoremove --purge -y
  else
    log "Skipping apt autoremove --purge (opt-in with --autoremove; prevents unrelated package removal)."
  fi
  run apt-get clean
}

repair_with_purge() {
  log "Strategy: purge system76-acpi-dkms, keep the kernel in-tree system76_acpi module, then repair dpkg/apt."

  if dpkg_has_record "system76-acpi-dkms"; then
    critical_removal_guard

    local versions=()
    mapfile -t versions < <(discover_system76_acpi_dkms_versions || true)

    if ((${#versions[@]} == 0)); then
      log "No valid system76_acpi DKMS version directories found. This is OK after a partial previous cleanup."
    else
      local version
      for version in "${versions[@]}"; do
        [[ -n "$version" ]] || continue
        run_optional dkms remove -m system76_acpi -v "$version" --all
      done
    fi

    # Purge the Debian package so future kernel postinst hooks stop autoinstalling system76_acpi via DKMS.
    run apt-get purge -y system76-acpi-dkms
  else
    log "system76-acpi-dkms has no dpkg record; skipping apt purge."
  fi

  quarantine_stale_dkms_tree
  repair_package_manager
}

repair_with_force_dkms() {
  log "Strategy: force DKMS installation of system76_acpi over any in-tree module."

  local version
  version="$(latest_system76_acpi_dkms_version || true)"

  if [[ -z "$version" ]]; then
    die "No valid system76_acpi DKMS version found under /var/lib/dkms/system76_acpi. Use --mode purge-dkms for the recommended recovery, or reinstall system76-acpi-dkms manually before force mode."
  fi

  local kernels=()
  mapfile -t kernels < <(all_kernel_dirs || true)
  ((${#kernels[@]} > 0)) || die "No generic kernels found under /lib/modules."

  local kernel
  for kernel in "${kernels[@]}"; do
    if [[ -e "/lib/modules/${kernel}/build" ]]; then
      run_optional dkms build -m system76_acpi -v "$version" -k "$kernel" --force
      run dkms install -m system76_acpi -v "$version" -k "$kernel" --force
    else
      log "Skipping ${kernel}; missing /lib/modules/${kernel}/build headers link."
    fi
  done

  repair_package_manager
}

flatpak_maintenance() {
  ((ENABLE_FLATPAK)) || { log "Flatpak maintenance disabled."; return 0; }
  command -v flatpak >/dev/null 2>&1 || { log "flatpak command not found; skipping."; return 0; }

  local target_user="${SUDO_USER:-}"
  if [[ -n "$target_user" && "$target_user" != "root" ]] && id "$target_user" >/dev/null 2>&1; then
    run_optional runuser -u "$target_user" -- flatpak repair --user
    run_optional runuser -u "$target_user" -- flatpak update -y
    run_optional runuser -u "$target_user" -- flatpak uninstall --unused -y
  else
    run_optional flatpak repair --user
    run_optional flatpak update -y
    run_optional flatpak uninstall --unused -y
  fi
}

post_checks() {
  capture "post-dpkg-audit" dpkg --audit
  capture "post-dkms-status" dkms status
  capture "post-apt-simulate-upgrade" bash -c "apt-get -s full-upgrade | sed -n '1,220p'"
  capture "post-system76-acpi-modinfo" bash -c "modinfo system76_acpi 2>/dev/null | sed -n '1,120p' || true"
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
    log "Recommended verification:"
    log "  sudo dpkg --audit"
    log "  dkms status"
    log "  uname -r"
    log "Reboot after verifying: sudo reboot"
  else
    log "No changes were made because --apply was not provided."
  fi
}

main "$@"
