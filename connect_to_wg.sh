#!/usr/bin/env bash
###################################################################################
# Script connects to specified wireguard server.
# If port forwarding is enabled, it calls the script to start it.
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
    echo "$cmd could not be found"; echo "Please install $package"
    exit 1
  fi
}

############### CHECKS ###############
# Now we call the function to make sure we can use wg-quick, curl and jq.
check_tool wg wireguard-tools
check_tool curl curl
check_tool jq jq

# Check if the mandatory environment variables are set.
if [[ -z $WG_SERVER_IP || -z $WG_HOSTNAME || -z $PIA_TOKEN || -z $NETNS_NAME
 || -z $WG_LINK ]]; then
  echo "$(basename "$0") script requires:"
  echo "WG_SERVER_IP - IP that you want to connect to"
  echo "WG_HOSTNAME  - name of the server, required for ssl"
  echo "PIA_TOKEN    - your authentication token"
  echo "NETNS_NAME   - name of the namespace"
  echo "PIA_PF       - [OPTIONAL] enable port forwarding (true by default)"
  exit 1
fi

# Check if running as root/sudo
[ ${EUID:-$(id -u)} -eq 0 ] || exec sudo -E "$(readlink -f "$0")" "$@"

# Check if namespace already exists, if so delete it
if ip netns list | grep -q "$NETNS_NAME"; then
  [[ $DEBUG == true ]] && echo "Namespace $NETNS_NAME already exists, deleting it"
  ip netns delete "$NETNS_NAME"
fi

############### VARIABLES ###############
readonly _DEFAULT_DNS="1.1.1.1"
readonly _PORT_SCRIPT=$SCRIPTS_DIR/port_forwarding.sh
readonly private_key="$(wg genkey)"
readonly public_key="$(echo "$private_key" | wg pubkey)"

############### WIREGUARD CONFIG ###############
# Authenticate via the PIA WireGuard RESTful API.
# This will return a JSON with data required for authentication.
wireguard_json="$(curl -s -G \
  --connect-to "$WG_HOSTNAME::$WG_SERVER_IP:" \
  --cacert "$CERT" \
  --data-urlencode "pt=${PIA_TOKEN}" \
  --data-urlencode "pubkey=$public_key" \
  "https://${WG_HOSTNAME}:1337/addKey" )"
[[ $DEBUG == true ]] && echo "WireGuard response: $wireguard_json"

# Check if the API returned OK and stop this script if it didn't.
if [ "$(echo "$wireguard_json" | jq -r '.status')" != "OK" ]; then
  >&2 echo "Server did not return OK. Stopping now."
  exit 1
fi

# Set IP address of interface
readonly wg_address="$(echo "$wireguard_json" | jq -r '.peer_ip')"

# Create the WireGuard config based on the JSON received from the API
[[ $DEBUG == true ]] && echo "Creating WireGuard config based on JSON received"
mkdir -p /etc/wireguard
echo "\
[Interface]
PrivateKey = $private_key

[Peer]
PersistentKeepalive = 25
PublicKey = $(echo "$wireguard_json" | jq -r '.server_key')
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_SERVER_IP}:$(echo "$wireguard_json" | jq -r '.server_port')
" | sudo -u felipe tee "$CONFIG_DIR/$WG_LINK.conf" > /dev/null || exit 1

############### NAMESPACE ###############
[[ $DEBUG == true ]] && echo "Starting WireGuard interface..."

# Create wireguard interface
ip link add "$WG_LINK" type wireguard

# Load wireguard configuration
wg setconf "$WG_LINK" "$CONFIG_DIR/$WG_LINK.conf"

# Create a new namespace
ip netns add "$NETNS_NAME"

# Move Wireguard interface to namespace
ip link set "$WG_LINK" netns "$NETNS_NAME"

# Set IP address of wireguard interface
ip -n "$NETNS_NAME" addr add "$wg_address" dev "$WG_LINK"

# Start the WireGuard interface and sets it as default
ip -n "$NETNS_NAME" link set lo up
ip -n "$NETNS_NAME" link set "$WG_LINK" up
ip -n "$NETNS_NAME" route add default dev "$WG_LINK"

############### DNS ###############
# Sets the DNS server. We can use PIA's server, instead of default one:
# dnsServer="$(echo "$wireguard_json" | jq -r '.dns_servers[0]')"
echo "nameserver $_DEFAULT_DNS" | ip netns exec "$NETNS_NAME" resolvconf -a "$WG_LINK" -m 0 -x > /dev/null 2>&1

# Stop the script if PIA_PF is not set to "true".
[[ $PIA_PF != true ]] && exit

# Start port forwarding and make sure it runs under my user
[[ $DEBUG == true ]] && echo "Starting port forwarding"
PF_GATEWAY="$(echo "$wireguard_json" | jq -r '.server_vip')" $_PORT_SCRIPT || exit 20
