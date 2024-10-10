#!/bin/bash
# shellcheck disable=SC1091
export PROJECTS=$HOME/Projects/
export HELPERS_BASH_SCRIPTS=$PROJECTS/helpers-bash-scripts
export HELPERS="$MY_CLI/BashLib/src/helpers"
export DOCKER=$HELPERS_BASH_SCRIPTS/Docker

# shellcheck source=./bin/remove_old_installation.sh
source "$DOCKER"/bin/remove_old_installation.sh
# shellcheck source=./bin/install_docker_engine.sh
source "$DOCKER"/bin/install_docker_engine.sh
# shellcheck source=./bin/docker-utils.sh
source "$DOCKER"/bin/docker-utils.sh
# shellcheck source=./helpers/root-password.sh
source "$HELPERS"/root-password.sh

password="$(getRootPassword)"
url="https://desktop.docker.com/linux/main/amd64/170107/docker-desktop-amd64.deb?_gl=1*8xm1jd*_ga*NDA2NDY4MzcyLjE3MjgyNTAyNjk.*_ga_XJWPQMJYHQ*MTcyODU2NTM3Ny4yLjEuMTcyODU2NTk5OS41OS4wLjA."
dest_path="$HOME/Downloads/docker-desktop-amd64.deb"

install_docker_desktop() {
  install_docker_components
  echo "$password" | sudo -S dpkg -i ~/Downloads/docker-desktop-amd64.deb
  rm -rf ~/Downloads/docker-desktop-amd64.deb
}

purge_docker_desktop

if check_docker_setup; then
  echo "Docker APT keyrings and repository are already set up."
else
  echo "Setting up Docker APT keyrings and repository..."
  add_docker_apt_keyrings
  add_docker_repository
fi

if ls ~/Downloads/docker-desktop-amd64.deb 1>/dev/null 2>&1; then
  echo "Deb file found"
  install_docker_desktop
else
  echo "Downloading Docker Desktop .deb package..."
  wget -O "$dest_path" "$url"
  install_docker_desktop
fi

check_and_link_docker_sock
