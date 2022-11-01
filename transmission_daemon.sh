#!/usr/bin/env bash

readonly transmission_config_dir=/home/felipe/.config/transmission
readonly transmission_pid=${transmission_config_dir}/pid
readonly transmission_log=/dev/null

export TRANSMISSION_WEB_HOME="/home/felipe/transmission_themes/current"

/usr/bin/transmission-daemon --log-error\
 --config-dir "${transmission_config_dir}"\
 --logfile "${transmission_log}"\
 --pid-file "${transmission_pid}"
