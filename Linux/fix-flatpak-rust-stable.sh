#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REF="runtime/org.freedesktop.Sdk.Extension.rust-stable/x86_64/25.08"
REMOTE="flathub"
FLATHUB_REPO_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
FLATHUB_OSTREE_URL="https://dl.flathub.org/repo/"

STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/flatpak-rust-stable-fix"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$STATE_BASE/run-$RUN_ID"
STEP_DIR="$RUN_DIR/steps"
LOG_FILE="$RUN_DIR/run.log"
BACKUP_LINK="$STATE_BASE/latest-backup"
RUN_LINK="$STATE_BASE/latest-run"
ADDED_MASKS_FILE="$RUN_DIR/added-masks.tsv"
ADDED_MASKS_LINK="$STATE_BASE/latest-added-masks"

YES=0
ROLLBACK=0
UNMASK=0
INCLUDE_UNUSED=0
USER_ONLY=0
SYSTEM_ONLY=0
DRY_RUN=0
AUTO_MASK=1

usage() {
  cat <<EOF
Usage:
  $0 [--yes] [--include-unused] [--user-only|--system-only] [--dry-run] [--no-mask]
  $0 --unmask [--user-only|--system-only]
  $0 --rollback

Options:
  --yes, -y          Do not ask for confirmation.
  --include-unused  Also run flatpak uninstall --unused after successful repair/update.
  --user-only       Only operate on the per-user Flatpak installation.
  --system-only     Only operate on the system-wide Flatpak installation.
  --dry-run         Print what would run without changing anything.
  --no-mask         Do not mask the broken ref if Flathub returns HTTP 404.
  --unmask          Remove the temporary mask for the Rust stable extension.
  --rollback        Restore Flatpak remote configs from the last backup and remove
                    any masks added by the last run of this script.

What this script changes:
  - Creates a per-run state directory and log.
  - Backs up Flatpak remote configs, package lists, masks, and history.
  - Ensures the Flathub remote exists and points to https://dl.flathub.org/repo/.
  - Refreshes appstream metadata.
  - Runs flatpak repair.
  - Tries the broken Rust runtime update.
  - If Flathub still returns HTTP 404, temporarily masks only that exact ref so the
    rest of your Flatpaks can update and the GUI updater stops retrying it.
  - Optionally removes unused Flatpak refs.

Why masking exists here:
  HTTP 404 is returned by the remote server/CDN while pulling the latest commit.
  A local repair cannot create a missing remote object. Masking is a reversible
  local workaround until the remote publishes/replicates a valid object.

After Flathub is fixed:
  $0 --unmask
  flatpak update
EOF
}

log() {
  local line
  line="$(printf '[%s] %s\n' "$(date '+%F %T')" "$*")"
  if [[ -n "${LOG_FILE:-}" && -d "$(dirname "$LOG_FILE")" ]]; then
    printf '%s' "$line" | tee -a "$LOG_FILE"
  else
    printf '%s' "$line" >&2
  fi
}

die() {
  log "ERROR: $*"
  exit 1
}

on_error() {
  local line="$1"
  log "ERROR: command failed near line $line."
  log "Log: $LOG_FILE"
  log "To restore remote config backup and remove masks added by the last run: $0 --rollback"
}
trap 'on_error "$LINENO"' ERR

quote_cmd() {
  local out="" arg
  for arg in "$@"; do
    printf -v arg '%q' "$arg"
    out+="$arg "
  done
  printf '%s' "${out% }"
}

run() {
  log "+ $(quote_cmd "$@")"
  if (( DRY_RUN )); then
    return 0
  fi
  "$@"
}

run_capture() {
  local outfile="$1"
  shift

  log "+ $(quote_cmd "$@")"
  if (( DRY_RUN )); then
    : > "$outfile"
    return 0
  fi

  set +e
  "$@" >"$outfile" 2>&1
  local status=$?
  set -e

  cat "$outfile" | tee -a "$LOG_FILE"
  return "$status"
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

  printf 'Proceed with Flatpak repair/update for %s? [y/N] ' "$REF"
  read -r answer
  case "$answer" in
  y|Y|yes|YES) ;;
  *) die "Cancelled by user." ;;
  esac
}

prepare() {
  mkdir -p "$RUN_DIR" "$STEP_DIR"
  : > "$LOG_FILE"
  ln -sfn "$RUN_DIR" "$RUN_LINK"

  need_command flatpak
  need_command awk
  need_command grep
  need_command cp
  need_command mkdir
  need_command tee
  need_command readlink

  if (( ! USER_ONLY )); then
    need_command sudo
    sudo -v
  fi

  log "State directory: $RUN_DIR"
  log "Log file: $LOG_FILE"
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

mask_exists_user() {
  flatpak --user mask 2>/dev/null | grep -Fxq "$REF"
}

mask_exists_system() {
  sudo flatpak --system mask 2>/dev/null | grep -Fxq "$REF"
}

record_added_mask() {
  local scope="$1"
  local pattern="$2"
  printf '%s\t%s\n' "$scope" "$pattern" >> "$ADDED_MASKS_FILE"
  ln -sfn "$ADDED_MASKS_FILE" "$ADDED_MASKS_LINK"
}

backup_state() {
  local backup_dir="$STATE_BASE/backup-$RUN_ID"
  mkdir -p "$backup_dir"

  log "Creating backup at: $backup_dir"

  flatpak --user remotes --show-details > "$backup_dir/user-remotes.txt" 2>&1 || true
  flatpak --user list --columns=application,arch,branch,origin > "$backup_dir/user-list.txt" 2>&1 || true
  flatpak --user mask > "$backup_dir/user-masks.txt" 2>&1 || true
  flatpak history > "$backup_dir/history-before.txt" 2>&1 || true

  if [[ -f "$HOME/.local/share/flatpak/repo/config" ]]; then
    cp -a "$HOME/.local/share/flatpak/repo/config" "$backup_dir/user-repo.config"
  fi

  if (( ! USER_ONLY )); then
    sudo flatpak --system remotes --show-details > "$backup_dir/system-remotes.txt" 2>&1 || true
    sudo flatpak --system list --columns=application,arch,branch,origin > "$backup_dir/system-list.txt" 2>&1 || true
    sudo flatpak --system mask > "$backup_dir/system-masks.txt" 2>&1 || true

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

  if [[ -L "$ADDED_MASKS_LINK" || -f "$ADDED_MASKS_LINK" ]]; then
    local masks_file
    masks_file="$(readlink -f "$ADDED_MASKS_LINK")"
    if [[ -f "$masks_file" ]]; then
      log "Removing masks added by the last run: $masks_file"
      while IFS=$'\t' read -r scope pattern; do
        [[ -n "${scope:-}" && -n "${pattern:-}" ]] || continue
        case "$scope" in
        user) run flatpak --user mask --remove "$pattern" || true ;;
        system) run sudo flatpak --system mask --remove "$pattern" || true ;;
        esac
      done < "$masks_file"
    fi
  else
    log "No script-added mask record found; skipping mask rollback."
  fi

  log "Rollback completed."
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

mask_user_ref() {
  if mask_exists_user; then
    log "User scope: $REF is already masked."
    return 0
  fi

  run flatpak --user mask "$REF"
  record_added_mask user "$REF"
  log "User scope: temporarily masked $REF."
}

mask_system_ref() {
  if mask_exists_system; then
    log "System scope: $REF is already masked."
    return 0
  fi

  run sudo flatpak --system mask "$REF"
  record_added_mask system "$REF"
  log "System scope: temporarily masked $REF."
}

unmask_user_ref() {
  if mask_exists_user; then
    run flatpak --user mask --remove "$REF"
    log "User scope: removed mask for $REF."
  else
    log "User scope: no mask exists for $REF."
  fi
}

unmask_system_ref() {
  if mask_exists_system; then
    run sudo flatpak --system mask --remove "$REF"
    log "System scope: removed mask for $REF."
  else
    log "System scope: no mask exists for $REF."
  fi
}

handle_update_failure() {
  local scope="$1"
  local outfile="$2"

  if grep -Eqi 'HTTP 404|Server returned HTTP 404|status code 404' "$outfile"; then
    log "$scope scope: Flathub returned HTTP 404 for $REF."
    log "$scope scope: This is a remote-server/CDN object problem, not a local Flatpak metadata problem."

    if (( AUTO_MASK )); then
      case "$scope" in
      User) mask_user_ref ;;
      System) mask_system_ref ;;
      esac
      log "$scope scope: continuing after mask so other Flatpaks can update."
      return 0
    fi

    die "$scope scope: HTTP 404 detected and --no-mask was used."
  fi

  die "$scope scope: update failed for a reason other than HTTP 404. See $outfile"
}

update_user_ref_or_mask() {
  if ! ref_installed_user; then
    log "User scope: $REF is not installed; skipping user ref update."
    return 0
  fi

  if step_done user_ref_checked; then
    log "Skipping completed step: user_ref_checked"
    return 0
  fi

  local outfile="$RUN_DIR/user-ref-update.log"
  log "User scope: trying update for $REF"

  if run_capture "$outfile" flatpak --user update -y --noninteractive "$REF"; then
    log "User scope: $REF updated successfully."
    mark_step_done user_ref_checked
    return 0
  fi

  handle_update_failure "User" "$outfile"
  mark_step_done user_ref_checked
}

update_system_ref_or_mask() {
  if ! ref_installed_system; then
    log "System scope: $REF is not installed; skipping system ref update."
    return 0
  fi

  if step_done system_ref_checked; then
    log "Skipping completed step: system_ref_checked"
    return 0
  fi

  local outfile="$RUN_DIR/system-ref-update.log"
  log "System scope: trying update for $REF"

  if run_capture "$outfile" sudo flatpak --system update -y --noninteractive "$REF"; then
    log "System scope: $REF updated successfully."
    mark_step_done system_ref_checked
    return 0
  fi

  handle_update_failure "System" "$outfile"
  mark_step_done system_ref_checked
}

final_update_user() {
  step user_update_all flatpak --user update -y --noninteractive
  if (( INCLUDE_UNUSED )); then
    step user_uninstall_unused flatpak --user uninstall --unused -y
  fi
}

final_update_system() {
  step system_update_all sudo flatpak --system update -y --noninteractive
  if (( INCLUDE_UNUSED )); then
    step system_uninstall_unused sudo flatpak --system uninstall --unused -y
  fi
}

verify() {
  log "Verification:"
  flatpak remotes --show-details | tee -a "$LOG_FILE" || true
  flatpak --user mask | tee -a "$LOG_FILE" || true
  if (( ! USER_ONLY )); then
    sudo flatpak --system mask | tee -a "$LOG_FILE" || true
  fi
  flatpak list --runtime | grep -F "org.freedesktop.Sdk.Extension.rust-stable" | tee -a "$LOG_FILE" || true

  log "Done."
  log "Log saved at: $LOG_FILE"

  if [[ -s "$ADDED_MASKS_FILE" ]]; then
    log "A temporary mask was added because Flathub returned HTTP 404."
    log "After Flathub fixes the remote object, run: $0 --unmask && flatpak update"
  else
    log "No temporary mask was added."
  fi
}

while (( $# > 0 )); do
  case "$1" in
  --yes|-y) YES=1 ;;
  --rollback) ROLLBACK=1 ;;
  --unmask) UNMASK=1 ;;
  --include-unused) INCLUDE_UNUSED=1 ;;
  --user-only) USER_ONLY=1 ;;
  --system-only) SYSTEM_ONLY=1 ;;
  --dry-run) DRY_RUN=1 ;;
  --no-mask) AUTO_MASK=0 ;;
  --help|-h) usage; exit 0 ;;
  *) usage; die "Unknown option: $1" ;;
  esac
  shift
done

if (( USER_ONLY && SYSTEM_ONLY )); then
  die "Choose either --user-only or --system-only, not both."
fi

if (( ROLLBACK && UNMASK )); then
  die "Choose either --rollback or --unmask, not both."
fi

prepare

if (( ROLLBACK )); then
  rollback
  exit 0
fi

if (( UNMASK )); then
  if (( ! SYSTEM_ONLY )); then
    unmask_user_ref
  fi
  if (( ! USER_ONLY )); then
    unmask_system_ref
  fi
  log "Unmask completed. Now retry: flatpak update"
  exit 0
fi

confirm
backup_state

if (( ! SYSTEM_ONLY )); then
  ensure_user_remote
  repair_user
  update_user_ref_or_mask
  final_update_user
fi

if (( ! USER_ONLY )); then
  ensure_system_remote
  repair_system
  update_system_ref_or_mask
  final_update_system
fi

verify
