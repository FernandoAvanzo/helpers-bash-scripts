#!/bin/bash
# shellcheck disable=SC1091
export PROJECTS=$HOME/Projects/
export HELPERS_BASH_SCRIPTS=$PROJECTS/helpers-bash-scripts
export DOCKER=$HELPERS_BASH_SCRIPTS/Docker

# shellcheck source=./bin/remove_old_installation.sh
source "$DOCKER"/bin/remove_old_installation.sh

purge_docker_desktop