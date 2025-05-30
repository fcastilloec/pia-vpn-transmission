#!/usr/bin/env bash

trap 'exit 0' SIGTERM

readonly root_dir="/home/felipe/workspace/containers/pia-transmission-prowlarr"
readonly transmission_port="${root_dir}/data/pia-port/port.dat"

if ! transmission-remote -l >/dev/null 2>&1; then # Checks that Transmission is running
  echo "Transmission not running."; exit 0
fi

if ! [[ -f ${transmission_port} && -r ${transmission_port} ]]; then
  >&2 echo "Port file doesn't exist or is not readable!"; exit 1
fi

# Reading port
PORT=$(cat "${transmission_port}")
echo "Port read from file (${PORT})"

# Changing port
transmission-remote -p "${PORT}"
sleep 2
# Testing port
if [[ $(transmission-remote -pt) != "Port is open: Yes" ]]; then
  echo "Transmission port (${PORT}) is not open!"; exit 1
fi

exit 0
