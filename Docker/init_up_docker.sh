#!/bin/bash
export MY_DOCKER_LIBS="$MY_CLI/Docker/bin"

# shellcheck source=./bin/docker-utils.sh
source "$MY_DOCKER_LIBS/docker-utils.sh"

create_up_docker_service_symlink
manage_up_docker_service
