#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_ID="com.obsproject.Studio"
PLUGIN_ID="com.obsproject.Studio.Plugin.LocalVocal"
PLUGIN_NAME="obs-localvocal"

STATE_DIR="${HOME}/.local/state/localvocal-obs-flatpak-fix"
BACKUP_FILE="${STATE_DIR}/flatpak-override-before-user-plugin-shim-$(date +%Y%m%d-%H%M%S).txt"

LOCALVOCAL_LD_PATHS=(
  "/app/plugins/LocalVocal/lib64"
  "/app/plugins/LocalVocal/lib"
  "/app/plugins/LocalVocal/lib64/obs-plugins/obs-localvocal"
)

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
  printf '[ERROR] Script failed near line %s with exit code %s.\n' "${BASH_LINENO[0]}" "$exit_code" >&2
  exit "$exit_code"
}

trap on_error ERR

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

detect_flatpak_scope() {
  if flatpak info --user "$APP_ID" >/dev/null 2>&1; then
    SCOPE_ARGS=(--user)
    OVERRIDE_CMD=(flatpak override --user)
    log "Detected OBS Flatpak scope: user"
    return
  fi

  if flatpak info --system "$APP_ID" >/dev/null 2>&1; then
    SCOPE_ARGS=(--system)
    OVERRIDE_CMD=(sudo flatpak override --system)
    log "Detected OBS Flatpak scope: system"
    return
  fi

  die "OBS Flatpak app '${APP_ID}' was not found."
}

get_existing_override_env() {
  local key="$1"

  flatpak override "${SCOPE_ARGS[@]}" --show "$APP_ID" 2>/dev/null \
    | awk -F= -v key="$key" '$1 == key {print substr($0, length(key) + 2)}' \
    | tail -n 1
}

join_unique_colon() {
  local existing="${1:-}"
  shift || true

  local result=""
  local item=""

  add_item() {
    local value="$1"
    [[ -n "$value" ]] || return 0

    case ":${result}:" in
    *":${value}:"*) ;;
    *) result="${result:+${result}:}${value}" ;;
    esac
  }

  for item in "$@"; do
    add_item "$item"
  done

  if [[ -n "$existing" ]]; then
    local old_ifs="$IFS"
    IFS=':'
    read -r -a existing_items <<< "$existing"
    IFS="$old_ifs"

    for item in "${existing_items[@]}"; do
      add_item "$item"
    done
  fi

  printf '%s' "$result"
}

backup_overrides() {
  mkdir -p "$STATE_DIR"
  log "Backing up current Flatpak overrides to: $BACKUP_FILE"
  flatpak override "${SCOPE_ARGS[@]}" --show "$APP_ID" > "$BACKUP_FILE" 2>/dev/null || true
}

verify_extension_is_mounted() {
  log "Checking LocalVocal Flatpak extension inside OBS sandbox..."

  flatpak run --command=sh "$APP_ID" -c '
    test -f /app/plugins/LocalVocal/lib64/obs-plugins/obs-localvocal.so
    test -d /app/plugins/LocalVocal/share/obs/obs-plugins/obs-localvocal
  ' || die "LocalVocal is not visible inside the OBS Flatpak sandbox. Reinstall the LocalVocal Flatpak extension first."

  log "LocalVocal extension files are visible inside the OBS sandbox."
}

clear_bad_obs_plugin_path_overrides() {
  log "Removing custom OBS_PLUGINS_PATH / OBS_PLUGINS_DATA_PATH overrides..."

  "${OVERRIDE_CMD[@]}" \
    --unset-env=OBS_PLUGINS_PATH \
    --unset-env=OBS_PLUGINS_DATA_PATH \
    "$APP_ID" >/dev/null 2>&1 || true
}

apply_ld_library_path_override() {
  local existing_ld
  local new_ld

  existing_ld="$(get_existing_override_env LD_LIBRARY_PATH || true)"
  new_ld="$(join_unique_colon "$existing_ld" "${LOCALVOCAL_LD_PATHS[@]}")"

  log "Applying LD_LIBRARY_PATH so copied plugin can find LocalVocal libraries..."

  "${OVERRIDE_CMD[@]}" \
    --env="LD_LIBRARY_PATH=${new_ld}" \
    "$APP_ID"
}

install_user_plugin_shim() {
  log "Installing LocalVocal into OBS Flatpak user plugin folder..."

  flatpak run --command=sh "$APP_ID" -s <<'SANDBOX_SCRIPT'
set -eu

PLUGIN_NAME="obs-localvocal"

EXT_ROOT="/app/plugins/LocalVocal"
SOURCE_SO="${EXT_ROOT}/lib64/obs-plugins/${PLUGIN_NAME}.so"
SOURCE_BIN_EXTRA="${EXT_ROOT}/lib64/obs-plugins/${PLUGIN_NAME}"
SOURCE_DATA="${EXT_ROOT}/share/obs/obs-plugins/${PLUGIN_NAME}"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DEST_ROOT="${CONFIG_HOME}/obs-studio/plugins/${PLUGIN_NAME}"
DEST_BIN="${DEST_ROOT}/bin/64bit"
DEST_DATA="${DEST_ROOT}/data"

timestamp="$(date +%Y%m%d-%H%M%S)"

echo "[SANDBOX] XDG_CONFIG_HOME=${CONFIG_HOME}"

if [ ! -f "$SOURCE_SO" ]; then
  echo "[SANDBOX][ERROR] Missing plugin binary: $SOURCE_SO" >&2
  exit 20
fi

if [ ! -d "$SOURCE_DATA" ]; then
  echo "[SANDBOX][ERROR] Missing plugin data directory: $SOURCE_DATA" >&2
  exit 21
fi

if [ -d "$DEST_ROOT" ]; then
  backup="${DEST_ROOT}.backup-${timestamp}"
  echo "[SANDBOX] Existing LocalVocal user plugin found. Moving it to: $backup"
  mv "$DEST_ROOT" "$backup"
fi

mkdir -p "$DEST_BIN" "$DEST_DATA"

cp -a "$SOURCE_SO" "$DEST_BIN/"

if [ -d "$SOURCE_BIN_EXTRA" ]; then
  cp -a "$SOURCE_BIN_EXTRA" "$DEST_BIN/"
fi

cp -a "$SOURCE_DATA/." "$DEST_DATA/"

chmod -R u+rwX "$DEST_ROOT"

echo "[SANDBOX] Installed:"
echo "[SANDBOX]   ${DEST_BIN}/${PLUGIN_NAME}.so"
echo "[SANDBOX]   ${DEST_DATA}"
SANDBOX_SCRIPT
}

verify_user_plugin_shim() {
  log "Verifying OBS user plugin layout..."

  flatpak run --command=sh "$APP_ID" -c '
    CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    PLUGIN_ROOT="${CONFIG_HOME}/obs-studio/plugins/obs-localvocal"

    test -f "${PLUGIN_ROOT}/bin/64bit/obs-localvocal.so"
    test -d "${PLUGIN_ROOT}/data"

    echo "OK: ${PLUGIN_ROOT}/bin/64bit/obs-localvocal.so"
    echo "OK: ${PLUGIN_ROOT}/data"
  '
}

print_next_steps() {
  cat <<EOF

Done.

Now start OBS from the terminal:

  flatpak run $APP_ID

Then check:

  Audio Mixer → Mic/Aux → Filters → + menu

You should look for:

  LocalVocal Transcription

If it still does not appear, close OBS and run:

  latest_log="\$(ls -t ~/.var/app/com.obsproject.Studio/config/obs-studio/logs/*.txt | head -n1)"
  grep -iE 'localvocal|obs-localvocal|module.*not loaded|loading module|failed|error|undefined|symbol' "\$latest_log"

Important: after this fix, the log should mention obs-localvocal.so. If it still only mentions
com.obsproject.Studio.Plugin.LocalVocal, OBS is still not reaching the plugin binary.

Backup of previous Flatpak overrides:

  $BACKUP_FILE

EOF
}

main() {
  if [[ "${EUID}" -eq 0 ]]; then
    die "Do not run this script as root. Run it as your normal desktop user."
  fi

  require_command flatpak
  require_command awk
  require_command date
  require_command mkdir

  detect_flatpak_scope

  log "Closing OBS if it is running..."
  flatpak kill "$APP_ID" >/dev/null 2>&1 || true

  backup_overrides
  verify_extension_is_mounted
  clear_bad_obs_plugin_path_overrides
  apply_ld_library_path_override
  install_user_plugin_shim
  verify_user_plugin_shim
  print_next_steps
}

main "$@"
