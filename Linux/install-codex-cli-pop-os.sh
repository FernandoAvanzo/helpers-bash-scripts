#!/usr/bin/env bash
# Install OpenAI Codex CLI on Pop!_OS 24.04.
# Usage: ./install-codex-cli-pop-os.sh [--npm] [--help]

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"
readonly OFFICIAL_INSTALLER_URL="https://chatgpt.com/codex/install.sh"
readonly NPM_PACKAGE="@openai/codex"
readonly MINIMUM_NPM_MAJOR=18
INSTALL_METHOD="standalone"
TEMP_DIR=""

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*" >&2; }
die() { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<USAGE
Uso: ${SCRIPT_NAME} [opção]

Instala o Codex CLI no Pop!_OS 24.04 para o usuário atual.

Opções:
  --npm     Instala pelo pacote npm @openai/codex (requer Node.js e npm).
  -h, --help  Exibe esta ajuda.

Padrão: usa o instalador standalone oficial para Linux.
O script não executa apt upgrade, não usa sudo npm e não configura credenciais.
USAGE
}

cleanup() {
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf -- "${TEMP_DIR}"
  fi
}

on_error() {
  local exit_code=$?
  printf '[ERRO] Falha na linha %s (código %s).\n' "${BASH_LINENO[0]:-desconhecida}" "${exit_code}" >&2
  exit "${exit_code}"
}

trap cleanup EXIT
trap on_error ERR

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --npm)
        INSTALL_METHOD="npm"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Opção desconhecida: $1"
        ;;
    esac
    shift
  done
}

check_os() {
  [[ -r /etc/os-release ]] || die "Não foi possível identificar a distribuição (/etc/os-release ausente)."
  # shellcheck disable=SC1091
  source /etc/os-release

  [[ "${ID:-}" == "pop" ]] || die "Este script foi preparado para Pop!_OS; distribuição detectada: ${PRETTY_NAME:-desconhecida}."
  [[ "${VERSION_ID:-}" == "24.04" ]] || die "Versão esperada: Pop!_OS 24.04; detectada: ${VERSION_ID:-desconhecida}."

  case "$(uname -m)" in
    x86_64|aarch64) ;;
    *) die "Arquitetura não suportada por este guia: $(uname -m)." ;;
  esac
  log "Sistema validado: ${PRETTY_NAME} ($(uname -m))."
}

check_network_tools() {
  command -v curl >/dev/null 2>&1 || die "curl não encontrado. Instale com: sudo apt update && sudo apt install curl"
  command -v mktemp >/dev/null 2>&1 || die "mktemp não encontrado. Instale os utilitários básicos do sistema."
}

check_npm_runtime() {
  command -v node >/dev/null 2>&1 || die "Node.js não encontrado. Instale Node.js/npm ou execute sem --npm para usar o instalador oficial."
  command -v npm >/dev/null 2>&1 || die "npm não encontrado. Instale Node.js/npm ou execute sem --npm para usar o instalador oficial."

  local node_major
  node_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
  (( node_major >= MINIMUM_NPM_MAJOR )) || die "Node.js ${MINIMUM_NPM_MAJOR}+ é necessário para o método npm (encontrado: $(node --version))."
}

install_standalone() {
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-cli-install.XXXXXXXX")"
  local installer="${TEMP_DIR}/install.sh"

  log "Baixando o instalador oficial via HTTPS..."
  curl --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 \
    --output "${installer}" "${OFFICIAL_INSTALLER_URL}"

  [[ -s "${installer}" ]] || die "O instalador baixado está vazio."
  chmod 0700 "${installer}"
  log "Executando o instalador oficial como usuário atual (sem sudo)..."
  # O instalador oficial pode selecionar o binário correto e validar sua distribuição.
  sh "${installer}"
}

install_with_npm() {
  check_npm_runtime
  log "Instalando ${NPM_PACKAGE} globalmente para o usuário, sem sudo..."

  if ! npm install --global "${NPM_PACKAGE}"; then
    die "A instalação npm falhou. Não use sudo npm; configure um prefixo npm no usuário ou use o instalador standalone."
  fi
}

verify_installation() {
  hash -r
  if ! command -v codex >/dev/null 2>&1; then
    warn "O comando codex não está no PATH desta sessão. Reabra o terminal e tente: codex --version"
    if [[ "${INSTALL_METHOD}" == "npm" ]]; then
      warn "Prefixo npm: $(npm config get prefix 2>/dev/null || true)"
    fi
    return 1
  fi

  log "Codex CLI instalado: $(command -v codex)"
  codex --version
}

main() {
  parse_args "$@"
  check_os

  if [[ "${EUID}" -eq 0 ]]; then
    die "Execute como usuário comum, sem sudo. A instalação é por usuário."
  fi

  check_network_tools
  case "${INSTALL_METHOD}" in
    standalone) install_standalone ;;
    npm) install_with_npm ;;
    *) die "Método interno inválido: ${INSTALL_METHOD}" ;;
  esac

  verify_installation || die "Instalação concluída, mas não foi possível verificar o executável. Revise o PATH."

  cat <<'NEXT_STEPS'

Próximos passos:
  1. Execute: codex
  2. Escolha Sign in with ChatGPT e conclua o login no navegador.
  3. Entre na pasta de um repositório e inicie o Codex ali.
  4. Revise as permissões e confira as alterações com git status e git diff.

Este script não salva chaves de API nem copia credenciais entre estações.
NEXT_STEPS
}

main "$@"
