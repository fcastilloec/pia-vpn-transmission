#!/usr/bin/env bash
####################################################################################
# Closes Transmission (if running) if PIA is not connected
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
readonly version=2.0.0

############### CHECKS ###############
# Check the script is running as root
[[ "${EUID:-$(id -u)}" -eq 0 ]] || exec sudo -E "$(readlink -f "$0")"

check_tool piactl PIA
##########################################
echo "Starting PIA monitoring: v${version}"

piactl monitor connectionstate | while read -r status; do
  if [[ ${status} == Disconnect* ]]; then
    if pidof transmission-gtk > /dev/null; then
      echo "transmission-gtk is active. Stopping..."
      kill -9 "$(pidof transmission-gtk)"
      /home/felipe/.bin/pushbullet "VPN was disconnected" "Transmission was stopped"
    fi
  fi
done
