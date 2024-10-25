#!/bin/bash

export HELPERS="$MY_CLI/BashLib/src/helpers"

# shellcheck source=./../../BashLib/src/helpers/root-password.sh
source "$HELPERS"/root-password.sh

password="$(getRootPassword)"

remove_old_docker() {
  /usr/bin/expect <<EOF
set timeout -1

spawn sudo apt purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
expect "password for"

send -- "$password\r"
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

        send -- "$password\r"
        expect eof
EOF
    else
      echo "$pkg is not installed."
    fi
  done
}

purge_docker_desktop() {
  # Check if docker-desktop is installed
  if dpkg-query -W -f='${Status}' docker-desktop 2>/dev/null | grep -q "install ok installed"; then
    /usr/bin/expect <<EOF
      log_user 1  ;# Enable logging for debugging
      set timeout -1

      spawn sudo apt purge docker-desktop
      expect {
        "password for*" {
          send "$password\r"
          exp_continue
        }
        "Do you want to continue?*" {
          send "y\r"
          exp_continue
        }
        eof {
          exit
        }
      }
EOF
    # Remove any related directories if necessary
    if [ -d /var/lib/docker-desktop ]; then
      echo "$password" | sudo -S rm -rf /var/lib/docker-desktop
    fi

    if [ -d /var/lib/docker ]; then
      echo "$password" | sudo -S rm -rf /var/lib/docker
    fi

    if [ -d /var/lib/containerd ]; then
      echo "$password" | sudo -S rm -rf /var/lib/containerd
    fi

    if echo "$password" | sudo -S [ -L /run/docker.sock ]; then
        echo "$password" | sudo -S rm -f /run/docker.sock
    fi

  else
    echo "docker-desktop is not installed. Nothing to do."
  fi
}

export -f purge_docker_desktop
export -f remove_old_docker
export -f remove_conflict_packages
