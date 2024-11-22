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
# shellcheck source=./../../BashLib/src/helpers/tool_check_script.sh
source "$HELPERS"/tool_check_script.sh


password="$(getRootPassword)"
url="https://desktop.docker.com/linux/main/amd64/175267/docker-desktop-amd64.deb?_gl=1*3as6qw*_ga*MTUwMDgyNjEzNC4xNzMwMzE1MjY3*_ga_XJWPQMJYHQ*MTczMjI5OTU0MS4yLjEuMTczMjI5OTU0Mi41OS4wLjA."
dest_path="$HOME/Downloads/docker-desktop-amd64.deb"

install_docker_desktop() {
  install_docker_components
  echo "$password" | sudo -S dpkg -i ~/Downloads/docker-desktop-amd64.deb
  rm -rf ~/Downloads/docker-desktop-amd64.deb
}

check_and_install_expect

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
