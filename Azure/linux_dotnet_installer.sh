#!/usr/bin/env bash
set -euo pipefail

# .NET Runtime installer for Pop!_OS 22.04 (Ubuntu 22.04 "jammy")
# - Adds Microsoft package repo
# - Installs dotnet-runtime-X.Y or (optionally) dotnet-sdk-X.Y
# - Verifies install and prints helpful paths for IntelliJ Bicep settings

RUNTIME_VERSION="8.0"   # Allowed: 6.0, 7.0, 8.0, 9.0 (if available)
INSTALL_FLAVOR="runtime" # runtime | sdk
NONINTERACTIVE="false"   # true | false

info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERR ]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[ OK ]\033[0m $*"; }

usage() {
  cat <<EOF
Install Microsoft .NET on Pop!_OS 22.04.

Options:
  --version <6.0|7.0|8.0|9.0>   .NET major.minor to install (default: 8.0)
  --flavor runtime|sdk          Install Runtime (default) or SDK
  --noninteractive              Do not prompt for confirmation
  -h|--help                     Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --version 8.0 --flavor sdk
  $(basename "$0") --version 6.0 --noninteractive

Notes:
- Uses Microsoft APT repository for Ubuntu 22.04 "jammy" [[2]](https://www.linode.com/docs/guides/install-dotnet-on-ubuntu/)
EOF
}

confirm() {
  if [[ "${NONINTERACTIVE}" == "true" ]]; then return 0; fi
  read -r -p "$1 [y/N]: " ans
  [[ "${ans:-}" == "y" || "${ans:-}" == "Y" ]]
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_pop_os_22_04() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" == "pop" && "${VERSION_ID:-}" == "22.04" ]]; then
      ok "Detected Pop!_OS ${VERSION_ID}"
      return 0
    fi
  fi
  warn "This script targets Pop!_OS 22.04; continuing anyway."
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --version)        RUNTIME_VERSION="${2:-}"; shift 2;;
    --version=*)      RUNTIME_VERSION="${1#*=}"; shift 1;;
    --flavor)         INSTALL_FLAVOR="${2:-}"; shift 2;;
    --flavor=*)       INSTALL_FLAVOR="${1#*=}"; shift 1;;
    --noninteractive) NONINTERACTIVE="true"; shift 1;;
    -h|--help)        usage; exit 0;;
    *) error "Unknown argument: $1"; usage; exit 1;;
    esac
  done
  case "${INSTALL_FLAVOR}" in
  runtime|sdk) : ;;
  *) error "--flavor must be 'runtime' or 'sdk'"; exit 1;;
  esac
  case "${RUNTIME_VERSION}" in
  6.0|7.0|8.0|9.0) : ;;
  *) warn "Version '${RUNTIME_VERSION}' may not exist in Ubuntu 22.04 repo."; sleep 1;;
  esac
}

install_prereqs() {
  info "Installing prerequisites..."
  sudo apt-get update -y
  sudo apt-get install -y curl gnupg lsb-release apt-transport-https ca-certificates
  ok "Prerequisites installed."
}

add_ms_repo() {
  local UBUNTU_VERSION CODENAME
  UBUNTU_VERSION="$(lsb_release -rs)"   # 22.04
  CODENAME="$(lsb_release -cs)"         # jammy

  info "Adding Microsoft package repository for Ubuntu ${UBUNTU_VERSION} (${CODENAME})..."
  curl -sSL https://packages.microsoft.com/keys/microsoft.asc \
    | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/${UBUNTU_VERSION}/prod ${CODENAME} main" \
    | sudo tee /etc/apt/sources.list.d/microsoft-prod.list >/dev/null

  info "Updating package lists..."
  sudo apt-get update -y
  ok "Microsoft repo configured. [[2]](https://www.linode.com/docs/guides/install-dotnet-on-ubuntu/)"
}

install_dotnet() {
  local pkg
  if [[ "${INSTALL_FLAVOR}" == "sdk" ]]; then
    pkg="dotnet-sdk-${RUNTIME_VERSION}"
  else
    pkg="dotnet-runtime-${RUNTIME_VERSION}"
  fi

  info "Installing ${pkg}..."
  if ! sudo apt-get install -y "${pkg}"; then
    error "Failed to install ${pkg}. It may be unavailable for this Ubuntu release."
    exit 1
  fi
  ok "${pkg} installed."
}

print_paths_and_tips() {
  local DOTNET_BIN DOTNET_ROOT
  DOTNET_BIN="$(command -v dotnet || true)"
  DOTNET_ROOT="/usr/share/dotnet"

  echo
  ok "dotnet found at: ${DOTNET_BIN}"
  dotnet --info || true

  echo
  echo "If IntelliJ asks for '.NET Runtime path' (e.g., Bicep settings):"
  echo "  - Path to dotnet executable: ${DOTNET_BIN}"
  echo "  - DOTNET_ROOT directory:     ${DOTNET_ROOT}"
  echo
}

main() {
  parse_args "$@"
  detect_pop_os_22_04
  install_prereqs
  add_ms_repo
  install_dotnet
  print_paths_and_tips
  ok ".NET installation complete."
}

main "$@"