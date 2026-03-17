#!/usr/bin/env bash
# install_unity_popos_lts.sh
#
# Installs Unity Hub on Pop!_OS / Ubuntu-like systems, then installs:
#   - Unity 6 LTS
#   - Unity 2022 LTS
#   - Android Build Support (+ SDK/NDK + OpenJDK)
#   - WebGL Build Support
#   - Linux Build Support (IL2CPP)
#
# Best-effort note:
# Unity officially supports Ubuntu on Linux. Pop!_OS often works, but it is not
# officially supported by Unity Hub support policy.
#
# Defaults are pinned to current LTS patch versions as of script creation time:
#   UNITY6_VERSION_DEFAULT=6000.3.10f1
#   UNITY2022_VERSION_DEFAULT=2022.3.71f1
#
# Usage examples:
#   sudo ./install_unity_popos_lts.sh
#   sudo ./install_unity_popos_lts.sh --hub-only
#   sudo ./install_unity_popos_lts.sh --unity6-version 6000.3.10f1 --unity2022-version 2022.3.71f1
#   sudo ./install_unity_popos_lts.sh --no-2022
#   sudo ./install_unity_popos_lts.sh --modules android,webgl,linux-il2cpp
#
# After install, log in to Unity Hub once with your Unity account.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly SCRIPT_NAME="${0##*/}"
readonly UNITY6_VERSION_DEFAULT="6000.3.10f1"
readonly UNITY2022_VERSION_DEFAULT="2022.3.71f1"

INSTALL_HUB_ONLY=0
INSTALL_UNITY6=1
INSTALL_UNITY2022=1
UNITY6_VERSION="${UNITY6_VERSION_DEFAULT}"
UNITY2022_VERSION="${UNITY2022_VERSION_DEFAULT}"
# Module IDs from Unity Hub CLI docs.
# Android needs the Android Build Support module plus SDK/NDK and OpenJDK.
MODULES_CSV="android,android-sdk-ndk-tools,android-open-jdk,webgl,linux-il2cpp"
TARGET_USER="${SUDO_USER:-${USER:-}}"
TARGET_HOME=""
TARGET_GROUP=""
EDITOR_INSTALL_PATH=""
NONINTERACTIVE_APT=1
HUB_CLI_STYLE=""

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
  sudo ./install_unity_popos_lts.sh [options]

Options:
  --hub-only                     Install/update Unity Hub only.
  --no-unity6                    Skip Unity 6 LTS installation.
  --no-2022                      Skip Unity 2022 LTS installation.
  --unity6-version VERSION       Set Unity 6 LTS editor version.
  --unity2022-version VERSION    Set Unity 2022 LTS editor version.
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
  sudo ./install_unity_popos_lts.sh
  sudo ./install_unity_popos_lts.sh --hub-only
  sudo ./install_unity_popos_lts.sh --no-2022
  sudo ./install_unity_popos_lts.sh --unity6-version 6000.3.10f1 --unity2022-version 2022.3.71f1
  sudo ./install_unity_popos_lts.sh --modules android,android-sdk-ndk-tools,android-open-jdk,webgl,linux-il2cpp
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

resolve_target_user() {
  [[ -n "${TARGET_USER}" ]] || die "Unable to determine target user. Use --user USERNAME."
  getent passwd "${TARGET_USER}" >/dev/null 2>&1 || die "User does not exist: ${TARGET_USER}"
  TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  TARGET_GROUP="$(id -gn "${TARGET_USER}")"
  [[ -d "${TARGET_HOME}" ]] || die "Target user home directory not found: ${TARGET_HOME}"

  if [[ -z "${EDITOR_INSTALL_PATH}" ]]; then
    EDITOR_INSTALL_PATH="${TARGET_HOME}/Unity/Hub/Editor"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hub-only)
        INSTALL_HUB_ONLY=1
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
    warn "Both editor installs were disabled; only Unity Hub will be installed."
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
    warn "Detected COSMIC session. Unity's Linux docs explicitly list Ubuntu + GNOME as the supported Linux desktop environment."
  fi
}

apt_env() {
  if (( NONINTERACTIVE_APT == 1 )); then
    export DEBIAN_FRONTEND=noninteractive
  fi
}

install_system_prereqs() {
  log "Installing base system packages required to add the Unity Hub repository..."
  apt-get update -y
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg
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

run_as_target_user() {
  local cmd=("$@")
  sudo -u "${TARGET_USER}" -H env \
    HOME="${TARGET_HOME}" \
    XDG_CONFIG_HOME="${TARGET_HOME}/.config" \
    XDG_DATA_HOME="${TARGET_HOME}/.local/share" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "${cmd[@]}"
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
  # shellcheck disable=SC2206
  out_ref=(${csv})
  IFS="${old_ifs}"

  local i
  for i in "${!out_ref[@]}"; do
    out_ref[$i]="$(printf '%s' "${out_ref[$i]}" | xargs)"
  done
}

install_editor_with_modules() {
  local hub_bin="$1"
  local version="$2"
  local -a modules=("${@:3}")

  log "Setting Unity editor install path for ${TARGET_USER}: ${EDITOR_INSTALL_PATH}"
  hub_cli "${hub_bin}" install-path -s "${EDITOR_INSTALL_PATH}"

  log "Installing Unity Editor ${version} for ${TARGET_USER}..."
  if [[ "${#modules[@]}" -gt 0 ]]; then
    hub_cli "${hub_bin}" install --version "${version}" --module "${modules[@]}"
  else
    hub_cli "${hub_bin}" install --version "${version}"
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

ulimit -n 4096 || true
exec "\${EDITOR_BIN}" "\$@"
EOF

  chown "${TARGET_USER}:${TARGET_GROUP}" "${wrapper_path}"
  chmod 0755 "${wrapper_path}"
}

show_post_install_notes() {
  local wrappers=()
  local launch_examples=()

  if (( INSTALL_UNITY6 == 1 )); then
    wrappers+=("${TARGET_HOME}/.local/bin/unity6-lts")
    launch_examples+=("unity6-lts")
  fi

  if (( INSTALL_UNITY2022 == 1 )); then
    wrappers+=("${TARGET_HOME}/.local/bin/unity2022-lts")
    launch_examples+=("unity2022-lts")
  fi

  cat <<EOF

Installation finished.

Installed for user: ${TARGET_USER}
Editor path:        ${EDITOR_INSTALL_PATH}

EOF

  if [[ "${#wrappers[@]}" -gt 0 ]]; then
    printf 'Wrappers created:\n'
    printf '  %s\n' "${wrappers[@]}"
    printf '\n'
  fi

  cat <<EOF
Next steps:
  1. Log in as ${TARGET_USER}.
  2. Start Unity Hub once and sign in to your Unity account.
  3. Make sure ~/.local/bin is in PATH:
       echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
       source ~/.profile
EOF

  if [[ "${#launch_examples[@]}" -gt 0 ]]; then
    printf '  4. Launch an editor:\n'
    printf '       %s\n' "${launch_examples[@]}"
    printf '\n'
  fi

  cat <<EOF
If Unity Hub login or startup is unstable on Pop!_OS/COSMIC:
  - Try the latest Hub build.
  - Try running under a more Ubuntu/GNOME-like session.
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
  need_cmd getent
  need_cmd sudo
  need_cmd dpkg
  need_cmd awk
  need_cmd xargs
  need_cmd id

  prepare_target_user_dirs
  install_system_prereqs
  configure_unity_hub_repo
  install_unity_hub_package

  local hub_bin=""
  hub_bin="$(find_hub_binary)" || die "Unity Hub executable not found after package installation."

  log "Using Unity Hub executable: ${hub_bin}"

  detect_hub_cli_style "${hub_bin}" || die "Unity Hub CLI is not responding in headless mode for user ${TARGET_USER}."
  log "Detected Unity Hub CLI style: ${HUB_CLI_STYLE}"

  if (( INSTALL_HUB_ONLY == 1 )); then
    log "Hub-only mode complete."
    exit 0
  fi

  local -a modules=()
  csv_to_array "${MODULES_CSV}" modules

  if (( INSTALL_UNITY6 == 1 )); then
    install_editor_with_modules "${hub_bin}" "${UNITY6_VERSION}" "${modules[@]}"
    create_launcher_wrapper "${UNITY6_VERSION}" "unity6-lts"
  fi

  if (( INSTALL_UNITY2022 == 1 )); then
    install_editor_with_modules "${hub_bin}" "${UNITY2022_VERSION}" "${modules[@]}"
    create_launcher_wrapper "${UNITY2022_VERSION}" "unity2022-lts"
  fi

  show_post_install_notes
}

main "$@"
