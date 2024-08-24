#!/bin/bash
# shellcheck disable=SC1091
export PROJECTS=$HOME/Projects/
export HELPERS_BASH_SCRIPTS=$PROJECTS/helpers-bash-scripts
export DOCKER=$HELPERS_BASH_SCRIPTS/Docker

# shellcheck source=./bin/install_docker_engine.sh
source "$DOCKER"/bin/install_docker_engine.sh

password="fer010486"

if ls ~/Downloads/docker-desktop-amd64.deb 1> /dev/null 2>&1; then
    echo "Deb file found"
    add_docker_apt_keyrings
    add_docker_repository
    echo $password | sudo -S dpkg -i ~/Downloads/docker-desktop-amd64.deb
    rm -rf ~/Downloads/docker-desktop-amd64.deb
else
    echo "Error: No .deb file found in the Downloads folder."
    return 1
fi