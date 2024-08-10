#!/bin/bash

# Function definition for the expect script
rclone_reconnect() {
  /usr/bin/expect <<-EOF
    set timeout -1

    spawn rclone config reconnect remote:

    expect "Already have a token - refresh?"
    send -- "y\r"

    expect "Use web browser to automatically authenticate rclone with remote?"
    send -- "y\r"

    expect "Configure this as a Shared Drive (Team Drive)?"
    send -- "n\r"

    expect eof
EOF
}

# Export the function to make it available to other scripts
export -f rclone_reconnect