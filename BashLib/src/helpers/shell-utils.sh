#!/bin/bash

extract_user_shell() {
  local shell_path
  local shell_name
  shell_path="$SHELL"
  shell_name=$(basename "$shell_path")
  echo "$shell_name"
}
