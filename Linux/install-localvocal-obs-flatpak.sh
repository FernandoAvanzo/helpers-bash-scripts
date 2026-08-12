#!/usr/bin/env bash
# install-localvocal-obs-flatpak.sh
#
# Defensive LocalVocal installer/reinstaller for OBS Studio installed as Flatpak.
# Target: Pop!_OS / Ubuntu-like systems, but most Flatpak parts are distro-agnostic.
#
# What this script does:
#   - Checks OBS Flatpak health before touching the plugin.
#   - Detects an existing user/system LocalVocal Flatpak extension.
#   - If the user plugin is already present and OBS starts, exits unless --force-reinstall is used.
#   - Backs up OBS Flatpak configuration and exports the existing user plugin as a rollback bundle when possible.
#   - Builds LocalVocal as a Flatpak extension.
#   - Removes only the user-level LocalVocal extension immediately before reinstalling.
#   - Verifies OBS still starts after installation.
#   - Rolls back the user-level plugin on failure.
#
# Safety choices:
#   - Does NOT remove system-wide OBS or system-wide LocalVocal.
#   - Does NOT run as root; uses sudo only for apt prerequisites.
#   - Installs LocalVocal as a user Flatpak extension.
#   - Stops if OBS appears to be running.
#
# Usage:
#   bash install-localvocal-obs-flatpak.sh
#   bash install-localvocal-obs-flatpak.sh --force-reinstall --yes
#   bash install-localvocal-obs-flatpak.sh --acceleration generic --force-reinstall
#   bash install-localvocal-obs-flatpak.sh --acceleration nvidia --force-reinstall
#   bash install-localvocal-obs-flatpak.sh --rollback-only /path/to/backup-directory
#
# Notes:
#   - "Working" can only be partially verified without GUI automation. This script verifies
#     OBS Flatpak startup/version and plugin Flatpak extension installation, not the visual
#     presence of the LocalVocal filter inside the OBS GUI.

set -Eeuo pipefail
IFS=$'\n\t'

readonly OBS_ID="com.obsproject.Studio"
readonly PLUGIN_ID="com.obsproject.Studio.Plugin.LocalVocal"
readonly SDK_REF="org.kde.Sdk//6.8"
readonly DEFAULT_REPO_URL="https://github.com/locaal-ai/obs-localvocal.git"

ACCELERATION="generic"
ASSUME_YES=0
FORCE_REINSTALL=0
SKIP_APT=0
INSTALL_OBS_IF_MISSING=0
KEEP_BUILD=0
ROLLBACK_ONLY=""
REPO_URL="$DEFAULT_REPO_URL"
BRANCH="master"
WORKROOT="${XDG_CACHE_HOME:-$HOME/.cache}/localvocal-obs-installer"
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/localvocal-obs-installer/backups"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
WORKDIR=""
LOGFILE=""
BACKUP_DIR=""
OBS_CONFIG_BACKUP=""
PLUGIN_BUNDLE_BACKUP=""
HAD_USER_PLUGIN=0
HAD_SYSTEM_PLUGIN=0
CHANGED_PLUGIN=0
NEW_USER_PLUGIN_INSTALLED=0
ERROR_ROLLBACK_DONE=0

usage() {
  cat <<'EOF'
Usage:
  install-localvocal-obs-flatpak.sh [options]

Options:
  --acceleration generic|nvidia|amd
      Select LocalVocal build acceleration backend. Default: generic.

  --force-reinstall
      Rebuild and reinstall even if LocalVocal appears already installed.

  --yes
      Non-interactive mode. Assumes yes for safe prompts.

  --skip-apt
      Do not install apt prerequisites automatically.

  --install-obs-if-missing
      If OBS Flatpak is missing, install it from Flathub. Without this, the script stops.

  --workroot PATH
      Build/work directory root. Default: ~/.cache/localvocal-obs-installer

  --backup-root PATH
      Backup directory root. Default: ~/.local/state/localvocal-obs-installer/backups

  --repo-url URL
      LocalVocal git repository URL. Default: https://github.com/locaal-ai/obs-localvocal.git

  --branch BRANCH
      Git branch/tag to clone. Default: master

  --keep-build
      Keep build directory after success.

  --rollback-only BACKUP_DIR
      Try to restore a previous user-level plugin backup bundle from BACKUP_DIR.

  -h, --help
      Show help.

Examples:
  bash install-localvocal-obs-flatpak.sh --force-reinstall
  bash install-localvocal-obs-flatpak.sh --acceleration nvidia --force-reinstall --yes
EOF
}

log() {
  local msg="$*"
  printf '[%s] %s\n' "$(date '+%F %T')" "$msg" | tee -a "${LOGFILE:-/dev/null}" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

confirm() {
  local prompt="$1"
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    log "Auto-confirmed: $prompt"
    return 0
  fi
  local ans
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" || "$ans" == "yes" || "$ans" == "YES" ]]
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run() {
  log "+ $*"
  "$@"
}

run_quiet() {
  "$@" >/dev/null 2>&1
}

flatpak_info_user() {
  flatpak info --user "$1" >/dev/null 2>&1
}

flatpak_info_system() {
  flatpak info --system "$1" >/dev/null 2>&1
}

flatpak_info_any() {
  flatpak info "$1" >/dev/null 2>&1
}

obs_flatpak_version() {
  flatpak run --command=obs "$OBS_ID" --version
}

obs_health_check() {
  log "Checking OBS Flatpak startup/version..."
  local out
  if ! out="$(obs_flatpak_version 2>&1)"; then
    log "$out"
    return 1
  fi
  log "OBS responds: $out"
}

plugin_user_installed() {
  flatpak_info_user "$PLUGIN_ID"
}

plugin_system_installed() {
  flatpak_info_system "$PLUGIN_ID"
}

plugin_any_installed() {
  flatpak_info_any "$PLUGIN_ID"
}

plugin_health_check() {
  if plugin_user_installed; then
    log "LocalVocal is installed as a user Flatpak extension."
    return 0
  fi
  if plugin_system_installed; then
    log "LocalVocal is installed as a system Flatpak extension."
    return 0
  fi
  return 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --acceleration)
        [[ $# -ge 2 ]] || die "--acceleration requires a value"
        ACCELERATION="$2"
        shift 2
        ;;
      --force-reinstall)
        FORCE_REINSTALL=1
        shift
        ;;
      --yes)
        ASSUME_YES=1
        shift
        ;;
      --skip-apt)
        SKIP_APT=1
        shift
        ;;
      --install-obs-if-missing)
        INSTALL_OBS_IF_MISSING=1
        shift
        ;;
      --workroot)
        [[ $# -ge 2 ]] || die "--workroot requires a path"
        WORKROOT="$2"
        shift 2
        ;;
      --backup-root)
        [[ $# -ge 2 ]] || die "--backup-root requires a path"
        BACKUP_ROOT="$2"
        shift 2
        ;;
      --repo-url)
        [[ $# -ge 2 ]] || die "--repo-url requires a URL"
        REPO_URL="$2"
        shift 2
        ;;
      --branch)
        [[ $# -ge 2 ]] || die "--branch requires a branch/tag"
        BRANCH="$2"
        shift 2
        ;;
      --keep-build)
        KEEP_BUILD=1
        shift
        ;;
      --rollback-only)
        [[ $# -ge 2 ]] || die "--rollback-only requires a backup directory"
        ROLLBACK_ONLY="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  case "$ACCELERATION" in
    generic|nvidia|amd) ;;
    *) die "--acceleration must be one of: generic, nvidia, amd" ;;
  esac
}

init_paths() {
  WORKDIR="$WORKROOT/run-$RUN_ID"
  BACKUP_DIR="$BACKUP_ROOT/run-$RUN_ID"
  mkdir -p "$WORKDIR" "$BACKUP_DIR"
  LOGFILE="$BACKUP_DIR/install.log"
  touch "$LOGFILE"
  log "Log file: $LOGFILE"
  log "Backup directory: $BACKUP_DIR"
}

cleanup_on_exit() {
  local rc=$?
  if [[ $rc -eq 0 && "$KEEP_BUILD" -eq 0 && -n "${WORKDIR:-}" && -d "${WORKDIR:-}" ]]; then
    rm -rf "$WORKDIR" || true
  fi
}

rollback() {
  if [[ "$ERROR_ROLLBACK_DONE" -eq 1 ]]; then
    return 0
  fi
  ERROR_ROLLBACK_DONE=1

  log "Starting rollback..."

  # If we installed a new user plugin and there was no previous user plugin backup, remove it.
  if [[ "$NEW_USER_PLUGIN_INSTALLED" -eq 1 && ! -s "${PLUGIN_BUNDLE_BACKUP:-}" ]]; then
    log "Removing newly installed user-level LocalVocal extension..."
    flatpak uninstall --user -y "$PLUGIN_ID" >>"$LOGFILE" 2>&1 || true
  fi

  # If a previous user-level plugin bundle exists, reinstall it.
  if [[ -s "${PLUGIN_BUNDLE_BACKUP:-}" ]]; then
    log "Restoring previous user-level LocalVocal extension from bundle..."
    flatpak install --user -y "$PLUGIN_BUNDLE_BACKUP" >>"$LOGFILE" 2>&1 || \
      log "WARNING: Could not reinstall plugin backup bundle. See log: $LOGFILE"
  fi

  # OBS config is not normally modified by this script. Keep the backup available
  # instead of overwriting the user's config automatically.
  if [[ -s "${OBS_CONFIG_BACKUP:-}" ]]; then
    log "OBS config backup preserved at: $OBS_CONFIG_BACKUP"
    log "Not restoring OBS config automatically because this script does not edit it."
  fi

  log "Rollback finished. Check OBS with: flatpak run $OBS_ID"
}

on_error() {
  local line="$1"
  log "Failure at line $line."
  if [[ "$CHANGED_PLUGIN" -eq 1 || "$NEW_USER_PLUGIN_INSTALLED" -eq 1 ]]; then
    rollback
  else
    log "No plugin change was made; rollback not needed."
  fi
  exit 1
}

manual_rollback_only() {
  local dir="$1"
  [[ -d "$dir" ]] || die "Backup directory not found: $dir"

  LOGFILE="$dir/rollback-$(date +%Y%m%d-%H%M%S).log"
  PLUGIN_BUNDLE_BACKUP="$(find "$dir" -maxdepth 1 -name "${PLUGIN_ID}.previous."*.flatpak -type f | sort | tail -n 1 || true)"
  OBS_CONFIG_BACKUP="$(find "$dir" -maxdepth 1 -name "obs-config."*.tar.gz -type f | sort | tail -n 1 || true)"

  [[ -n "$PLUGIN_BUNDLE_BACKUP" && -s "$PLUGIN_BUNDLE_BACKUP" ]] || \
    die "No previous plugin bundle found in $dir"

  if ! confirm "Restore previous user-level LocalVocal plugin from $PLUGIN_BUNDLE_BACKUP?"; then
    die "Rollback cancelled by user."
  fi

  run flatpak install --user -y "$PLUGIN_BUNDLE_BACKUP"
  log "Rollback plugin restore complete."
  if [[ -n "$OBS_CONFIG_BACKUP" ]]; then
    log "OBS config backup is available, but not automatically restored: $OBS_CONFIG_BACKUP"
  fi
}

preflight() {
  [[ "${BASH_VERSINFO[0]}" -ge 4 ]] || die "Bash 4+ is required."
  [[ "$(id -u)" -ne 0 ]] || die "Do not run this script as root. Run as your normal desktop user."

  case "$(uname -s)" in
    Linux) ;;
    *) die "This script is for Linux only." ;;
  esac

  if pgrep -u "$USER" -f "com\.obsproject\.Studio|(^|/)obs([[:space:]]|$)" >/dev/null 2>&1; then
    die "OBS appears to be running. Close OBS before installing/reinstalling plugins."
  fi

  if [[ -e "/run/user/$(id -u)/flatpak-info" ]]; then
    die "Do not run this script from inside a Flatpak sandbox. Run it from your host terminal."
  fi

  local need_space_kb=$((8 * 1024 * 1024))
  local avail_kb
  avail_kb="$(df -Pk "$WORKROOT" 2>/dev/null | awk 'NR==2 {print $4}')"
  if [[ -n "$avail_kb" && "$avail_kb" -lt "$need_space_kb" ]]; then
    die "Less than 8 GiB free under $WORKROOT. Free space or use --workroot on a larger filesystem."
  fi

  if ! have_cmd git || ! have_cmd flatpak || ! have_cmd flatpak-builder; then
    if [[ "$SKIP_APT" -eq 1 ]]; then
      die "Missing required commands. Install git flatpak flatpak-builder or rerun without --skip-apt."
    fi
    if have_cmd apt; then
      if confirm "Install missing prerequisites with apt: git flatpak flatpak-builder?"; then
        run sudo apt update
        run sudo apt install -y git flatpak flatpak-builder ca-certificates
      else
        die "Prerequisite installation cancelled."
      fi
    else
      die "Missing git/flatpak/flatpak-builder and apt was not found. Install them manually."
    fi
  fi

  have_cmd git || die "git still not found."
  have_cmd flatpak || die "flatpak still not found."
  have_cmd flatpak-builder || die "flatpak-builder still not found."
}

ensure_flatpak_basics() {
  log "Ensuring Flathub remote exists..."
  run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

  if ! flatpak_info_any "$OBS_ID"; then
    if [[ "$INSTALL_OBS_IF_MISSING" -eq 1 ]] || confirm "OBS Flatpak is missing. Install OBS Flatpak from Flathub?"; then
      run flatpak install --user -y flathub "$OBS_ID"
    else
      die "OBS Flatpak is required and was not installed."
    fi
  fi

  obs_health_check || die "OBS Flatpak did not pass startup/version check before plugin changes."

  log "Ensuring KDE SDK required by LocalVocal Flatpak build exists..."
  run flatpak install --user -y flathub "$SDK_REF"
}

save_state() {
  log "Saving current Flatpak and OBS state..."
  flatpak list --columns=application,branch,installation >"$BACKUP_DIR/flatpak-list.before.txt" || true
  flatpak info "$OBS_ID" >"$BACKUP_DIR/obs-flatpak-info.before.txt" 2>&1 || true

  if plugin_user_installed; then
    HAD_USER_PLUGIN=1
    flatpak info --user "$PLUGIN_ID" >"$BACKUP_DIR/localvocal-user-info.before.txt" 2>&1 || true

    local branch
    branch="$(flatpak info --user --show-branch "$PLUGIN_ID" 2>/dev/null || printf 'stable')"
    PLUGIN_BUNDLE_BACKUP="$BACKUP_DIR/${PLUGIN_ID}.previous.${branch}.flatpak"

    log "Exporting existing user-level LocalVocal extension for rollback..."
    if flatpak build-bundle "$HOME/.local/share/flatpak/repo" "$PLUGIN_BUNDLE_BACKUP" "$PLUGIN_ID" "$branch" >>"$LOGFILE" 2>&1; then
      log "Plugin rollback bundle: $PLUGIN_BUNDLE_BACKUP"
    else
      log "WARNING: Could not export user plugin bundle. Rollback can remove new plugin, but may not restore old plugin automatically."
      rm -f "$PLUGIN_BUNDLE_BACKUP" || true
    fi
  fi

  if plugin_system_installed; then
    HAD_SYSTEM_PLUGIN=1
    flatpak info --system "$PLUGIN_ID" >"$BACKUP_DIR/localvocal-system-info.before.txt" 2>&1 || true
    log "Detected system-level LocalVocal extension. It will not be removed."
  fi

  local obs_config="${HOME}/.var/app/${OBS_ID}/config/obs-studio"
  if [[ -d "$obs_config" ]]; then
    OBS_CONFIG_BACKUP="$BACKUP_DIR/obs-config.${RUN_ID}.tar.gz"
    log "Backing up OBS Flatpak config..."
    tar -C "$(dirname "$obs_config")" -czf "$OBS_CONFIG_BACKUP" "$(basename "$obs_config")"
    log "OBS config backup: $OBS_CONFIG_BACKUP"
  else
    log "OBS Flatpak config directory not found yet: $obs_config"
  fi
}

already_healthy_decision() {
  if plugin_health_check && obs_health_check; then
    if [[ "$FORCE_REINSTALL" -eq 0 ]]; then
      log "LocalVocal appears installed and OBS starts correctly."
      log "No reinstall performed. Use --force-reinstall if you want to rebuild/reinstall."
      exit 0
    fi
    log "--force-reinstall was provided; continuing with reinstall."
  else
    log "LocalVocal is missing or not verifiably installed; continuing with installation."
  fi
}

clone_repo() {
  log "Cloning LocalVocal repository..."
  local src="$WORKDIR/obs-localvocal"
  run git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$src"
  [[ -x "$src/flatpak/build.sh" ]] || die "LocalVocal flatpak/build.sh not found or not executable."
  [[ -f "$src/flatpak/com.obsproject.Studio.Plugin.LocalVocal.yaml" ]] || die "LocalVocal Flatpak manifest not found."
  printf '%s\n' "$src"
}

build_plugin() {
  local src="$1"
  log "Building LocalVocal Flatpak extension with ACCELERATION=$ACCELERATION..."
  (
    cd "$src"
    export ACCELERATION
    ./flatpak/build.sh --disable-rofiles-fuse --force-clean build-dir ./flatpak/com.obsproject.Studio.Plugin.LocalVocal.yaml
  ) >>"$LOGFILE" 2>&1
  log "Build completed."
}

remove_existing_user_plugin_if_present() {
  if plugin_user_installed; then
    log "Removing existing user-level LocalVocal extension before reinstall..."
    CHANGED_PLUGIN=1
    run flatpak uninstall --user -y "$PLUGIN_ID"
  else
    log "No user-level LocalVocal extension to remove."
  fi
}

install_plugin() {
  local src="$1"
  log "Installing LocalVocal Flatpak extension as user..."
  CHANGED_PLUGIN=1
  (
    cd "$src"
    export ACCELERATION
    ./flatpak/build.sh --disable-rofiles-fuse --install build-dir ./flatpak/com.obsproject.Studio.Plugin.LocalVocal.yaml
  ) >>"$LOGFILE" 2>&1
  NEW_USER_PLUGIN_INSTALLED=1
  log "Install command completed."
}

verify_after_install() {
  log "Verifying LocalVocal Flatpak extension is installed..."
  if ! plugin_user_installed; then
    flatpak list --columns=application,branch,installation | tee -a "$LOGFILE" >&2 || true
    die "LocalVocal user extension is not visible to Flatpak after install."
  fi

  flatpak info --user "$PLUGIN_ID" >"$BACKUP_DIR/localvocal-user-info.after.txt" 2>&1 || true
  flatpak list --columns=application,branch,installation >"$BACKUP_DIR/flatpak-list.after.txt" || true

  obs_health_check || die "OBS did not pass startup/version check after LocalVocal install."

  log "Installation verified."
}

main() {
  parse_args "$@"

  if [[ -n "$ROLLBACK_ONLY" ]]; then
    manual_rollback_only "$ROLLBACK_ONLY"
    exit 0
  fi

  init_paths
  trap cleanup_on_exit EXIT
  trap 'on_error "$LINENO"' ERR

  log "Starting LocalVocal installer for OBS Flatpak."
  log "Acceleration: $ACCELERATION"
  log "Repository: $REPO_URL"
  log "Branch/tag: $BRANCH"

  preflight
  ensure_flatpak_basics
  save_state
  already_healthy_decision

  if [[ "$FORCE_REINSTALL" -eq 1 ]]; then
    if ! confirm "Proceed with rebuilding and reinstalling the user-level LocalVocal Flatpak extension?"; then
      die "Cancelled by user."
    fi
  fi

  src="$(clone_repo)"
  build_plugin "$src"
  remove_existing_user_plugin_if_present
  install_plugin "$src"
  verify_after_install

  log "SUCCESS: LocalVocal is installed for OBS Flatpak."
  log "Open OBS, right-click your audio source, choose Filters, then add the LocalVocal transcription filter."
  log "Backups/logs kept at: $BACKUP_DIR"
}

main "$@"
