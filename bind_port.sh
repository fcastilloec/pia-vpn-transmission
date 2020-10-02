#!/usr/bin/env bash
####################################################################################
# Keeps binding the port, otherwise it's deleted from the servers
####################################################################################

set -eE -o functrace
failure() {
  local lineno=$1
  local msg=$2
  echo "$(basename "$0"): failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### CHECKS ###############
# Check if the mandatory environment variables are set.
if [[ -z $PF_HOSTNAME || -z $PAYLOAD || -z $SIGNATURE || -z $PF_GATEWAY ]]; then
  echo This script requires 3 env vars:
  echo "PF_HOSTNAME - name of the host used for SSL/TLS certificate verification"
  echo "PAYLOAD     - the payload for port forwarding"
  echo "SIGNATURE   - the signature to authenticate port forwarding"
  echo "PF_GATEWAY  - IP address of the gateway"
  exit 1
fi

############### VARIABLES ###############
CONFIG_DIR=/home/felipe/.config/pia_vpn
CERT=$CONFIG_DIR/ca.rsa.4096.crt

############### BINDING ###############
bind_port_response="$(curl -Gs -m 5 \
  --connect-to "$PF_HOSTNAME::$PF_GATEWAY:" \
  --cacert "$CERT" \
  --data-urlencode "payload=${PAYLOAD}" \
  --data-urlencode "signature=${SIGNATURE}" \
  "https://${PF_HOSTNAME}:19999/bindPort")"

if [ "$(echo "$bind_port_response" | jq -r '.status')" != "OK" ]; then
  echo "The API did not return OK when trying to bind port. Exiting."
  exit 1
fi

echo "Port refreshed on $(date)"
