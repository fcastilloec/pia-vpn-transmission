#!/usr/bin/env bash
####################################################################################
# Modifies Transmission settings by changing the port to the VPN one.
# It starts Transmission at the end
####################################################################################

set -eE
failure() {
  local lineno=$1; local msg=$2
  [[ "$-" =~ .*e.* ]] && echo "$(basename "$0"): failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### CHECKS & VARIABLES ###############
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

SETTINGS=/home/felipe/.config/transmission/settings.json
PAYLOAD_FILE=/home/felipe/.config/pia_vpn/payload.json
PORT=$(jq -r '.payload' < $PAYLOAD_FILE | base64 -d | jq -r '.port')

# Checks that Transmission settings file exist
if [[ ! -f $SETTINGS ]]; then
  >&2 echo "Cannot modify Transmission settings. $SETTINGS not found"; exit 1
fi

##########################################
# Stop transmission-daemon if it's active
if pidof transmission-daemon > /dev/null; then
  if [[ -n $DEBUG ]]; then echo "transmission-daemon is active. Stopping..."; fi
  kill -9 "$(pidof transmission-daemon)"
fi

# Modifies the Transmission settings with the new port
tempSettings=$(jq '."peer-port"'="$PORT" $SETTINGS)
printf "%s" "$tempSettings" > $SETTINGS

# Adds the port to UFW
# ufw allow "$PORT/tcp" > /dev/null
echo "VPN port forwarded, port $PORT is being used"

# Re-start transmission
ip netns exec "$NETNS_NAME" sudo -u felipe /usr/bin/transmission-daemon -g /home/felipe/.config/transmission

# Start redirection to access web interface
socat tcp-listen:9091,reuseaddr,fork tcp-connect:192.168.100.2:9091 > /dev/null 2>&1 &
