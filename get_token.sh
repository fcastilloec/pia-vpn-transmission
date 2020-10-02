#!/usr/bin/env bash
###################################################################################
# Script retrieves a token from a file, if the file doesn't exist or  token has
# expired. We retrieve it from server.
# It then call the script to connect to specified wireguard server
###################################################################################

set -eE -o functrace
failure() {
  local lineno=$1
  local msg=$2
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
# Needs the following env variables PIA_USER, PIA_PASS, SERVER_META_HOSTNAME, SERVER_META_IP, CERT, TOKEN_FILE
function get_auth_token() {
  # Retrieves token
  local generateTokenResponse
  local token

  generateTokenResponse=$(curl -s -f -u "$PIA_USER:$PIA_PASS" \
    --connect-to "$SERVER_META_HOSTNAME::$SERVER_META_IP:" \
    --cacert "$CERT" \
    "https://$SERVER_META_HOSTNAME/authv3/generateToken")
  [[ -n $DEBUG ]] && echo "Retrieved token: $generateTokenResponse"

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
  }" > "$TOKEN_FILE"
}

############### CHECKS ###############
check_tool curl curl
check_tool jq jq

# Check if the mandatory environment variables are set.
if [[ ! $SERVER_ID || ! $AUTH_FILE ]]; then
  echo This script requires 2 env vars:
  echo "SERVER_ID - id of the server you want to connect to"
  echo "AUTH_FILE - filename that contains username and password (in that order, one per line)"
  echo "PIA_PF    - [OPTIONAL] enable port forwarding (true by default)"
  exit 1
fi

# Checks that file exists
if [[ ! -f $AUTH_FILE ]]; then
  >&2 echo "$AUTH_FILE doesn't exist, please provide a valid AUTH_FILE"; exit 1
fi

# Show debugging info
if [[ -n $DEBUG ]]; then
  echo "SERVER_ID: $SERVER_ID"
  echo "AUTH_FILE: $AUTH_FILE"
  echo "PIA_PF: $PIA_PF"
fi

############### VARIABLES ###############
# Read username and password from passwd file
readarray -t AUTH < "$AUTH_FILE" # Read username and password
if [[ ${#AUTH[@]} -ne 2 ]]; then >&2 echo -e "\e[31mNo username or password provided\e[0m\n"; exit 1; fi
PIA_USER=${AUTH[0]}
PIA_PASS=${AUTH[1]}

PIA_CONFIG_DIR=/home/felipe/.config/pia_vpn
SERVER_LIST=$PIA_CONFIG_DIR/servers.json
TOKEN_FILE=$PIA_CONFIG_DIR/token.json
CERT=$PIA_CONFIG_DIR/ca.rsa.4096.crt
CONNECT_SCRIPT=/home/felipe/workspace/pia-vpn-transmission/connect_to_wg.sh

# retrieve servers data specified by SERVER_ID from servers.json
SERVER_DATA="$(jq ".[] | select(.id==\"$SERVER_ID\")" < "$SERVER_LIST")"
if [[ ! $SERVER_DATA ]]; then # Checks that a server was found
  >&2 echo "No server with id \"$SERVER_ID\" was found"
  echo "The following are valid servers ids (Name: ID):"
  jq -r '.[] | .name + ": " + .id' < $SERVER_LIST
  exit 1
fi
SERVER_META_IP="$(echo "$SERVER_DATA" | jq -r '.servers.meta[0].ip')"
SERVER_META_HOSTNAME="$(echo "$SERVER_DATA" | jq -r '.servers.meta[0].cn')"
SERVER_WG_IP="$(echo "$SERVER_DATA" | jq -r '.servers.wg[0].ip')"
SERVER_WG_HOSTNAME="$(echo "$SERVER_DATA" | jq -r '.servers.wg[0].cn')"

############### TOKEN ###############
# Check saved token if still valid, otherwise retrieve it
if [[ -f $TOKEN_FILE ]]; then
  [[ -n $DEBUG ]] && echo "Reading token from $TOKEN_FILE"
  # Check if token has expired (valid for 24 hours)
  if (( $(date +%s) < $(jq -r '.date' < "$TOKEN_FILE") + 86400 )); then
    TOKEN="$(jq -r '.token' < "$TOKEN_FILE")"
  else
    [[ -n $DEBUG ]] && echo "Token expired or empty, retrieving a new one"
    TOKEN=$(get_auth_token)
  fi
else
  [[ -n $DEBUG ]] && echo "No token file found, retrieving token"
  TOKEN=$(get_auth_token)
fi

[[ -z "$PIA_PF" ]] && PIA_PF="true"

# Connect to Wireguard server
DEBUG=$DEBUG \
  PIA_PF=$PIA_PF \
  WG_TOKEN=$TOKEN \
  WG_SERVER_IP=$SERVER_WG_IP \
  WG_HOSTNAME=$SERVER_WG_HOSTNAME \
  $CONNECT_SCRIPT || exit 20
