#!/bin/bash

getRootPassword() {
  local psw
  psw="$(op item get Galaxy-Book_4-Ultra --format human-readable --fields password --reveal)"
  echo "$psw"
}