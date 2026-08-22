#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REF="runtime/org.freedesktop.Sdk.Extension.rust-stable/x86_64/25.08"
REMOTE="flathub"
FLATHUB_REPO_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
FLATHUB_OSTREE_URL="https://dl.flathub.org/repo/"

STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/flatpak-rust-stable-fix"
STEP_DIR="$STATE_BASE/steps"
BACKUP_LINK="$STATE_BASE/latest-backup"
LOG_FILE="$STATE_BASE/run-$(date +%Y%m%d-%H%M%S).log"

YES=0
ROLLBACK=0
INCLUDE_UNUSED=0
USER_ONLY=0
SYSTEM_ONLY=0
DRY_RUN=0

usage() {
  cat <<EOF
Usage:
  $0 [--yes] [--include-unused] [--user-only|--system-only] [--dry-run]
  $0 --rollback

Options:
  --yes, -y          Do not ask for confirmation.
  --include-unused  Also run flatpak uninstall --unused after a successful repair.
  --user-only       Only repair the per-user Flatpak installation.
  --system-only     Only repair the system-wide Flatpak installation.
  --dry-run         Print what would run without changing anything.
  --rollback        Restore the backed-up Flatpak remote config from the last run.

What this script changes:
  - Backs up Flatpak remote configs and package lists.
  - Ensures Flathub exists.
  - Points Flathub to https://dl.flathub.org/repo/.
  - Refreshes appstream metadata.
  - Runs flatpak repair.
  - Retries the broken Rust runtime update.
  - Optionally removes unused Flatpak refs.

What rollback restores:
  - Flatpak remote config files backed up before this script changed them.

Rollback does not undo successful Flatpak app/runtime updates. Failed Flatpak
updates are transactional and normally leave the old deployment in place.
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

on_error() {
  local line="$1"
  log "ERROR: command failed near line $line."
  log "Log: $LOG_FILE"
  log "To restore remote config backup: $0 --rollback"
}
trap 'on_error "$LINENO"' ERR

run() {
  log "+ $*"
  if (( DRY_RUN )); then
    return 0
  fi
  "$@"
}

step_done() {
  [[ -f "$STEP_DIR/$1.done" ]]
}

mark_step_done() {
  mkdir -p "$STEP_DIR"
  : > "$STEP_DIR/$1.done"
}

step() {
  local id="$1"
  shift

  if step_done "$id"; then
    log "Skipping completed step: $id"
    return 0
  fi

  run "$@"
  mark_step_done "$id"
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

confirm() {
  if (( YES || DRY_RUN )); then
    return 0
  fi

  printf 'Proceed with Flatpak repair for %s? [y/N] ' "$REF"
  read -r answer
  case "$answer" in
  y|Y|yes|YES) ;;
  *) die "Cancelled by user." ;;
  esac
}

remote_exists_user() {
  flatpak --user remotes 2>/dev/null | awk '{print $1}' | grep -Fxq "$REMOTE"
}

remote_exists_system() {
  flatpak --system remotes 2>/dev/null | awk '{print $1}' | grep -Fxq "$REMOTE"
}

ref_installed_user() {
  flatpak --user info "$REF" >/dev/null 2>&1
}

ref_installed_system() {
  sudo flatpak --system info "$REF" >/dev/null 2>&1
}

prepare() {
  mkdir -p "$STATE_BASE" "$STEP_DIR"
  : > "$LOG_FILE"

  need_command flatpak
  need_command awk
  need_command grep
  need_command cp
  need_command mkdir
  need_command tee

  if (( ! USER_ONLY )); then
    need_command sudo
    sudo -v
  fi

  log "State directory: $STATE_BASE"
  log "Log file: $LOG_FILE"
}

backup_state() {
  local backup_dir="$STATE_BASE/backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"

  log "Creating backup at: $backup_dir"

  flatpak --user remotes --show-details > "$backup_dir/user-remotes.txt" 2>&1 || true
  flatpak --user list --columns=application,arch,branch,origin > "$backup_dir/user-list.txt" 2>&1 || true
  flatpak history > "$backup_dir/history-before.txt" 2>&1 || true

  if [[ -f "$HOME/.local/share/flatpak/repo/config" ]]; then
    cp -a "$HOME/.local/share/flatpak/repo/config" "$backup_dir/user-repo.config"
  fi

  if (( ! USER_ONLY )); then
    sudo flatpak --system remotes --show-details > "$backup_dir/system-remotes.txt" 2>&1 || true
    sudo flatpak --system list --columns=application,arch,branch,origin > "$backup_dir/system-list.txt" 2>&1 || true

    if sudo test -f /var/lib/flatpak/repo/config; then
      sudo cp -a /var/lib/flatpak/repo/config "$backup_dir/system-repo.config"
      sudo chown "$(id -u):$(id -g)" "$backup_dir/system-repo.config"
    fi
  fi

  ln -sfn "$backup_dir" "$BACKUP_LINK"
  log "Backup complete."
}

rollback() {
  [[ -L "$BACKUP_LINK" || -d "$BACKUP_LINK" ]] || die "No backup found at $BACKUP_LINK"

  local backup_dir
  backup_dir="$(readlink -f "$BACKUP_LINK")"
  log "Rolling back remote configs from: $backup_dir"

  if [[ -f "$backup_dir/user-repo.config" ]]; then
    mkdir -p "$HOME/.local/share/flatpak/repo"
    run cp -a "$backup_dir/user-repo.config" "$HOME/.local/share/flatpak/repo/config"
    log "Restored user Flatpak repo config."
  else
    log "No user repo config backup found; skipping user restore."
  fi

  if [[ -f "$backup_dir/system-repo.config" ]]; then
    run sudo cp -a "$backup_dir/system-repo.config" /var/lib/flatpak/repo/config
    log "Restored system Flatpak repo config."
  else
    log "No system repo config backup found; skipping system restore."
  fi

  log "Rollback completed. Remote configuration restored."
  log "Now run: flatpak remotes --show-details"
}

ensure_user_remote() {
  if remote_exists_user; then
    step user_remote_modify flatpak --user remote-modify "$REMOTE" \
      --url="$FLATHUB_OSTREE_URL" \
      --enable \
      --update-metadata
  else
    step user_remote_add flatpak --user remote-add \
      --if-not-exists "$REMOTE" "$FLATHUB_REPO_URL"
  fi
}

ensure_system_remote() {
  if remote_exists_system; then
    step system_remote_modify sudo flatpak --system remote-modify "$REMOTE" \
      --url="$FLATHUB_OSTREE_URL" \
      --enable \
      --update-metadata
  else
    step system_remote_add sudo flatpak --system remote-add \
      --if-not-exists "$REMOTE" "$FLATHUB_REPO_URL"
  fi
}

repair_user() {
  step user_appstream flatpak --user update --appstream "$REMOTE"
  step user_repair_dry flatpak --user repair --dry-run
  step user_repair flatpak --user repair
}

repair_system() {
  step system_appstream sudo flatpak --system update --appstream "$REMOTE"
  step system_repair_dry sudo flatpak --system repair --dry-run
  step system_repair sudo flatpak --system repair
}

update_or_reinstall_user_ref() {
  if ! ref_installed_user; then
    log "User scope: $REF is not installed; skipping user ref update."
    return 0
  fi

  if step_done user_ref_fixed; then
    log "Skipping completed step: user_ref_fixed"
    return 0
  fi

  log "User scope: trying update for $REF"
  if run flatpak --user update -y "$REF"; then
    mark_step_done user_ref_fixed
    return 0
  fi

  log "User scope: update failed; trying reinstall of the already-installed ref."
  run flatpak --user install --reinstall -y "$REMOTE" "$REF"
  mark_step_done user_ref_fixed
}

update_or_reinstall_system_ref() {
  if ! ref_installed_system; then
    log "System scope: $REF is not installed; skipping system ref update."
    return 0
  fi

  if step_done system_ref_fixed; then
    log "Skipping completed step: system_ref_fixed"
    return 0
  fi

  log "System scope: trying update for $REF"
  if run sudo flatpak --system update -y "$REF"; then
    mark_step_done system_ref_fixed
    return 0
  fi

  log "System scope: update failed; trying reinstall of the already-installed ref."
  run sudo flatpak --system install --reinstall -y "$REMOTE" "$REF"
  mark_step_done system_ref_fixed
}

final_update_user() {
  step user_update_all flatpak --user update -y
  if (( INCLUDE_UNUSED )); then
    step user_uninstall_unused flatpak --user uninstall --unused -y
  fi
}

final_update_system() {
  step system_update_all sudo flatpak --system update -y
  if (( INCLUDE_UNUSED )); then
    step system_uninstall_unused sudo flatpak --system uninstall --unused -y
  fi
}

verify() {
  log "Verification:"
  flatpak remotes --show-details | tee -a "$LOG_FILE" || true
  flatpak list --runtime | grep -F "org.freedesktop.Sdk.Extension.rust-stable" | tee -a "$LOG_FILE" || true

  log "Done. Reopen the graphical updater and check again."
  log "Log saved at: $LOG_FILE"
}

while (( $# > 0 )); do
  case "$1" in
  --yes|-y) YES=1 ;;
  --rollback) ROLLBACK=1 ;;
  --include-unused) INCLUDE_UNUSED=1 ;;
  --user-only) USER_ONLY=1 ;;
  --system-only) SYSTEM_ONLY=1 ;;
  --dry-run) DRY_RUN=1 ;;
  --help|-h) usage; exit 0 ;;
  *) usage; die "Unknown option: $1" ;;
  esac
  shift
done

if (( USER_ONLY && SYSTEM_ONLY )); then
  die "Choose either --user-only or --system-only, not both."
fi

prepare

if (( ROLLBACK )); then
  rollback
  exit 0
fi

confirm
backup_state

if (( ! SYSTEM_ONLY )); then
  ensure_user_remote
  repair_user
  update_or_reinstall_user_ref
  final_update_user
fi

if (( ! USER_ONLY )); then
  ensure_system_remote
  repair_system
  update_or_reinstall_system_ref
  final_update_system
fi

verify
