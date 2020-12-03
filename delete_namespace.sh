#!/bin/bash

set -E
failure() {
  local lineno=$1; local msg=$2
  echo "$(basename "$0"): failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

# Check if running as root/sudo
[ ${EUID:-$(id -u)} -eq 0 ] || exec sudo -E "$(readlink -f "$0")" "$@"

############### CHECKS ###############
# Check if the mandatory environment variables are set.
if [[ -z $NETNS_NAME ]]; then
  echo "$(basename "$0") script requires:"
  echo "NETNS_NAME  - name of the namespace"
  exit 1
fi

############### VARIABLES ###############
IFACE_DEFAULT=$(route | grep '^default' | grep -o '[^ ]*$')
iface_local=$NETNS_NAME-veth0

# deletes namespace, virtual interfaces associated with it, and iptables rules
{
  ip netns delete "$NETNS_NAME"
  ip link delete "$iface_local"
  iptables -t nat -D POSTROUTING -s 192.168.100.0/24 -o "$IFACE_DEFAULT" -j MASQUERADE
  iptables -D FORWARD -i "$IFACE_DEFAULT" -o "$iface_local" -j ACCEPT
  iptables -D FORWARD -o "$IFACE_DEFAULT" -i "$iface_local" -j ACCEPT
  killall socat
} > /dev/null 2>&1

exit 0
