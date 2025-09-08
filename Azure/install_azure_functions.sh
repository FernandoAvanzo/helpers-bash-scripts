#!/usr/bin/env bash
set -euo pipefail

# Azure Functions Core Tools installer for Pop!_OS 22.04 (Ubuntu 22.04 base)
# - Installs Core Tools v4 via APT (system-wide) or npm (user-space).
# - Cleans broken IntelliJ auto-install leftovers.
# - Verifies installation and prints the path to 'func' for IntelliJ.

METHOD="apt"                 # apt | npm
NONINTERACTIVE="false"       # true | false
CLEAN_LEFTOVERS="false"      # true | false
CORE_TOOLS_NPM_VERSION="azure-functions-core-tools@4"
NPM_PREFIX_DIR="${HOME}/.npm-global"
BASHRC="${HOME}/.bashrc"
ZSHRC="${HOME}/.zshrc"

info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERR ]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[ OK ]\033[0m $*"; }

usage() {
  cat <<EOF
Install Azure Functions Core Tools v4 on Pop!_OS 22.04.

Options:
  --method apt|npm         Installation method (default: apt)
  --noninteractive         Do not prompt for confirmation
  --clean-leftovers        Remove broken IntelliJ auto-install leftovers in /usr/bin
  -h|--help                Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --method npm
  $(basename "$0") --noninteractive --clean-leftovers
EOF
}

confirm() {
  if [[ "${NONINTERACTIVE}" == "true" ]]; then
    return 0
  fi
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
  warn "This script is tailored for Pop!_OS 22.04. Continuing anyway."
}

clean_leftovers() {
  local pattern="/usr/bin/Azure.Functions.Cli.linux-x64.*"
  if compgen -G "${pattern}" > /dev/null; then
    if [[ "${NONINTERACTIVE}" == "true" ]] || confirm "Remove leftover files matching ${pattern}?"; then
      info "Removing leftovers under /usr/bin..."
      sudo rm -f ${pattern} || true
      ok "Leftovers removed."
    else
      warn "Skipped removing leftovers."
    fi
  else
    info "No leftovers found in /usr/bin."
  fi
}

install_prereqs() {
  info "Installing prerequisites (curl, gnupg, lsb-release, apt-transport-https)..."
  sudo apt-get update -y
  sudo apt-get install -y curl gnupg lsb-release apt-transport-https ca-certificates
  ok "Prerequisites installed."
}

install_via_apt() {
  install_prereqs

  local UBUNTU_VERSION
  UBUNTU_VERSION="$(lsb_release -rs)"      # 22.04
  local CODENAME
  CODENAME="$(lsb_release -cs)"            # jammy

  info "Adding Microsoft package repository for Ubuntu ${UBUNTU_VERSION} (${CODENAME})..."
  curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/${UBUNTU_VERSION}/prod ${CODENAME} main" \
    | sudo tee /etc/apt/sources.list.d/microsoft-prod.list >/dev/null

  info "Updating package lists..."
  sudo apt-get update -y

  info "Installing Azure Functions Core Tools v4 via APT..."
  sudo apt-get install -y azure-functions-core-tools-4
  ok "Azure Functions Core Tools installed via APT."
}

ensure_npm() {
  if have_cmd npm && have_cmd node; then
    ok "Node.js and npm are present."
    return
  fi

  warn "Node.js/npm not found. Installing from Ubuntu repos (sufficient for Core Tools packaging)..."
  sudo apt-get update -y
  sudo apt-get install -y nodejs npm
  if ! have_cmd npm || ! have_cmd node; then
    error "Failed to install Node.js/npm. Please install Node.js 18+ and npm, then re-run."
    exit 1
  fi
  ok "Node.js/npm installed."
}

configure_user_npm_prefix() {
  info "Configuring npm user prefix at ${NPM_PREFIX_DIR}..."
  mkdir -p "${NPM_PREFIX_DIR}"
  npm config set prefix "${NPM_PREFIX_DIR}"

  local export_line="export PATH=\"${NPM_PREFIX_DIR}/bin:\$PATH\""
  for rc in "${BASHRC}" "${ZSHRC}"; do
    if [[ -f "${rc}" ]]; then
      if ! grep -qs "${NPM_PREFIX_DIR}/bin" "${rc}"; then
        echo "${export_line}" >> "${rc}"
        info "Added PATH update to ${rc}"
      fi
    fi
  done

  # Apply to current shell if possible
  export PATH="${NPM_PREFIX_DIR}/bin:${PATH}"
  ok "npm prefix configured and PATH updated for current shell."
}

install_via_npm() {
  ensure_npm
  configure_user_npm_prefix

  info "Installing Azure Functions Core Tools v4 via npm (user-space)..."
  npm install -g "${CORE_TOOLS_NPM_VERSION}" --unsafe-perm true
  ok "Azure Functions Core Tools installed via npm."
}

verify_install() {
  info "Verifying installation..."
  if ! have_cmd func; then
    error "'func' not found in PATH after installation."
    exit 1
  fi
  local FUNC_PATH
  FUNC_PATH="$(command -v func)"
  local FUNC_VERSION
  FUNC_VERSION="$(func --version 2>/dev/null || true)"
  ok "func found at: ${FUNC_PATH}"
  ok "func version: ${FUNC_VERSION}"

  echo
  echo "Next steps for IntelliJ:"
  echo "1) In IntelliJ: Settings/Preferences > Tools > Azure > Functions."
  echo "2) Check 'Use custom Azure Functions Core Tools executable'."
  echo "3) Set the path to: ${FUNC_PATH}"
  echo
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --method)
      METHOD="${2:-}"; shift 2;;
    --method=*)
      METHOD="${1#*=}"; shift 1;;
    --noninteractive)
      NONINTERACTIVE="true"; shift 1;;
    --clean-leftovers)
      CLEAN_LEFTOVERS="true"; shift 1;;
    -h|--help)
      usage; exit 0;;
    *)
      error "Unknown argument: $1"
      usage; exit 1;;
    esac
  done

  if [[ "${METHOD}" != "apt" && "${METHOD}" != "npm" ]]; then
    error "--method must be 'apt' or 'npm'"
    exit 1
  fi
}

main() {
  parse_args "$@"
  detect_pop_os_22_04

  if [[ "${CLEAN_LEFTOVERS}" == "true" ]]; then
    clean_leftovers
  fi

  if have_cmd func; then
    warn "An existing 'func' was found at: $(command -v func)"
    if [[ "${NONINTERACTIVE}" == "true" ]] || confirm "Continue and reinstall/update Azure Functions Core Tools?"; then
      info "Proceeding to (re)install..."
    else
      ok "No changes made."
      verify_install
      exit 0
    fi
  fi

  case "${METHOD}" in
  apt) install_via_apt ;;
  npm) install_via_npm ;;
  esac

  verify_install

  echo
  ok "Azure Functions Core Tools setup completed."
  echo "Open a new shell or run 'source ~/.bashrc' if 'func' is not immediately available."
}

main "$@"