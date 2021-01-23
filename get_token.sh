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
  echo "$(basename "$0"): failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

############### FUNCTIONS ###############
# Checks if the required tools have been installed.
function check_tool() {
  local cmd=$1; local package=$2
  if ! command -v "$cmd" &>/dev/null; then
    >&2 echo "$cmd could not be found"; echo "Please install $package"
    exit 1
  fi
}

# Retrieves a token from an specified server.
# Needs the following variables _PIA_USER, _PIA_PASS, server_meta_hostname, server_meta_ip, CERT, _TOKEN_FILE
function get_auth_token() {
  # Retrieves token
  local generateTokenResponse
  local token

  generateTokenResponse=$(curl -s -u "$_PIA_USER:$_PIA_PASS" "https://privateinternetaccess.com/gtoken/generateToken")

  # Checks response
  if [ "$(echo "$generateTokenResponse" | jq -r '.status')" != "OK" ]; then
    >&2 echo "Could not get a token. Please check your account credentials." && exit 1
  fi

  token="$(echo "$generateTokenResponse" | jq -r '.token')"
  echo "$token"
  # Saves to file, including a date to check if token is valid
  echo "{
    \"token\": \"$token\",
    \"expires\": \"$(date +"%s" --date='1 day')\"
  }" > "$_TOKEN_FILE"
}

############### CHECKS ###############
check_tool curl curl
check_tool jq jq

# Check if the mandatory environment variables are set.
if [[ -z $AUTH_FILE || -z $CONFIG_DIR ]]; then
  echo "$(basename "$0") script requires:"
  echo "AUTH_FILE   - filename that contains username and password (in that order, one per line)"
  echo "CONFIG_DIR  - directory for all configuration files"
  exit 1
fi

# Checks that file exists
if [[ ! -f $AUTH_FILE ]]; then
  >&2 echo "$AUTH_FILE doesn't exist, please provide a valid AUTH_FILE"; exit 1
fi

if [[ $DEBUG == true ]]; then echo "AUTH_FILE: $AUTH_FILE"; fi

############### VARIABLES ###############
# Read username and password from passwd file
readarray -t authorization < "$AUTH_FILE" # Read username and password
if [[ ${#authorization[@]} -ne 2 ]]; then >&2 echo -e "\e[31mNo username or password provided\e[0m\n"; exit 1; fi
readonly _PIA_USER=${authorization[0]}
readonly _PIA_PASS=${authorization[1]}

readonly _TOKEN_FILE=$CONFIG_DIR/token.json

############### TOKEN ###############
# Check saved token if still valid, otherwise retrieve it
if [[ -f $_TOKEN_FILE ]]; then
  if [[ $DEBUG == true ]]; then echo "Reading token from $_TOKEN_FILE"; fi
  # Check if token has expired (valid for 24 hours)
  if (( $(date +%s) < $(jq -r '.expires' < "$_TOKEN_FILE") )); then
    PIA_TOKEN="$(jq -r '.token' < "$_TOKEN_FILE")"
  else
    if [[ $DEBUG == true ]]; then echo "Token expired, retrieving a new one"; fi
    PIA_TOKEN=$(get_auth_token)
  fi
else
  if [[ $DEBUG == true ]]; then echo "No token file found, retrieving token"; fi
  PIA_TOKEN=$(get_auth_token)
fi
readonly PIA_TOKEN
export PIA_TOKEN
