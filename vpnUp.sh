#!/usr/bin/env bash

# EXIT CODES:
# 1:  Port can't be retrieved, either an error or wrong server
# 2:  Can't modify transmission settings file
# 3:  Couldn't find required packages/dependencies

set -eE -o functrace

failure() {
  local lineno=$1
  local msg=$2
  echo "$me: failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

me=$(basename "$0") # name of this script use for debugging

################ CHECKS ################
# Check if running as root/sudo
if [ ${EUID:-$(id -u)} -eq 0 ]; then
  if [ -n "$DEBUG" ]; then printf "%s: running as sudo\n" "$me"; fi
else
  if [ -n "$DEBUG" ]; then printf "%s: NOT running as sudo\n" "$me"; fi
  exec sudo DEBUG="$DEBUG" "$0" "$@"
fi

# Check if JQ is installed, needed to handle JSON
if ! command -v jq > /dev/null 2>&1; then
  printf "JQ not installed. Please install before proceeding\n"
  exit 3
fi

# Check if nmap is installed, needed to check for ports
if ! command -v nmap > /dev/null 2>&1; then
  printf "NMAP not installed. Please install before proceeding\n"
  exit 3
fi
########################################

settings="/home/felipe/.config/transmission/settings.json"
port_config="/home/felipe/.config/transmission/port"
client_id=$(head -n 100 /dev/urandom | sha256sum | tr -d " -")
public_ip=$(dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | awk -F'"' '{ print $2}')
saved_port=$(cat $port_config) # Retrieves the saved port to check if it's already being used


if [ -n "$DEBUG" ]; then
  printf "%s: public IP: %s\n" "$me" "$public_ip"
  printf "%s: saved port is %s\n" "$me" "$saved_port"
fi

# Retrieves the port based on https://www.privateinternetaccess.com/forum/discussion/23431/new-pia-port-forwarding-api
json_port=$(curl "http://209.222.18.222:2000/?client_id=$client_id" 2>/dev/null || printf "")

if [ -n "$DEBUG" ]; then printf "%s: received json: %s\n" "$me" "$json_port"; fi

# Check that we received a port.
if [ -n "$json_port" ]; then
  vpnPort=$(printf "%s" "$json_port" | jq '."port"') # Use jq to get the port number
  if [ -n "$DEBUG" ]; then printf "%s: the parsed received port is %s\n" "$me" "$vpnPort"; fi
elif [ -n "$saved_port" ]; then # Didn't receive a port ($json_port), so let's use the saved one
  if nmap -p "$saved_port" "$public_ip" | grep -q 'filtered' > /dev/null 2>&1; then
    if [ -n "$DEBUG" ]; then
      printf "%s: port forwarding is already activated on this connection, using port %s" "$me" "$saved_port"
    fi
    vpnPort=$saved_port
  else
    printf "Saved port is obsolete. It might have expired, deleting it\n"
    printf "" > $port_config # deletes the obsolete port
    exit 1
  fi
else # Didn't receive a port and there's no old one saved.
  # count=1 # Doesn't let the next while loop, run forever
  # while [ -z "$json_port" ] && (( "$count" <= 20 )); do
  #   sleep 5 # Wait before checking for new IP
  #   json_port=$(curl "http://209.222.18.222:2000/?client_id=$client_id" 2>/dev/null || printf "")
  #   vpnPort=$(printf "%s" "$json_port" | jq '."port"') # Use jq to get the port number
  #   if [ -n "$DEBUG" ]; then printf "%s: %d check for forwarding port\n" "$me" "$count"; fi
  #   if [ -n "$DEBUG" ]; then printf "%s: the parsed received port is %s\n" "$me" "$vpnPort"; fi
  #   (( count++ ))
  # done
  # if [ -z "$json_port" ]; then printf "Cannot retrieve port and none was previously saved\n"; exit 1; fi
  printf "Cannot retrieve port and none was previously saved\n"; exit 1
fi

# Saves the retrieve port on disk (or the old $saved_port)
printf "%s" "$vpnPort" > $port_config

# Stop transmission-daemon if it's active
if systemctl -q is-active transmission-daemon.service; then
  if [ -n "$DEBUG" ]; then printf "%s: transmission-daemon is active\n" "$me"; fi
  set +e; systemctl stop transmission-daemon.service; set -e
fi

if [ -e "$settings" ]; then
  tempSettings=$(jq '."peer-port"'="$vpnPort" $settings)
  printf "%s" "$tempSettings" > $settings

  # Adds the port to UFW
  ufw allow "$vpnPort/tcp"
  printf "VPN port forwarded, port %s is being used\n" "$vpnPort"
else
  printf "Cannot modify Transmission. Transmission settings file not found\n"
  exit 2
fi

# Re-start transmission
systemctl start transmission-daemon.service

exit 0
