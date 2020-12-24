#!/usr/bin/env bash
###################################################################################
# Script retrieves a token from a file, if the file doesn't exist or  token has
# expired. We retrieve it from server.
# It then call the script to connect to specified wireguard server
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

  generateTokenResponse=$(curl -s -f -u "$_PIA_USER:$_PIA_PASS" \
    --connect-to "$server_meta_hostname::$server_meta_ip:" \
    --cacert "$CERT" \
    "https://$server_meta_hostname/authv3/generateToken")
  [[ $DEBUG == true ]] && echo "Retrieved token: $generateTokenResponse"

  # Checks response
  if [ "$(echo "$generateTokenResponse" | jq -r '.status')" != "OK" ]; then
    >&2 echo "Could not get a token. Please check your account credentials." && exit 1
  fi

  token="$(echo "$generateTokenResponse" | jq -r '.token')" # Expires in 24 hours
  echo "$token"
  # Saves to file, including a date to check if token is valid
  echo "{
    \"token\": \"$token\",
    \"date\": \"$(date +%s)\"
  }" > "$_TOKEN_FILE"
}

############### CHECKS ###############
check_tool curl curl
check_tool jq jq

# Check if the mandatory environment variables are set.
if [[ -z $CERT || -z $AUTH_FILE || -z $SERVER_ID || -z $PIA_PF || -z $CONFIG_DIR || -z $SCRIPTS_DIR ]]; then
  echo "$(basename "$0") script requires:"
  echo "CERT        - The PIA certificate"
  echo "AUTH_FILE   - filename that contains username and password (in that order, one per line)"
  echo "SERVER_ID   - id of the server you want to connect to"
  echo "PIA_PF      - enable port forwarding (true by default)"
  echo "CONFIG_DIR  - directory for all configuration files"
  echo "SCRIPTS_DIR - directory for all scripts"
  exit 1
fi

# Checks that file exists
if [[ ! -f $AUTH_FILE ]]; then
  >&2 echo "$AUTH_FILE doesn't exist, please provide a valid AUTH_FILE"; exit 1
fi

# Show debugging info
if [[ $DEBUG == true ]]; then
  echo "SERVER_ID: $SERVER_ID"
  echo "AUTH_FILE: $AUTH_FILE"
  echo "PIA_PF: $PIA_PF"
fi

############### VARIABLES ###############
# Read username and password from passwd file
readarray -t authorization < "$AUTH_FILE" # Read username and password
if [[ ${#authorization[@]} -ne 2 ]]; then >&2 echo -e "\e[31mNo username or password provided\e[0m\n"; exit 1; fi
readonly _PIA_USER=${authorization[0]}
readonly _PIA_PASS=${authorization[1]}

readonly _SERVER_LIST=$CONFIG_DIR/servers.json
readonly _TOKEN_FILE=$CONFIG_DIR/token.json
readonly _CONNECT_SCRIPT=$SCRIPTS_DIR/connect_to_wg.sh

# retrieve servers data specified by SERVER_ID from servers.json
server_data="$(jq ".[] | select(.id==\"$SERVER_ID\")" < "$_SERVER_LIST")"
if [[ ! $server_data ]]; then # Checks that a server was found
  >&2 echo "No server with id \"$SERVER_ID\" was found"
  echo "The following are valid servers ids (Name: ID):"
  jq -r '.[] | .name + ": " + .id' < "$_SERVER_LIST"
  exit 1
fi
readonly server_meta_ip="$(echo "$server_data" | jq -r '.servers.meta[0].ip')"
readonly server_meta_hostname="$(echo "$server_data" | jq -r '.servers.meta[0].cn')"
readonly can_forward="$(echo "$server_data" | jq -r '.port_forward')"
readonly WG_SERVER_IP="$(echo "$server_data" | jq -r '.servers.wg[0].ip')"
readonly WG_HOSTNAME="$(echo "$server_data" | jq -r '.servers.wg[0].cn')"
export WG_SERVER_IP
export WG_HOSTNAME

############### TOKEN ###############
# Check saved token if still valid, otherwise retrieve it
if [[ -f $_TOKEN_FILE ]]; then
  [[ $DEBUG == true ]] && echo "Reading token from $_TOKEN_FILE"
  # Check if token has expired (valid for 24 hours)
  if (( $(date +%s) < $(jq -r '.date' < "$_TOKEN_FILE") + 86400 )); then
    PIA_TOKEN="$(jq -r '.token' < "$_TOKEN_FILE")"
  else
    [[ $DEBUG == true ]] && echo "Token expired or empty, retrieving a new one"
    PIA_TOKEN=$(get_auth_token)
  fi
else
  [[ $DEBUG == true ]] && echo "No token file found, retrieving token"
  PIA_TOKEN=$(get_auth_token)
fi
readonly PIA_TOKEN
export PIA_TOKEN

[[ $can_forward == false ]] && PIA_PF=false
[[ $DEBUG == true ]] && echo "Server $SERVER_ID has support for port forwarding: $can_forward"

# Connect to Wireguard server
$_CONNECT_SCRIPT || exit 10
