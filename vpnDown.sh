#!/usr/bin/env bash

# Exit codes:
# 1:  Can't modify Transmission settings file.
# 3:  Missing required dependencies.

set -eE -o functrace

failure() {
  local lineno=$1
  local msg=$2
  echo "$me: failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

me=$(basename "$0") # name of this script use for debugging

# Check if running as root/sudo
if [ ${EUID:-$(id -u)} -eq 0 ]; then
  if [ -n "$DEBUG" ]; then printf "%s: running as sudo\n" "$me"; fi
else
  if [ -n "$DEBUG" ]; then printf "%s: NOT running as sudo\n" "$me"; fi
  exec sudo DEBUG="$DEBUG" "$0" "$@"
fi

# Check if JQ is installed, needed to handle JSON
if ! command -v jq > /dev/null 2>&1; then
  echo "JQ not installed. Please install before proceeding"
  exit 3
fi

settings="/home/felipe/.config/transmission/settings.json"
port="62021"

# Kills transmission if running
if systemctl -q is-active transmission-daemon.service; then
  if [ -n "$DEBUG" ]; then printf "%s: transmission-daemon is active\n" "$me"; fi
  set +e; systemctl stop transmission-daemon.service; set -e
fi

# Changes port back to its default
if [ -e "$settings" ]; then
  vpnPort=$(jq '."peer-port"' $settings)
  if [ -n "$DEBUG" ]; then printf "%s: VPN port inside Transmission settings file: %d\n" "$me" "$vpnPort"; fi

  if [ "$vpnPort" != "$port" ]; then
    tempSettings=$(jq '."peer-port"'="$port" $settings)
    printf "%s" "$tempSettings" > $settings

    # deletes UFW rule only if it's not the default port number
    ufw delete allow "$vpnPort/tcp"

    printf "Port rule back to default value\n"
  else
    printf "Port rule is already at default value\n"
  fi
else
  printf "Transmission settings file not found\n"
  exit 1
fi

exit 0
