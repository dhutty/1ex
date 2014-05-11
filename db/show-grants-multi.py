#!/usr/bin/env python

""" Brief Summary: A mysqld_multi aware wrapper for pt-show-grants from percona-toolkit
Maintainer: Duncan Hutty <dhutty@allgoodbits.org>
Purpose: Dump all grants from instances defined in /etc/my.cnf
Where/How/When:
Return Values:
Expected Output: SQL statements that can be used to reinstantiate privilege grants in a new mysqld instance
Assumptions: requires my.cnf with:
                #instance-name
                [mysqldN]
                various config options for this instance
            See function load_multi_map()

Dependencies: python26, python argparse, percona-toolkit 

Example usage:
    show-grants-multi -c /etc/my.cnf -f /etc/my.backup.cnf -u root --log-level=info --instance scdoeinfo_prod -m
"""

__author__ = "Duncan Hutty"
__credits__ = ["Duncan Hutty"]
__version__ = "$Id$"
__maintainer__ = "Duncan Hutty"
__email__ = "dhutty@allgoodbits.org"

import os, pwd, sys
import logging
import MySQLdb
import re
import subprocess

try: import argparse
except ImportError:
    print "Install python-argparse?"
    sys.exit(1)

EXCLUDED = ['mysql', 'information_schema', 'performance_schema', 'test', 'lost+found']
CONFIG = {}
DBOPTS = {}
LOGGER = None

def get_logger():
    """ Set up logging level. default: ERROR.
    """
    global LOGGER
    LOGGER = logging.getLogger()
    LOGGER.setLevel(logging.ERROR)
    stderr = logging.StreamHandler()
    stderr.setFormatter(logging.Formatter("%(asctime)s %(levelname)s: %(message)s", datefmt='%Y-%m-%d %H:%M:%S'))
    LOGGER.addHandler(stderr)
    return LOGGER

def handle_command_line():
    """ Handle command line.
    """
    parser = argparse.ArgumentParser(description='Database Grant Dumper', epilog="Dump privileges from specified mysql instance(s).")
    parser.add_argument('-b', '--backup-root', default=None, help='specify root destination directory for grant dumps')
    parser.add_argument('-c', '--config-file', default='/etc/my.cnf', help='specify config file for mysql')
    parser.add_argument('-f', '--defaults-file', default='/etc/my.backup.cnf', help='specify defaults file for mysql')
    parser.add_argument('-u', '--user', default=pwd.getpwuid(os.getuid())[0], help='specify a database user')
    parser.add_argument('-p', '--password', help='specify a database password')
    parser.add_argument('-s', '--socket', default='/var/lib/mysql/mysql.sock', help='specify socket')
    parser.add_argument('--log-level', dest='log_level', choices=['debug', 'info', 'warning', 'error', 'critical'], help='specify a log level')
    parser.add_argument('-i', '--instance', action='append', help='specify a instance, can be repeated.')
    parser.add_argument('-m', '--multi-aware', action='store_true', help='make aware of mysqld_multi: calculate sockets')
    parser.add_argument('-n', '--dry-run', action='store_true', help='Dry run, do not change anything, only report what would happen')
    parser.add_argument('-v', '--verbose', action='store_true', help='more verbosity')
    args = parser.parse_args()
    
    #Parameter checking TODO
    if args.defaults_file:
        try:
            open(args.defaults_file, 'r')
        except IOError, e:
            sys.exit(e)

    for f in [args.config_file, args.defaults_file]:
        if not os.path.exists(f):
            print("Specified file: %s does not exist" % f)
            sys.exit(1)
    DBOPTS['read_default_file'] = os.path.abspath(args.defaults_file)
    DBOPTS['user'] = args.user
    DBOPTS['socket'] = args.socket
    DBOPTS['config_file'] = args.config_file
    CONFIG['log_level'] = args.log_level
    CONFIG['multi_aware'] = args.multi_aware
    CONFIG['dry_run'] = args.dry_run
    CONFIG['verbose'] = args.verbose
    if args.backup_root:
        CONFIG['backup_root'] = args.backup_root
    if args.password:
        DBOPTS['passwd'] = args.password
    return  args.instance, CONFIG

def load_multi_map(conf_path):
    """ Takes a path to a my.cnf file and returns an array of dicts: [ { "name": <instance_name>, "socket": <instance_socket>, "databases": [db1, db2]} ]
        Requires that the stanza defining the instance is immediately preceded by a commented line with the database name
    """
    try: import configparser as CP
    except ImportError:
        try: import ConfigParser as CP
        except ImportError:
            LOGGER.error("no python module for configparser?")
            sys.exit(1)
    mysqlconfig = CP.ConfigParser()
    try: 
        mysqlconfig.read(conf_path)
    except IOError, e:
        LOGGER.error("Could not parse config: %s, %s" % (conf_path, e))
    except CP.ParsingError, e:
        LOGGER.error("Could not parse config: %s, %s" % (conf_path, e))
    except Exception, e:
        LOGGER.error("Could not parse config: %s, %s" % (conf_path, e))
    instance_list = []
    instances = mysqlconfig.sections()
    LOGGER.info("Found instances: %s" % instances)
    for instance in instances:
        p = re.compile(r"\d+$")
        number = p.search(instance)
        if number:
            instance_dict = {}
            # grep the file for the preceding line and grab the name
            p1 = subprocess.Popen(["egrep", "-B", "1", ''.join(['\[', instance, '\]']), conf_path], stdout=subprocess.PIPE)
            p2 = subprocess.Popen(["egrep", "-v", "'^\['"], stdin=p1.stdout, stdout=subprocess.PIPE)
            name = p2.communicate()[0].lstrip('#')
            name = re.sub(r'\n.*$', '', name)
            # populate the dict
            LOGGER.debug("Found an instance %s" % name)
            instance_dict['name'] = name 
            instance_dict['socket'] = mysqlconfig.get(instance, 'socket')
            instance_list.append(instance_dict)
    return  instance_list

def get_databases(socket):
    """ Connect to a mysqld instance and return the databases.
    """
    databases = []
    try:
        conn = MySQLdb.connect(user=DBOPTS['user'], unix_socket=socket, read_default_file=DBOPTS['read_default_file'])
        cursor = conn.cursor()
        cursor.execute("SHOW DATABASES;")
        for row in cursor.fetchall():
            if row[0] not in EXCLUDED:
                databases.append(row[0])
        return databases
    except MySQLdb.Error, e:
        LOGGER.error("Error %d: %s" % (e.args[0], e.args[1]))
        sys.exit (1)

def get_grants(socket, outhandle, inst_name=None):
    """ Wrap pt-show-grants to get mysql grant statements for all privileges granted on this instance.
        Takes a socket and a name for the instance and a destination filehandle.
        Returns SQL.
    """
    show_grants = ['pt-show-grants']
    # --defaults-extra-file, if offered, must be the first option
    show_grants.append(''.join(['--defaults-file=', DBOPTS['read_default_file']]))
    if 'passwd' in DBOPTS:
        show_grants.append(''.join(['--password=', DBOPTS['passwd']]))
    show_grants.append(''.join(['--user=', DBOPTS['user']]))
    show_grants.append(''.join(['--socket=', socket]))
    if CONFIG['dry_run']:
        LOGGER.info("mysql show_grants: %s" % show_grants)
        return True
    else:
        try:
            subprocess.call(show_grants, stdout=outhandle)
            LOGGER.info('Dumped privileges for "%s" from %s' % (inst_name, socket))
        except subprocess.CalledProcessError, e:
            LOGGER.error("Failed subprocess for pt-show-grants %s: %s" % (show_grants, e))
        except:
            LOGGER.error( "mysql show_grants: %s" % show_grants)
            return False

def main():
    global DBOPTS
    global CONFIG
    instance, CONFIG = handle_command_line()
    dry_run = CONFIG['dry_run']
    log_level = CONFIG['log_level']
    LEVELS = {'debug': logging.DEBUG,
              'info': logging.INFO,
              'warning': logging.WARNING,
              'error': logging.ERROR,
              'critical': logging.CRITICAL}
    logger = get_logger()
    if log_level is not None:
        logger.setLevel(LEVELS.get(log_level))
        logger.debug("set logging to %s" % log_level)
    if dry_run:
        logger.info( "DRYRUN %s" % dry_run)
    instances = []
    if CONFIG['multi_aware']:
        multi_map = load_multi_map(os.path.abspath(DBOPTS['config_file']))
        if instance is None:
            instances = multi_map
        else:
            #only add an instance from multi_map if it matches one requested
            for inst in multi_map:
                if inst['name'] in instance:
                    instances.append(inst) 
    else:
        # not mysqld_multi: ensure that instances is a single element array, containing a dict that describes the (only) instance
        instances = [ { 'socket': DBOPTS['socket'] } ]
    for inst in instances:
        logger.debug("instance keys: %s" % inst.keys())
        if 'backup_root' in CONFIG.keys():
            #backup_root given: write there
            if 'name' in inst.keys():
                target = os.path.join(CONFIG['backup_root'], inst['name'], 'grants.sql')
                if not os.path.exists(os.path.dirname(target)):
                    logger.debug( "making dir: %s " % (os.path.dirname(target)))
                    try:
                        os.makedirs(os.path.dirname(target))
                    except Error, e:
                        logger.error( "Failed to mkdir %s" % e)
                outhandle = open(target, 'w')
            else:
                target = os.path.join(CONFIG['backup_root'], 'grants.sql')
                outhandle = open(target, 'w')
            if CONFIG['verbose'] > 0:
                outhandle.write("-- Instance: %s" % inst['name'])
                outhandle.write('-- Databases in %s: %s' % (inst['name'], get_databases(inst['socket'])))
                outhandle.flush()
            get_grants(inst['socket'], outhandle)
            if CONFIG['verbose'] > 0:
                outhandle.write("-- End of Instance: %s" % inst['name'])
        else:
            # No backup_root: write to stdout
            if CONFIG['verbose'] > 0:
                print("-- Instance: %s" % inst['name'])
                print('-- Databases in %s: %s' % (inst['name'], get_databases(inst['socket'])))
                sys.stdout.flush()
            get_grants(inst['socket'], sys.stdout, inst_name=inst['name'])
            if CONFIG['verbose'] > 0:
                print("-- End of Instance: %s" % inst['name'])

if __name__ == '__main__':
    """If this is a module file only, run tests, otherwise do work!
    """
    sys.exit(main())

