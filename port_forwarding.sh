#!/usr/bin/env bash
####################################################################################
# Starts port forwarding by retrieving a port (store inside a payload) and signature
# from a file. If the file doesn't exist or the port has expired, it retrieves it
# from the server. It then calls the binding script for the first time and sets a
# cron job to keep binding the port
####################################################################################

set -eE
failure() {
  local lineno=$1; local msg=$2
  echo "$(basename "$0"): failed at ${lineno}: ${msg}"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### FUNCTIONS ###############
function get_signature_and_payload() {
  local payload_and_signature
  payload_and_signature="$(ip netns exec "${NETNS_NAME:?}" curl -s -m 5 \
    --connect-to "${WG_HOSTNAME:?}::${PF_GATEWAY:?}:" \
    --cacert "${CERT:?}" \
    -G --data-urlencode "token=${PIA_TOKEN:?}" \
    "https://${WG_HOSTNAME}:19999/getSignature")"

  # Check if the payload and the signature are OK.
  if [ "$(echo "${payload_and_signature}" | jq -r '.status')" != "OK" ]; then
    echo "The payload_and_signature variable does not contain an OK status."; exit 1
  fi

  echo "${payload_and_signature}" | tee "${PAYLOAD_FILE:?}"
}

############### CHECKS ###############
# Check if running as root/sudo
[ "${EUID:-$(id -u)}" -eq 0 ] || exec sudo -E "$(readlink -f "$0")" "$@"

############### VARIABLES ###############
readonly bind_interval=15 # time in minutes to re-bind the port, otherwise it gets deleted
readonly port_log=${CONFIG_DIR:?}/vpnPort.log
_debug=${DEBUG:-false}

##########################################
# Checks that payload file exists
if [[ -f ${PAYLOAD_FILE:?} ]]; then
  payload_and_signature=$(<"${PAYLOAD_FILE}")
  expires_at=$(echo "${payload_and_signature}" | jq -r '.payload' | base64 -d | jq -r '.expires_at' | date +%s -f -)
  if [[ ${_debug} == true ]]; then echo "Port will expire on $(date --date="@${expires_at}")"; fi

  # Check if port has expired. It expires in 2 months
  if ((  expires_at < $(date +%s) )); then
    if [[ ${_debug} == true ]]; then echo "Payload from file has expired"; fi
    payload_and_signature="$(get_signature_and_payload)"
  fi
else
  payload_and_signature="$(get_signature_and_payload)"
fi
if [[ ${_debug} == true ]]; then echo "Payload and signature: ${payload_and_signature}"; fi

# We need to get the signature out. It will allow the us to bind the port on the server
signature="$(echo "${payload_and_signature}" | jq -r '.signature')"
if [[ ${_debug} == true ]]; then echo "The signature: ${signature}"; fi

# Extract payload, port and expires_at.
payload="$(echo "${payload_and_signature}" | jq -r '.payload')" # The payload has a base64 format
port="$(echo "${payload}" | base64 -d | jq -r '.port')"
if [[ ${_debug} == true ]]; then echo "The port in use is ${port}"; fi

# Creates a variable to run the script and use on crontab
binding_command="CONFIG_DIR=${CONFIG_DIR}\
 WG_HOSTNAME=${WG_HOSTNAME:?}\
 PF_GATEWAY=${PF_GATEWAY:?}\
 PAYLOAD=${payload}\
 SIGNATURE=${signature}\
 NETNS_NAME=${NETNS_NAME:?}\
 CERT=${CERT:?}\
 ${BIND_SCRIPT:?}"

eval "${binding_command}" || exit 20 # runs the command store in binding_command

# Set crontab to keep binding the port every bind_interval minutes
minutes=$(seq -s , $(( $(date +"%-M") % bind_interval )) "${bind_interval}" 59) # Calculate 15min from current time
echo "${minutes} * * * * ${binding_command} >> ${port_log} 2>&1" | crontab -u root -

true > "${port_log}" # empties the log file, so the output is only for the current session
