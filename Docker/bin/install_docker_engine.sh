#!/bin/bash

sudo_password="fer010486"

add_docker_apt_keyrings () {
  # The command block to be executed by expect
  expect << EOF
  set timeout -1
  spawn /bin/bash -c "sudo apt update && sudo apt install -y ca-certificates curl && sudo install -m 0755 -d /etc/apt/keyrings && sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && sudo chmod a+r /etc/apt/keyrings/docker.asc"

  expect {
      "password for" { send "$sudo_password\r"; exp_continue }
      eof
  }
EOF
}

add_docker_repository () {
  # The command block to be executed by expect
  expect << EOF
  set timeout -1
  spawn /bin/bash -c "echo \
    \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    \$(. /etc/os-release && echo \\\"\$VERSION_CODENAME\\\") stable\" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && sudo apt-get update"

  expect {
      "password for" { send "$sudo_password\r"; exp_continue }
      eof
  }
EOF
}

install_docker_components () {
  # The command block to be executed by expect
  expect << EOF
  set timeout -1
  spawn /bin/bash -c "sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

  expect {
      "password for" { send "$sudo_password\r"; exp_continue }
      eof
  }
EOF
}

# Function to check whether Docker was installed and run hello-world container
run_docker_hello_world () {
  if command -v docker &> /dev/null
  then
    expect << EOF
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