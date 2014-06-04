#!/bin/sh
#
# Author: Duncan Hutty <dhutty@allgoodbits.org>
# Last Modified: 2014-06-04
#
SUMMARY="Backup script to push innobackupex datadirs to a backup file server"
# Description: After innobackupex/xtrabackup has created a backup and the log has been applied, this script will rsync the directory to a backup server
# Where/How/When: cron on the database nodes on a nightly basis or more frequently
# Return Values: 0 - success, 1 - errors
# Expected Output: none, except errors
# Assumptions/Dependencies: linux(!), rsync, scp, ssh (including a key)
#
# Notes: Do not forget to have a script to purge old backups from the backup server!
# 13 3 * * * root rm -rf /data/backups/full && innobackupex --defaults-extra-file=/etc/my.backup.cnf --parallel=8 --no-timestamp --rsync /data/backups/full && innobackupex --use-memory=32G --apply-log /data/backups/full && /opt/bin/backup_mariadb.sh -i -b backup1.example.com -l /data/backups/full -u buinfra -r '/backups/array7/databases'
#       

#set -o nounset  # error on referencing an undefined variable
set -o errexit  # exit on command or pipeline returns non-true
set -o pipefail # exit if *any* command in a pipeline fails, not just the last

PROGNAME=$( /bin/basename $0 )
PROGPATH=$( /usr/bin/dirname $0 )
verbosity=0
dryrun=0

print_usage() {
    echo "${SUMMARY}"; echo ""
    echo "Usage: $PROGNAME [options]"
    echo ""

    echo "-i insecure. Add some lower security options to ssh to cope with changing ssh host keys."
    echo "-k <path to ssh key>"
    echo "-x <path to exclude file>"
    echo "-b backup server (ex: backup1.example.com)"
    echo "-l local path (ex: /data/backups)"
    echo "-r destination root path (ex: /backups/array7/databases/$(hostname --fqdn))"
    echo '-p full destination path (ex: /backups/array7/infra/machine.example.com/testpath), default <remote root>/$(hostname --fqdn)/$(date +%Y%m%d)/$(date +%H%M)'
    echo "-u user name for rsync/ssh, default to current user"

    echo "-n dry run"
    echo "-h Print this usage"
    echo "-v Increase verbosity"
}

print_help() {
        echo "$PROGNAME"
        echo ""
        print_usage
}

while getopts "nhvik:x:b:l:r:p:u:" OPTION;
do
  case "$OPTION" in
    i) insecure=1;;
    k) ssh_key=${OPTARG};;
    x) exclude_file=${OPTARG};;
    b) server=${OPTARG};;
    l) local_path="${OPTARG}/*";;
    r) remote_root=${OPTARG};;
    p) remote_path=${OPTARG};;
    u) user=${OPTARG};;
    n) dryrun=1;;
    h) print_usage
       exit 0 ;;
    v) verbosity=$(($verbosity+1)) ;;
    *) echo "Unrecognised Option: ${OPTARG}"
       print_usage
       exit 1 ;;
  esac
done

[[ $verbosity -gt 2 ]] && set -x
shift $((OPTIND - 1))

# Set vars with defaults
: ${ssh_key:='/etc/backup.key'}
: ${exclude_file:='/etc/backup/mariadbexclude.txt'}
: ${server:='backup'}
: ${local_path:='/data/test'}
: ${remote_root:='/backups/array7/databases'}
: ${user:=$USER}

## Options to rsync
# Get more info out of rsync; use this if you're running by hand instead from cron
[[ $verbosity -gt 0 ]] && verbose="--verbose -h --progress"
# If we want rsync excludes, set them in here
[[ -s ${exclude_file} ]] && exclude="--exclude-from $exclude_file}"
##

DATE="$(date +%Y%m%d)"
TIME="$(date +%H%M)"
FQDN=$(hostname --fqdn)

: ${remote_path:="${remote_root}/${FQDN}/${DATE}/${TIME}"}

# Do we have a (non-vendor) rsync in /opt? Sometimes, for a more recent version
if [[ -x '/opt/bin/rsync' ]];
then 
    rsync='/opt/bin/rsync'
else
    rsync=$(which rsync)
fi

log() {  # standard logger
   local prefix="[$(date +%Y/%m/%d\ %H:%M:%S)]: "
   echo "${prefix} $@" >&2
} 

## Build up ssh opts
ssh_opts="-q"
[[ -s "${ssh_key}" ]] && ssh_opts="${ssh_opts} -i ${ssh_key}"

if [[ $insecure -eq 1 ]];
then
    ssh_opts="$ssh_opts -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
    log "WARN" "Setting -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
fi
##

inprogress() {
# check to see if an rsync to backup server is already in progress
    if ps -ef | grep rsync | egrep -q "${server}"; then
        inprogress="rsync transfer to backup server is in progress: $(ps -ef | grep [r]sync | egrep "${server}")"
    else 
        inprogress=0
    fi
}

inprogress = $(inprogress)
if [[ "$inprogress" != 0 ]];
then
    log "ERROR" "$inprogress"
    exit 1
fi

if [[ $verbosity -gt 1 ]]; then 
    log "DEBUG" "ssh options: $ssh_opts"
    log "DEBUG" "local path: $local_path"
    log "DEBUG" "user: $user"
    log "DEBUG" "server: $server"
    log "DEBUG" "remote path: $remote_path"
fi

[[ $dryrun -eq 1 ]] && exit 0

ssh -l ${user} ${ssh_opts} ${server} "mkdir -p ${remote_path}"

$rsync \
          --archive \
          --inplace \
          --delete-after \
          --delete-excluded \
          ${exclude} ${verbose} \
          -e "ssh $ssh_opts" \
          ${local_path} "${user}@${server}:${remote_path}"

rc_rsync=$?

if (( $rc_rsync)); then
    log "ERROR" "rsync exited with a non-zero exit code: $rc_rsync"
fi

