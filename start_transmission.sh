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
readonly version=2.2.2
# The next list has all the possible values, except for Connected, which is the one we want
readonly CONNECTION_VALUES=(Disconnected Connecting Interrupted Reconnecting DisconnectingToReconnect Disconnecting)
readonly TRANSMISSION_WINDOW="Transmission"
readonly TIMEOUT=10 # in seconds

############### CHECKS ###############
check_tool piactl PIA
check_tool transmission-remote transmission-cli
check_tool wmctrl wmctrl

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

# We're connected, let's start transmission minimized for tests
transmission-gtk &
if ! TRANSMISSION_PID=$(pidof transmission-gtk); then
  zenity --error --text="Transmssion failed to start minimized" --title="Start Transmission"
  exit 1
fi
until wmctrl -l | grep -q "felipe-desktop Transmission"; do # wait until window can be interacted with
  sleep 0.1
done
wmctrl -F -r "${TRANSMISSION_WINDOW}" -b toggle,shaded # collapses it (shaded), but doesn't minimize (hidden minimize but doesn't work)

# SECONDS is a bash special variable that returns the seconds since set. Prevents the following loop to run forever
SECONDS=0
until lsof -Pi :9091 -sTCP:LISTEN -t > /dev/null; do # wait until Transmission remote port is open
  if [[ ${SECONDS} -ge ${TIMEOUT} ]]; then
    zenity --error --text="Transmssion remote not enabled\nMake sure that remote access is allowed" --title="Start Transmission"
    exit 1
  fi
  sleep 0.1
done

# Check if port is open. If not, we might be bypassing the VPN
if [[ $(transmission-remote -pt) != "Port is open: Yes" ]]; then
  zenity --error --text="Port is not open\nTransmission won't start" --title="Start Transmission"
  kill -9 "${TRANSMISSION_PID}"
  exit 1
fi

# Maximize Transmission
wmctrl -F -r "${TRANSMISSION_WINDOW}" -b toggle,shaded
