#!/bin/bash

export MY_NODE_LIB="$MY_CLI/Node/bin"

# shellcheck source=./bin/node-utils.sh
source "$MY_NODE_LIB/node-utils.sh"

purge_all_node_installations
install_node_dependencies
install_node_8-2-1
