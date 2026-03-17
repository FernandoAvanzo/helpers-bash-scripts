#!/usr/bin/env bash
# install_unity_popos_lts_v2.sh
#
# Installs Unity Hub on Pop!_OS / Ubuntu-like systems, then installs:
#   - latest Unity 6 LTS patch advertised by Unity Hub for branch 6000.3
#   - latest Unity 2022 LTS patch advertised by Unity Hub for branch 2022.3
#   - Android Build Support (+ SDK/NDK + OpenJDK)
#   - WebGL Build Support
#   - Linux Build Support (IL2CPP)
#
# Why this version of the script exists:
#   Unity Hub CLI installs versions from its known release list. If an exact
#   hard-coded version is not present in that list, Hub can fail with:
#     "Provided editor version does not match to any known Unity Editor versions."
#   Unity's docs say a changeset can be required when the version is not in the
#   release list, and they recommend checking the release list with:
#     unityhub --headless editors -r
#
# This script fixes that by:
#   1) asking Unity Hub for the available releases,
#   2) resolving the latest version for the requested LTS branches, and
#   3) only using an exact version directly when Hub already knows it, or when
#      you also provide a matching changeset.
#
# Usage examples:
#   sudo ./install_unity_popos_lts_v2.sh
#   sudo ./install_unity_popos_lts_v2.sh --hub-only
#   sudo ./install_unity_popos_lts_v2.sh --list-releases
#   sudo ./install_unity_popos_lts_v2.sh --unity6-branch 6000.3 --unity2022-branch 2022.3
#   sudo ./install_unity_popos_lts_v2.sh --unity6-version 6000.3.10f1 --unity6-changeset e35f0c77bd8e
#   sudo ./install_unity_popos_lts_v2.sh --no-2022
#
# After install, sign in to Unity Hub once as the target user.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly SCRIPT_NAME="${0##*/}"
readonly DEFAULT_UNITY6_BRANCH="6000.3"
readonly DEFAULT_UNITY2022_BRANCH="2022.3"
readonly DEFAULT_MODULES_CSV="android,android-sdk-ndk-tools,android-open-jdk,webgl,linux-il2cpp"

INSTALL_HUB_ONLY=0
LIST_RELEASES_ONLY=0
INSTALL_UNITY6=1
INSTALL_UNITY2022=1

UNITY6_BRANCH="${DEFAULT_UNITY6_BRANCH}"
UNITY2022_BRANCH="${DEFAULT_UNITY2022_BRANCH}"
UNITY6_VERSION=""
UNITY2022_VERSION=""
UNITY6_CHANGESET=""
UNITY2022_CHANGESET=""
MODULES_CSV="${DEFAULT_MODULES_CSV}"

TARGET_USER="${SUDO_USER:-${USER:-}}"
TARGET_UID=""
TARGET_GROUP=""
TARGET_HOME=""
TARGET_RUNTIME_DIR=""
TARGET_DBUS_ADDRESS=""
EDITOR_INSTALL_PATH=""
NONINTERACTIVE_APT=1
HUB_CLI_STYLE=""

RESOLVED_UNITY6_VERSION=""
RESOLVED_UNITY2022_VERSION=""

log()  { printf '[INFO] %s\n' "$*" >&2; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

on_error() {
  local exit_code=$?
  err "Command failed (exit ${exit_code}) at line ${BASH_LINENO[0]}: ${BASH_COMMAND}"
  exit "${exit_code}"
}
trap on_error ERR

usage() {
  cat <<'EOF'
Usage:
  sudo ./install_unity_popos_lts_v2.sh [options]

Options:
  --hub-only                     Install/update Unity Hub only.
  --list-releases                Print versions visible to the Unity Hub CLI and exit.
  --no-unity6                    Skip Unity 6 LTS installation.
  --no-2022                      Skip Unity 2022 LTS installation.

  --unity6-branch BRANCH         Unity 6 branch selector. Default: 6000.3
  --unity2022-branch BRANCH      Unity 2022 branch selector. Default: 2022.3

  --unity6-version VERSION       Exact Unity 6 version to install.
  --unity2022-version VERSION    Exact Unity 2022 version to install.

  --unity6-changeset CHANGESET   Optional changeset for exact Unity 6 version.
  --unity2022-changeset CHANGESET
                                 Optional changeset for exact Unity 2022 version.

  --modules CSV                  Comma-separated module IDs.
                                 Default:
                                 android,android-sdk-ndk-tools,android-open-jdk,webgl,linux-il2cpp

  --editor-path PATH             Editor install path for the target user.
                                 Default: TARGET_HOME/Unity/Hub/Editor
  --user USERNAME                User that should own the Hub config and editor installs.
                                 Default: SUDO_USER (or current user if not using sudo)
  --interactive-apt              Do not force DEBIAN_FRONTEND=noninteractive.
  -h, --help                     Show this help.

Examples:
  sudo ./install_unity_popos_lts_v2.sh
  sudo ./install_unity_popos_lts_v2.sh --list-releases
  sudo ./install_unity_popos_lts_v2.sh --no-2022
  sudo ./install_unity_popos_lts_v2.sh --unity6-version 6000.3.10f1 --unity6-changeset e35f0c77bd8e
  sudo ./install_unity_popos_lts_v2.sh --unity2022-version 2022.3.62f1 --unity2022-changeset 4af31df58517
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run this script with sudo or as root."
  fi
}

append_if_available() {
  local pkg="$1"
  if apt-cache show "${pkg}" >/dev/null 2>&1; then
    printf '%s\n' "${pkg}"
  fi
}

resolve_target_user() {
  [[ -n "${TARGET_USER}" ]] || die "Unable to determine target user. Use --user USERNAME."
  getent passwd "${TARGET_USER}" >/dev/null 2>&1 || die "User does not exist: ${TARGET_USER}"

  TARGET_UID="$(id -u "${TARGET_USER}")"
  TARGET_GROUP="$(id -gn "${TARGET_USER}")"
  TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  TARGET_RUNTIME_DIR="/run/user/${TARGET_UID}"

  [[ -d "${TARGET_HOME}" ]] || die "Target user home directory not found: ${TARGET_HOME}"

  if [[ -z "${EDITOR_INSTALL_PATH}" ]]; then
    EDITOR_INSTALL_PATH="${TARGET_HOME}/Unity/Hub/Editor"
  fi

  if [[ -S "${TARGET_RUNTIME_DIR}/bus" ]]; then
    TARGET_DBUS_ADDRESS="unix:path=${TARGET_RUNTIME_DIR}/bus"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hub-only)
        INSTALL_HUB_ONLY=1
        shift
        ;;
      --list-releases)
        LIST_RELEASES_ONLY=1
        shift
        ;;
      --no-unity6)
        INSTALL_UNITY6=0
        shift
        ;;
      --no-2022)
        INSTALL_UNITY2022=0
        shift
        ;;
      --unity6-branch)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        UNITY6_BRANCH="$2"
        shift 2
        ;;
      --unity2022-branch)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        UNITY2022_BRANCH="$2"
        shift 2
        ;;
      --unity6-version)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        UNITY6_VERSION="$2"
        shift 2
        ;;
      --unity2022-version)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        UNITY2022_VERSION="$2"
        shift 2
        ;;
      --unity6-changeset)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        UNITY6_CHANGESET="$2"
        shift 2
        ;;
      --unity2022-changeset)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        UNITY2022_CHANGESET="$2"
        shift 2
        ;;
      --modules)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        MODULES_CSV="$2"
        shift 2
        ;;
      --editor-path)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        EDITOR_INSTALL_PATH="$2"
        shift 2
        ;;
      --user)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        TARGET_USER="$2"
        shift 2
        ;;
      --interactive-apt)
        NONINTERACTIVE_APT=0
        shift
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

  if (( INSTALL_HUB_ONLY == 0 )) && (( INSTALL_UNITY6 == 0 )) && (( INSTALL_UNITY2022 == 0 )); then
    warn "Both editor installs were disabled; switching to Hub-only mode."
    INSTALL_HUB_ONLY=1
  fi
}

detect_os() {
  [[ -r /etc/os-release ]] || die "/etc/os-release not found."
  . /etc/os-release

  local pretty_name="${PRETTY_NAME:-unknown}"
  local distro_id="${ID:-unknown}"
  local distro_like="${ID_LIKE:-}"

  log "Detected OS: ${pretty_name}"

  case "$(dpkg --print-architecture)" in
    amd64) ;;
    *)
      die "Unity Hub's official Debian repository is x86_64/amd64 only."
      ;;
  esac

  if [[ "${distro_id}" != "ubuntu" && "${distro_id}" != "pop" && "${distro_like}" != *"ubuntu"* && "${distro_like}" != *"debian"* ]]; then
    warn "This script targets Pop!_OS / Ubuntu-like systems. Continuing on an untested distro."
  fi

  if [[ "${distro_id}" == "pop" ]]; then
    warn "Pop!_OS is Ubuntu-based and often works, but Unity Hub support on Pop!_OS is best-effort."
  fi

  if [[ "${XDG_CURRENT_DESKTOP:-}" == *"COSMIC"* ]]; then
    warn "Detected COSMIC session. Unity's Linux docs explicitly list Ubuntu + GNOME as the supported Linux desktop environment."
  fi
}

apt_env() {
  if (( NONINTERACTIVE_APT == 1 )); then
    export DEBIAN_FRONTEND=noninteractive
  fi
}

install_system_prereqs() {
  log "Installing base packages..."
  apt-get update -y

  local -a pkgs=(
    ca-certificates
    curl
    gnupg
    dbus-user-session
    xdg-utils
    gsettings-desktop-schemas
    dconf-gsettings-backend
    libgtk-3-0
    libnss3
    libnotify4
    libxss1
    libgbm1
  )

  local asound_pkg=""
  asound_pkg="$(append_if_available libasound2t64 || true)"
  if [[ -z "${asound_pkg}" ]]; then
    asound_pkg="$(append_if_available libasound2 || true)"
  fi
  if [[ -n "${asound_pkg}" ]]; then
    pkgs+=("${asound_pkg}")
  fi

  apt-get install -y --no-install-recommends "${pkgs[@]}"
}

configure_unity_hub_repo() {
  log "Configuring the official Unity Hub apt repository..."
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL "https://hub.unity3d.com/linux/keys/public" \
    | gpg --dearmor \
    | tee /etc/apt/keyrings/unityhub.gpg >/dev/null
  chmod 0644 /etc/apt/keyrings/unityhub.gpg

  cat >/etc/apt/sources.list.d/unityhub.list <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/unityhub.gpg] https://hub.unity3d.com/linux/repos/deb stable main
EOF
}

install_unity_hub_package() {
  log "Installing or updating Unity Hub..."
  apt-get update -y
  apt-get install -y unityhub
}

find_hub_binary() {
  local candidates=(
    "${TARGET_HOME}/Applications/Unity Hub.AppImage"
    "/usr/bin/unityhub"
    "/usr/bin/unity-hub"
    "/opt/unityhub/unityhub"
    "/opt/UnityHub/unityhub"
  )
  local candidate=""
  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  if command -v unityhub >/dev/null 2>&1; then
    command -v unityhub
    return 0
  fi

  if dpkg -L unityhub >/dev/null 2>&1; then
    candidate="$(dpkg -L unityhub | awk '/\/unityhub$/ {print; exit}')"
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  return 1
}

build_env_for_target_user() {
  local -a env_vars=(
    "HOME=${TARGET_HOME}"
    "USER=${TARGET_USER}"
    "LOGNAME=${TARGET_USER}"
    "XDG_CONFIG_HOME=${TARGET_HOME}/.config"
    "XDG_DATA_HOME=${TARGET_HOME}/.local/share"
    "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  )

  if [[ -d "${TARGET_RUNTIME_DIR}" ]]; then
    env_vars+=("XDG_RUNTIME_DIR=${TARGET_RUNTIME_DIR}")
  fi

  if [[ -n "${TARGET_DBUS_ADDRESS}" ]]; then
    env_vars+=("DBUS_SESSION_BUS_ADDRESS=${TARGET_DBUS_ADDRESS}")
  fi

  if [[ -n "${DISPLAY:-}" ]]; then
    env_vars+=("DISPLAY=${DISPLAY}")
  fi

  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    env_vars+=("WAYLAND_DISPLAY=${WAYLAND_DISPLAY}")
  fi

  if [[ -n "${XAUTHORITY:-}" ]]; then
    env_vars+=("XAUTHORITY=${XAUTHORITY}")
  fi

  if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
    env_vars+=("XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP}")
  fi

  if [[ -n "${DESKTOP_SESSION:-}" ]]; then
    env_vars+=("DESKTOP_SESSION=${DESKTOP_SESSION}")
  fi

  printf '%s\0' "${env_vars[@]}"
}

run_as_target_user() {
  local cmd=("$@")
  local -a env_vars=()
  mapfile -d '' -t env_vars < <(build_env_for_target_user)

  sudo -u "${TARGET_USER}" -H env "${env_vars[@]}" "${cmd[@]}"
}

detect_hub_cli_style() {
  local hub_bin="$1"

  if run_as_target_user "${hub_bin}" --headless help >/dev/null 2>&1; then
    HUB_CLI_STYLE="single-dashdash"
    return 0
  fi

  if run_as_target_user "${hub_bin}" -- --headless help >/dev/null 2>&1; then
    HUB_CLI_STYLE="double-dashdash"
    return 0
  fi

  return 1
}

hub_cli() {
  local hub_bin="$1"
  shift

  case "${HUB_CLI_STYLE}" in
    single-dashdash)
      run_as_target_user "${hub_bin}" --headless "$@"
      ;;
    double-dashdash)
      run_as_target_user "${hub_bin}" -- --headless "$@"
      ;;
    *)
      die "Unity Hub CLI style is unknown. detect_hub_cli_style must run first."
      ;;
  esac
}

hub_cli_capture() {
  local hub_bin="$1"
  shift

  case "${HUB_CLI_STYLE}" in
    single-dashdash)
      run_as_target_user "${hub_bin}" --headless "$@" 2>&1
      ;;
    double-dashdash)
      run_as_target_user "${hub_bin}" -- --headless "$@" 2>&1
      ;;
    *)
      die "Unity Hub CLI style is unknown. detect_hub_cli_style must run first."
      ;;
  esac
}

prepare_target_user_dirs() {
  log "Preparing directories for ${TARGET_USER}..."
  install -d -m 0755 -o "${TARGET_USER}" -g "${TARGET_GROUP}" "${TARGET_HOME}/.local/bin"
  install -d -m 0755 -o "${TARGET_USER}" -g "${TARGET_GROUP}" "${TARGET_HOME}/.config"
  install -d -m 0755 -o "${TARGET_USER}" -g "${TARGET_GROUP}" "${TARGET_HOME}/.local/share"
  install -d -m 0755 -o "${TARGET_USER}" -g "${TARGET_GROUP}" "${EDITOR_INSTALL_PATH}"
}

csv_to_array() {
  local csv="$1"
  local -n out_ref="$2"
  local old_ifs="${IFS}"
  IFS=','
  out_ref=(${csv})
  IFS="${old_ifs}"

  local i
  for i in "${!out_ref[@]}"; do
    out_ref[$i]="$(printf '%s' "${out_ref[$i]}" | xargs)"
  done
}

list_release_versions() {
  local hub_bin="$1"
  local raw=""
  raw="$(hub_cli_capture "${hub_bin}" editors -r || true)"

  printf '%s\n' "${raw}" \
    | grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+[abcfp][0-9]+' \
    | awk '!seen[$0]++'
}

print_release_versions() {
  local hub_bin="$1"
  local -a versions=()
  mapfile -t versions < <(list_release_versions "${hub_bin}" | sort -V)

  if [[ "${#versions[@]}" -eq 0 ]]; then
    die "Unity Hub did not return any release versions. Check network access and Hub logs in ${TARGET_HOME}/.config/UnityHub/logs."
  fi

  printf 'Unity Hub visible releases:\n'
  printf '  %s\n' "${versions[@]}"
}

select_latest_version_for_branch() {
  local hub_bin="$1"
  local branch="$2"
  local escaped_branch
  escaped_branch="$(printf '%s' "${branch}" | sed 's/\./\\./g')"

  local -a matches=()
  mapfile -t matches < <(
    list_release_versions "${hub_bin}" \
      | grep -E "^${escaped_branch}\.[0-9]+[abcfp][0-9]+$" \
      | sort -V
  )

  if [[ "${#matches[@]}" -eq 0 ]]; then
    die "No Unity versions matching branch '${branch}' were visible to the Hub CLI. Run with --list-releases to inspect what Hub can currently install."
  fi

  printf '%s\n' "${matches[$((${#matches[@]} - 1))]}"
}

version_is_visible_to_hub() {
  local hub_bin="$1"
  local version="$2"

  if list_release_versions "${hub_bin}" | grep -Fxq "${version}"; then
    return 0
  fi
  return 1
}

show_nearby_versions_for_branch() {
  local hub_bin="$1"
  local branch="$2"
  local escaped_branch
  escaped_branch="$(printf '%s' "${branch}" | sed 's/\./\\./g')"

  list_release_versions "${hub_bin}" \
    | grep -E "^${escaped_branch}\.[0-9]+[abcfp][0-9]+$" \
    | sort -V || true
}

resolve_install_spec() {
  local hub_bin="$1"
  local branch="$2"
  local requested_version="$3"
  local requested_changeset="$4"
  local label="$5"

  local version=""
  local changeset=""

  if [[ -n "${requested_version}" ]]; then
    if version_is_visible_to_hub "${hub_bin}" "${requested_version}"; then
      version="${requested_version}"
      changeset=""
      log "${label}: exact version ${version} is visible to Hub."
    else
      if [[ -n "${requested_changeset}" ]]; then
        version="${requested_version}"
        changeset="${requested_changeset}"
        warn "${label}: exact version ${version} is not currently in Hub's visible release list; using supplied changeset ${changeset}."
      else
        err "${label}: exact version ${requested_version} is not currently visible to the Hub CLI."
        err "${label}: either provide a matching --changeset for that exact version, or let the script resolve the latest version from branch ${branch}."
        local nearby=""
        nearby="$(show_nearby_versions_for_branch "${hub_bin}" "${branch}" | tail -n 5 || true)"
        if [[ -n "${nearby}" ]]; then
          err "${label}: visible versions for branch ${branch}:"
          while IFS= read -r line; do
            [[ -n "${line}" ]] && err "  ${line}"
          done <<<"${nearby}"
        fi
        exit 1
      fi
    fi
  else
    version="$(select_latest_version_for_branch "${hub_bin}" "${branch}")"
    changeset=""
    log "${label}: resolved latest visible version for branch ${branch}: ${version}"
  fi

  printf '%s|%s\n' "${version}" "${changeset}"
}

install_editor_with_modules() {
  local hub_bin="$1"
  local version="$2"
  local changeset="$3"
  shift 3
  local -a modules=("$@")

  log "Setting Unity editor install path for ${TARGET_USER}: ${EDITOR_INSTALL_PATH}"
  hub_cli "${hub_bin}" install-path -s "${EDITOR_INSTALL_PATH}"

  log "Installing Unity Editor ${version} for ${TARGET_USER}..."
  if [[ -n "${changeset}" ]]; then
    if [[ "${#modules[@]}" -gt 0 ]]; then
      hub_cli "${hub_bin}" install --version "${version}" --changeset "${changeset}" --module "${modules[@]}"
    else
      hub_cli "${hub_bin}" install --version "${version}" --changeset "${changeset}"
    fi
  else
    if [[ "${#modules[@]}" -gt 0 ]]; then
      hub_cli "${hub_bin}" install --version "${version}" --module "${modules[@]}"
    else
      hub_cli "${hub_bin}" install --version "${version}"
    fi
  fi
}

create_launcher_wrapper() {
  local version="$1"
  local launcher_name="$2"
  local wrapper_path="${TARGET_HOME}/.local/bin/${launcher_name}"
  local editor_bin="${EDITOR_INSTALL_PATH}/${version}/Editor/Unity"

  cat >"${wrapper_path}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

EDITOR_BIN="${editor_bin}"

if [[ ! -x "\${EDITOR_BIN}" ]]; then
  echo "Unity executable not found: \${EDITOR_BIN}" >&2
  exit 1
fi

# Unity documents raising the open-file limit as a workaround for Linux
# "Pipe error !" issues.
ulimit -n 4096 || true
exec "\${EDITOR_BIN}" "\$@"
EOF

  chown "${TARGET_USER}:${TARGET_GROUP}" "${wrapper_path}"
  chmod 0755 "${wrapper_path}"
}

show_post_install_notes() {
  cat <<EOF

Installation finished.

Installed for user: ${TARGET_USER}
Editor path:        ${EDITOR_INSTALL_PATH}
EOF

  if [[ -n "${RESOLVED_UNITY6_VERSION}" ]]; then
    printf 'Unity 6 LTS:       %s\n' "${RESOLVED_UNITY6_VERSION}"
  fi

  if [[ -n "${RESOLVED_UNITY2022_VERSION}" ]]; then
    printf 'Unity 2022 LTS:    %s\n' "${RESOLVED_UNITY2022_VERSION}"
  fi

  printf '\n'
  printf 'Wrappers created:\n'
  if [[ -n "${RESOLVED_UNITY6_VERSION}" ]]; then
    printf '  %s\n' "${TARGET_HOME}/.local/bin/unity6-lts"
  fi
  if [[ -n "${RESOLVED_UNITY2022_VERSION}" ]]; then
    printf '  %s\n' "${TARGET_HOME}/.local/bin/unity2022-lts"
  fi
  printf '\n'

  cat <<EOF
Next steps:
  1. Log in as ${TARGET_USER}.
  2. Start Unity Hub once and sign in to your Unity account.
  3. Make sure ~/.local/bin is in PATH:
       echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
       source ~/.profile
EOF

  if [[ -n "${RESOLVED_UNITY6_VERSION}" || -n "${RESOLVED_UNITY2022_VERSION}" ]]; then
    printf '  4. Launch an editor:\n'
    if [[ -n "${RESOLVED_UNITY6_VERSION}" ]]; then
      printf '       unity6-lts\n'
    fi
    if [[ -n "${RESOLVED_UNITY2022_VERSION}" ]]; then
      printf '       unity2022-lts\n'
    fi
    printf '\n'
  fi

  cat <<EOF
If Unity Hub login or startup is unstable on Pop!_OS/COSMIC:
  - Try the latest Hub build.
  - Try a more Ubuntu/GNOME-like session.
  - Check Hub logs in:
      ~/.config/UnityHub/logs
EOF
}

main() {
  parse_args "$@"
  require_root
  resolve_target_user
  detect_os
  apt_env

  need_cmd apt-get
  need_cmd awk
  need_cmd cut
  need_cmd dpkg
  need_cmd getent
  need_cmd grep
  need_cmd id
  need_cmd sed
  need_cmd sort
  need_cmd sudo
  need_cmd tail
  need_cmd xargs

  prepare_target_user_dirs
  install_system_prereqs
  configure_unity_hub_repo
  install_unity_hub_package

  local hub_bin=""
  hub_bin="$(find_hub_binary)" || die "Unity Hub executable not found after package installation."
  log "Using Unity Hub executable: ${hub_bin}"

  detect_hub_cli_style "${hub_bin}" || die "Unity Hub CLI is not responding in headless mode for user ${TARGET_USER}."
  log "Detected Unity Hub CLI style: ${HUB_CLI_STYLE}"

  if (( LIST_RELEASES_ONLY == 1 )); then
    print_release_versions "${hub_bin}"
    exit 0
  fi

  if (( INSTALL_HUB_ONLY == 1 )); then
    log "Hub-only mode complete."
    exit 0
  fi

  local -a modules=()
  csv_to_array "${MODULES_CSV}" modules

  if (( INSTALL_UNITY6 == 1 )); then
    local spec=""
    spec="$(resolve_install_spec "${hub_bin}" "${UNITY6_BRANCH}" "${UNITY6_VERSION}" "${UNITY6_CHANGESET}" "Unity 6 LTS")"
    RESOLVED_UNITY6_VERSION="${spec%%|*}"
    local unity6_changeset="${spec#*|}"
    install_editor_with_modules "${hub_bin}" "${RESOLVED_UNITY6_VERSION}" "${unity6_changeset}" "${modules[@]}"
    create_launcher_wrapper "${RESOLVED_UNITY6_VERSION}" "unity6-lts"
  fi

  if (( INSTALL_UNITY2022 == 1 )); then
    local spec=""
    spec="$(resolve_install_spec "${hub_bin}" "${UNITY2022_BRANCH}" "${UNITY2022_VERSION}" "${UNITY2022_CHANGESET}" "Unity 2022 LTS")"
    RESOLVED_UNITY2022_VERSION="${spec%%|*}"
    local unity2022_changeset="${spec#*|}"
    install_editor_with_modules "${hub_bin}" "${RESOLVED_UNITY2022_VERSION}" "${unity2022_changeset}" "${modules[@]}"
    create_launcher_wrapper "${RESOLVED_UNITY2022_VERSION}" "unity2022-lts"
  fi

  show_post_install_notes
}

main "$@"
