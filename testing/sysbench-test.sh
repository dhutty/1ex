#!/bin/bash
#
# Author: Duncan Hutty <dhutty@allgoodbits.org>
# Last Modified: 2014-01-23
# Usage: ./$0 [options] <args>
#
SUMMARY="Run sysbench OLTP tests against a database service"
# Description:
#
#
# Input:
#
# Output:
#   A series of files that contain sysbench output, whose names include the datetime, the db name and the number of threads used.
#   Summary files that contain a table of the number of transactions per second against the number of threads used
#
# Examples:
#   ./sysbench-test.sh -u dhutty -p foo -n test_sas -m 8 -o ~/tmp/sysbench -s /var/lib/mysql/mysql.sock
#   ./sysbench-test.sh -vv -f -u dhutty -p foo -n test_ssd -m 48 -r 1000 -z 1000000 -o ~/tmp/sysbench -s /var/lib/mysql/mysql.sock; sh sysbench-test.sh -u dhutty -p foo -n test_sas -m 48 -r 1000 -z 1000000 -o ~/tmp/sysbench -s /var/lib/mysql/mysql.sock
#
# Dependencies:
#   Known to work with sysbench-0.4.12, probably some earlier versions
#
# Assumptions:
#   Database access for the specified creds/dbname, you should already have created the database, although it need not have any tables in it.
#
# Notes:
#   As with other benchmarking, ensure that the system is doing as little as possible other than your test: turn off cron, any other services you can.
#
#   You probably want to boot the test system limiting the amount of memory so that you're actually hitting disk instead of just memory caches, by setting a kernel boot parameter mem=512M or similar
#   You can then use gnuplot to
# gnuplot > set xlabel "Threads"; set ylabel "Transactions/sec";
#           plot "/home/dhutty/tmp/sysbench/sysbench.test_ssd.dat" using 1:2 title 'SSD', "/home/dhutty/tmp/sysbench/sysbench.test_sas.dat" using 1:2 title 'SAS'
#

VERSION="0.1"
PROGNAME=$( /bin/basename $0 )
PROGPATH=$( dirname $0 )
DATETIME=$(date "+%Y%m%d-%H%M")

# Import library functions
#. $PROGPATH/utils.sh

#Modify these to override defaults
DB_DEFAULT='mysql'
REQUESTS_DEFAULT='250000'
SIZE_DEFAULT='1000000'
[[ -e $(which nproc) ]] && CORES=$(nproc)
THREADS_DEFAULT=${CORES-1}

print_usage() {
    echo "${SUMMARY}"; echo ""
    echo "Usage: $PROGNAME [options] [<args>]"
    echo ""

    echo "-d <mysql|pgsql>, default: mysql"
    echo "-n <db database name>, default: sbtest"
    echo "-u <db username>"
    echo "-p <db password>"
    echo "-s <mysql socket>"
    echo ""
    echo "-m <max number of threads>, default: # of cores or 1"
    echo "-r <max number of requests>, default: 250000"
    echo "-z <oltp table size>, default: 1000000"
    echo "-o <output directory>"
    echo "-l <logfile>"
    echo ""
    echo "-f force: this is a machine that isn't doing anything else, a database that doesn't have any important data"
    echo "-h Print this usage"
    echo "-v Increase verbosity"
    echo "-V Print version number and exit"
}

print_help() {
        echo "$PROGNAME $VERSION"
        echo ""
        print_usage
        echo ""
        echo "${SUMMARY}"
}

while getopts "fhvVd:n:u:p:s:m:r:z:o:l:" OPTION;
do
  case "$OPTION" in
    d) 
        driver="$OPTARG"
        ;;
    n)
        name="$OPTARG"
        ;;
    u) 
        user="$OPTARG"
        ;;
    p)
        pass="$OPTARG"
        ;;
    s)
        socket="$OPTARG"
        ;;        
    m)
        max_threads="$OPTARG"
        ;;
    r)
        max_requests="$OPTARG"
        ;;
    z)
        size="$OPTARG"
        ;;
    o)
        outdir="$OPTARG"
        ;;
    l)
        logfile="$OPTARG"
        ;;
    h)
        print_help
        exit 0
        ;;
    f)
        force=1
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

[[  $verbosity -gt 2 ]] && set -x
shift $((OPTIND - 1))

# set defaults
db=${dbdriver-$DB_DEFAULT}
requests=${max_requests-$REQUESTS_DEFAULT}
threads=${max_threads-$THREADS_DEFAULT}
size=${size-$SIZE_DEFAULT}
logfile=${logfile-${outdir}/sysbench.log}

# Bad parameter checking
if [ "$db" != 'mysql' ] && [ "$db" != 'pgsql' ];
then print_usage
    exit 1
fi

if [ "$socket" != '' ];
then
    if [ "$db" == 'mysql' ];
    then 
        socket=--mysql-socket=${socket}
    else
        print_usage
    fi
fi

if [ ! -d $outdir ];
then
    echo "Output directory: $outdir does not exist"
    exit 1
fi

#TODO: if mysql, no HOST and no socket, then socket=/var/lib/mysql/mysql.sock


[ "$name" != '' ] && DBNAME="--${db}-db=${name}"
[ "$user" != '' ] && DBUSER="--${db}-user=${user}"
[ "$pass" != '' ] && DBPASS="--${db}-password=${pass}"


[[ $verbosity -gt 0 ]] && echo "Beginning OLTP test(s) on ${db}: ${name}"
for t in $(seq 1 ${threads}); do
if [[ $force -gt 0 ]];
then    
# (re)init
# drop the table
mysql -u $user --password="$pass" -D "${name}" -e "drop table sbtest;"
[[ $USER == 'root' ]] && echo 3 > /proc/sys/vm/drop_caches && sleep 3
fi

#"prepare" for sysbench test
[[ $verbosity -gt 0 ]] && echo "Preparing table, size: ${size} for ${name}"
if [ $db == 'mysql' ] ;
then
sysbench --db-driver=$db  --test=oltp --mysql-table-engine=innodb --oltp-table-size=${size} $socket $DBUSER $DBPASS $DBNAME prepare 2>&1 >> $logfile
else 
sysbench --db-driver=$db  --test=oltp --oltp-table-size=${size} $DBUSER $DBPASS $DBNAME prepare 2>&1 >> $logfile
fi

#run test
[[ $verbosity -gt 1 ]] && echo "Test with threads: ${t} for ${name}"
if [ $db == 'mysql' ] ;
then
sysbench --db-driver=$db  --test=oltp --mysql-table-engine=innodb --oltp-table-size=${size} $socket $DBUSER $DBPASS $DBNAME --num-threads=$t --max-requests=$requests --oltp-test-mode=complex run >> ${outdir}/sysbench-${DATETIME}-${db}-${name}-${t}
else 
sysbench --db-driver=$db  --test=oltp --oltp-table-size=${size} $DBUSER $DBPASS $DBNAME prepare
fi

done

# This parses each of the files written by sysbench, writing the number of threads against the number of transactions per sec into a file that can be read by gnuplot
for f in $(ls ${outdir}/sysbench-${DATETIME}*);
do
    if [[ "$basename $f" =~ "$name" ]];
    then 
        echo -e "$(echo $f|cut -d'-' -f6) \t $(awk '/transactions:/ { print $3 }' $f | sed 's/^(//')" >> ${outdir}/sysbench.${DATETIME}-${name}.dat
    fi
done

