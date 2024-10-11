#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"
export DOCKER_LOCAL="$HOME/.docker"
export MY_DOCKER_UTILS="$MY_CLI/Docker"

# shellcheck source=./../../BashLib/src/helpers/root-password.sh
source "$HELPERS"/root-password.sh

password="$(getRootPassword)"

check_and_link_docker_sock() {
  local docker_desktop
  local default_docker
  docker_desktop="$DOCKER_LOCAL/desktop/docker.sock"
  default_docker="/run/docker.sock"
  if echo "$password" | sudo -S [ ! -e "$default_docker" ]; then
      echo "$password" | sudo -S ln -s "$docker_desktop" "$default_docker"
  fi
}

create_up_docker_service_symlink() {
  local system_service_path="/etc/systemd/system/up-docker.service"

  if [ ! -L "$system_service_path" ]; then
    echo "Symbolic link does not exist. Creating symbolic link."
    if ! echo "$password" | sudo -S ln -sf "$MY_DOCKER_UTILS/up-docker.service" "$system_service_path"; then
      echo "Failed to create symbolic link."
      return 1
    fi
  else
    echo "Symbolic link already exists."
  fi

  return 0
}

manage_up_docker_service() {

  # Reload the systemd manager configuration
  if ! echo "$password" | sudo -S systemctl daemon-reload; then
    echo "Failed to reload the systemd daemon."
    return 1
  fi

  # Enable the rclone service
  if ! echo "$password" | sudo -S systemctl enable up-docker.service; then
    echo "Failed to enable rclone-mount.service."
    return 1
  fi

  # Start the rclone service
  if ! echo "$password" | sudo -S systemctl start up-docker.service; then
    echo "Failed to start rclone-mount.service."
    return 1
  fi

  echo "up-docker.service successfully reloaded, enabled, and started."
  return 0
}
