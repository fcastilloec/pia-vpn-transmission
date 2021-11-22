#!/usr/bin/env bash
####################################################################################
# Keeps binding the port, otherwise it's deleted from the servers
####################################################################################

set -eE
failure() {
  local lineno=$1; local msg=$2
  echo "$(date --rfc-3339=seconds) - ERROR - failed at line ${lineno} - ${msg}"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### CHECKS ###############
# Check if running as root/sudo
[[ "${EUID:-$(id -u)}" -eq 0 ]] || exec sudo -E "$(readlink -f "$0")" "$@"

# Remove port binding script only if it exists
if ! ip netns list | grep -q "${NETNS_NAME:?}"; then
  crontab -l | grep -v "$(readlink -f "$0")" | crontab -u root -
  exit 0
fi

############### BINDING ###############
bind_port_response="$(ip netns exec "${NETNS_NAME}" curl -Gs -m 5 \
--connect-to "${WG_HOSTNAME:?}::${PF_GATEWAY:?}:" \
--cacert "${CERT:?}" \
--data-urlencode "payload=${PAYLOAD:?}" \
--data-urlencode "signature=${SIGNATURE:?}" \
"https://${WG_HOSTNAME}:19999/bindPort")"

if [[ "$(echo "${bind_port_response}" | jq -r '.status')" != "OK" ]]; then
  echo "$(date --rfc-3339=seconds) - ERROR - response was not 'OK' - $(echo "${bind_port_response}" | jq -r '.status')"
  exit 1
fi
