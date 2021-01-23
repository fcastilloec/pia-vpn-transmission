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
    --connect-to "$WG_HOSTNAME::$PF_GATEWAY:" \
    --cacert "$CERT" \
    -G --data-urlencode "token=${PIA_TOKEN}" \
    "https://${WG_HOSTNAME}:19999/getSignature")"

  # Check if the payload and the signature are OK.
  if [ "$(echo "$payload_and_signature" | jq -r '.status')" != "OK" ]; then
    echo "The payload_and_signature variable does not contain an OK status."; exit 1
  fi

  echo "$payload_and_signature" | tee "$_PAYLOAD_FILE"
}

############### CHECKS ###############
# Check if the mandatory environment variables are set.
if [[ -z $PF_GATEWAY || -z $CONFIG_DIR || -z $SCRIPTS_DIR || -z $WG_HOSTNAME || -z $NETNS_NAME ]]; then
  echo "$(basename "$0") script requires:"
  echo "PF_GATEWAY     - the IP of your gateway"
  echo "CONFIG_DIR - Configuration directory for PIA"
  echo "SCRIPTS_DIR    - Scripts directory for PIA"
  echo "WG_HOSTNAME    - name of the host used for SSL/TLS certificate verification"
  echo "NETNS_NAME     - name of the namespace"
  exit 1
fi

# Check if running as root/sudo
[ ${EUID:-$(id -u)} -eq 0 ] || exec sudo -E "$(readlink -f "$0")" "$@"

############### VARIABLES ###############
readonly _BIND_INTERVAL=15 # time in minutes to re-bind the port, otherwise it gets deleted
readonly _PAYLOAD_FILE=$CONFIG_DIR/payload.json
readonly _PORT_LOG=$CONFIG_DIR/vpnPort.log
readonly _BIND_SCRIPT=$SCRIPTS_DIR/bind_port.sh

##########################################
# Checks that payload file exists
if [[ -f $_PAYLOAD_FILE ]]; then
  _PAYLOAD_AND_SIGNATURE=$(<"$_PAYLOAD_FILE")
  expires_at=$(echo "$_PAYLOAD_AND_SIGNATURE" | jq -r '.payload' | base64 -d | jq -r '.expires_at' | date +%s -f -)
  if [[ $DEBUG == true ]]; then echo "Port will expire on $(date --date="@$expires_at")"; fi

  # Check if port has expired. It expires in 2 months
  if ((  expires_at < $(date +%s) )); then
    if [[ $DEBUG == true ]]; then echo "Payload from file has expired"; fi
    _PAYLOAD_AND_SIGNATURE="$(get_signature_and_payload)"
  fi
else
  _PAYLOAD_AND_SIGNATURE="$(get_signature_and_payload)"
fi
if [[ $DEBUG == true ]]; then echo "Payload and signature: $_PAYLOAD_AND_SIGNATURE"; fi

# We need to get the signature out. It will allow the us to bind the port on the server
signature="$(echo "$_PAYLOAD_AND_SIGNATURE" | jq -r '.signature')"
if [[ $DEBUG == true ]]; then echo "The signature: $signature"; fi

# Extract payload, port and expires_at.
payload="$(echo "$_PAYLOAD_AND_SIGNATURE" | jq -r '.payload')" # The payload has a base64 format
port="$(echo "$payload" | base64 -d | jq -r '.port')"
if [[ $DEBUG == true ]]; then echo "The port in use is $port"; fi

# Creates a variable to run the script and use on crontab
_BINDING="CONFIG_DIR=$CONFIG_DIR\
 WG_HOSTNAME=$WG_HOSTNAME\
 PF_GATEWAY=$PF_GATEWAY\
 PAYLOAD=$payload\
 SIGNATURE=$signature\
 NETNS_NAME=$NETNS_NAME\
 $_BIND_SCRIPT"

eval "$_BINDING" || exit 20 # runs the command store in _BINDING

# Set crontab to keep binding the port every _BIND_INTERVAL minutes
minutes=$(seq -s , $(( $(date +"%M") % _BIND_INTERVAL )) $_BIND_INTERVAL 59) # Calculate 15min from current time
echo "$minutes * * * * $_BINDING >> $_PORT_LOG 2>&1" | crontab -u root -

true > "$_PORT_LOG" # empties the log file, so the output is only for the current session
