#!/bin/bash
#
# Author: Duncan Hutty <>
# Last Modified: 2014-04-17
#
SUMMARY="Rename mysql database schema by renaming tables"

# Dependencies:
#
# Assumptions:
#
# Notes: Based on Percona's rename_db, with additional logging, conveniences, error checking, scripting conventions

### This is setup/invocation handling

VERSION="0.0.1"
PROGNAME=$( /bin/basename $0 )
PROGPATH=$( /usr/bin/dirname $0 )

print_usage() {
    echo "${SUMMARY}"; echo ""
    echo "Usage: $PROGNAME [options] <old schema name> <new schema name>"
    echo ""

    echo "-f defaults-extra-file"
    echo "-H mysql server hostname"
    echo "-h Print this usage"
    echo "-v Increase verbosity"
    echo "-V Print version number and exit"
}

print_help() {
        echo "$PROGNAME $VERSION"
        echo ""
        print_usage
}

while getopts "hvf:H:V" OPTION;
do
  case "$OPTION" in
    f)  defaults_file=${OPTARG}
        ;;
    H)  host=${OPTARG}
        ;;
    h)  print_usage
        exit 0
        ;;
    v)  verbosity=$(($verbosity+1))
        ;;
    V)  echo "${VERSION}"
        exit 0
        ;;
    *)  echo "Unrecognised Option: ${OPTARG}"
        exit 1
        ;;
  esac
done

log() {  # standard logger
   local prefix="[$(date +%Y/%m/%d\ %H:%M:%S)]: "
   echo "${prefix} $@" >&2
} 

[[ $verbosity -gt 2 ]] && set -x
shift $((OPTIND - 1))

mysql="mysql"
mysqldump="mysqldump"

if [[ $defaults_file != "" ]];
then
     mysql="${mysql} --defaults-extra-file=${defaults_file}"
     mysqldump="${mysqldump} --defaults-extra-file=${defaults_file}"
fi

if [[ $host != "" ]];
then 
    mysql="${mysql} -h ${host}"
    mysqldump="${mysqldump} -h ${host}"
fi

log "DEBUG" "mysql command syntax: ${mysql}"

if [[ "$#" -lt 2 ]]; then
    print_usage
    log "ERROR" "Two database schemata required"
    exit 1
fi

if [[ "$1" == "$2" ]];
then
    log "ERROR" "Two DIFFERENT database schemata required"
    exit 1
fi

db_exists=$( ${mysql} -e "show databases like '$2'" -sss )
if [ -n "$db_exists" ]; then
    log "ERROR" "New database already exists $2"
    exit 1
fi

### This is the start of the action

TIMESTAMP=$( date +%s )
character_set=$( ${mysql} -e "show create database $1\G" -sss |  awk '/^Create/ {print $10}')
TABLES=$( ${mysql} -e "select TABLE_NAME from information_schema.tables where table_schema='$1' and TABLE_TYPE='BASE TABLE'" -sss )
STATUS=$?
if [ "$STATUS" != 0 ] || [ -z "$TABLES" ]; then
    log "ERROR"  "Cannot retrieve tables from $1"
    exit 1
fi
log "INFO" "create database $2 DEFAULT CHARACTER SET $character_set"
${mysql} -e "create database $2 DEFAULT CHARACTER SET $character_set"
TRIGGERS=$( ${mysql} $1 -e "show triggers\G" | grep Trigger: | awk '{print $2}' )
VIEWS=$( ${mysql} -e "select TABLE_NAME from information_schema.tables where table_schema='$1' and TABLE_TYPE='VIEW'" -sss )
if [ -n "$VIEWS" ]; then
    ${mysqldump} $1 $VIEWS > /tmp/${2}_views${TIMESTAMP}.dump
fi
${mysqldump} $1 -d -t -R -E > /tmp/${2}_triggers${TIMESTAMP}.dump
for TRIGGER in $TRIGGERS; do
    log "INFO" "drop trigger $TRIGGER"
    ${mysql} $1 -e "drop trigger $TRIGGER"
done
for TABLE in $TABLES; do
    log "INFO" "rename table $1.$TABLE to $2.$TABLE"
    ${mysql} $1 -e "SET FOREIGN_KEY_CHECKS=0; rename table $1.$TABLE to $2.$TABLE"
done
if [ -n "$VIEWS" ]; then
    log "INFO" "loading views"
    ${mysql} $2 < /tmp/${2}_views${TIMESTAMP}.dump
fi
log "INFO" "loading triggers, routines and events"
${mysql} $2 < /tmp/${2}_triggers${TIMESTAMP}.dump
TABLES=`${mysql} -e "select TABLE_NAME from information_schema.tables where table_schema='$1' and TABLE_TYPE='BASE TABLE'" -sss`
if [ -z "$TABLES" ]; then
    log "INFO" "Dropping database $1"
    ${mysql} $1 -e "drop database $1"
fi
if [ $( ${mysql} -e "select count(*) from mysql.columns_priv where db='$1'" -sss ) -gt 0 ]; then
    COLUMNS_PRIV="    UPDATE mysql.columns_priv set db='$2' WHERE db='$1';"
fi
if [ $( ${mysql} -e "select count(*) from mysql.procs_priv where db='$1'" -sss ) -gt 0 ]; then
    PROCS_PRIV="    UPDATE mysql.procs_priv set db='$2' WHERE db='$1';"
fi
if [ $( ${mysql} -e "select count(*) from mysql.tables_priv where db='$1'" -sss ) -gt 0 ]; then
    TABLES_PRIV="    UPDATE mysql.tables_priv set db='$2' WHERE db='$1';"
fi
if [ $( ${mysql} -e "select count(*) from mysql.db where db='$1'" -sss ) -gt 0 ]; then
    DB_PRIV="    UPDATE mysql.db set db='$2' WHERE db='$1';"
fi
FINISH=$(date +%s)
ELAPSED=$((${FINISH} - ${TIMESTAMP}))
if [[ ${ELAPSED} -eq 0 ]]
then ELAPSED="NEXT TO NO TIME"
else ELAPSED="${ELAPSED} seconds"
fi
echo "Renamed $1 to $2 in ${ELAPSED}"

if [ -n "$COLUMNS_PRIV" ] || [ -n "$PROCS_PRIV" ] || [ -n "$TABLES_PRIV" ] || [ -n "$DB_PRIV" ]; then
    log "WARNING" "If you want to rename the grants you need to run ALL output below:"
    if [ -n "$COLUMNS_PRIV" ]; then echo "$COLUMNS_PRIV"; fi
    if [ -n "$PROCS_PRIV" ]; then echo "$PROCS_PRIV"; fi
    if [ -n "$TABLES_PRIV" ]; then echo "$TABLES_PRIV"; fi
    if [ -n "$DB_PRIV" ]; then echo "$DB_PRIV"; fi
    echo "    flush privileges;"
    log "WARNING" "And if you are running on a Galera cluster, you need to run the above on EVERY node in the cluster individually!"
fi
