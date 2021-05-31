#!/usr/bin/env bash
####################################################################################
# Modifies Transmission settings by changing the port to the VPN one.
# It starts Transmission at the end
####################################################################################

set -eE
failure() {
  local lineno=$1; local msg=$2
  echo "$(basename "$0"): failed at ${lineno}: ${msg}"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### CHECKS & VARIABLES ###############
# Check if running as root/sudo
[ "${EUID:-$(id -u)}" -eq 0 ] || exec sudo -E "$(readlink -f "$0")" "$@"

_debug=${DEBUG:-false}

# Checks if jq is installed
if ! command -v jq &>/dev/null; then
  echo "jq could not be found"; echo "Please install jq"; exit 1
fi

readonly transmission_config_dir=/home/felipe/.config/transmission
readonly transmission_settings=${transmission_config_dir}/settings.json
readonly transmission_log=/var/log/transmission.log

# Checks that Transmission settings file exists
if [[ ! -f ${transmission_settings} ]]; then
  >&2 echo "Cannot modify Transmission settings. ${transmission_settings} not found"; exit 1
fi
# Check that Payload file exists
if [[ ! -f ${PAYLOAD_FILE:?} ]]; then
  >&2 echo "Cannot find Payload file: ${PAYLOAD_FILE}"; exit 1
fi

forwarding_port=$(jq -r '.payload' < "${PAYLOAD_FILE}" | base64 -d | jq -r '.port')
web_port=$(jq -r '."rpc-port"' "${transmission_settings}")
readonly forwarding_port
readonly web_port

if [[ ${_debug} == true ]]; then
  echo "VPN port forwarded, port ${forwarding_port} is being used"
  echo "Web interface port ${web_port} is being used"
fi

##########################################
# Stop transmission-daemon if it's active
if pidof transmission-daemon > /dev/null; then
  if [[ ${_debug} == true ]]; then echo "transmission-daemon is active. Stopping..."; fi
  kill -9 "$(pidof transmission-daemon)"
fi

# Modifies the Transmission settings with the new port
tempSettings=$(jq '."peer-port"'="${forwarding_port}" "${transmission_settings}")
printf "%s" "${tempSettings}" > "${transmission_settings}"

# Restart transmission
ip netns exec "${NETNS_NAME:?}"\
 /usr/bin/transmission-daemon --log-error\
 --config-dir "${transmission_config_dir}"\
 --logfile "${transmission_log}"

# Start redirection to access web interface
socat tcp-listen:"${web_port}",fork,reuseaddr\
  exec:"ip netns exec ${NETNS_NAME} socat STDIO \"tcp-connect:127.0.0.1:${web_port}\"",nofork > /dev/null 2>&1 &
