#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() { printf "[setup] %s\n" "$*"; }
warn() { printf "[setup][warn] %s\n" "$*"; }
err() { printf "[setup][error] %s\n" "$*"; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing required command: $1"
    return 1
  fi
}

SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    err "This script needs root privileges (sudo not found)."
    exit 1
  fi
fi

OS_ID=""
OS_LIKE=""
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-}"
  OS_LIKE="${ID_LIKE:-}"
fi

ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
  warn "Unsupported architecture ($ARCH). CUDA Toolkit may not be available."
fi

log "System checks"
if command -v lspci >/dev/null 2>&1; then
  if lspci | grep -qi nvidia; then
    log "NVIDIA GPU detected."
  else
    warn "No NVIDIA GPU detected via lspci. CUDA Toolkit may not be useful."
  fi
else
  warn "lspci not available; skipping GPU detection."
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  log "NVIDIA driver detected (nvidia-smi present)."
else
  warn "nvidia-smi not found; NVIDIA driver may be missing."
fi

install_cuda_toolkit() {
  if command -v nvcc >/dev/null 2>&1; then
    log "nvcc already present; skipping CUDA Toolkit install."
    return 0
  fi

  log "Installing CUDA Toolkit (nvcc)"
  case "$OS_ID" in
    ubuntu|debian)
      ${SUDO} apt-get update
      ${SUDO} apt-get install -y --no-install-recommends nvidia-cuda-toolkit
      ;;
    fedora|rhel|centos)
      if command -v dnf >/dev/null 2>&1; then
        if ! ${SUDO} dnf install -y cuda-toolkit; then
          err "Failed to install cuda-toolkit via dnf. NVIDIA repo may be required."
          return 1
        fi
      elif command -v yum >/dev/null 2>&1; then
        if ! ${SUDO} yum install -y cuda-toolkit; then
          err "Failed to install cuda-toolkit via yum. NVIDIA repo may be required."
          return 1
        fi
      else
        err "No dnf/yum found."
        return 1
      fi
      ;;
    arch)
      ${SUDO} pacman -Sy --noconfirm cuda
      ;;
    *)
      if echo "$OS_LIKE" | grep -q "debian"; then
        ${SUDO} apt-get update
        ${SUDO} apt-get install -y --no-install-recommends nvidia-cuda-toolkit
      elif echo "$OS_LIKE" | grep -q "rhel"; then
        if command -v dnf >/dev/null 2>&1; then
          ${SUDO} dnf install -y cuda-toolkit
        else
          ${SUDO} yum install -y cuda-toolkit
        fi
      elif echo "$OS_LIKE" | grep -q "arch"; then
        ${SUDO} pacman -Sy --noconfirm cuda
      else
        err "Unsupported distribution. Install CUDA Toolkit manually."
        return 1
      fi
      ;;
  esac

  if ! command -v nvcc >/dev/null 2>&1; then
    err "nvcc still not found after installation."
    return 1
  fi

  log "nvcc installed: $(command -v nvcc)"
}

install_python_headers() {
  require_cmd python3

  PY_MAJ_MIN="$(python3 - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"

  INCLUDEPY="$(python3 - <<'PY'
import sysconfig
print(sysconfig.get_config_var('INCLUDEPY') or '')
PY
)"

  if [ -n "$INCLUDEPY" ] && [ -f "$INCLUDEPY/pyconfig.h" ]; then
    log "Python dev headers already present: $INCLUDEPY/pyconfig.h"
    return 0
  fi

  log "Installing Python dev headers"
  case "$OS_ID" in
    ubuntu|debian)
      if apt-cache show "python${PY_MAJ_MIN}-dev" >/dev/null 2>&1; then
        ${SUDO} apt-get install -y "python${PY_MAJ_MIN}-dev"
      fi
      ${SUDO} apt-get install -y python3-dev
      ;;
    fedora|rhel|centos)
      if command -v dnf >/dev/null 2>&1; then
        ${SUDO} dnf install -y python3-devel
      else
        ${SUDO} yum install -y python3-devel
      fi
      ;;
    arch)
      ${SUDO} pacman -Sy --noconfirm python
      ;;
    *)
      if echo "$OS_LIKE" | grep -q "debian"; then
        ${SUDO} apt-get install -y python3-dev
      elif echo "$OS_LIKE" | grep -q "rhel"; then
        if command -v dnf >/dev/null 2>&1; then
          ${SUDO} dnf install -y python3-devel
        else
          ${SUDO} yum install -y python3-devel
        fi
      elif echo "$OS_LIKE" | grep -q "arch"; then
        ${SUDO} pacman -Sy --noconfirm python
      else
        err "Unsupported distribution. Install Python dev headers manually."
        return 1
      fi
      ;;
  esac

  INCLUDEPY="$(python3 - <<'PY'
import sysconfig
print(sysconfig.get_config_var('INCLUDEPY') or '')
PY
)"

  if [ -z "$INCLUDEPY" ] || [ ! -f "$INCLUDEPY/pyconfig.h" ]; then
    err "pyconfig.h still missing after install."
    return 1
  fi

  log "Python dev headers installed: $INCLUDEPY/pyconfig.h"
}

set_cuda_inc_dir() {
  local candidates=()

  if [ -n "${CUDA_HOME:-}" ]; then
    candidates+=("${CUDA_HOME}/include")
  fi
  candidates+=(
    "/usr/local/cuda/include"
    "/usr/include"
    "/usr/include/cuda"
    "/opt/cuda/include"
    "/opt/nvidia/cuda/include"
  )

  local found=""
  for dir in "${candidates[@]}"; do
    if [ -f "$dir/cuda.h" ] || [ -f "$dir/cuda_runtime.h" ]; then
      found="$dir"
      break
    fi
  done

  if [ -z "$found" ]; then
    warn "CUDA headers not found in standard locations."
    return 0
  fi

  if [ "$found" = "/usr/local/cuda/include" ] || [ "$found" = "/usr/include" ] || [ "$found" = "/usr/include/cuda" ]; then
    log "CUDA headers found in standard path: $found"
    return 0
  fi

  export CUDA_INC_DIR="$found"

  local env_file="${PROJECT_ROOT}/.env.cuda"
  cat > "$env_file" <<EOF
export CUDA_INC_DIR="$found"
EOF

  log "Set CUDA_INC_DIR to $found (written to $env_file)"
  log "To apply in your shell: source $env_file"
}

post_install_checks() {
  log "Post-install checks"

  if command -v nvcc >/dev/null 2>&1; then
    nvcc --version >/dev/null 2>&1 && log "nvcc is functional." || warn "nvcc found but not functional."
  else
    err "nvcc not found after installation."
    return 1
  fi

  if command -v g++ >/dev/null 2>&1; then
    log "g++ present."
  else
    warn "g++ not found; building PyCUDA will fail."
  fi

  if command -v python3 >/dev/null 2>&1; then
    local include
    include="$(python3 - <<'PY'
import sysconfig
print(sysconfig.get_config_var('INCLUDEPY') or '')
PY
)"
    if [ -n "$include" ] && [ -f "$include/pyconfig.h" ]; then
      log "pyconfig.h present at $include/pyconfig.h"
    else
      err "pyconfig.h missing after setup."
      return 1
    fi
  else
    err "python3 not found."
    return 1
  fi

  log "All required tools appear to be installed."
}

main() {
  install_cuda_toolkit
  install_python_headers
  set_cuda_inc_dir
  post_install_checks
  log "Setup complete."
}

main "$@"
