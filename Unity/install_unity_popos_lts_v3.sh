#!/usr/bin/env bash
# install_unity_popos_lts_v3.sh
#
# Safer Unity installer for Pop!_OS / Ubuntu-like systems.
#
# Main fixes vs v2:
#   - If Unity Hub is already installed, this script skips APT entirely by default.
#     That avoids touching unrelated desktop/meta packages on systems where APT's
#     resolver is currently unhappy.
#   - If Unity Hub is not installed (or you pass --refresh-hub), the script uses
#     only Unity's documented Linux repo flow: install minimal repo tools,
#     configure the repo, and install unityhub.
#   - It no longer force-installs extra GUI/runtime libraries such as libgtk-3-0.
#     The Unity Hub package manager metadata should pull what it needs.
#
# What it installs:
#   - Unity 6 LTS (latest visible release from branch 6000.3 by default)
#   - Unity 2022 LTS (latest visible release from branch 2022.3 by default)
#   - Modules: Android, Android SDK & NDK Tools, OpenJDK, WebGL, Linux IL2CPP
#
# Usage:
#   sudo ./install_unity_popos_lts_v3.sh --list-releases
#   sudo ./install_unity_popos_lts_v3.sh
#   sudo ./install_unity_popos_lts_v3.sh --refresh-hub
#   sudo ./install_unity_popos_lts_v3.sh --no-2022
#   sudo ./install_unity_popos_lts_v3.sh --unity6-version 6000.3.10f1 --unity6-changeset e35f0c77bd8e
#
# Notes:
#   - Unity Hub CLI on Linux is experimental.
#   - Pop!_OS is not a Unity-supported Linux distro for Hub support, so this is
#     best-effort on Pop!_OS/COSMIC.

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
REFRESH_HUB=0

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
  sudo ./install_unity_popos_lts_v3.sh [options]

Options:
  --hub-only                     Install/update Unity Hub only.
  --list-releases                Print versions visible to the Unity Hub CLI and exit.
  --refresh-hub                  Reconfigure Unity's apt repo and install/upgrade unityhub,
                                 even if a working unityhub is already present.
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
  sudo ./install_unity_popos_lts_v3.sh --list-releases
  sudo ./install_unity_popos_lts_v3.sh
  sudo ./install_unity_popos_lts_v3.sh --refresh-hub
  sudo ./install_unity_popos_lts_v3.sh --no-2022
  sudo ./install_unity_popos_lts_v3.sh --unity6-version 6000.3.10f1 --unity6-changeset e35f0c77bd8e
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

package_installed() {
  dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -q '^install ok installed$'
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
      --refresh-hub)
        REFRESH_HUB=1
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
  # shellcheck disable=SC1091
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
    warn "Detected COSMIC session. Unity documents GNOME on X11 for supported desktop Linux environments."
  fi
}

apt_env() {
  if (( NONINTERACTIVE_APT == 1 )); then
    export DEBIAN_FRONTEND=noninteractive
  fi
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

install_minimal_repo_tools() {
  local -a missing=()

  package_installed ca-certificates || missing+=(ca-certificates)
  package_installed curl || missing+=(curl)
  package_installed gnupg || missing+=(gnupg)

  if [[ "${#missing[@]}" -eq 0 ]]; then
    log "Minimal repo tools already installed."
    return 0
  fi

  log "Installing minimal repo tools: ${missing[*]}"
  apt-get update -y
  apt-get install -y "${missing[@]}"
}

configure_unity_hub_repo() {
  log "Configuring the official Unity Hub apt repository..."
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL "https://hub.unity3d.com/linux/keys/public" \
    | gpg --dearmor -o /etc/apt/keyrings/unityhub.gpg
  chmod 0644 /etc/apt/keyrings/unityhub.gpg

  cat >/etc/apt/sources.list.d/unityhub.list <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/unityhub.gpg] https://hub.unity3d.com/linux/repos/deb stable main
EOF
}

install_or_refresh_unity_hub_if_needed() {
  local hub_bin=""

  if (( REFRESH_HUB == 0 )); then
    if hub_bin="$(find_hub_binary)"; then
      log "Found existing Unity Hub: ${hub_bin}"
      log "Skipping APT because Unity Hub is already installed. Use --refresh-hub to force a repo/package refresh."
      return 0
    fi
  fi

  install_minimal_repo_tools
  configure_unity_hub_repo

  log "Installing or updating Unity Hub..."
  apt-get update -y
  apt-get install -y unityhub
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

  out_ref=()
  [[ -n "${csv}" ]] || return 0

  local old_ifs="${IFS}"
  IFS=','
  # shellcheck disable=SC2206
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
    | tr -d '\r' \
    | grep -oE '\b[0-9]{4}\.[0-9]+\.[0-9]+[abcfp][0-9]+\b' \
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

  list_release_versions "${hub_bin}" | grep -Fxq "${version}"
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
        err "${label}: either provide a matching changeset, or let the script resolve the latest version from branch ${branch}."
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

  cat >"${wrapper_path}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

CANDIDATE_1="${EDITOR_INSTALL_PATH}/${version}/Editor/Unity"
CANDIDATE_2="${EDITOR_INSTALL_PATH}/${version}/Unity"

if [[ -x "\${CANDIDATE_1}" ]]; then
  EDITOR_BIN="\${CANDIDATE_1}"
elif [[ -x "\${CANDIDATE_2}" ]]; then
  EDITOR_BIN="\${CANDIDATE_2}"
else
  echo "Unity executable not found under:" >&2
  echo "  \${CANDIDATE_1}" >&2
  echo "  \${CANDIDATE_2}" >&2
  exit 1
fi

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

  need_cmd awk
  need_cmd cut
  need_cmd dpkg
  need_cmd dpkg-query
  need_cmd getent
  need_cmd grep
  need_cmd id
  need_cmd sed
  need_cmd sort
  need_cmd sudo
  need_cmd tail
  need_cmd tr
  need_cmd xargs

  prepare_target_user_dirs
  install_or_refresh_unity_hub_if_needed

  local hub_bin=""
  hub_bin="$(find_hub_binary)" || die "Unity Hub executable not found. Install it first or rerun with --refresh-hub."
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
