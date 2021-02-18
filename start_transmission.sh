#!/usr/bin/env bash
####################################################################################
# Modifies Transmission settings by changing the port to the VPN one.
# It starts Transmission at the end
####################################################################################

set -eE
failure() {
  local lineno=$1; local msg=$2
  echo "$(basename "$0"): failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### CHECKS & VARIABLES ###############
# Check if the mandatory environment variables are set.
if [[ -z $CONFIG_DIR || -z $PAYLOAD_FILE ]]; then
  echo "$(basename "$0") script requires:"
  echo "CONFIG_DIR    - Configuration directory for PIA"
  echo "PAYLOAD_FILE  - path to PIA payload (port forwarding response) file"
  exit 1
fi

# Check if running as root/sudo
[ ${EUID:-$(id -u)} -eq 0 ] || exec sudo -E "$(readlink -f "$0")" "$@"

# Checks if jq is installed
if ! command -v jq &>/dev/null; then
  echo "jq could not be found"; echo "Please install jq"; exit 1
fi

# Check if the mandatory environment variables are set.
if [[ -z $NETNS_NAME ]]; then
  echo "$(basename "$0") script requires:"
  echo "NETNS_NAME  - name of the namespace"
  exit 1
fi

readonly _TRANSMISSION_CONFIG_DIR=/home/felipe/.config/transmission
readonly _TRANSMISSION_SETTINGS=$_TRANSMISSION_CONFIG_DIR/settings.json
readonly _TRANSMISSION_LOG=/var/log/transmission.log

# Checks that Transmission settings file exists
if [[ ! -f $_TRANSMISSION_SETTINGS ]]; then
  >&2 echo "Cannot modify Transmission settings. $_TRANSMISSION_SETTINGS not found"; exit 1
fi
# Check that Payload file exists
if [[ ! -f $PAYLOAD_FILE ]]; then
  >&2 echo "Cannot find Payload file: $PAYLOAD_FILE"; exit 1
fi

readonly _FORWARDING_PORT=$(jq -r '.payload' < "$PAYLOAD_FILE" | base64 -d | jq -r '.port')
readonly _WEB_PORT=$(jq -r '."rpc-port"' $_TRANSMISSION_SETTINGS)

if [[ $DEBUG == true ]]; then
  echo "VPN port forwarded, port $_FORWARDING_PORT is being used"
  echo "Web interface port $_WEB_PORT is being used"
fi

##########################################
# Stop transmission-daemon if it's active
if pidof transmission-daemon > /dev/null; then
  if [[ $DEBUG == true ]]; then echo "transmission-daemon is active. Stopping..."; fi
  kill -9 "$(pidof transmission-daemon)"
fi

# Modifies the Transmission settings with the new port
tempSettings=$(jq '."peer-port"'="$_FORWARDING_PORT" $_TRANSMISSION_SETTINGS)
printf "%s" "$tempSettings" > $_TRANSMISSION_SETTINGS

# No longer needed to allow firewall port inside netns
# ufw allow "$_FORWARDING_PORT/tcp" > /dev/null

# Restart transmission
ip netns exec "$NETNS_NAME"\
 /usr/bin/transmission-daemon --log-error\
 --config-dir $_TRANSMISSION_CONFIG_DIR\
 --logfile $_TRANSMISSION_LOG

# Start redirection to access web interface
socat tcp-listen:"$_WEB_PORT",fork,reuseaddr\
  exec:"ip netns exec $NETNS_NAME socat STDIO \"tcp-connect:127.0.0.1:$_WEB_PORT\"",nofork > /dev/null 2>&1 &
