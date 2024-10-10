#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"

# shellcheck source=./../../BashLib/src/helpers/root-password.sh
source "$HELPERS"/root-password.sh

check_and_link_docker_sock() {
  local docker_desktop
  local default_docker
  local password
  password="$(getRootPassword)"
  docker_desktop="$HOME/.docker/desktop/docker.sock"
  default_docker="/run/docker.sock"
  if echo "$password" | sudo -S [ ! -e "$default_docker" ]; then
      echo "$password" | sudo -S ln -s "$docker_desktop" "$default_docker"
  fi
}
