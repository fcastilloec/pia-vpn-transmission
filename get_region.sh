#!/usr/bin/env bash
###################################################################################
# Get the details on the specific region server
#
# exports: WG_SERVER_IP, WG_HOSTNAME
###################################################################################

set -ueE
failure() {
  local lineno=$1; local msg=$2
  echo "$(basename "$0"): failed at ${lineno}: ${msg}"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### FUNCTIONS ###############
# Checks if the required tools have been installed.
function check_tool() {
  local cmd=$1; local package=$2
  if ! command -v "${cmd}" &>/dev/null; then
    >&2 echo "${cmd} could not be found"; echo "Please install ${package}"
    exit 1
  fi
}

############### CHECKS ###############
check_tool curl curl
check_tool jq jq

_debug=${DEBUG:-false}

############### REGION ###############
readonly server_list_url='https://serverlist.piaservers.net/vpninfo/servers/v6'

# retrieve a list of all servers and filter by SERVER_ID
all_region_data=$(curl -s "${server_list_url}" | head -1)
server_data="$(echo "${all_region_data}" | jq --arg REGION_ID "${SERVER_ID:?}" -r '.regions[] | select(.id==$REGION_ID)')"
readonly all_region_data
readonly server_data

# Checks that a server was found
if [[ -z ${server_data} ]]; then
  >&2 echo "No server with id \"${SERVER_ID}\" was found"
  exit 1
fi

can_forward="$(echo "${server_data}" | jq -r '.port_forward')"
country="$(echo "${server_data}" | jq -r '.country')"
name="$(echo "${server_data}" | jq -r '.name')"
WG_SERVER_IP="$(echo "${server_data}" | jq -r '.servers.wg[0].ip')"
WG_HOSTNAME="$(echo "${server_data}" | jq -r '.servers.wg[0].cn')"
export WG_SERVER_IP
export WG_HOSTNAME
readonly can_forward
readonly country
readonly name
readonly WG_SERVER_IP
readonly WG_HOSTNAME

if [[ ${can_forward} == false ]]; then PORT_FORWARD=false; export PORT_FORWARD; fi
if [[ ${_debug} == true ]]; then echo "Server ${SERVER_ID} has support for port forwarding: ${can_forward}"; fi

echo "Attempting to connected to ${name}, ${country}"
