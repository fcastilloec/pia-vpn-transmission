#!/usr/bin/env bash
####################################################################################
# It stops Transmission and modifies it's settings back to the default port
####################################################################################

set -eE
failure() {
  local lineno=$1; local msg=$2
  echo "$(basename "$0"): failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### CHECKS & VARIABLES ###############
# Check if JQ is installed, needed to handle JSON
if ! command -v jq &>/dev/null; then
  echo "jq could not be found"; echo "Please install jq"; exit 1
fi

SETTINGS=/home/felipe/.config/transmission/settings.json
DEFAULT_PORT="62021" # default port when not using VPN

# Checks that Transmission settings file exist
if [[ ! -f $SETTINGS ]]; then
  >&2 echo "Cannot modify Transmission settings. $SETTINGS not found"; exit 1
fi

# Check if running as root/sudo
[ ${EUID:-$(id -u)} -eq 0 ] || exec sudo DEBUG="$DEBUG" "$0" "$@"

##########################################
# Stop transmission-daemon if it's active
if pidof transmission-daemon > /dev/null; then
  [[ -n $DEBUG ]] && echo "transmission-daemon is active. Stopping..."
  kill -9 "$(pidof transmission-daemon)"
fi

# Changes port back to its default
PORT=$(jq -r '."peer-port"' $SETTINGS) # retrieve port from settings file
[[ -n $DEBUG ]] && echo "VPN port inside Transmission settings file: $PORT"

# Check if port needs modifiying
if (( PORT == DEFAULT_PORT )); then
  [[ -n $DEBUG ]] && echo "Port rule is already at default value"
  exit 0
fi

tempSettings=$(jq '."peer-port"'="$DEFAULT_PORT" $SETTINGS)
printf "%s" "$tempSettings" > $SETTINGS

# deletes UFW rule of VPN port
# ufw delete allow "$PORT/tcp" > /dev/null

echo "Port rule back to default value"
