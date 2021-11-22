#!/usr/bin/env bash
###################################################################################
# Script connects to specified wireguard server.
# If port forwarding is enabled, it calls the script to start it.
#
# exports: PF_GATEWAY
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
    echo "${cmd} could not be found"; echo "Please install ${package}"
    exit 1
  fi
}

############### CHECKS ###############
# Now we call the function to make sure we can use wg-quick, curl and jq.
check_tool wg wireguard-tools
check_tool curl curl
check_tool jq jq

# Check if running as root/sudo
[[ "${EUID:-$(id -u)}" -eq 0 ]] || exec sudo -E "$(readlink -f "$0")" "$@"

_debug=${DEBUG:-false}

# Check if namespace already exists, if so delete it
if ip netns list | grep -q "${NETNS_NAME:?}"; then
  if [[ ${_debug} == true ]]; then echo "Namespace ${NETNS_NAME} already exists, deleting it"; fi
  ip netns delete "${NETNS_NAME}"
fi

############### VARIABLES ###############
readonly default_dns="1.1.1.1"
private_key="$(wg genkey)"
public_key="$(echo "${private_key}" | wg pubkey)"
readonly private_key
readonly public_key

############### WIREGUARD CONFIG ###############
# Authenticate via the PIA WireGuard RESTful API.
# This will return a JSON with data required for authentication.
wireguard_json="$(curl -s -G \
  --connect-to "${WG_HOSTNAME:?}::${WG_SERVER_IP:?}:" \
  --cacert "${CERT:?}" \
  --data-urlencode "pt=${PIA_TOKEN:?}" \
  --data-urlencode "pubkey=${public_key}" \
  "https://${WG_HOSTNAME}:1337/addKey" )"
if [[ ${_debug} == true ]]; then echo "WireGuard response: ${wireguard_json}"; fi

# Check if the API returned OK and stop this script if it didn't.
if [[ "$(echo "${wireguard_json}" | jq -r '.status')" != "OK" ]]; then
  >&2 echo "Server did not return OK. Stopping now."
  exit 1
fi

# Set IP address of interface
wg_address="$(echo "${wireguard_json}" | jq -r '.peer_ip')"
readonly wg_address

# Create the WireGuard config based on the JSON received from the API
if [[ ${_debug} == true ]]; then echo "Creating WireGuard config based on JSON received"; fi
mkdir -p /etc/wireguard
echo "\
[Interface]
PrivateKey = ${private_key}

[Peer]
PersistentKeepalive = 25
PublicKey = $(echo "${wireguard_json}" | jq -r '.server_key')
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_SERVER_IP}:$(echo "${wireguard_json}" | jq -r '.server_port')
" > "${CONFIG_DIR:?}/${WG_LINK:?}.conf"

############### NAMESPACE ###############
if [[ ${_debug} == true ]]; then echo "Starting WireGuard interface..."; fi

# Create wireguard interface
ip link add "${WG_LINK}" type wireguard

# Load wireguard configuration
wg setconf "${WG_LINK}" "${CONFIG_DIR}/${WG_LINK}.conf"

# Create a new namespace
ip netns add "${NETNS_NAME}"

# Move Wireguard interface to namespace
ip link set "${WG_LINK}" netns "${NETNS_NAME}"

# Set IP address of wireguard interface
ip -n "${NETNS_NAME}" addr add "${wg_address}" dev "${WG_LINK}"

# Start the WireGuard interface and sets it as default
ip -n "${NETNS_NAME}" link set lo up
ip -n "${NETNS_NAME}" link set "${WG_LINK}" up
ip -n "${NETNS_NAME}" route add default dev "${WG_LINK}"

############### DNS ###############
# Sets the DNS server. We can use PIA's server, instead of default one:
# dnsServer="$(echo "$wireguard_json" | jq -r '.dns_servers[0]')"
echo "nameserver ${default_dns}" | ip netns exec "${NETNS_NAME}" resolvconf -a "${WG_LINK}" -m 0 -x > /dev/null 2>&1

PF_GATEWAY="$(echo "${wireguard_json}" | jq -r '.server_vip')"
export PF_GATEWAY
