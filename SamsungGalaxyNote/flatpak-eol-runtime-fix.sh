#!/usr/bin/env bash
# flatpak-eol-runtime-fix.sh
#
# Safely audit and remediate apps that still depend on an EOL Flatpak runtime.
# Default mode is audit-only.
#
# Tested design target:
#   - Pop!_OS / Ubuntu-family hosts with Flatpak installed
#   - user and system Flatpak installations
#
# What it does:
#   1. Audits apps using org.kde.Platform//6.8
#   2. Saves before/after snapshots
#   3. Runs safe verification (flatpak repair --dry-run)
#   4. Updates affected apps
#   5. Prunes unused refs
#   6. Optionally runs flatpak repair for real
#   7. Optionally reinstalls apps that are still stuck on the EOL runtime
#
# What it cannot do:
#   - It cannot force an app to use a newer runtime if the maintainer has not
#     published a newer Flatpak build.

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly SCRIPT_NAME="${0##*/}"
readonly TARGET_RUNTIME="org.kde.Platform//6.8"

MODE="audit"
WITH_REPAIR=0
REINSTALL_STUCK=0
FORCE_STOP=0
LOG_DIR="${PWD}/flatpak-eol-fix-$(date +%Y%m%d-%H%M%S)"

TMPDIR_CREATED=""

usage() {
  cat <<'EOF'
Usage:
  flatpak-eol-runtime-fix.sh [options]

Options:
  --audit              Audit only (default)
  --apply              Apply safe remediation
  --with-repair        Also run flatpak repair (not just --dry-run)
  --reinstall-stuck    Reinstall apps that still require the EOL runtime after update
  --force-stop         Stop affected running Flatpak apps before remediation
  --log-dir DIR        Write logs/snapshots to DIR
  -h, --help           Show this help

Examples:
  ./flatpak-eol-runtime-fix.sh --audit
  ./flatpak-eol-runtime-fix.sh --apply
  ./flatpak-eol-runtime-fix.sh --apply --with-repair --reinstall-stuck
EOF
}

ts() {
  date '+%F %T'
}

log() {
  printf '[%s] %s\n' "$(ts)" "$*"
}

warn() {
  printf '[%s] WARNING: %s\n' "$(ts)" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2
  exit 1
}

on_err() {
  local line="$1"
  local cmd="$2"
  printf '[%s] ERROR: command failed at line %s: %s\n' "$(ts)" "$line" "$cmd" >&2
}
trap 'on_err "${LINENO}" "${BASH_COMMAND}"' ERR

cleanup() {
  if [[ -n "${TMPDIR_CREATED}" && -d "${TMPDIR_CREATED}" ]]; then
    rm -rf -- "${TMPDIR_CREATED}"
  fi
}
trap cleanup EXIT

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

scope_flag() {
  case "$1" in
  user)   printf '%s' '--user' ;;
  system) printf '%s' '--system' ;;
  *) die "Unknown scope: $1" ;;
  esac
}

run_flatpak() {
  local scope="$1"
  shift

  if [[ "$scope" == "system" ]]; then
    if [[ "${EUID}" -eq 0 ]]; then
      flatpak --system "$@"
    else
      need_cmd sudo
      sudo flatpak --system "$@"
    fi
  else
    flatpak --user "$@"
  fi
}

mkdir_secure() {
  mkdir -p -- "$1"
  chmod 700 -- "$1"
}

count_lines() {
  local file="$1"
  if [[ -s "$file" ]]; then
    awk 'END{print NR}' "$file"
  else
    printf '0'
  fi
}

list_scopes() {
  # user scope
  if flatpak list --user >/dev/null 2>&1; then
    printf '%s\n' user
  fi

  # system scope
  if flatpak list --system >/dev/null 2>&1; then
    printf '%s\n' system
  fi
}

snapshot_scope() {
  local scope="$1"
  local prefix="${LOG_DIR}/${scope}"

  log "Saving snapshot for scope=${scope}"
  flatpak "$(scope_flag "$scope")" list --app \
    --columns=application,branch,origin,installation,runtime \
    > "${prefix}-apps-before-or-after.tsv" 2>/dev/null || true

  flatpak "$(scope_flag "$scope")" list --runtime \
    --columns=application,branch,origin,installation \
    > "${prefix}-runtimes-before-or-after.tsv" 2>/dev/null || true
}

snapshot_scope_named() {
  local scope="$1"
  local name="$2"
  local prefix="${LOG_DIR}/${scope}-${name}"

  flatpak "$(scope_flag "$scope")" list --app \
    --columns=application,branch,origin,installation,runtime \
    > "${prefix}-apps.tsv" 2>/dev/null || true

  flatpak "$(scope_flag "$scope")" list --runtime \
    --columns=application,branch,origin,installation \
    > "${prefix}-runtimes.tsv" 2>/dev/null || true
}

list_affected_scope() {
  local scope="$1"
  local outfile="$2"

  flatpak "$(scope_flag "$scope")" list --app \
    --columns=application,branch,origin,installation,runtime \
    | awk -v target="$TARGET_RUNTIME" '
        NR > 1 && NF >= 5 && $5 == target {
          print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5
        }
      ' > "$outfile"
}

repair_dry_run_scope() {
  local scope="$1"
  local outfile="$2"

  log "Running safe verification: flatpak repair --dry-run (${scope})"
  if [[ "$scope" == "system" && "${EUID}" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    printf 'Skipped: sudo not available for system repair dry-run.\n' > "$outfile"
    return 0
  fi

  run_flatpak "$scope" repair --dry-run > "$outfile" 2>&1 || true
}

repair_scope() {
  local scope="$1"
  local outfile="$2"

  log "Running repair for scope=${scope}"
  run_flatpak "$scope" repair > "$outfile" 2>&1 || true
}

is_app_running() {
  local app_id="$1"

  flatpak ps --columns=application 2>/dev/null \
    | awk 'NR > 1 && NF { print $1 }' \
    | grep -Fxq -- "$app_id"
}

handle_running_apps() {
  local affected_file="$1"
  local running_found=0

  while IFS=$'\t' read -r app_id branch origin installation runtime; do
    [[ -n "${app_id:-}" ]] || continue
    if is_app_running "$app_id"; then
      running_found=1
      if (( FORCE_STOP )); then
        warn "Stopping running Flatpak app: $app_id"
        flatpak kill "$app_id" >/dev/null 2>&1 || warn "Could not stop $app_id"
      else
        warn "Affected app is currently running: $app_id"
      fi
    fi
  done < "$affected_file"

  if (( running_found )) && (( ! FORCE_STOP )); then
    die "Close affected Flatpak apps first, or rerun with --force-stop"
  fi
}

update_affected_scope() {
  local scope="$1"
  local affected_file="$2"

  if [[ ! -s "$affected_file" ]]; then
    log "No affected apps in scope=${scope}"
    return 0
  fi

  log "Refreshing appstream metadata for scope=${scope}"
  run_flatpak "$scope" update --appstream -y --noninteractive >/dev/null 2>&1 || true

  while IFS=$'\t' read -r app_id branch origin installation runtime; do
    [[ -n "${app_id:-}" ]] || continue
    log "Updating app ${app_id} (${scope})"
    run_flatpak "$scope" update -y --noninteractive "$app_id" || warn "Update failed: ${app_id}"
  done < "$affected_file"

  log "Pruning unused refs for scope=${scope}"
  run_flatpak "$scope" uninstall --unused -y --noninteractive || warn "Unused-ref cleanup failed for ${scope}"
}

reinstall_stuck_scope() {
  local scope="$1"
  local stuck_file="$2"

  if [[ ! -s "$stuck_file" ]]; then
    log "No stuck apps to reinstall in scope=${scope}"
    return 0
  fi

  while IFS=$'\t' read -r app_id branch origin installation runtime; do
    [[ -n "${app_id:-}" ]] || continue

    local ref remote
    ref="$(flatpak "$(scope_flag "$scope")" info --show-ref "$app_id" 2>/dev/null || true)"
    remote="$(flatpak "$(scope_flag "$scope")" info --show-origin "$app_id" 2>/dev/null || true)"

    if [[ -z "$ref" || -z "$remote" ]]; then
      warn "Skipping reinstall for ${app_id}: could not determine ref/origin"
      continue
    fi

    warn "Reinstalling stuck app ${app_id} from remote ${remote} (${scope})"
    warn "App data is NOT deleted by this script."

    run_flatpak "$scope" uninstall -y --noninteractive "$app_id" \
      || { warn "Uninstall failed for ${app_id}"; continue; }

    run_flatpak "$scope" install -y --noninteractive "$remote" "$ref" \
      || { warn "Reinstall failed for ${app_id}"; continue; }
  done < "$stuck_file"

  run_flatpak "$scope" uninstall --unused -y --noninteractive || true
}

print_report() {
  local scope="$1"
  local file="$2"
  local count
  count="$(count_lines "$file")"

  if [[ "$count" == "0" ]]; then
    log "scope=${scope}: no apps currently using ${TARGET_RUNTIME}"
    return 0
  fi

  log "scope=${scope}: ${count} app(s) currently using ${TARGET_RUNTIME}"
  while IFS=$'\t' read -r app_id branch origin installation runtime; do
    printf '  - app=%s branch=%s origin=%s installation=%s runtime=%s\n' \
      "$app_id" "$branch" "$origin" "$installation" "$runtime"
  done < "$file"
}

parse_args() {
  while (($#)); do
    case "$1" in
    --audit)
      MODE="audit"
      ;;
    --apply)
      MODE="apply"
      ;;
    --with-repair)
      WITH_REPAIR=1
      ;;
    --reinstall-stuck)
      REINSTALL_STUCK=1
      ;;
    --force-stop)
      FORCE_STOP=1
      ;;
    --log-dir)
      shift
      [[ $# -gt 0 ]] || die "--log-dir requires a path"
      LOG_DIR="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"

  need_cmd flatpak
  need_cmd awk
  need_cmd grep
  need_cmd date
  need_cmd mktemp

  TMPDIR_CREATED="$(mktemp -d)"
  mkdir_secure "$LOG_DIR"

  log "Mode: ${MODE}"
  log "Target runtime: ${TARGET_RUNTIME}"
  log "Logs: ${LOG_DIR}"

  mapfile -t scopes < <(list_scopes)
  [[ "${#scopes[@]}" -gt 0 ]] || die "No Flatpak installation found"

  local total_before=0

  for scope in "${scopes[@]}"; do
    snapshot_scope_named "$scope" "before"
    local affected_before="${LOG_DIR}/${scope}-affected-before.tsv"
    local repair_before="${LOG_DIR}/${scope}-repair-before.txt"

    list_affected_scope "$scope" "$affected_before"
    repair_dry_run_scope "$scope" "$repair_before"
    print_report "$scope" "$affected_before"

    total_before=$(( total_before + $(count_lines "$affected_before") ))
  done

  if (( total_before == 0 )); then
    log "No apps found using ${TARGET_RUNTIME}. Nothing to do."
    exit 0
  fi

  if [[ "$MODE" == "audit" ]]; then
    log "Audit complete. No changes were made."
    exit 0
  fi

  # Safety: ensure affected apps are not running before apply/reinstall work.
  for scope in "${scopes[@]}"; do
    local affected_before="${LOG_DIR}/${scope}-affected-before.tsv"
    handle_running_apps "$affected_before"
  done

  # Remediation.
  for scope in "${scopes[@]}"; do
    local affected_before="${LOG_DIR}/${scope}-affected-before.tsv"
    update_affected_scope "$scope" "$affected_before"

    if (( WITH_REPAIR )); then
      repair_scope "$scope" "${LOG_DIR}/${scope}-repair-apply.txt"
    fi
  done

  # Check what remains after update/prune/optional repair.
  local total_after_update=0
  for scope in "${scopes[@]}"; do
    local affected_after_update="${LOG_DIR}/${scope}-affected-after-update.tsv"
    list_affected_scope "$scope" "$affected_after_update"
    print_report "$scope" "$affected_after_update"
    total_after_update=$(( total_after_update + $(count_lines "$affected_after_update") ))
  done

  # Optional reinstall for apps still stuck on the EOL runtime.
  if (( REINSTALL_STUCK )) && (( total_after_update > 0 )); then
    for scope in "${scopes[@]}"; do
      local affected_after_update="${LOG_DIR}/${scope}-affected-after-update.tsv"
      reinstall_stuck_scope "$scope" "$affected_after_update"
    done
  fi

  # Final verification and snapshots.
  local total_final=0
  for scope in "${scopes[@]}"; do
    snapshot_scope_named "$scope" "after"

    local affected_final="${LOG_DIR}/${scope}-affected-final.tsv"
    local repair_final="${LOG_DIR}/${scope}-repair-after.txt"

    list_affected_scope "$scope" "$affected_final"
    repair_dry_run_scope "$scope" "$repair_final"
    print_report "$scope" "$affected_final"

    total_final=$(( total_final + $(count_lines "$affected_final") ))
  done

  if (( total_final == 0 )); then
    log "Success: no installed apps are still using ${TARGET_RUNTIME}"
  else
    warn "Some apps still require ${TARGET_RUNTIME}."
    warn "This usually means the app maintainer has not yet published a build against a supported runtime."
    warn "See logs in: ${LOG_DIR}"
  fi
}

main "$@"
