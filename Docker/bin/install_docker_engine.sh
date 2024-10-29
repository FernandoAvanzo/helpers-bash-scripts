#!/bin/bash

export HELPERS="$MY_CLI/BashLib/src/helpers"

# shellcheck source=./../../BashLib/src/helpers/root-password.sh
source "$HELPERS"/root-password.sh

sudo_password="$(getRootPassword)"

add_docker_apt_keyrings() {
  # The command block to be executed by expect
  expect <<EOF
  set timeout -1
  spawn /bin/bash -c "sudo apt update && sudo apt install -y ca-certificates curl && sudo install -m 0755 -d /etc/apt/keyrings && sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && sudo chmod a+r /etc/apt/keyrings/docker.asc"

  expect {
      "password for" { send "$sudo_password\r"; exp_continue }
      eof
  }
EOF
}

add_docker_repository() {
  local password
  password="$(getRootPassword)"
  echo "$password" | sudo -S apt-get update
  echo "$password" | sudo -S apt-get install ca-certificates curl
  echo "$password" | sudo -S install -m 0755 -d /etc/apt/keyrings
  echo "$password" | sudo -S curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  echo "$password" | sudo -S chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  echo "$password" | sudo -S apt-get update
}

# Function to check if Docker APT keyrings and repository are already set up
check_docker_setup() {
  echo "$sudo_password" | sudo -S apt install --fix-broken -y
  # Check if the docker keyring file exists and is readable
  if [ -r /etc/apt/keyrings/docker.asc ]; then
    # Check if the Docker repository is in the sources list
    if grep -q "^deb .*/download.docker.com/linux/ubuntu" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
      return 0 # True
    fi
  fi
  return 1 # False
}

install_docker_components() {
echo "$sudo_password" | sudo -S apt install -y --fix-broken

  # The command block to be executed by expect
  expect <<EOF
  set timeout -1
  spawn /bin/bash -c "sudo apt install -y docker-ce-cli libqrencode4 uidmap tree qrencode xclip pass qemu-system-x86"

  expect {
      "password for" { send "$sudo_password\r"; exp_continue }
      eof
  }
EOF

echo "$sudo_password" | sudo -S apt install -y qemu-system-x86
echo "$sudo_password" | sudo -S apt install -y pass
echo "$sudo_password" | sudo -S apt install -y uidmap
echo "$sudo_password" | sudo -S apt install -y docker-ce-cli

}

# Function to check whether Docker was installed and run hello-world container
run_docker_hello_world() {
  if command -v docker &>/dev/null; then
    expect <<EOF
    set timeout -1
    spawn sudo docker run hello-world

    expect {
        "password for" { send "$sudo_password\r"; exp_continue }
        eof
    }
EOF
    echo "Docker is successfully installed and the hello-world container ran."
  else
    echo "Docker installation failed, please check the previous steps."
  fi
}

export -f add_docker_apt_keyrings
export -f add_docker_repository
export -f install_docker_components
export -f run_docker_hello_world
