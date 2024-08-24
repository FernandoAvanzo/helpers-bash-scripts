#!/bin/bash

remove_old_docker() {
  /usr/bin/expect <<EOF
set timeout -1

spawn sudo apt purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
expect "password for"

send -- "fer010486\r"
expect eof
EOF

  if [ -d /var/lib/docker ]; then
    sudo rm -rf /var/lib/docker
  fi

  if [ -d /var/lib/containerd ]; then
    sudo rm -rf /var/lib/containerd
  fi
}

remove_conflict_packages() {
  local pkg
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' $pkg 2>/dev/null | grep -q "install ok installed"; then
      /usr/bin/expect <<EOF
set timeout -1

spawn sudo apt-get remove -y $pkg
expect "password for"

send -- "fer010486\r"
expect eof
EOF
    else
      echo "$pkg is not installed."
    fi
  done
}


purge_docker_desktop() {
  /usr/bin/expect <<EOF
set timeout -1

spawn sudo apt purge docker-desktop
expect "password for"

send -- "fer010486\r"
expect eof
EOF

  # Remove any related directories if necessary
  if [ -d /var/lib/docker-desktop ]; then
    sudo rm -rf /var/lib/docker-desktop
  fi

  if [ -d /var/lib/docker ]; then
    sudo rm -rf /var/lib/docker
  fi

  if [ -d /var/lib/containerd ]; then
    sudo rm -rf /var/lib/containerd
  fi
}

export -f purge_docker_desktop
export -f remove_old_docker
export -f remove_conflict_packages