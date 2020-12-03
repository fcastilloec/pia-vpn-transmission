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
check_tool wg-quick wireguard-tools
check_tool curl curl
check_tool jq jq

# Check if the mandatory environment variables are set.
if [[ -z $WG_SERVER_IP || -z $WG_HOSTNAME || -z $PIA_TOKEN || -z $NETNS_NAME ]]; then
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

############### VARIABLES ###############
defaultDNS="1.1.1.1"
PORT_SCRIPT=/home/felipe/workspace/pia-vpn-transmission/port_forwarding.sh
PIA_CONFIG_DIR=/home/felipe/.config/pia_vpn
CERT=$PIA_CONFIG_DIR/ca.rsa.4096.crt
PRIVATE_KEY="$(wg genkey)"
PUBLIC_KEY="$( echo "$PRIVATE_KEY" | wg pubkey)"
IFACE_DEFAULT=$(route | grep '^default' | grep -o '[^ ]*$')

############### NAMESPACE ###############
# Set correct nameserver for DNS
mkdir -p "/etc/netns/$NETNS_NAME"
# dnsServer="$(echo "$wireguard_json" | jq -r '.dns_servers[0]')"
# we can use above PIA dns if needed
echo "nameserver $defaultDNS" > "/etc/netns/$NETNS_NAME/resolv.conf"

# Check if namespace already exists, if so delete it
if ip netns list | grep -q "$NETNS_NAME"; then
  [[ -n $DEBUG ]] && echo "Namespace $NETNS_NAME already exists, deleting it"
  ip netns delete "$NETNS_NAME"
fi
ip netns add "$NETNS_NAME" # create namespace

# Creates necessary network for wireguard
[[ -n $DEBUG ]] && echo "Starting WireGuard interface..."

############### NAMESPACES ###############
iface_local="$NETNS_NAME-veth0"
iface_peer="$NETNS_NAME-veth1"
ip link add name "$iface_local" type veth peer name "$iface_peer" netns "$NETNS_NAME"
ip addr add 192.168.100.1/24 dev "$iface_local"
ip link set "$iface_local" up
ip netns exec "$NETNS_NAME" ip addr add 192.168.100.2/24 dev "$iface_peer"
ip -n "$NETNS_NAME" link set "$iface_peer" up
ip -n "$NETNS_NAME" link set lo up
ip -n "$NETNS_NAME" route add default via 192.168.100.1
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o "$IFACE_DEFAULT" -j MASQUERADE
iptables -A FORWARD -i "$IFACE_DEFAULT" -o "$iface_local" -j ACCEPT
iptables -A FORWARD -o "$IFACE_DEFAULT" -i "$iface_local" -j ACCEPT

############### CONNECT ###############
# Authenticate via the PIA WireGuard RESTful API.
# This will return a JSON with data required for authentication.
wireguard_json="$(curl -s -G \
  --connect-to "$WG_HOSTNAME::$WG_SERVER_IP:" \
  --cacert "$CERT" \
  --data-urlencode "pt=${PIA_TOKEN}" \
  --data-urlencode "pubkey=$PUBLIC_KEY" \
  "https://${WG_HOSTNAME}:1337/addKey" )"
[[ -n $DEBUG ]] && echo "WireGuard response: $wireguard_json"

# Check if the API returned OK and stop this script if it didn't.
if [ "$(echo "$wireguard_json" | jq -r '.status')" != "OK" ]; then
  >&2 echo "Server did not return OK. Stopping now."
  exit 1
fi

# Create the WireGuard config based on the JSON received from the API
[[ -n $DEBUG ]] && echo "Creating WireGuard config based on JSON received"
mkdir -p /etc/wireguard
echo "
[Interface]
Address = $(echo "$wireguard_json" | jq -r '.peer_ip')
PrivateKey = $PRIVATE_KEY
## If you want wg-quick to also set up your DNS, uncomment the line below.
# DNS = $(echo "$wireguard_json" | jq -r '.dns_servers[0]')

[Peer]
PersistentKeepalive = 25
PublicKey = $(echo "$wireguard_json" | jq -r '.server_key')
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_SERVER_IP}:$(echo "$wireguard_json" | jq -r '.server_port')
" > /etc/wireguard/pia.conf || exit 1

# Start the WireGuard interface.
[[ -n $DEBUG ]] && echo "Starting WireGuard interface..."
if [[ -n $DEBUG ]]; then
  if ! ip netns exec "$NETNS_NAME" wg-quick up pia; then echo "Failed to start wireguard"; exit 1; fi
else
  if ! ip netns exec "$NETNS_NAME" wg-quick up pia > /dev/null 2>&1; then echo "Failed to start wireguard"; exit 1; fi
fi

# Stop the script if PIA_PF is not set to "true".
[[ "$PIA_PF" != true ]] && exit

# Start port forwarding and make sure it runs under my user
[[ -n $DEBUG ]] && echo "Starting port forwarding"
DEBUG="$DEBUG" PIA_TOKEN="$PIA_TOKEN" PF_HOSTNAME="$WG_HOSTNAME" NETNS_NAME="$NETNS_NAME" \
  PF_GATEWAY="$(echo "$wireguard_json" | jq -r '.server_vip')" \
  $PORT_SCRIPT || exit 20
