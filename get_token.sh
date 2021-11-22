#!/usr/bin/env bash
###################################################################################
# Script retrieves a token from a file. If the file doesn't exist or token has
# expired, we retrieve it from server.
# It then call the script to connect to specified wireguard server
#
# exports: PIA_TOKEN
###################################################################################

set -eE
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

# Retrieves a token from an specified server.
# Needs the following variables pia_user, pia_pass, server_meta_hostname, server_meta_ip, CERT, token_file
function get_auth_token() {
  # Retrieves token
  local generateTokenResponse
  local token

  generateTokenResponse=$(curl -s -u "${pia_user}:${pia_pass}" "https://privateinternetaccess.com/gtoken/generateToken")

  # Checks response
  if [[ "$(echo "${generateTokenResponse}" | jq -r '.status')" != "OK" ]]; then
    >&2 echo "Could not get a token. Please check your account credentials." && exit 1
  fi

  token="$(echo "${generateTokenResponse}" | jq -r '.token')"
  echo "${token}"
  # Saves to file, including a date to check if token is valid
  echo "{
    \"token\": \"${token}\",
    \"expires\": \"$(date +"%s" --date='1 day')\"
  }" > "${token_file}"
}

############### CHECKS ###############
check_tool curl curl
check_tool jq jq

_debug=${DEBUG:-false}

# Checks that file exists
if [[ ! -f ${AUTH_FILE:?} ]]; then
  >&2 echo "${AUTH_FILE} doesn't exist, please provide a valid AUTH_FILE"; exit 1
fi

if [[ ${_debug} == true ]]; then echo "AUTH_FILE: ${AUTH_FILE}"; fi

############### VARIABLES ###############
# Read username and password from passwd file
readarray -t authorization < "${AUTH_FILE}" # Read username and password
if [[ ${#authorization[@]} -ne 2 ]]; then >&2 echo -e "\e[31mNo username or password provided\e[0m\n"; exit 1; fi
readonly pia_user=${authorization[0]}
readonly pia_pass=${authorization[1]}

readonly token_file=${CONFIG_DIR:?}/token.json

############### TOKEN ###############
# Check saved token if still valid, otherwise retrieve it
if [[ -f ${token_file} ]]; then
  if [[ ${_debug} == true ]]; then echo "Reading token from ${token_file}"; fi
  # Check if token has expired (valid for 24 hours)
  if (( $(date +%s) < $(jq -r '.expires' < "${token_file}") )); then
    PIA_TOKEN="$(jq -r '.token' < "${token_file}")"
  else
    if [[ ${_debug} == true ]]; then echo "Token expired, retrieving a new one"; fi
    PIA_TOKEN=$(set -e; get_auth_token)
  fi
else
  if [[ ${_debug} == true ]]; then echo "No token file found, retrieving token"; fi
  PIA_TOKEN=$(set -e; get_auth_token)
fi
readonly PIA_TOKEN
export PIA_TOKEN
