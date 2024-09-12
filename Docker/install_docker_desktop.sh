#!/bin/bash
# shellcheck disable=SC1091
export PROJECTS=$HOME/Projects/
export HELPERS_BASH_SCRIPTS=$PROJECTS/helpers-bash-scripts
export DOCKER=$HELPERS_BASH_SCRIPTS/Docker

# shellcheck source=./bin/remove_old_installation.sh
source "$DOCKER"/bin/remove_old_installation.sh
# shellcheck source=./bin/install_docker_engine.sh
source "$DOCKER"/bin/install_docker_engine.sh


password="fer010486"
url="https://desktop.docker.com/linux/main/amd64/167172/docker-desktop-amd64.deb?_gl=1*1id00j9*_gcl_au*MTEwNTUzMjc4Ni4xNzIzMzkxMTU2*_ga*ODgwNzUwODQ5LjE3MjMzMDQwOTI.*_ga_XJWPQMJYHQ*MTcyNjE2NDc2OS43LjEuMTcyNjE2NTAzNC40Mi4wLjA."
dest_path="$HOME/Downloads/docker-desktop-amd64.deb"

install_docker_desktop() {
  install_docker_components
  echo $password | sudo -S dpkg -i ~/Downloads/docker-desktop-amd64.deb
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