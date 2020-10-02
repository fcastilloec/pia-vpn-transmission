#!/usr/bin/env bash
####################################################################################
# Modifies Transmission settings by changing the port to the VPN one.
# It starts Transmission at the end
####################################################################################

set -eE -o functrace

failure() {
  local lineno=$1; local msg=$2
  echo "$(basename "$0"): failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### CHECKS & VARIABLES ###############
# Checks if jq is installed
if ! command -v jq &>/dev/null; then
  echo "jq could not be found"; echo "Please install jq"; exit 1
fi

SETTINGS=/home/felipe/.config/transmission/settings.json
PAYLOAD_FILE=/home/felipe/.config/pia_vpn/payload.json
PORT=$(jq -r '.payload' < $PAYLOAD_FILE | base64 -d | jq -r '.port')

# Checks that Transmission settings file exist
if [[ ! -f $SETTINGS ]]; then
  >&2 echo "Cannot modify Transmission settings. $SETTINGS not found"; exit 1
fi

# Check if running as root/sudo
[ ${EUID:-$(id -u)} -eq 0 ] || exec sudo -E "$0" "$@"

##########################################
# Stop transmission-daemon if it's active
if systemctl -q is-active transmission-daemon.service; then
  if [[ -n $DEBUG ]]; then echo "transmission-daemon is active. Stopping..."; fi
  set +e; systemctl stop transmission-daemon.service; set -e
fi

# Modifies the Transmission settings with the new port
tempSettings=$(jq '."peer-port"'="$PORT" $SETTINGS)
printf "%s" "$tempSettings" > $SETTINGS

# Adds the port to UFW
ufw allow "$PORT/tcp"
echo "VPN port forwarded, port $PORT is being used"

# Re-start transmission
systemctl start transmission-daemon.service
