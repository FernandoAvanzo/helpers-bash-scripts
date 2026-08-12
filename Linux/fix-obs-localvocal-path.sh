#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_ID="com.obsproject.Studio"

LOCALVOCAL_SO="/app/plugins/LocalVocal/lib64/obs-plugins/obs-localvocal.so"
LOCALVOCAL_PLUGIN_DIR="/app/plugins/LocalVocal/lib64/obs-plugins"
LOCALVOCAL_DATA_DIR="/app/plugins/LocalVocal/share/obs/obs-plugins"

STATE_DIR="${HOME}/.local/state/obs-localvocal-fix"
BACKUP_FILE="${STATE_DIR}/flatpak-override-before-$(date +%Y%m%d-%H%M%S).txt"

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  printf '[ERROR] Script failed at line %s with exit code %s.\n' "${BASH_LINENO[0]}" "$exit_code" >&2
  exit "$exit_code"
}

trap on_error ERR

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

join_unique_colon() {
  local existing="${1:-}"
  shift || true

  local -a result=()
  local -A seen=()
  local item

  for item in "$@"; do
    [[ -n "$item" ]] || continue
    if [[ -z "${seen[$item]+x}" ]]; then
      result+=("$item")
      seen["$item"]=1
    fi
  done

  if [[ -n "$existing" ]]; then
    local old_ifs="$IFS"
    IFS=':'
    read -r -a existing_items <<< "$existing"
    IFS="$old_ifs"

    for item in "${existing_items[@]}"; do
      [[ -n "$item" ]] || continue
      if [[ -z "${seen[$item]+x}" ]]; then
        result+=("$item")
        seen["$item"]=1
      fi
    done
  fi

  local joined=""
  for item in "${result[@]}"; do
    if [[ -z "$joined" ]]; then
      joined="$item"
    else
      joined="${joined}:${item}"
    fi
  done

  printf '%s' "$joined"
}

get_existing_override_env() {
  local key="$1"
  flatpak override "${FLATPAK_SCOPE[@]}" --show "$APP_ID" 2>/dev/null \
    | awk -F= -v key="$key" '$1 == key {print substr($0, length(key) + 2)}' \
    | tail -n 1
}

verify_flatpak_scope() {
  if flatpak info --user "$APP_ID" >/dev/null 2>&1; then
    FLATPAK_SCOPE=(--user)
    OVERRIDE_CMD=(flatpak override --user)
    log "OBS Flatpak installation scope: user"
    return
  fi

  if flatpak info --system "$APP_ID" >/dev/null 2>&1; then
    FLATPAK_SCOPE=(--system)
    OVERRIDE_CMD=(sudo flatpak override --system)
    log "OBS Flatpak installation scope: system"
    return
  fi

  die "OBS Flatpak app '${APP_ID}' was not found. Install OBS Flatpak first."
}

verify_localvocal_inside_sandbox() {
  log "Checking whether LocalVocal exists inside the OBS Flatpak sandbox..."

  if flatpak run --command=sh "$APP_ID" -c "test -f '$LOCALVOCAL_SO'"; then
    log "Found LocalVocal plugin binary: $LOCALVOCAL_SO"
  else
    die "LocalVocal is installed as a Flatpak extension, but the plugin binary was not found at: $LOCALVOCAL_SO"
  fi

  if flatpak run --command=sh "$APP_ID" -c "test -d '$LOCALVOCAL_DATA_DIR'"; then
    log "Found LocalVocal data directory: $LOCALVOCAL_DATA_DIR"
  else
    warn "LocalVocal data directory was not found: $LOCALVOCAL_DATA_DIR"
  fi
}

backup_existing_overrides() {
  mkdir -p "$STATE_DIR"

  log "Backing up current Flatpak overrides to: $BACKUP_FILE"
  flatpak override "${FLATPAK_SCOPE[@]}" --show "$APP_ID" > "$BACKUP_FILE" 2>/dev/null || true
}

apply_overrides() {
  local existing_plugins_path
  local existing_data_path
  local existing_ld_path
  local runtime_ld_path
  local new_plugins_path
  local new_data_path
  local new_ld_path

  existing_plugins_path="$(get_existing_override_env OBS_PLUGINS_PATH || true)"
  existing_data_path="$(get_existing_override_env OBS_PLUGINS_DATA_PATH || true)"
  existing_ld_path="$(get_existing_override_env LD_LIBRARY_PATH || true)"

  runtime_ld_path="$(
    flatpak run --command=sh "$APP_ID" -c 'printf "%s" "${LD_LIBRARY_PATH:-}"' 2>/dev/null || true
  )"

  new_plugins_path="$(
    join_unique_colon "$existing_plugins_path" \
      "/app/lib/obs-plugins" \
      "/app/plugins/lib/obs-plugins" \
      "$LOCALVOCAL_PLUGIN_DIR"
  )"

  new_data_path="$(
    join_unique_colon "$existing_data_path" \
      "/app/share/obs/obs-plugins" \
      "/app/plugins/share/obs/obs-plugins" \
      "$LOCALVOCAL_DATA_DIR"
  )"

  new_ld_path="$(
    join_unique_colon "$existing_ld_path" \
      "/app/plugins/LocalVocal/lib64" \
      "/app/plugins/LocalVocal/lib" \
      "/app/plugins/lib" \
      "$runtime_ld_path"
  )"

  log "Applying OBS Flatpak environment overrides..."

  "${OVERRIDE_CMD[@]}" \
    --env="OBS_PLUGINS_PATH=${new_plugins_path}" \
    --env="OBS_PLUGINS_DATA_PATH=${new_data_path}" \
    --env="LD_LIBRARY_PATH=${new_ld_path}" \
    "$APP_ID"

  log "Overrides applied."
}

verify_overrides() {
  log "Verifying new OBS sandbox environment..."

  flatpak run --command=sh "$APP_ID" -c "
    echo 'OBS_PLUGINS_PATH='\"\${OBS_PLUGINS_PATH:-}\"
    echo 'OBS_PLUGINS_DATA_PATH='\"\${OBS_PLUGINS_DATA_PATH:-}\"
    echo 'LD_LIBRARY_PATH='\"\${LD_LIBRARY_PATH:-}\"
    echo
    if test -f '$LOCALVOCAL_SO'; then
      echo 'OK: LocalVocal plugin binary is visible.'
    else
      echo 'ERROR: LocalVocal plugin binary is not visible.'
      exit 1
    fi
  "
}

main() {
  require_command flatpak
  require_command awk
  require_command date

  verify_flatpak_scope

  log "Closing OBS if it is currently running..."
  flatpak kill "$APP_ID" >/dev/null 2>&1 || true
  if command -v pkill >/dev/null 2>&1; then
    pkill -u "$(id -u)" -x obs >/dev/null 2>&1 || true
  else
    warn "pkill was not found; skipped host OBS process cleanup."
  fi

  verify_localvocal_inside_sandbox
  backup_existing_overrides
  apply_overrides
  verify_overrides

  cat <<EOF

Done.

Now start OBS with:

  flatpak run $APP_ID

Then check:

  Audio Mixer → Desktop Audio gear → Filters → + menu

Look for LocalVocal / transcription filter.

If something goes wrong, your previous Flatpak override backup is here:

  $BACKUP_FILE

To remove only the overrides created by this fix, run:

  flatpak override ${FLATPAK_SCOPE[*]} \\
    --unset-env=OBS_PLUGINS_PATH \\
    --unset-env=OBS_PLUGINS_DATA_PATH \\
    --unset-env=LD_LIBRARY_PATH \\
    $APP_ID

EOF
}

main "$@"
