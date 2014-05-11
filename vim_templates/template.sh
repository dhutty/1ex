#!/bin/sh
#
# Author: Duncan Hutty <>
# Last Modified: 2014-04-16
# Usage: ./$0 [options] <args>
#
SUMMARY="one line summary"
# Description:
#
#
# Input:
#
# Output:
#
# Examples:
#
# Dependencies:
#
# Assumptions:
#
# Notes:

set -o nounset  # error on referencing an undefined variable
set -o errexit  # exit on command or pipeline returns non-true
set -o pipefail # exit if *any* command in a pipeline fails, not just the last

VERSION="0.0.1"
PROGNAME=$( /bin/basename $0 )
PROGPATH=$( /usr/bin/dirname $0 )

# Import library functions
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

while getopts "hvfV" OPTION;
do
  case "$OPTION" in
    h)
        print_usage
        exit 0
        ;;
    v)
        verbosity=$(($verbosity+1))
        ;;
    V)
        echo "${VERSION}"
        exit 0
        ;;
    *)
        echo "Unrecognised Option: ${OPTARG}"
        exit 1
        ;;
  esac
done

log() {  # standard logger: log "INFO" "something happened"
   local prefix="[$(date +%Y/%m/%d\ %H:%M:%S)]: "
   echo "${prefix} $@" >&2
} 

[[ $verbosity -gt 2 ]] && set -x
shift $((OPTIND - 1))

