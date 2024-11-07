#!/bin/bash

export MY_DOCKER_LIBS="$MY_CLI/Docker/bin"

# shellcheck source=./bin/docker-utils.sh
source "$MY_DOCKER_LIBS/docker-utils.sh"

check_and_link_docker_sock

#install Script
#echo "$(get-root-psw)" | sudo -S ln -sf "$MY_CLI"/Docker/set-docker-default.sh /usr/bin/set-docker-default