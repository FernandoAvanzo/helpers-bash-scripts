#!/bin/bash
# shellcheck disable=SC1091
export PROJECTS=$HOME/Projects/
export HELPERS_BASH_SCRIPTS=$PROJECTS/helpers-bash-scripts
export DOCKER=$HELPERS_BASH_SCRIPTS/Docker

# shellcheck source=./remove_old_installation.sh
source "$DOCKER"/bin/remove_old_installation.sh
# shellcheck source=./bin/install_docker_engine.sh
source "$DOCKER"/bin/install_docker_engine.sh

echo "Remove Old Installations"
remove_old_docker
remove_conflict_packages

echo "Install Docker"
add_docker_apt_keyrings
add_docker_repository
install_docker_components

echo "check installations"
run_docker_hello_world