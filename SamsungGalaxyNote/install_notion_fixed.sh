#!/usr/bin/env bash
# Instala o Notion Repackaged (vanilla ou enhanced) em sistemas Debian/Ubuntu/Pop!_OS.
# Padrão: instala a variante vanilla por ser a opção mais conservadora/estável.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"
readonly REPO="notion-enhancer/notion-repackaged"
readonly GITHUB_API_URL="https://api.github.com/repos/${REPO}/releases/latest"
readonly APT_SOURCE_FILE="/etc/apt/sources.list.d/notion-repackaged.list"
readonly APT_SOURCE_LINE='deb [trusted=yes] https://apt.fury.io/notion-repackaged/ /'

TMP_DIR=""

if [[ -t 1 ]]; then
  readonly C_RESET=$'\033[0m'
  readonly C_GREEN=$'\033[0;32m'
  readonly C_YELLOW=$'\033[0;33m'
  readonly C_RED=$'\033[0;31m'
else
  readonly C_RESET=''
  readonly C_GREEN=''
  readonly C_YELLOW=''
  readonly C_RED=''
fi

log() {
  printf '%s[INFO]%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"
}

warn() {
  printf '%s[WARN]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2
}

error() {
  printf '%s[ERRO]%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2
}

die() {
  error "$*"
  exit 1
}

usage() {
  cat <<'EOF'
Uso:
  sudo ./install_notion_fixed.sh [opções]

Opções:
  --vanilla            Instala a variante vanilla (padrão)
  --enhanced           Instala a variante enhanced
  --auto               Tenta instalar via repositório APT e, se falhar, usa o .deb do GitHub (padrão)
  --repo               Instala somente via repositório APT
  --deb                Instala somente via .deb do release mais recente no GitHub
  -h, --help           Mostra esta ajuda

Exemplos:
  sudo ./install_notion_fixed.sh
  sudo ./install_notion_fixed.sh --enhanced
  sudo ./install_notion_fixed.sh --enhanced --deb
EOF
}

cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf -- "${TMP_DIR}"
  fi
}

on_error() {
  local line_no="$1"
  local exit_code="$2"
  error "Falha na linha ${line_no} (exit code: ${exit_code})."
  exit "${exit_code}"
}

trap cleanup EXIT
trap 'on_error "${LINENO}" "$?"' ERR

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"
}

ensure_root() {
  if (( EUID != 0 )); then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -- "$0" "$@"
    fi
    die "Execute este script como root ou via sudo."
  fi
}

ensure_apt_based_system() {
  need_cmd apt-get
  need_cmd dpkg
}

detect_arch() {
  local arch
  arch="$(dpkg --print-architecture)"
  case "${arch}" in
    amd64|arm64)
      printf '%s\n' "${arch}"
      ;;
    *)
      die "Arquitetura não suportada: ${arch}. Use amd64 ou arm64."
      ;;
  esac
}

os_name() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    printf '%s\n' "${PRETTY_NAME:-Linux}"
  else
    printf 'Linux\n'
  fi
}

install_prereqs() {
  export DEBIAN_FRONTEND=noninteractive
  log "Atualizando índices APT..."
  apt-get update
  log "Instalando dependências do script..."
  apt-get install -y ca-certificates curl jq
}

configure_repo() {
  if [[ ! -f "${APT_SOURCE_FILE}" ]] || ! grep -qxF "${APT_SOURCE_LINE}" "${APT_SOURCE_FILE}"; then
    log "Configurando repositório notion-repackaged..."
    printf '%s\n' "${APT_SOURCE_LINE}" > "${APT_SOURCE_FILE}"
  else
    log "Repositório notion-repackaged já está configurado."
  fi

  log "Atualizando índices APT após configurar o repositório..."
  apt-get update
}

package_installed() {
  local pkg="$1"
  dpkg-query -W -f='${Status}\n' "${pkg}" 2>/dev/null | grep -qx 'install ok installed'
}

installed_version() {
  local pkg="$1"
  dpkg-query -W -f='${Version}\n' "${pkg}"
}

install_via_repo() {
  local pkg="$1"

  configure_repo
  log "Instalando ${pkg} via APT..."
  apt-get install -y "${pkg}"
}

install_via_latest_deb() {
  local pkg="$1"
  local arch="$2"
  local release_json=""
  local asset_url=""
  local asset_name=""
  local deb_path=""

  TMP_DIR="$(mktemp -d)"
  log "Consultando o release mais recente no GitHub..."
  release_json="$(curl -fsSL \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "${GITHUB_API_URL}")"

  asset_url="$(jq -r \
    --arg pkg "${pkg}" \
    --arg arch "${arch}" \
    '.assets[]
     | select(.name | startswith($pkg + "_"))
     | select(.name | endswith("_" + $arch + ".deb"))
     | .browser_download_url' <<<"${release_json}" | head -n 1)"

  asset_name="$(jq -r \
    --arg pkg "${pkg}" \
    --arg arch "${arch}" \
    '.assets[]
     | select(.name | startswith($pkg + "_"))
     | select(.name | endswith("_" + $arch + ".deb"))
     | .name' <<<"${release_json}" | head -n 1)"

  [[ -n "${asset_url}" && "${asset_url}" != "null" ]] || \
    die "Não foi possível localizar um asset .deb para ${pkg} (${arch}) no release mais recente."

  deb_path="${TMP_DIR}/${asset_name}"

  log "Baixando ${asset_name}..."
  curl -fL --output "${deb_path}" "${asset_url}"

  log "Instalando pacote local com dpkg..."
  dpkg -i "${deb_path}" || true

  log "Corrigindo dependências pendentes com APT..."
  apt-get install -f -y
}

verify_installation() {
  local pkg="$1"

  package_installed "${pkg}" || die "O pacote ${pkg} não foi instalado corretamente."

  log "Pacote instalado com sucesso: ${pkg}"
  log "Versão instalada: $(installed_version "${pkg}")"

  if [[ -x "/usr/bin/${pkg}" ]]; then
    log "Executável detectado em /usr/bin/${pkg}"
  else
    warn "Pacote instalado, mas /usr/bin/${pkg} não foi encontrado. Isso pode ser normal, dependendo do empacotamento."
  fi
}

main() {
  local variant="vanilla"
  local method="auto"
  local pkg=""
  local arch=""
  local -a original_args=("$@")

  while (($# > 0)); do
    case "$1" in
      --vanilla)
        variant="vanilla"
        ;;
      --enhanced)
        variant="enhanced"
        ;;
      --auto)
        method="auto"
        ;;
      --repo)
        method="repo"
        ;;
      --deb)
        method="deb"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Opção inválida: $1"
        ;;
    esac
    shift
  done

  ensure_root "${original_args[@]}"
  ensure_apt_based_system
  arch="$(detect_arch)"

  case "${variant}" in
    vanilla)  pkg="notion-app" ;;
    enhanced) pkg="notion-app-enhanced" ;;
    *) die "Variante inválida: ${variant}" ;;
  esac

  log "Sistema detectado: $(os_name)"
  log "Arquitetura detectada: ${arch}"
  log "Variante selecionada: ${variant}"
  log "Método selecionado: ${method}"

  if [[ "${variant}" == "enhanced" ]]; then
    warn "A variante enhanced pode quebrar com mudanças recentes do Notion. Se houver problemas, reinstale com --vanilla."
  fi

  install_prereqs

  case "${method}" in
    repo)
      install_via_repo "${pkg}"
      ;;
    deb)
      install_via_latest_deb "${pkg}" "${arch}"
      ;;
    auto)
      if ! install_via_repo "${pkg}"; then
        warn "Instalação via APT falhou. Tentando o .deb do release mais recente..."
        install_via_latest_deb "${pkg}" "${arch}"
      fi
      ;;
    *)
      die "Método inválido: ${method}"
      ;;
  esac

  verify_installation "${pkg}"
  log "Concluído."
}

main "$@"
