#!/bin/bash

export MY_DOCKER_LIBS="$MY_CLI/Docker/bin"

# shellcheck source=./bin/docker-utils.sh
source "$MY_DOCKER_LIBS/docker-utils.sh"

check_and_link_docker_sock
