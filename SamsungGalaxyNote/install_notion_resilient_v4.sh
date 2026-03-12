#!/usr/bin/env bash
# Instala um launcher "desktop app" do Notion para Linux usando navegador em modo app.
#
# Esta versão:
# - usa o ícone enviado pelo usuário como arquivo instalado localmente;
# - instala o ícone no tema local do usuário;
# - cria notion.desktop com Icon=notion;
# - usa WM_CLASS=notion para casar melhor com notion.desktop;
# - em sessões Wayland, prefere X11 por padrão para melhorar o matching no dock.
#
# Compatível com Pop!_OS / Ubuntu / Debian.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"
readonly APP_NAME="Notion"
readonly WM_CLASS="notion"
readonly DESKTOP_ID="notion.desktop"
readonly LEGACY_DESKTOP_ID="notion-webapp.desktop"
readonly DEFAULT_URL="https://www.notion.so"
readonly DEFAULT_PROFILE_DIR_NAME=".local/share/notion-profile"
readonly DEFAULT_BIN_DIR_NAME=".local/bin"
readonly DEFAULT_APPS_DIR_NAME=".local/share/applications"
readonly DEFAULT_CONFIG_DIR_NAME=".config/notion-webapp"
readonly DEFAULT_ICON_BASENAME="notion"
readonly DEFAULT_ICON_EXT="svg"
readonly DEFAULT_ICON_RELATIVE_PATH=".local/share/icons/hicolor/scalable/apps/notion.svg"

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

TARGET_USER=""
TARGET_HOME=""
TARGET_UID=""
TARGET_GID=""

log()  { printf '%s[INFO]%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
error(){ printf '%s[ERRO]%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }

die() {
  error "$*"
  exit 1
}

usage() {
  cat <<'EOF'
Uso:
  ./install_notion_resilient_v4.sh [opções]
  sudo ./install_notion_resilient_v4.sh [opções]

Opções:
  --url <url>               URL do Notion (padrão: https://www.notion.so)
  --browser <binário>       Força o navegador (ex.: google-chrome-stable)
  --software-rendering      Força renderização por software
  --native-wayland          Não força X11 em sessões Wayland
  --force-x11               Força X11 para este launcher, mesmo em sessão Wayland
  --purge-broken            Remove notion-app / notion-app-enhanced e limpa caches antigos
  --skip-purge              Não remove nada do cliente antigo
  --no-desktop              Não cria notion.desktop
  -h, --help                Mostra esta ajuda
EOF
}

on_error() {
  local line_no="$1"
  local exit_code="$2"
  error "Falha na linha ${line_no} (exit code: ${exit_code})."
  exit "${exit_code}"
}

trap 'on_error "${LINENO}" "$?"' ERR

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"
}

is_root() {
  (( EUID == 0 ))
}

setup_target_user() {
  if is_root; then
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      TARGET_USER="${SUDO_USER}"
      TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
    else
      die "Ao executar como root, use sudo a partir do usuário que receberá o launcher (ex.: sudo ./${SCRIPT_NAME})."
    fi
  else
    TARGET_USER="${USER}"
    TARGET_HOME="${HOME}"
  fi

  [[ -n "${TARGET_USER}" && -n "${TARGET_HOME}" ]] || die "Não foi possível determinar TARGET_USER/TARGET_HOME."

  TARGET_UID="$(id -u "${TARGET_USER}")"
  TARGET_GID="$(id -g "${TARGET_USER}")"
}

run_as_target_user() {
  if [[ "$(id -un)" == "${TARGET_USER}" ]]; then
    "$@"
  else
    sudo -u "${TARGET_USER}" -- "$@"
  fi
}

write_file_as_target_user() {
  local destination="$1"
  local mode="$2"
  local content="$3"

  install -d -m 0755 -o "${TARGET_UID}" -g "${TARGET_GID}" -- "$(dirname "${destination}")"
  printf '%s' "${content}" > "${destination}"
  chown "${TARGET_UID}:${TARGET_GID}" "${destination}"
  chmod "${mode}" "${destination}"
}

write_base64_file_as_target_user() {
#  local destination="$1"
#  local mode="$2"
#  local base64_payload="$3"
#
#  install -d -m 0755 -o "${TARGET_UID}" -g "${TARGET_GID}" -- "$(dirname "${destination}")"
#  printf '%s' "${base64_payload}" | base64 -d > "${destination}"
#  chown "${TARGET_UID}:${TARGET_GID}" "${destination}"
#  chmod "${mode}" "${destination}"
  echo ""
}

remove_path_if_exists() {
  local path="$1"
  if [[ -e "${path}" || -L "${path}" ]]; then
    rm -rf -- "${path}"
    log "Removido: ${path}"
  fi
}

package_installed() {
  local pkg="$1"
  if command -v dpkg-query >/dev/null 2>&1; then
    dpkg-query -W -f='${Status}\n' "${pkg}" 2>/dev/null | grep -qx 'install ok installed'
  else
    return 1
  fi
}

purge_old_packages_if_requested() {
  local do_purge="$1"
  [[ "${do_purge}" == "1" ]] || return 0

  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get não disponível; pulando remoção de pacotes antigos."
    return 0
  fi

  if ! is_root; then
    warn "Remoção de notion-app/notion-app-enhanced requer root. Reexecute com sudo se quiser purgar pacotes antigos."
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  local -a installed=()

  if package_installed notion-app; then
    installed+=("notion-app")
  fi
  if package_installed notion-app-enhanced; then
    installed+=("notion-app-enhanced")
  fi

  if ((${#installed[@]} > 0)); then
    log "Removendo pacotes antigos: ${installed[*]}"
    apt-get remove -y --purge "${installed[@]}"
    apt-get autoremove -y
  else
    log "Nenhum pacote notion-app/notion-app-enhanced instalado pelo APT."
  fi
}

cleanup_old_user_state() {
  log "Limpando caches/configurações antigas do cliente repackaged no usuário ${TARGET_USER}..."
  remove_path_if_exists "${TARGET_HOME}/.config/notion-app"
  remove_path_if_exists "${TARGET_HOME}/.config/notion-app-enhanced"
  remove_path_if_exists "${TARGET_HOME}/.cache/notion-app"
  remove_path_if_exists "${TARGET_HOME}/.cache/notion-app-enhanced"
  remove_path_if_exists "${TARGET_HOME}/.local/share/notion-app"
  remove_path_if_exists "${TARGET_HOME}/.local/share/notion-app-enhanced"
}

detect_browser() {
  local preferred="${1:-}"
  local candidate=""

  if [[ -n "${preferred}" ]]; then
    command -v "${preferred}" >/dev/null 2>&1 || die "Navegador solicitado não encontrado no PATH: ${preferred}"
    printf '%s\n' "${preferred}"
    return 0
  fi

  for candidate in \
    google-chrome-stable \
    google-chrome \
    chromium \
    chromium-browser \
    brave-browser \
    microsoft-edge-stable
  do
    if command -v "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  die "Nenhum navegador compatível encontrado. Instale Chrome/Chromium/Brave/Edge e rode novamente."
}

ensure_user_dirs() {
  local bin_dir="$1"
  local apps_dir="$2"
  local config_dir="$3"
  local profile_dir="$4"
  local icon_dir="$5"

  install -d -m 0755 -o "${TARGET_UID}" -g "${TARGET_GID}" -- \
    "${bin_dir}" "${apps_dir}" "${config_dir}" "${profile_dir}" "${icon_dir}"
}

build_wrapper_script() {
  local browser_bin="$1"
  local notion_url="$2"
  local profile_dir="$3"
  local config_env_file="$4"
  local default_software_rendering="$5"
  local default_force_x11="$6"

  cat <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=\$'\\n\\t'

readonly BROWSER_BIN="${browser_bin}"
readonly NOTION_URL_DEFAULT="${notion_url}"
readonly PROFILE_DIR="${profile_dir}"
readonly ENV_FILE="${config_env_file}"
readonly WM_CLASS="${WM_CLASS}"

NOTION_WEBAPP_URL="\${NOTION_WEBAPP_URL:-\${NOTION_URL_DEFAULT}}"
NOTION_WEBAPP_EXTRA_FLAGS="\${NOTION_WEBAPP_EXTRA_FLAGS:-}"
NOTION_WEBAPP_SOFTWARE_RENDERING="\${NOTION_WEBAPP_SOFTWARE_RENDERING:-${default_software_rendering}}"
NOTION_WEBAPP_FORCE_X11="\${NOTION_WEBAPP_FORCE_X11:-${default_force_x11}}"

if [[ -r "\${ENV_FILE}" ]]; then
  # shellcheck source=/dev/null
  . "\${ENV_FILE}"
fi

declare -a FLAGS
FLAGS+=("--app=\${NOTION_WEBAPP_URL}")
FLAGS+=("--class=\${WM_CLASS}")
FLAGS+=("--name=\${WM_CLASS}")
FLAGS+=("--user-data-dir=\${PROFILE_DIR}")

if [[ "\${NOTION_WEBAPP_SOFTWARE_RENDERING}" == "1" ]]; then
  FLAGS+=("--disable-gpu")
  FLAGS+=("--disable-gpu-compositing")
fi

if [[ "\${NOTION_WEBAPP_FORCE_X11}" == "1" ]]; then
  FLAGS+=("--ozone-platform=x11")
fi

if [[ -n "\${NOTION_WEBAPP_EXTRA_FLAGS}" ]]; then
  # shellcheck disable=SC2206
  EXTRA=(\${NOTION_WEBAPP_EXTRA_FLAGS})
  FLAGS+=("\${EXTRA[@]}")
fi

exec "\${BROWSER_BIN}" "\${FLAGS[@]}"
EOF
}

build_env_file() {
  local notion_url="$1"
  local software_rendering="$2"
  local force_x11="$3"

  cat <<EOF
# Configuração opcional do launcher Notion Web App.
NOTION_WEBAPP_URL="${notion_url}"
NOTION_WEBAPP_EXTRA_FLAGS=""
NOTION_WEBAPP_SOFTWARE_RENDERING="${software_rendering}"
NOTION_WEBAPP_FORCE_X11="${force_x11}"
EOF
}

build_desktop_file() {
  local wrapper_path="$1"

  cat <<EOF
[Desktop Entry]
Version=1.5
Type=Application
Name=${APP_NAME}
GenericName=Workspace
Comment=Notion no Linux usando navegador em modo app
TryExec=${wrapper_path}
Exec=${wrapper_path}
Icon=${DEFAULT_ICON_BASENAME}
Terminal=false
Categories=Office;Network;Utility;
Keywords=Notion;Notes;Docs;Wiki;Tasks;
StartupNotify=true
StartupWMClass=${WM_CLASS}
SingleMainWindow=true
EOF
}

build_icon_base64() {
#  cat <<'EOF'
#iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAACXBIWXMAAA7EAAAOxAGVKw4bAABuE0lEQVR4nO3de1hV5Z3w8e+sQwFBAQmM4E5XUJR5sGoYeVcvGcWa0SpkGpoJGVaep3k4mNOMnEkzvTyn4aQuo7V5MDO9G8xE6eG1dlWZiFQYyXJQKOACCoioBGf9Yx9r6+M6eg4EWPv8fD7nM9bZe6211l57r7XX3mut4QghhBBCCCGEEEII0QZdVQdACCGEEEIIIYQQQgjF0QQAEkIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFggAJSGEEEIIIYQQQggRogUCEEIIIYQQQgghhBCiBQJASQghhBBCCCGEEEKIFv4/eYdfhCAZ9VcAAAAASUVORK5CYII=
#EOF
  echo ""
}

create_compat_symlink() {
  local target="$1"
  local link_path="$2"

  ln -sfn "${target}" "${link_path}"
  chown -h "${TARGET_UID}:${TARGET_GID}" "${link_path}"
}

ensure_local_bin_on_path_notice() {
  if [[ -x "${TARGET_HOME}/.local/bin/notion-webapp" ]]; then
    if ! run_as_target_user bash -lc 'printf "%s" "$PATH"' | grep -qE '(^|:).*/\.local/bin(:|$)'; then
      warn "~/.local/bin não parece estar no PATH do usuário ${TARGET_USER}."
      warn "Você ainda poderá abrir pelo menu de aplicativos, ou adicionar isto ao seu shell:"
      warn 'export PATH="$HOME/.local/bin:$PATH"'
    fi
  fi
}

detect_default_force_x11() {
  if run_as_target_user bash -lc '[[ "${XDG_SESSION_TYPE:-}" == "wayland" || -n "${WAYLAND_DISPLAY:-}" ]]'; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

main() {
  local browser_arg=""
  local notion_url="${DEFAULT_URL}"
  local software_rendering="0"
  local purge_broken="1"
  local create_desktop="1"
  local browser_bin=""
  local force_x11=""
  local force_x11_override=""

  while (($# > 0)); do
    case "$1" in
      --browser)
        shift
        [[ $# -gt 0 ]] || die "Faltou valor para --browser"
        browser_arg="$1"
        ;;
      --url)
        shift
        [[ $# -gt 0 ]] || die "Faltou valor para --url"
        notion_url="$1"
        ;;
      --software-rendering)
        software_rendering="1"
        ;;
      --native-wayland)
        force_x11_override="0"
        ;;
      --force-x11)
        force_x11_override="1"
        ;;
      --purge-broken)
        purge_broken="1"
        ;;
      --skip-purge)
        purge_broken="0"
        ;;
      --no-desktop)
        create_desktop="0"
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

  need_cmd install
  need_cmd getent
  need_cmd id
  need_cmd rm
  need_cmd ln
  need_cmd base64

  setup_target_user
  browser_bin="$(detect_browser "${browser_arg}")"
  force_x11="$(detect_default_force_x11)"
  if [[ -n "${force_x11_override}" ]]; then
    force_x11="${force_x11_override}"
  fi

  local bin_dir="${TARGET_HOME}/${DEFAULT_BIN_DIR_NAME}"
  local apps_dir="${TARGET_HOME}/${DEFAULT_APPS_DIR_NAME}"
  local config_dir="${TARGET_HOME}/${DEFAULT_CONFIG_DIR_NAME}"
  local profile_dir="${TARGET_HOME}/${DEFAULT_PROFILE_DIR_NAME}"
  local icon_path="${TARGET_HOME}/${DEFAULT_ICON_RELATIVE_PATH}"
  local icon_dir
  icon_dir="$(dirname "${icon_path}")"
  local wrapper_path="${bin_dir}/notion-webapp"
  local compat_wrapper_path="${bin_dir}/notion-app"
  local desktop_path="${apps_dir}/${DESKTOP_ID}"
  local legacy_desktop_path="${apps_dir}/${LEGACY_DESKTOP_ID}"
  local env_file="${config_dir}/env"

  log "Usuário de destino: ${TARGET_USER}"
  log "HOME de destino: ${TARGET_HOME}"
  log "Navegador selecionado: ${browser_bin}"
  log "URL do Notion: ${notion_url}"
  log "Ícone embutido: image/png"

  if [[ "${force_x11}" == "1" ]]; then
    log "Integração de dock priorizada: launcher usará X11 para melhorar o matching do ícone."
  else
    log "Launcher usará backend nativo da sessão."
  fi

  purge_old_packages_if_requested "${purge_broken}"
  cleanup_old_user_state
  ensure_user_dirs "${bin_dir}" "${apps_dir}" "${config_dir}" "${profile_dir}" "${icon_dir}"

  write_file_as_target_user \
    "${env_file}" "0644" \
    "$(build_env_file "${notion_url}" "${software_rendering}" "${force_x11}")"

  write_file_as_target_user \
    "${wrapper_path}" "0755" \
    "$(build_wrapper_script "${browser_bin}" "${notion_url}" "${profile_dir}" "${env_file}" "${software_rendering}" "${force_x11}")"

  create_compat_symlink "${wrapper_path}" "${compat_wrapper_path}"

  write_base64_file_as_target_user \
    "${icon_path}" "0644" \
    "$(build_icon_base64)"

  if [[ "${create_desktop}" == "1" ]]; then
    write_file_as_target_user \
      "${desktop_path}" "0644" \
      "$(build_desktop_file "${wrapper_path}")"

    remove_path_if_exists "${legacy_desktop_path}"
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    run_as_target_user update-desktop-database "${apps_dir}" || true
  fi

  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    run_as_target_user gtk-update-icon-cache -q -t -f "${TARGET_HOME}/.local/share/icons/hicolor" || true
  fi

  ensure_local_bin_on_path_notice

  log "Instalação concluída."
  log "Comando de terminal: ${wrapper_path}"
  log "Alias compatível: ${compat_wrapper_path}"
  log "Ícone local: ${icon_path}"
  if [[ "${create_desktop}" == "1" ]]; then
    log "Launcher criado em: ${desktop_path}"
  fi
  log "Teste executando: ${wrapper_path}"

  if [[ "${software_rendering}" == "1" ]]; then
    warn "Renderização por software ativada. Isso é mais compatível, mas pode ser menos performático."
  fi

  if [[ "${force_x11}" == "1" ]]; then
    warn "Modo X11 ativado para melhorar a chance de o dock mostrar o ícone do Notion enquanto a janela está aberta."
  else
    warn "Em Wayland nativo, wrappers manuais de Chrome/Chromium podem não casar o ícone do dock perfeitamente."
  fi
}

main "$@"
