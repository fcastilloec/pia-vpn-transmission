#!/usr/bin/env bash

set -e
trap 'exit 0' SIGTERM

readonly NAME="media-management"
config_file=$(
  /usr/local/bin/docker-compose ls --format json --filter name="${NAME}" \
    | jq -r 'select(length > 0) | .[0].ConfigFiles // empty'
)

## Checks
if [[ -z ${config_file} ]]; then
  >&2 echo "Docker compose project doesn't exist"
  exit 0
fi
transmission_port="$(dirname "${config_file}")/data/pia-port/port.dat"
readonly transmission_port

if ! [[ -f ${transmission_port} && -r ${transmission_port} ]]; then
  >&2 echo "Port file doesn't exist or is not readable!"
  exit 1
fi

if ! transmission-remote -l > /dev/null 2>&1; then # Checks that Transmission is running
  echo "Transmission not running."
  exit 1
fi

# Reading port
PORT=$(cat "${transmission_port}")
echo "Port read from file (${PORT})"

# Changing port
transmission-remote -p "${PORT}"
sleep 2
# Testing port
if [[ $(transmission-remote -pt) != "Port is open: Yes" ]]; then
  echo "Transmission port (${PORT}) is not open!"
  exit 1
fi

exit 0
