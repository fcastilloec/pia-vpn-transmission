#!/usr/bin/env bash
####################################################################################
# Keeps binding the port, otherwise it's deleted from the servers
####################################################################################

set -eE
failure() {
  local lineno=$1; local msg=$2
  echo "$(date --rfc-3339=seconds) - ERROR - failed at line $lineno - $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### CHECKS ###############
# Check if running as root/sudo
[ ${EUID:-$(id -u)} -eq 0 ] || exec sudo -E "$(readlink -f "$0")" "$@"

# Check if the mandatory environment variables are set.
if [[ -z $CONFIG_DIR || -z $WG_HOSTNAME || -z $PAYLOAD || -z $SIGNATURE || -z $PF_GATEWAY || -z $NETNS_NAME ||
      -z $CERT ]]; then
  echo "$(basename "$0") script requires:"
  echo "CONFIG_DIR  - configuration directory"
  echo "CERT        - path to the PIA certificate"
  echo "WG_HOSTNAME - name of the host used for SSL/TLS certificate verification"
  echo "PAYLOAD     - payload for port forwarding"
  echo "SIGNATURE   - signature to authenticate port forwarding"
  echo "PF_GATEWAY  - IP address of the gateway"
  echo "NETNS_NAME  - name of the namespace"
  exit 1
fi

############### CHECKS ###############
if ! ip netns list | grep -q "$NETNS_NAME"; then
  # Remove port binding script only
  crontab -l | grep -v "$(readlink -f "$0")" | crontab -u root -
  exit 0
fi

############### BINDING ###############
bind_port_response="$(ip netns exec "$NETNS_NAME" curl -Gs -m 5 \
--connect-to "$WG_HOSTNAME::$PF_GATEWAY:" \
--cacert "$CERT" \
--data-urlencode "payload=${PAYLOAD}" \
--data-urlencode "signature=${SIGNATURE}" \
"https://${WG_HOSTNAME}:19999/bindPort")"

if [ "$(echo "$bind_port_response" | jq -r '.status')" != "OK" ]; then
  echo "$(date --rfc-3339=seconds) - ERROR - response was not 'OK' - $(echo "$bind_port_response" | jq -r '.status')"
  exit 1
fi
