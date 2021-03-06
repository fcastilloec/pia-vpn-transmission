#!/usr/bin/env bash
####################################################################################
# It stops Transmission and modifies it's settings back to the default port
####################################################################################

set -eE
failure() {
  local lineno=$1; local msg=$2
  echo "$(basename "$0"): failed at ${lineno}: ${msg}"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### CHECKS & VARIABLES ###############
# Check if JQ is installed, needed to handle JSON
if ! command -v jq &>/dev/null; then
  echo "jq could not be found"; echo "Please install jq"; exit 1
fi

_debug=${DEBUG:-false}
settings=/home/felipe/.config/transmission/settings.json
default_port="62021" # default port when not using VPN

# Checks that Transmission settings file exist
if [[ ! -f ${settings} ]]; then
  >&2 echo "Cannot modify Transmission settings. ${settings} not found"; exit 1
fi

# Check if running as root/sudo
[ "${EUID:-$(id -u)}" -eq 0 ] || exec sudo -E "$(readlink -f "$0")" "$@"

##########################################
# Stop transmission-daemon if it's active
if pidof transmission-daemon > /dev/null; then
  if [[ ${_debug} == true ]]; then echo "transmission-daemon is active. Stopping..."; fi
  # Kill all process inside the namespace or at least just transmission
  ip netns pids "${NETNS_NAME:?}" | xargs kill -9 > /dev/null 2>&1 || kill -9 "$(pidof transmission-daemon)"
fi

# Changes port back to its default
port=$(jq -r '."peer-port"' "${settings}") # retrieve port from settings file
if [[ ${_debug} == true ]]; then echo "VPN port inside Transmission settings file: ${port}"; fi

# Check if port needs modifying
if (( port == default_port )); then
  if [[ ${_debug} == true ]]; then echo "Port rule is already at default value"; fi
  exit 0
fi

tempSettings=$(jq '."peer-port"'="${default_port}" "${settings}")
printf "%s" "${tempSettings}" > "${settings}"

if [[ ${_debug} == true ]]; then echo "Port rule back to default value"; fi
