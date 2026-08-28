#!/usr/bin/env bash
# update_system_hardened.sh
# Safer replacement for the original update_system.sh.
# It does not store a sudo password, creates a savepoint, repairs interrupted dpkg state,
# uses apt-get for scripting, and follows the Pop!_OS full-upgrade flow.

set -Eeuo pipefail
IFS=$'\n\t'

APPLY=0
ENABLE_FLATPAK=1
SAVE_ROOT="/var/backups/pop-update"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SAVEPOINT="${SAVE_ROOT}/${TIMESTAMP}"
LOG="${SAVEPOINT}/update.log"

usage() {
  cat <<'USAGE'
Usage:
  update_system_hardened.sh [--apply] [--no-flatpak]

Default is dry-run. Use --apply to actually update the system.
USAGE
}

while (($#)); do
  case "$1" in
  --apply) APPLY=1 ;;
  --no-flatpak) ENABLE_FLATPAK=0 ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [[ ${EUID} -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

mkdir -p "$SAVEPOINT"
chmod 700 "$SAVEPOINT"
: > "$LOG"
chmod 600 "$LOG"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2; }

trap 'rc=$?; log "ERROR exit ${rc}: ${BASH_COMMAND}"; log "Savepoint: ${SAVEPOINT}"; exit "$rc"' ERR

run() {
  log "+ $*"
  if ((APPLY)); then
    "$@" 2>&1 | tee -a "$LOG"
  else
    log "[dry-run] skipped: $*"
  fi
}

capture() {
  local name="$1"; shift
  { printf '$ %q ' "$@"; printf '\n\n'; "$@" || true; } > "${SAVEPOINT}/${name}.txt" 2>&1
}

log "Savepoint: $SAVEPOINT"
capture os-release cat /etc/os-release
capture uname uname -a
capture dpkg-audit dpkg --audit
capture dkms-status dkms status
capture apt-sources bash -c "find /etc/apt -maxdepth 3 -type f \( -name '*.list' -o -name '*.sources' \) -print -exec sed -n '1,220p' {} \;"
dpkg --get-selections > "${SAVEPOINT}/dpkg-selections.txt" || true
apt-mark showmanual > "${SAVEPOINT}/apt-manual.txt" || true
tar -cpf "${SAVEPOINT}/etc_apt.tar" -C /etc apt

if ((APPLY == 0)); then
  log "DRY RUN ONLY. Re-run with --apply to update."
fi

run apt-get clean
run apt-get update -m
run dpkg --configure -a
run apt-get -f install -y
run apt-get full-upgrade -y
run apt-get autoremove --purge -y
run apt-get clean

if ((ENABLE_FLATPAK)) && command -v flatpak >/dev/null 2>&1; then
  target_user="${SUDO_USER:-}"
  if [[ -n "$target_user" && "$target_user" != "root" ]] && id "$target_user" >/dev/null 2>&1; then
    run runuser -u "$target_user" -- flatpak repair --user -y
    run runuser -u "$target_user" -- flatpak update -y
    run runuser -u "$target_user" -- flatpak uninstall --unused -y
  else
    run flatpak repair --user -y
    run flatpak update -y
    run flatpak uninstall --unused -y
  fi
fi

capture post-dpkg-audit dpkg --audit
capture post-dkms-status dkms status
capture post-apt-simulate bash -c "apt-get -s full-upgrade | sed -n '1,220p'"

log "Finished. Savepoint: $SAVEPOINT"
