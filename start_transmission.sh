#!/usr/bin/env bash
####################################################################################
# Checks if VPN is running before starting Transmission
####################################################################################

set -eE
shopt -s inherit_errexit

############### FUNCTIONS ###############
# Trap failure
failure() {
  local lineno=$1; local msg=$2
  zenity --error --text="$(basename "$0"): failed at ${lineno}: ${msg}" --title="Start Transmission"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

# Checks if the required tools have been installed
function check_tool() {
  local cmd=$1; local package=$2
  if ! command -v "${cmd}" &>/dev/null; then
    >&2 zenity --error --text="${cmd} could not be found\nPlease install ${package}" --title="Start Transmission"
    exit 1
  fi
}

############### VARIABLES ###############
readonly version=1.1.1
# The next list has all the possible values, except for Connected, which is the one we want
readonly CONNECTION_VALUES=(Disconnected Connecting Interrupted Reconnecting DisconnectingToReconnect Disconnecting)

############### CHECKS ###############
check_tool piactl PIA

##########################################
if [[ ${DEBUG:=false} == true ]]; then
  zenity --notification --text="Starting Transmission via script: v${version}" --title="Start Transmission"
fi

# Check if we're anything but Connected
# shellcheck disable=SC2076
if [[ " ${CONNECTION_VALUES[*]} " =~ " $(piactl get connectionstate) " ]]; then
  zenity --info --text="Not connected to VPN\nTransmission won't start" --title="Start Transmission"
  exit 0
fi

# We're connected, let's start transmission
transmission-gtk "$@"
