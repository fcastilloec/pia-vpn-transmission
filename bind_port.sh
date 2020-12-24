#!/usr/bin/env bash
####################################################################################
# Keeps binding the port, otherwise it's deleted from the servers
####################################################################################

set -eE
failure() {
  local lineno=$1; local msg=$2
  echo "$(basename "$0"): failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### CHECKS ###############
# Check if running as root/sudo
[ ${EUID:-$(id -u)} -eq 0 ] || exec sudo -E "$(readlink -f "$0")" "$@"

# Check if the mandatory environment variables are set.
if [[ -z $WG_HOSTNAME || -z $PAYLOAD || -z $SIGNATURE || -z $PF_GATEWAY || -z $NETNS_NAME ]]; then
  echo "$(basename "$0") script requires:"
  echo "WG_HOSTNAME - name of the host used for SSL/TLS certificate verification"
  echo "PAYLOAD     - the payload for port forwarding"
  echo "SIGNATURE   - the signature to authenticate port forwarding"
  echo "PF_GATEWAY  - IP address of the gateway"
  echo "NETNS_NAME  - name of the namespace"
  exit 1
fi

############### VARIABLES ###############
_CONFIG_DIR=/home/felipe/.config/pia_vpn
_CERT=$_CONFIG_DIR/ca.rsa.4096.crt

############### BINDING ###############
bind_port_response="$(ip netns exec "$NETNS_NAME" curl -Gs -m 5 \
  --connect-to "$WG_HOSTNAME::$PF_GATEWAY:" \
  --cacert "$_CERT" \
  --data-urlencode "payload=${PAYLOAD}" \
  --data-urlencode "signature=${SIGNATURE}" \
  "https://${WG_HOSTNAME}:19999/bindPort")"

if [ "$(echo "$bind_port_response" | jq -r '.status')" != "OK" ]; then
  echo "$(date) ERROR: $(echo "$bind_port_response" | jq -r '.status')"
  exit 1
fi

# echo "Port refreshed on $(date)"
