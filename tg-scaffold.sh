#!/bin/bash
#
# Author: Duncan Hutty <dhutty@allgoodbits.org>
# Last Modified: 2023-06-21
# Usage: ./$0 [options] <args>
#
SUMMARY="Create a directory hierarchy for Terragrunt-managed resources"
# Description:
# Examples:
# Dependencies: bash(1), tree(1)
# Assumptions:
# Notes:

set -o nounset  # error on referencing an undefined variable
set -o errexit  # exit on command or pipeline returns non-true
set -o pipefail # exit if *any* command in a pipeline fails, not just the last

VERSION="0.0.1"
PROGNAME=$(command -v "$0" )
verbosity=0

# Import library functions ?
#. $PROGPATH/utils.sh

print_usage() {
    echo "${SUMMARY}"; echo ""
    echo "Usage: $PROGNAME [options] [<args>]"
    echo ""

    echo "-f force"
    echo "-h Print this usage"
    echo "-v Increase verbosity"
    echo "-V Print version number and exit"
}

print_help() {
        echo "$PROGNAME $VERSION"
        echo ""
        print_usage
}

while getopts "hvfVo:" OPTION;
do
  case "$OPTION" in
    o)  OUT_DIR=${OPTARG}
        ;;
    h)
        print_usage
        exit 0
        ;;
    v)
        verbosity=$((verbosity+1))
        ;;
    V)
        echo "${VERSION}"
        exit 0
        ;;
    *)
        echo "Unrecognised Option: ${OPTION}: ${OPTARG}"
        exit 1
        ;;
  esac
done

log() {
  local prefix
  prefix="[$(date +%Y/%m/%d\ %H:%M:%S)]: "
  echo -n "${prefix}" >&2
  echo "$@" >&2
}

[[ $verbosity -gt 2 ]] && set -x
shift $((OPTIND - 1))

# Set defaults
DEFAULT_OUT_DIR="."
declare -a DEFAULT_REGIONS
DEFAULT_REGIONS=("_global" "us-east-1")
declare -a DEFAULT_ENVS
DEFAULT_ENVS=("dev" "stage" "prod")
declare -a DEFAULT_PROVIDERS
DEFAULT_PROVIDERS=("aws" "kubernetes")
OUT_DIR=${OUT_DIR:-${DEFAULT_OUT_DIR}}
ENVS=${ENVS:-${DEFAULT_ENVS[@]}}
REGIONS=${REGIONS:-${DEFAULT_REGIONS[@]}}
PROVIDERS=${PROVIDERS:-${DEFAULT_PROVIDERS[@]}}
ACCT=1234567890

log "Scaffold Terragrunt to ${OUT_DIR}"

ACCOUNT_STANZA="
locals {
  account_id = \"${ACCT}\"
  account_name = \"\"
}
"

TG_STANZA="
terraform {
  source = \"\"
}

include \"root\" {
  path = find_in_parent_folder()
  expose = true
}

include \"account_config\" {
  path = find_in_parent_folders(\"account.hcl\")
  expose = true
}

include \"environment_config\" {
  path = find_in_parent_folders(\"environment.hcl\")
  expose = true
}

include \"region_config\" {
  path = find_in_parent_folders(\"region.hcl\")
  expose = true
}

# dependency \"foo\" {
#  config_path = \"../foo\"
# }

locals {
}

inputs = {}
"
# shellcheck disable=SC2068
for ENV in ${ENVS[@]}; do
  mkdir -p "${OUT_DIR}/terragrunt/${ACCT}/"

ENVIRONMENT_STANZA="
locals {
  environment = \"${ENV}\"
}
"
  mkdir -p "${OUT_DIR}/terragrunt/${ACCT}/${ENV}/"
  echo "$ENVIRONMENT_STANZA" > "${OUT_DIR}/terragrunt/${ACCT}/${ENV}/environment.hcl"
  for REGION in ${REGIONS[@]}; do

REGION_STANZA="
locals {
  region = \"${REGION}\"
}
"

    mkdir -p "${OUT_DIR}/terragrunt/${ACCT}/${ENV}/${REGION}/infra"
    mkdir -p "${OUT_DIR}/terragrunt/${ACCT}/${ENV}/${REGION}/app"
    echo "${ACCOUNT_STANZA}" > "${OUT_DIR}/terragrunt/${ACCT}/account.hcl"
    echo "${REGION_STANZA}" > "${OUT_DIR}/terragrunt/${ACCT}/${ENV}/${REGION}/region.hcl"
    echo "${TG_STANZA}" > "${OUT_DIR}/terragrunt/${ACCT}/${ENV}/${REGION}/infra/terragrunt.hcl"
    echo "${TG_STANZA}" > "${OUT_DIR}/terragrunt/${ACCT}/${ENV}/${REGION}/app/terragrunt.hcl"
    for PROVIDER in ${PROVIDERS[@]}; do

PROVIDER_STANZA="
generate \"${PROVIDER}_provider\" {
  path = \"${PROVIDER}_provider.tf\"
  if_exists = \"overwrite\"
  contents = <<EOF
provider \"${PROVIDER}\" {

}
EOF"

      echo "${PROVIDER_STANZA}" >> "${OUT_DIR}/terragrunt/${ACCT}/${ENV}/${REGION}"/infra/terragrunt.hcl
      echo "${PROVIDER_STANZA}" >> "${OUT_DIR}/terragrunt/${ACCT}/${ENV}/${REGION}"/app/terragrunt.hcl
    done
  done
done
tree "${OUT_DIR}"
