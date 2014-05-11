#!/bin/bash

SUMMARY="git pull all repositories"

VERSION="0.0.1"
PROGNAME=$( /bin/basename $0 )
PROGPATH=$( /usr/bin/dirname $0 )

print_usage() {
    echo "${SUMMARY}"; echo ""
    echo "Usage: $PROGNAME [options] [<args>]"
    echo ""

    echo "-d base directory that contains your git repos, default ~/gits"
    echo "-m maxdepth for find(1) to look for git repos below the base"
    echo "-h Print this usage"
    echo "-v Increase verbosity"
    echo "-V Print version number and exit"
}
  
print_help() {
        echo "$PROGNAME $VERSION"
        echo ""
        print_usage
}


while getopts "hvVd:m:" OPTION;
do
  case "$OPTION" in
    d)  GITDIR=${OPTARG} ;;
    m)  MAXDEPTH=${OPTARG} ;;
    h) print_usage
        exit 0 ;;
    v) verbosity=$(($verbosity+1)) ;;
    V) echo "${VERSION}"
        exit 0 ;;
    *)
        echo "Unrecognised Option: ${OPTARG}"
        exit 1 ;;
  esac
done

: ${MAXDEPTH:=2}
: ${GITDIR:="${HOME}/gits"}

for d in $(find ${GITDIR} -maxdepth ${MAXDEPTH} -type d );
do
    if [ -d ${d}/.git ]; then
        echo $d; cd $d; git pull && git l2 | head -n 1; cd ${GITDIR};
    fi;
done

