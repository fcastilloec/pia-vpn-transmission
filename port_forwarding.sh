#!/usr/bin/env bash
####################################################################################
# Starts port forwarding by retrieving a port (store inside a payload) and signature
# from a file. If the file doesn't exist or the port has expired, it retreives it
# from the server. It then calls the binding script for the first time and sets a
# cron job to keep binding the port
####################################################################################

set -eE
failure() {
  local lineno=$1; local msg=$2
  echo "$(basename "$0"): failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### FUNCTIONS ###############
function get_signature_and_payload() {
  local payload_and_signature
  payload_and_signature="$(ip netns exec "$NETNS_NAME" curl -s -m 5 \
    --connect-to "$PF_HOSTNAME::$PF_GATEWAY:" \
    --cacert "$CERT" \
    -G --data-urlencode "token=${PIA_TOKEN}" \
    "https://${PF_HOSTNAME}:19999/getSignature")"

  # Check if the payload and the signature are OK.
  if [ "$(echo "$payload_and_signature" | jq -r '.status')" != "OK" ]; then
    echo "The payload_and_signature variable does not contain an OK status."; exit 1
  fi

  echo "$payload_and_signature" | tee "$PAYLOAD_FILE"
}

############### CHECKS ###############
# Check if the mandatory environment variables are set.
if [[ -z $PF_GATEWAY || -z $PIA_TOKEN || -z $PF_HOSTNAME || -z $NETNS_NAME ]]; then
  echo "$(basename "$0") script requires:"
  echo "PF_GATEWAY  - the IP of your gateway"
  echo "PF_HOSTNAME - name of the host used for SSL/TLS certificate verification"
  echo "PIA_TOKEN   - the token you use to connect to the vpn services"
  echo "NETNS_NAME  - name of the namespace"
  exit 1
fi

# Check if running as root/sudo
[ ${EUID:-$(id -u)} -eq 0 ] || exec sudo -E "$(readlink -f "$0")" "$@"

############### VARIABLES ###############
BIND_INTERVAL=15 # time in minutes to re-bind the port, otherwise it gets deleted
PIA_CONFIG_DIR=/home/felipe/.config/pia_vpn
CERT=$PIA_CONFIG_DIR/ca.rsa.4096.crt
PAYLOAD_FILE=$PIA_CONFIG_DIR/payload.json
PORT_LOG=$PIA_CONFIG_DIR/vpnPort.log
BIND_SCRIPT=/home/felipe/workspace/pia-vpn-transmission/bind_port.sh

##########################################
# Checks that payload file exists
if [[ -f $PAYLOAD_FILE ]]; then
  PAYLOAD_AND_SIGNATURE=$(<$PAYLOAD_FILE)
  expires_at=$(echo "$PAYLOAD_AND_SIGNATURE" | jq -r '.payload' | base64 -d | jq -r '.expires_at' | date +%s -f -)
  [[ -n $DEBUG ]] && echo "Port will expire on $(date --date="@$expires_at")"

  # Check if port has expired. It expires in 2 months
  if ((  expires_at < $(date +%s) )); then
    [[ -n $DEBUG ]] && echo "Payload from file has expired"
    PAYLOAD_AND_SIGNATURE="$(get_signature_and_payload)"
  fi
else
  PAYLOAD_AND_SIGNATURE="$(get_signature_and_payload)"
fi
[[ -n $DEBUG ]] && echo "Payload and signature: $PAYLOAD_AND_SIGNATURE"

# We need to get the signature out. It will allow the us to bind the port on the server
signature="$(echo "$PAYLOAD_AND_SIGNATURE" | jq -r '.signature')"
[[ -n $DEBUG ]] && echo "The signature: $signature"

# Extract payload, port and expires_at.
payload="$(echo "$PAYLOAD_AND_SIGNATURE" | jq -r '.payload')" # The payload has a base64 format
port="$(echo "$payload" | base64 -d | jq -r '.port')"
[[ -n $DEBUG ]] && echo "The port in use is $port"

# Creates a variable to run the script and use on crontab
BINDING="PF_HOSTNAME=$PF_HOSTNAME\
 PF_GATEWAY=$PF_GATEWAY\
 PAYLOAD=$payload\
 SIGNATURE=$signature\
 NETNS_NAME=$NETNS_NAME\
 $BIND_SCRIPT"

eval "$BINDING" || exit 20 # runs the command store in BINDING

# Set crontab to keep binding the port every BIND_INTERVAL minutes
minutes=$(seq -s , $(( $(date +"%M") % BIND_INTERVAL )) $BIND_INTERVAL 59) # Calculate 15min from current time
echo "$minutes * * * * $BINDING >> $PORT_LOG 2>&1" | crontab -u root -

true > $PORT_LOG # empties the log file, so the output is only for the current session
