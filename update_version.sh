#!/usr/bin/env bash

set -e

version_regex="^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"
flags_regex="^(-M|-m|-p|-h)$"
_files=("get_port.sh" "transmission.sh")

function print_help() {
  local -r bold='\e[1m'; local -r emph='\e[2m'; local -r reset='\e[0m'
  echo    "Update version of get_port script"
  echo -e "$(basename "${0}") [options]"
  echo
  echo -e "${emph}Options:${reset}"
  echo -e "  ${bold}-M,--major${reset}      update the major version"
  echo -e "  ${bold}-m,--minor${reset}      update the minor version"
  echo -e "  ${bold}-p,--patch${reset}      update the patch version"
  echo -e "  ${bold}-v,--version${reset}    update to the specified semantic version"
  echo -e "  ${bold}-h,--help${reset}       shows this help"
}

# Check number of arguments, we only accept one unless custom version is specified
if (( $# == 1 )) && ! [[ $1 =~ ${flags_regex} ]]; then
  if [[ $1 != "-v" ]]; then printf "\e[31m%s%s\e[0m\n" "Error: Unsupported flag/argument " "$1"
  else printf "\e[31m%s\e[0m\n" "Error: A custom semantic version is required with this flag"; fi
  print_help; exit 1
elif (( $# == 2 )) && [[ $1 != "-v" ]]; then
  printf "\e[31m%s%s\e[0m\n" "Error: Unsupported flag " "$1"; print_help; exit 1
elif (( $# > 2 || $# == 0 )); then
  printf "\e[31m%s\e[0m\n" "Only a single flag can be passed"; print_help; exit 1;
fi

# Read version number
version_string=$(grep "readonly version=" "${_files[0]}" | cut -d "=" -f 2)
IFS="." read -r -a version_array <<< "${version_string}"

case "$1" in
  -h|--help)
    print_help; exit;;
  -M|--major)
    _version="$(( version_array[0] + 1 )).0.0";;
  -m|--minor)
    _version="${version_array[0]}.$(( version_array[1] + 1 )).0";;
  -p|--patch)
    _version="${version_array[0]}.${version_array[1]}.$(( version_array[2] + 1 ))";;
  -v|--version)
    if ! [[ $2 =~ ${version_regex} ]]; then # Check for basic semantic versioning
      printf "\e[31m%s\e[0m\n" "Wrong version format. Only semantic versioning is supported"; exit 1;
    fi
    _version=$2;;
  *) ;;
esac

# Set the new version
for file in "${_files[@]}"; do
  sed -i "s|\(readonly version=\)\(.*\)|\1${_version}|g" "${file}"
done
