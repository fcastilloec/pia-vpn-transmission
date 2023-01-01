#!/usr/bin/env bash

set -e

version_regex="^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"

while (( "$#" )); do
  case "$1" in
    -h|--help)
      printf "Update version of script\n"
      printf "Usage: %s [version]\n" "$(basename "$0")"
      exit;;
    -*) # unsupported flags
      printf "\e[31m%s%s\e[0m\n" "Error: Unsupported flag " "$1"
      exit 1;;
    *) # preserve positional arguments
      params+=("$1"); shift;;
  esac
done

# Check number of parameters
if (( ${#params[@]} != 1 )); then printf "\e[31m%s\e[0m\n" "Only a single version is accepted."; exit 1; fi

# Check for basic semantic versioning
if ! [[ ${params[0]} =~ ${version_regex} ]]; then
  printf "\e[31m%s\e[0m\n" "Wrong version format. Only semantic versioning is supported"; exit 1;
fi

_version=${params[0]}
sed -i "s|\(readonly version=\)\(.*\)|\1${_version}|g" get_port.sh
