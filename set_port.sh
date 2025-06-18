#!/usr/bin/env bash

trap 'exit 0' SIGTERM

root_dir=$(/usr/local/bin/docker-compose ls | grep pia-transmission-prowlarr | awk '{print $3}' | xargs dirname)
readonly root_dir
readonly transmission_port="${root_dir}/data/pia-port/port.dat"

## Checks
if [[ -z ${root_dir} ]]; then
  >&2 echo "Docker compose project is not running"; exit 1
fi

if ! [[ -f ${transmission_port} && -r ${transmission_port} ]]; then
  >&2 echo "Port file doesn't exist or is not readable!"; exit 1
fi

sleep 5 # give some time for Transmission to start

if ! transmission-remote -l >/dev/null 2>&1; then # Checks that Transmission is running
  echo "Transmission not running."; exit 1
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
