#!/usr/bin/env bash
####################################################################################
# Retrieves port from payload and adds it to the firewall rules.
# This script should run only when the PIA account.json file changes.
####################################################################################

set -eE
shopt -s inherit_errexit

############### FUNCTIONS ###############
# Trap failure
failure() {
  local lineno=$1; local msg=$2
  echo "$(basename "$0"): failed at ${lineno}: ${msg}"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

# Checks if the required tools have been installed
function check_tool() {
  local cmd=$1; local package=$2
  if ! command -v "${cmd}" &>/dev/null; then
    >&2 echo "${cmd} could not be found"; echo "Please install ${package}"; exit 1
  fi
}

############### VARIABLES ###############
readonly version=2.2.2
readonly payload_file="/opt/piavpn/etc/account.json"
readonly transmission_settings="${_HOME:?Home directory is not known}/.config/transmission/settings.json"
readonly retries=5
was_running=false
retry=1
empty=1
empty_retries=5

############### CHECKS ###############
# Check the script is running as root
[[ "${EUID:-$(id -u)}" -eq 0 ]] || exec sudo -E "$(readlink -f "$0")"

check_tool jq jq

# Check and assign if debugging
if [[ ${DEBUG:=false} == true ]]; then echo "Debugging enabled"; fi

# Checks that payload file exists
if [[ ! -f ${payload_file} ]]; then
  >&2 echo "Payload file not found"; exit 1
fi

# Checks that Transmission settings file exists
if [[ ! -f ${transmission_settings} ]]; then
  >&2 echo "Cannot modify Transmission settings. ${transmission_settings} not found"; exit 1
fi

##########################################
echo "Starting port forwarding: v${version}"

# check if payload file is empty
until [[ -s ${payload_file} ]]; do
  if [[ ${empty} -gt ${empty_retries} ]]; then
    echo "Payload file is empty after ${empty_retries} retries"
    exit 1
  fi
  (( empty++ ))
  sleep 5 # extra time in case file is still being written to
done

# Reads the port from the payload file
while [[ ${retry} -le ${retries} ]]; do
  payload=$(<"${payload_file}")
  portForwardPayload="$(echo "${payload}" | jq -r '.portForwardPayload')"
  port="$(echo "${portForwardPayload}" | base64 -d | jq -r '.port')" # The payload has a base64 format

  if [[ ${port} =~ ^[0-9]+$ && ${port} -le 65535 && ${port} -ge 0 ]]; then
    break # everything is OK, exit while loop
  fi
  echo "Port is malformed. Retry # ${retry}"
  (( retry++ ))
  sleep 6
done

if [[ ${retry} -gt ${retries} ]]; then
  echo "Port is malformed or empty. Port: '${port}'"
  exit 1
fi
if [[ ${DEBUG=false} == true ]]; then echo "The port in use is ${port}"; fi

# Reads the current port used on Transmission
current_port=$(jq -r '."peer-port"' "${transmission_settings}")

# Check if changes are needed
if [[ ${current_port} -eq ${port} ]]; then
  echo "Nothing to do, port is already in used"
  exit 0
fi

#### CHANGES ARE NEEDED ####

# Check if Transmission is running
if pidof transmission-gtk > /dev/null; then
  if [[ ${DEBUG} == true ]]; then echo "transmission-gtk is active. Stopping..."; fi
  kill -9 "$(pidof transmission-gtk)"
  was_running=true
fi

# Modifies the Transmission settings with the new port
tempSettings=$(jq '."peer-port"'="${port}" "${transmission_settings}")
printf "%s" "${tempSettings}" > "${transmission_settings}"

# Check firewall rules and delete them
if ufw status | grep -q "${current_port}"; then
  ufw delete allow "${current_port}/tcp"
fi

# Add the new firewall rule if not present
if ! ufw status | grep -q "${port}"; then
  ufw allow in "${port}/tcp" > /dev/null
else
  >&2 echo "The current port is already in the rules. This is weird and should be checked."
fi

# Notify user to restart Transmission
if [[ ${was_running} == 'true' ]]; then
  /home/felipe/.bin/pushbullet "New VPN port assigned" "Restart Transmission. The port changed at: $(date)"
fi

echo "Port forwarding done"
