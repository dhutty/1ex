#!/bin/sh
#
# Last Modified: 2014-05-04
# Usage: ./$0 [options] <args>
#
SUMMARY="wrapper for mysqlslap(1) with common options to create fake data/queries"
#
# Input:
#
# Output:
#
# Examples:
#    for c in $(seq 5 5 25)
#    do for q in 50 500 5000
#      do
#        mysql_test.sh -c $c -i 1 -q $q -f | logger -t dbtest
#      done
#    done
#
#
# Dependencies: mysqlslap(1), database privileges
#
# Assumptions:
#       That the tables and queries your application(s) care about look like those performed by this test.
#
# Notes:

VERSION="0.0.1"
PROGNAME=$( /bin/basename $0 )
PROGPATH=$( /usr/bin/dirname $0 )

# Import library functions
#. $PROGPATH/utils.sh

print_usage() {
    echo "${SUMMARY}"; echo ""
    echo "Usage: $PROGNAME [options] [<args>]"
    echo ""

    echo "-c N, specify concurrency"
    echo "-i N, specify iterations"
    echo "-q N, specify number of queries"
    echo "-u <user>, the database user"
    echo "-H <host>, the database server hostname"
    echo "-p <password>, specify a password"
    echo "-f , csv output"
    echo "-h Print this usage"
    echo "-v Increase verbosity"
    echo "-V Print version number and exit"
}

print_help() {
        echo "$PROGNAME $VERSION"
        echo ""
        print_usage
}

log() {  # standard logger
   local prefix="[$(date +%Y/%m/%d\ %H:%M:%S)]: "
   echo "${prefix} $@" >&2
} 

: ${SLAPUSER:="slaptest"}
: ${HOST:="mariadb.example.com"}
: ${queries:=500}

if [[ -r "${HOME}/.mysqlslappasswd" ]];
then PASS=$(cat "${HOME}/.mysqlslappasswd")
fi

while getopts "hvfVc:i:q:H:u:p:" OPTION;
do
  case "$OPTION" in
    c)  concurrency=${OPTARG} ;;
    i)  iterations=${OPTARG} ;;
    q)  queries=${OPTARG} ;;
    H)  HOST=${OPTARG} ;;
    u)  SLAPUSER=${OPTARG} ;;
    p)  PASS=${OPTARG} ;;
    f)  OPTS="$OPTS --csv" ;;
    h) print_usage; exit 0 ;;
    v) verbosity=$(($verbosity+1)) ;;
    V) echo "${VERSION}"; exit 0 ;;
    *) echo "Unrecognised Option: ${OPTARG}"; exit 1 ;;
  esac
done

[[ $verbosity -gt 2 ]] && set -x
shift $((OPTIND - 1))

if [[ $concurrency != "" ]];
then concurrency="--concurrency=${concurrency}"
fi

if [[ $iterations != "" ]];
then iterations="--iterations=${iterations}"
fi

SLAPOPTS="--auto-generate-sql --auto-generate-sql-add-autoincrement --auto-generate-sql-execute-number=${queries} --auto-generate-sql-secondary-indexes=5 --auto-generate-sql-unique-query-number=50 --auto-generate-sql-unique-write-number=50 --commit=50 --detach=100 --create-schema=slaptest --engine=InnoDB --number-char-cols=20 --number-int-cols=5 -h ${HOST} -u ${SLAPUSER} -p${PASS}"
#The sed at the end is to make mysqlslap's output be more suitable for our Splunk
mysqlslap $SLAPOPTS ${OPTS} $iterations $concurrency | sed -e "s/InnoDB,mixed,/$(date +%s),/" -e "s/$/,${HOST}/"
