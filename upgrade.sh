#!/bin/bash

## ----------------------------------------------------------------------------- ##
## TODO
## ----------------------------------------------------------------------------- ##
## -?-  Make PATH an argument (for binaries in non-standard locations) (??? sec)
## -?-  Yum/RPM exit with proper revert documentation links (???)
## -N-  Add upgrade=force option with logic for database_upgrade
## -N-  Database import function (???) [Considering optional]
## -N-  MariaDB 10.6 repo existence check... existence should be handled by puppet
## -x-  Add confirmation input/auto-confirm command-line flag
## -x-  Add disk usage command line options
## -x-  Add schema backup command line option
## -x-  Add schema backup compression hierarcy: xz, bz2, gz, none
## -x-  Add schema backup directory as command line option
## -x-  Add schema backup disk space check
## -x-  Add schema backup function
## -x-  Add short flags
## -x-  Add yum return code checks
## -x-  Backup removal/cleanup
## -x-  Check for innodb_fast_shutdown value in memory (???)
## -x-  Check for innodb_fast_shutdown value on disk
## -x-  Check for innodb_force_recovery value in memory (???)
## -x-  Check for innodb_force_recovery value on disk
## -x-  Cleanup trap function
## -x-  Clear database backup directory before each run (recreate file tree)
## -x-  Create DO_NOT_UPGRADE flag that supercedes --force-upgrade flag
## -x-  Dual disk usage check, include absolute (relative to datadir size)
## -x-  Dynamically define mysql wait for polling loop based on max wait time
## -x-  Error on empty DB_PACKAGE_LIST (or at least verify)
## -x-  Function for necessary/required package installation
## -x-  Help function
## -x-  Improve/Add comments
## -x-  Introduce replication check and --ignore-replication flag
## -x-  Log file
## -x-  Make run idempotent: Do not run if already on target version
## -x-  Place upper limit on database_backup_wait_for_completion (???)
## -x-  Reorder to check for packages prior to anything
## -x-  Set PATH variable
## -x-  Split initial and current service enabled/activation statuses
## -x-  Start service if deactivated, for the purpose of upgrade and backups
## -x-  Use getopts instead of iteration (not show stopper)
## -x-  Wait for service shutdown or error out
## -x-  Wait for service startup or error out
## -x-  What to do if database service is not running?

## ----------------------------------------------------------------------------- ##
## EXECUTE
## ----------------------------------------------------------------------------- ##
trap _trap_leave SIGINT SIGTERM


## ----------------------------------------------------------------------------- ##
## EXPORT
## ----------------------------------------------------------------------------- ##
export PS_FORMAT="user:15,lwp:10,stat:5,wchan:20,etime:10,command"
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin


## ----------------------------------------------------------------------------- ##
## VARIABLES
## ----------------------------------------------------------------------------- ##
declare -A CONFIG
declare -A DBCONFIG_RECURSIVE_ON_DISK
declare -A DBCONFIG_ON_DISK
declare -A DBCONFIG_IN_MEMORY
declare -A EXIT_CODE
declare -A EXIT_MESSAGE
declare -A REPOSITORY
declare -A OPTIONMAP


## -------------------------------------------------------------------------------
## This array will be populated with the currently installed database
## package names
DB_PACKAGE_LIST=()


## -------------------------------------------------------------------------------
## This array lists all binaries/packages that should be present on the server
REQUIRED_BINARIES=(ss mysqld yum mysqldump mariadb-upgrade)


## -------------------------------------------------------------------------------
## Mapping of long switches and flags to their short counterparts
## Options with arguments
OPTIONMAP[arg_backup-directory]='D'
OPTIONMAP[arg_backup-max-wait-seconds]='w'
OPTIONMAP[arg_disable-repo]='d'
OPTIONMAP[arg_disk-datadir-size-ratio]='R'
OPTIONMAP[arg_do-not-upgrade-file]='X'
OPTIONMAP[arg_enable-repo]='r'
OPTIONMAP[arg_log-file]='l'
OPTIONMAP[arg_max-disk-usage-percent]='P'
OPTIONMAP[arg_source-repo]='s'
OPTIONMAP[arg_target-repo]='t'

## Flags/switches (no values)
OPTIONMAP[flag_backup-schemas]='b'
OPTIONMAP[flag_cleanup-only]='O'
OPTIONMAP[flag_cleanup]='o'
OPTIONMAP[flag_color]='c'
OPTIONMAP[flag_colour]='c'
OPTIONMAP[flag_confirm-upgrade]='y'
OPTIONMAP[flag_debug]='v'
OPTIONMAP[flag_force-backup]='f'
OPTIONMAP[flag_help]='h'
OPTIONMAP[flag_ignore-replication]='i'
OPTIONMAP[flag_print-config]='p'


## -------------------------------------------------------------------------------
## All global (relative to the script) configurations are defined here
## Booleans associated with command line input
CONFIG[CLEANUP]=false
CONFIG[CLEANUP_ONLY]=false
CONFIG[DATABASE_BACKUP_PERFORM]=false
CONFIG[DATABASE_BACKUP_PERFORM_FORCE]=false
CONFIG[DATABASE_REPLICATION_IGNORE]=false
CONFIG[DEBUG]=false
CONFIG[PRINT_CONFIG]=false
CONFIG[PRINT_WITH_COLOUR]=false
CONFIG[UPGRADE_CONFIRM]=false
CONFIG[UPGRADE_FORCE]=false

## Remaining general configuration points
CONFIG[BACKUP_EXTENSION]=".database-upgrade.$(LANG=en date +%s)"
CONFIG[CONFIRM_READ_TIMEOUT_SECONDS]=30
CONFIG[DATABASE_BACKUP_DIRECTORY]="${HOME}/database-upgrade-backups/"
CONFIG[DATABASE_BACKUP_MAX_DISK_USAGE_PERCENT]=70
CONFIG[DATABASE_BACKUP_PARTITION_AVAILABLE_FACTOR]=4
CONFIG[DATABASE_BACKUP_WAIT_TOTAL_TIME_SECONDS]=1800
CONFIG[DATABASE_CONNECT_DEFAULTS_FILE]='/root/.my.cnf'
CONFIG[DATABASE_CONNECT_GROUP_SUFFIX]='_root'
CONFIG[DATABASE_MAIN_DEFAULTS_FILE]='/etc/my.cnf'
CONFIG[DATABASE_SERVICE_CONFIG_SEARCH_RESULT]=
CONFIG[DATABASE_SERVICE_CONNECTED_PIDS]=
CONFIG[DATABASE_SERVICE_CURRENTLY_ACTIVE]=false
CONFIG[DATABASE_SERVICE_CURRENTLY_ENABLED]=false
CONFIG[DATABASE_SERVICE_INITIALLY_ACTIVE]=false
CONFIG[DATABASE_SERVICE_INITIALLY_ENABLED]=false
CONFIG[DATABASE_SERVICE_MAIN_PID]=
CONFIG[DATABASE_SERVICE_NAME]=mariadb.service
CONFIG[DEBUG_LEVEL]=0
CONFIG[DO_NOT_UPGRADE_FILE_LOCATION]="/var/lib/mysql/DO_NOT_UPGRADE"
CONFIG[LOG_FILE]="/var/log/mariadb-upgrade-syseng"
CONFIG[LOG_FILE_EXTENSION]="-$(LANG=en date +'%d-%b-%Y').log"
CONFIG[OPTION_SPACE]='::ARG_SPACE_DELIMITER::'


## -------------------------------------------------------------------------------
## This section maps all exit/return codes to a id string. This string is
## what will be used throughout the script
# EXIT_CODE[]=
EXIT_CODE[script_success]=0
EXIT_CODE[script_general_error]=1
EXIT_CODE[script_premature_exit]=2
EXIT_CODE[script_not_confirmed]=3
EXIT_CODE[script_confirm_prompt_timeout]=4
EXIT_CODE[script_confirm_prompt_rejection]=5
EXIT_CODE[already_upgraded]=10
EXIT_CODE[do_not_upgrade_flag_found]=11
EXIT_CODE[file_system_usage_exceeded]=20
EXIT_CODE[error_encountered_directory_creation]=30
EXIT_CODE[cleanup_backup_directory]=31
EXIT_CODE[cleanup_defaults_file]=32
EXIT_CODE[error_encountered_defaults_file_backup]=33
EXIT_CODE[error_encountered_defaults_file_restoration]=34
EXIT_CODE[invalid_database_config_innodb_force_recovery]=40
EXIT_CODE[invalid_database_config_innodb_fast_shutdown]=41
EXIT_CODE[error_encountered_package_installation]=50
EXIT_CODE[error_encountered_package_removal]=51
EXIT_CODE[error_encountered_rpm_package_list]=52
EXIT_CODE[package_list_empty]=60
EXIT_CODE[invalid_config_file]=90
EXIT_CODE[invalid_defaults_file]=91
EXIT_CODE[invalid_service_action]=92
EXIT_CODE[missing_option_source_repo]=80
EXIT_CODE[missing_option_target_repo]=81
EXIT_CODE[missing_package_action]=70
EXIT_CODE[missing_service_action]=71
EXIT_CODE[invalid_comparison_portion]=100
EXIT_CODE[database_backup_failure]=110
EXIT_CODE[database_service_failed_to_start]=111
EXIT_CODE[database_service_failed_to_shutdown]=112
EXIT_CODE[database_replication_is_primary]=120
EXIT_CODE[database_replication_is_secondary]=121
EXIT_CODE[required_package_not_found]=130


## -------------------------------------------------------------------------------
## This section maps all exit messages to the same id string used for the
## associated exit code.
# EXIT_MESSAGE[]=""
EXIT_MESSAGE[script_general_error]="Generic error encountered. Please see output of debug for more information (use '--debug/-v' if not already provided at command line)."
EXIT_MESSAGE[script_success]="Script exiting successfully."
EXIT_MESSAGE[script_premature_exit]="Interrupting signal. Script exiting prematurely."
EXIT_MESSAGE[script_not_confirmed]="Confirmation of upgrade not provided. Please use --confirm-upgrade/--yes/-y, or type 'y' at confirmation prompt."
EXIT_MESSAGE[script_confirm_prompt_timeout]="Timeout encountered while prompting user for upgrade confirmation. Please use '--confirm-upgrade' or '--yes' or '-y' command line switch."
EXIT_MESSAGE[script_confirm_prompt_rejection]="User rejected upgrade confirmation. Exiting."
EXIT_MESSAGE[already_upgraded]="Packages already upgraded. Nothing to do."
EXIT_MESSAGE[do_not_upgrade_flag_found]="Aborting upgrade: Do not upgrade flag is present. See logs for more details."
EXIT_MESSAGE[file_system_usage_exceeded]="Insufficient disk space (as determined by --max-disk-usage-percentage/-P and --disk-datadir-size-ratio). Use --force-backup/-f if backups are needed."
EXIT_MESSAGE[error_encountered_directory_creation]="Unable to create directory. Refer to logs for last directory creation attempt."
EXIT_MESSAGE[cleanup_backup_directory]="Error encountered while performing cleanup on backup directory. Refer to logs for details"
EXIT_MESSAGE[cleanup_defaults_file]="Error encountered while performing cleanup on main defaults file. Refer to logs for details"
EXIT_MESSAGE[error_encountered_defaults_file_backup]="Error encountered while copying defaults file. Refer to logs for details"
EXIT_MESSAGE[error_encountered_defaults_file_restoration]="Error encountered while restoring defaults file."
EXIT_MESSAGE[invalid_database_config_innodb_force_recovery]="Invalid innodb_force_recovery value in use. Must be below three (3)."
EXIT_MESSAGE[invalid_database_config_innodb_fast_shutdown]="Invalid innodb_fast_shutdown value in use. Must not be equal to two (2)."
EXIT_MESSAGE[invalid_config_file]="Invalid or no configuration file provided."
EXIT_MESSAGE[invalid_defaults_file]="Defaults file (for mysql connection) does not exist."
EXIT_MESSAGE[invalid_service_action]="Invalid service action: expected 'set' or 'get'."
EXIT_MESSAGE[missing_option_source_repo]="Source repository option missing: expected --source-repo/-s <repo_name>."
EXIT_MESSAGE[missing_option_target_repo]="Target repository option missing: expected --target-repo/-t <repo_name>."
EXIT_MESSAGE[missing_package_action]="Missing package action: expected 'install' or 'remove'."
EXIT_MESSAGE[missing_service_action]="Missing service action: expected 'set' or 'get'."
EXIT_MESSAGE[package_list_empty]="No RPM packages for MariaDB were found."
EXIT_MESSAGE[error_encountered_package_installation]="There was an error encountered during yum package install. Please refer to logs."
EXIT_MESSAGE[error_encountered_package_removal]="There was an error encountered during yum package removal. Please refer to logs."
EXIT_MESSAGE[error_encountered_rpm_package_list]="There was an error encountered during RPM package listing. Please refer to logs."
EXIT_MESSAGE[invalid_comparison_portion]="Invalid comparison operator/comparison value."
EXIT_MESSAGE[database_backup_failure]="Errors encountered during schema backups"
EXIT_MESSAGE[database_service_failed_to_start]="Database failed to start in expected amount of time"
EXIT_MESSAGE[database_service_failed_to_shutdown]="Database failed to shutdown in expected amount of time"
EXIT_MESSAGE[database_replication_is_primary]="Database replication primary detected. Avoiding upgrade without --ignore-replication/-i flag"
EXIT_MESSAGE[database_replication_is_secondary]="Database replication secondary detected. Avoiding upgrade without --ignore-replication/-i flag"
EXIT_MESSAGE[required_package_not_found]="Required application, binary, or application not found or installed. Please see logs"




## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
##                                                                               ##
##                           GENERAL INTERNAL FUNCTIONS                          ##
##                                                                               ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##

function _print_parsed_configuration(){
    ## ---------------------------------------------------------------------------
    ## Print the resulting configuration from the main, and included,
    ## database configuration files
    if ${CONFIG[PRINT_CONFIG]}; then



        ## ---------------------------------------------------------------------------
        ## Print the recursively scanned configuration
        debug "Printing recursively loaded configuration. Please refer to log file for output"
        printf "\n\nRecursive configuration ------\n" >> ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]}
        for key in ${!DBCONFIG_RECURSIVE_ON_DISK[@]}; do
            echo "[${key%::AND::*}] ${key#*::AND::} ${DBCONFIG_RECURSIVE_ON_DISK[${key}]}"
        done \
            | sort \
            | column -t \
            >> ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]}



        ## ---------------------------------------------------------------------------
        ## Print the mysqld binary obtained configuration
        debug "Printing configuration loaded by mysqld binary loaded configuration. Please refer to log file for output"
        printf "\n\nConfiguration from mysqld binary ------\n" >> ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]}
        for key in ${!DBCONFIG_ON_DISK[@]}; do
            echo "[${key}] ${DBCONFIG_ON_DISK[${key}]}"
        done \
            | sort \
            | column -t \
            >> ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]}



        ## ---------------------------------------------------------------------------
        ## Onlp peform this if the service is actually up
        if ${CONFIG[DATABASE_SERVICE_INITIALLY_ACTIVE]}; then



            ## -----------------------------------------------------------------------
            ## print the live scanned configuration
            debug "Printing live configuration. Please refer to log file for output"
            printf  "\n\nLive configuration ------\n" >> ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]}
            for key in ${!DBCONFIG_IN_MEMORY[@]}; do
                echo "[${key}] ${DBCONFIG_IN_MEMORY[${key}]}"
            done \
                | sort \
                | column -t \
                >> ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]}
        fi
    fi
}




function _trim(){
    ## ---------------------------------------------------------------------------
    ## Function that removes either leading, trailing or leading
    ## and trailing whitespace from a string
    local side=${1:-LEFT_RIGHT}


    ## ---------------------------------------------------------------------------
    ## Conditionalise the trimming based on the function's input
    case ${side^^} in
        LEFT_RIGHT) sed -e 's,^  *,,' -e 's,  *$,,' < /dev/stdin ;;
        LEFT)       sed 's,^  *,,' < /dev/stdin ;;
        RIGHT)      sed 's,  *$,,' < /dev/stdin ;;
    esac
}




function _trap_leave(){
    ## ---------------------------------------------------------------------------
    ## Perform the following actions when experiencing a trapped signal



    ## ---------------------------------------------------------------------------
    ## INform the user that a signal was captured
    debug "Signal captured"



    ## ---------------------------------------------------------------------------
    ## Terminate any backup processes
    debug "Terminating remaining backup process (if any exist)"
    _database_backup_terminate_remaining_processes



    ## ---------------------------------------------------------------------------
    ## Leave prematurely. The leave() function will perform necessary
    ## cleanup measures, should the cleanup flag(s) be provided
    debug "Performing cleanup and exiting"
    leave script_premature_exit
}




## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
##                                                                               ##
##                           GENERAL FUNCTIONS                                   ##
##                                                                               ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##

function leave(){
    ## ---------------------------------------------------------------------------
    ## Function that receives an exit id, and prints the associated
    ## exit message and exits with the associated exit code
    local exit_code
    local exit_string=${1:-NULL}
    local print_string=true
    local string_colour='\x1B[0;31m'
    local print_string_format="[%s] (%s:%s) %s\n"



    ## ---------------------------------------------------------------------------
    ## Process some conditions
    case ${exit_string} in
        NULL)                   print_string=false ;;
        script_success)         string_colour='\x1B[0;36m' ;;
        script_premature_exit)  string_colour='\x1B[0;33m' ;;
        *)                      pass ;;
    esac



    ## ---------------------------------------------------------------------------
    ## Define string with colour codes, if the --colour/--color flag was provided
    ## at command line
    if ${CONFIG[PRINT_WITH_COLOUR]}; then
        print_string_format="\x1B[1;37m[\x1B[0;34m%s\x1B[1;37m] \x1B[1;37m(\x1B[1;32m%s:\x1B[1;33m%s\x1B[1;37m) ${string_colour}%s\x1B[0m\n"
    fi



    ## ---------------------------------------------------------------------------
    ## Perform any database upgraded-related cleanup here. Whether or not the
    ## steps are actually performed depend on what flags are provided at
    ## the command line
    database_upgrade_cleanup



    ## ---------------------------------------------------------------------------
    ## Print the exit string here
    if ${print_string}; then
        printf "${print_string_format}" \
            "$(LANG=en date)" \
            "${FUNCNAME[1]}" \
            "${BASH_LINENO[0]}" \
            "${EXIT_MESSAGE[${exit_string}]}" \
                | tee -a ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]}
    fi



    ## ---------------------------------------------------------------------------
    ## Declare this here since we unset all associative arrays before the exit
    exit_code=${EXIT_CODE[${exit_string}]}



    ## ---------------------------------------------------------------------------
    ## Unset things
    unset CONFIG
    unset DBCONFIG_RECURSIVE_ON_DISK
    unset EXIT_CODE
    unset EXIT_MESSAGE
    unset REPOSITORY



    ## ---------------------------------------------------------------------------
    ## Exit the program
    exit ${exit_code}
}




function parse_options(){
    ## ---------------------------------------------------------------------------
    ## Parse command line options. For the time being only long form options
    ## are considered, though this could easily be changed
    ## debug "Parsing command line options: ${@}"
    local OPTIND
    local optarray=()
    local getoptsstring=":"



    ## ---------------------------------------------------------------------------
    ## Iterate over command line options
    for argument in "${@}"; do



        ## -----------------------------------------------------------------------
        ## We've encountered a potential long switch
        if [[ ${argument} =~ ^-- ]]; then



            ## -------------------------------------------------------------------
            ## Compare the argument to what we have available in the long to
            ## short option map array. We've cfound a long argument
            if [[ ${OPTIONMAP[arg_${argument#--}]:-NULL} != NULL ]]; then



                ## ---------------------------------------------------------------
                ## If the getopts string doesn't already contain this naked
                ## map symbol, then add it
                if ! echo "${getoptsstring}" | grep -Fqe "${OPTIONMAP[arg_${argument#--}]:0:1}:"; then
                    getoptsstring+="${OPTIONMAP[arg_${argument#--}]:0:1}:"
                fi



                ## ---------------------------------------------------------------
                ## Add the short version to the option array
                optarray+=("-${OPTIONMAP[arg_${argument#--}]}")



            ## -------------------------------------------------------------------
            ## Compare the argument to what we have available in the long to
            ## short option map array. We've found a flag
            elif [[ ${OPTIONMAP[flag_${argument#--}]:-NULL} != NULL ]]; then



                ## ---------------------------------------------------------------
                ## If the getopts string doesn't already contain this naked
                ## map symbol, then add it
                if ! echo "${getoptsstring}" | grep -Fqe "${OPTIONMAP[flag_${argument#--}]:0:1}"; then
                    getoptsstring+="${OPTIONMAP[flag_${argument#--}]:0:1}"
                fi



                ## ---------------------------------------------------------------
                ## Add the short version to the option array
                optarray+=("-${OPTIONMAP[flag_${argument#--}]}")



            ## -------------------------------------------------------------------
            ## Compare the argument to what we have available in the long to
            ## short option map array. This is neither a short flag nor a long
            ## flag, so simply add it as it is
            else
                optarray+=("${argument// /${CONFIG[OPTION_SPACE]}}")
            fi



        ## -----------------------------------------------------------------------
        ## We've encountered a potential short switch
        elif [[ ${argument} =~ ^-[0-9a-zA-Z]* ]]; then



            ## -------------------------------------------------------------------
            ## Work our way backwards by iterating over all known values in the
            ## long to short options mapping array.
            for x in ${!OPTIONMAP[*]}; do



                ## ---------------------------------------------------------------
                ## The argument matches one of the values corresponding to a
                ## key in the option mapping
                if [[ ${argument#-} == ${OPTIONMAP[${x}]} ]]; then



                    ## -----------------------------------------------------------
                    ## If the value matches to a key associated with an argument
                    ## or flag then add it to the optarray.
                    case ${x} in
                        arg_*) getoptsstring+="${argument#-}:" ;;
                        flag_*) getoptsstring+="${argument#-}" ;;
                    esac
                    optarray+=("${argument}")



                    ## -----------------------------------------------------------
                    ## Stop processing sinc we've found something
                    break
                fi
            done



        ## -----------------------------------------------------------------------
        ## We've encountered a non flag. Add it as is to the optarray
        else
            optarray+=("${argument// /${CONFIG[OPTION_SPACE]}}")
        fi
    done



    ## ---------------------------------------------------------------------------
    ## We don't need this anymore since we've processed all long and short
    ## switches. Unset the option map now
    unset OPTIONMAP



    ## ---------------------------------------------------------------------------
    ## Iterate over the optoins and do the needful
    while getopts "${getoptsstring}" opt ${optarray[@]}; do
        case ${opt} in
            O)
                CONFIG[CLEANUP]=true
                CONFIG[CLEANUP_ONLY]=true
            ;;
            b)  CONFIG[DATABASE_BACKUP_PERFORM]=true ;;
            o)  CONFIG[CLEANUP]=true ;;
            v)
                CONFIG[DEBUG_LEVEL]=$[CONFIG[DEBUG_LEVEL]+1]
                CONFIG[DEBUG]=true
            ;;
            f)  CONFIG[DATABASE_BACKUP_PERFORM_FORCE]=true ;;
            p)  CONFIG[PRINT_CONFIG]=true ;;
            c)  CONFIG[PRINT_WITH_COLOUR]=true ;;
            y)  CONFIG[UPGRADE_CONFIRM]=true ;;
            i)  CONFIG[DATABASE_REPLICATION_IGNORE]=true ;;

            D)  CONFIG[DATABASE_BACKUP_DIRECTORY]=${OPTARG} ;;
            w)  CONFIG[DATABASE_BACKUP_WAIT_TOTAL_TIME_SECONDS]=${OPTARG} ;;
            l)  CONFIG[LOG_FILE]=${OPTARG} ;;
            X)  CONFIG[DO_NOT_UPGRADE_FILE_LOCATION]=${OPTARG} ;;

            P)  CONFIG[DATABASE_BACKUP_MAX_DISK_USAGE_PERCENT]=${OPTARG} ;;
            R)  CONFIG[DATABASE_BACKUP_PARTITION_AVAILABLE_FACTOR]=${OPTARG} ;;


            d)  REPOSITORY[disable]=${OPTARG} ;;
            e)  REPOSITORY[enable]=${OPTARG} ;;
            s)  REPOSITORY[source]=${OPTARG} ;;
            t)  REPOSITORY[target]=${OPTARG} ;;

            h)  help ;;
        esac
    done
    debug "Parsed over command line options"
}




function help(){
    ## ---------------------------------------------------------------------------
    ## Print the help page. Not much to see here
    printf "\x1B[0;31m
    \rUsage: ${0} <repoopts> [opts]
    \r---
    \r
    \r+ ------------------------------------------------------------------------------------------------------------- +
    \r| Required options (source and target repo names)                                                               |
    \r+ ============================ + == + ======= + =============================================================== +
    \r| --source-repo                | -s | string  | A repo name corresponding to the currently installed            |
    \r|                              |    |         | database version (e.g. mariadb_10_5)                            |
    \r+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
    \r| --target-repo                | -t | string  | A repo name corresponding to the upgrade target database        |
    \r|                              |    |         | version (e.g. mariadb_10_11)                                    |
    \r+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
    \r
    \r
    \r+ ------------------------------------------------------------------------------------------------------------- +
    \r| Options with values                                                                                           |
    \r+ ============================ + == + ======= + =============================================================== +
    \r| --backup-directory           | -D | string  | Directory path that will be used to house schema backups        |
    \r+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
    \r| --backup-max-wait-seconds    | -w | integer | Max duration of time (in seconds) allowed for backups to        |
    \r|                              |    |         | complete.                                                       |
    \r+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
    \r| --log-file                   | -l | string  | Path to log file (for script output)                            |
    \r+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
    \r| --do-not-upgrade-file        | -X | string  | Path to file indicating that an upgrade should not occur        |
    \r|                              |    |         | (this supercedes/ignores the '--force-backup' option)           |
    \r+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
    \r| --disable-repo               | -d | string  | Comma-delimited list of repository names that should be         |
    \r|                                               disabled during yum operations. Also accepts 'all'              |
    \r+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
    \r| --enable-repo                | -e | string  | Comma-delimited list of repository names that should be         |
    \r|                              |    |         | enabled during yum operations. Also accepts 'all'               |
    \r+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
    \r| --max-disk-usage-percent     | -P | integer | An integer representing the maximum allowed disk usage          |
    \r|                              |    |         | percentage before initial consideration that there is           |
    \r|                              |    |         | insufficient disk space to make backups. This is a              |
    \r|                              |    |         | particularly useful control for smaller disks, where            |
    \r|                              |    |         | backups could eat into a larger percentage of overall           |
    \r|                              |    |         | disk space.                                                     |
    \r|                              |    |         |                                                                 |
    \r|                              |    |         | For example: With a value of 70, and a                          |
    \r|                              |    |         | disk size of 10G, overall database backup size can NOT          |
    \r|                              |    |         | exceed 3G.                                                      |
    \r+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
    \r| --disk-datadir-size-ratio    | -R | integer | An integer describing the ratio of total free disk space        |
    \r|                              |    |         | to datadir size. Should the ratio exceed this value, in         |
    \r|                              |    |         | addition to the value of max-disk-usage-percent being           |
    \r|                              |    |         | exceeded, the script will determine that there is               |
    \r|                              |    |         | insufficient space to perform backups. This directive           |
    \r|                              |    |         | is particularly useful for /larger/ disks, where                |
    \r|                              |    |         | max-disk-usage-percent does not accurately describe the         |
    \r|                              |    |         | overall available disk space.                                   |
    \r|                              |    |         |                                                                 |
    \r|                              |    |         | For example: With a value of 4, and a datadir size of 50G       |
    \r|                              |    |         | it would be necessary for at LEAST 200G of disk space to        |
    \r|                              |    |         | be free in order for backups to occur                           |
    \r+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
    \r
    \r
    \r+ ------------------------------------------------------------------------------------------------- +
    \r| Flags                                                                                             |
    \r+ ========================= + == + ================================================================ +
    \r| --help                    | -h | Show this help file                                              |
    \r+ ------------------------- + -- + ---------------------------------------------------------------- +
    \r| --debug                   | -v | Enable debugging to stdout and log files. Use multiple times to  |
    \r|                           |    | increase the debug level.                                        |
    \r+ ------------------------- + -- + ---------------------------------------------------------------- +
    \r| --confirm-upgrade / --yes | -y | Confirm automatically that any changes will be performed by the  |
    \r|                           |    | script. This is useful when executing the script in an automated |
    \r|                           |    | fashion, such as via ansible. If not provided, a summary of      |
    \r|                           |    | changes will be presented on screen, along with a confirmation   |
    \r|                           |    | prompt.                                                          |
    \r+ ------------------------- + -- + ---------------------------------------------------------------- +
    \r| --colour/--color          | -c | Output to stdout (and log file) in colour.                       |
    \r+ ------------------------- + -- + ---------------------------------------------------------------- +
    \r| --cleanup                 | -o | Perform cleanup after upgrade                                    |
    \r+ ------------------------- + -- + ---------------------------------------------------------------- +
    \r| --cleanup-only            | -O | Only perform cleanup steps                                       |
    \r+ ------------------------- + -- + ---------------------------------------------------------------- +
    \r| --backup-schemas          | -b | Make a backup of all schemas prior to upgrade                    |
    \r+ ------------------------- + -- + ---------------------------------------------------------------- +
    \r| --ignore-replication      | -i | Ignore the fact that there is an active primary/secondary        |
    \r|                           |    | replication array, and proceed with the upgrade. The default     |
    \r|                           |    | behaviour is to halt execution if replication is detected        |
    \r+ ------------------------- + -- + ---------------------------------------------------------------- +
    \r| --force-backup            | -f | Force database backups to occur, even if the script deems        |
    \r|                           |    | that there is insufficient disk space, as determined through the |
    \r|                           |    | combination of 'max-disk-usage-percent' and                      |
    \r|                           |    | 'disk-datadir-size-ratio'                                        |
    \r|                           |    |                                                                  |
    \r|                           |    | Note: This does NOT override the presence of the                 |
    \r|                           |    |       --do-not-upgrade-file option                               |
    \r+ ------------------------- + -- + ---------------------------------------------------------------- +
    \r| --print-config            | -p | Print the overall configuration found by recursing               |
    \r|                           |    | /etc/my.cnf and all included files                               |
    \r+ ------------------------- + -- + ---------------------------------------------------------------- +
    \r
    \rExamples
    \r $ ./bin/upgrade.sh --source-repo=mariadb_105 --target-repo=mariadb_106 --log-file=/var/log/syseng-mariadb-upgrade --backup-directory=/var/lib/database_backups/ --max-disk-usage-percent=70 --disk-datadir-size-ratio=4 --debug --backup-schemas --cleanup --colour --print-config
    \r\x1B[0m
    \r"


    ## ---------------------------------------------------------------------------
    ## Leave successfully
    leave script_success
}




function check_for_required_binaries(){
    ## ---------------------------------------------------------------------------
    ## Function that checks to make sure that all given packages are present on
    ## the system
    local required_packages=(${@})


    ## ---------------------------------------------------------------------------
    ## Iterate over all the required packages presented as a function argument
    for required_package in ${required_packages[*]}; do



        ## -----------------------------------------------------------------------
        ## Inform user
        debug "Checking for required binary: ${required_package}" 2



        ## -----------------------------------------------------------------------
        ## The required package was not found
        if ! type -ft ${required_package} >/dev/null 2>&1; then



            ## -------------------------------------------------------------------
            ## Inform the user and exit
            debug "Required package/binary/application not found: ${required_package}" 2
            leave required_package_not_found
        fi
    done

}




function pass(){
    ## ---------------------------------------------------------------------------
    ## Literally a function that does nothing
    true
}




function debug(){
    ## ---------------------------------------------------------------------------
    ## This function prints debugging information to stdout and logs
    local string="${1}"
    local level=${2:-1}
    local print_string_format="[%s] (%s:%s) %s\n"



    ## ---------------------------------------------------------------------------
    ## Only print if the debugging flag was provided at command line
    if ${CONFIG[DEBUG]}; then



        ## -------------------------------------------------------------------
        ## Make sure that we are at the proper debug level
        if [[ ${level} -le ${CONFIG[DEBUG_LEVEL]} ]]; then



            ## -------------------------------------------------------------------
            ## Conditionalise print string with colour, if --colour/--color was
            ## provided at command line
            if ${CONFIG[PRINT_WITH_COLOUR]}; then
                print_string_format="\x1B[1;37m[\x1B[0;34m%s\x1B[1;37m] \x1B[1;37m(\x1B[1;32m%s\x1B[1;37m:\x1B[1;33m%s\x1B[1;37m) \x1B[0;34m%s\x1B[0m\n"
            fi



            ## -------------------------------------------------------------------
            ## Print fully composed line
            printf "${print_string_format}" \
                "$(LANG=en date)" \
                "${FUNCNAME[1]}" \
                "${BASH_LINENO[0]}" \
                "${string}" \
                    | tee -a ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]}
        fi
    fi
}




function compare_values(){
    ## ---------------------------------------------------------------------------
    ## Function that compares two values based off an operator. The function
    ## will compose a comparison string and return a true (0)/false (1)
    ## code
    local eval_retval
    local compare_array=(
        "${1:-NULL}" ## compare_from
        "${2:-NULL}" ## comparator
        "${3:-NULL}" ## compare_to
    )



    ## ---------------------------------------------------------------------------
    ## Ensure that all comparison portions are present, otherwise fail
    for compare_parts in ${compare_array[*]}; do
        case ${compare_parts} in
            NULL) leave invalid_comparison_portion ;;
        esac
    done



    ## ---------------------------------------------------------------------------
    ## Compose a comparison string, and evaluate it
    eval "[[ ${compare_array[0]} ${compare_array[1]} ${compare_array[2]} ]]"
    eval_retval=${?}



    ## ---------------------------------------------------------------------------
    ## Return the exit code of the comparison. Typically this will be the
    ## equivalent of "true/false"
    return ${eval_retval}

}




function check_exit_code(){
    ## ---------------------------------------------------------------------------
    ## Function that compares exit codes to a list of permitted ones, and in
    ## the event that it is not, exit from the script
    local allowed_return_codes=${1:-0}  ## Comma delimited list of allowed exit codes
    local return_code=${2}              ## Return code to be compared
    local leave_string=${3}             ## EXIT_CODE identifying string



    ## ---------------------------------------------------------------------------
    ## Compare the return code to the list of allowed codes, and exit if it is
    ## not in the list
    if ! echo ${allowed_return_codes} | grep -Fqwe ${return_code}; then
        leave ${leave_string}
    fi
}





## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
##                                                                               ##
##                            UPGRADE FUNCTIONS                                  ##
##                                                                               ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##

function database_upgrade_cleanup(){
    ## ---------------------------------------------------------------------------
    ## Function that peforms cleanups associated the upgrade
    local retval



    ## ---------------------------------------------------------------------------
    ## Only perform if the --cleanup/--cleanup-only flag(s) were provided
    if ${CONFIG[CLEANUP]}; then
        debug "Performing upgrade cleanup actions"



        ## -----------------------------------------------------------------------
        ## Remove the backup directory, if it exists
        if [[ -d ${CONFIG[DATABASE_BACKUP_DIRECTORY]} ]]; then
            debug "Removing backup directory: ${CONFIG[DATABASE_BACKUP_DIRECTORY]}"
            rm -rfv "${CONFIG[DATABASE_BACKUP_DIRECTORY]}" >> "${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]}" 2>&1
            retval=${?}
            check_exit_code 0 ${retval} cleanup_backup_directory
            debug "Backup directory removed"
        fi




        ## -----------------------------------------------------------------------
        ## Remove the backed up main defaults file
        debug "Removing main defaults file backups: $(ls ${CONFIG[DATABASE_MAIN_DEFAULTS_FILE]}${CONFIG[BACKUP_EXTENSION]%.*}* 2>/dev/null)"
        rm -rfv "${CONFIG[DATABASE_MAIN_DEFAULTS_FILE]}${CONFIG[BACKUP_EXTENSION]%.*}"* >> "${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]}" 2>&1
        retval=${?}
        check_exit_code 0 ${retval} cleanup_defaults_file
        debug "Removed main defaults file backups."
    fi
}




function confirm_upgrade(){
    ## ---------------------------------------------------------------------------
    ## This function checks for the user upgrade confirmation, and
    ## asks the user in the event that it was not provided on command line
    local choice
    local retval


    ## ---------------------------------------------------------------------------
    ## Check to see if the user has provided this as a command-line option
    if ! ${CONFIG[UPGRADE_CONFIRM]}; then



        ## -----------------------------------------------------------------------
        ## Inform the user that confirmation is required before proceeding with
        ## the rest of the actions in the script
        debug "Confirmation required before continuing with upgrade process"
        debug ""
        debug "++ ---------------------------------------------------------------------- ++"
        debug "++ ---------------------------------------------------------------------- ++"
        debug "++                                                                        ++"
        debug "++      CONTINUING FROM THIS POINT WILL EFFECT CHANGES ON THE SYSTEM      ++"
        debug "++                   ARE YOU SURE WISH TO CONTINUE?                       ++"
        debug "++                                                                        ++"
        debug "++ ---------------------------------------------------------------------- ++"
        debug "++ ---------------------------------------------------------------------- ++"



        ## -----------------------------------------------------------------------
        ## Obtain confirmation from the user. Only wait for a certain amount of
        ## time before erroring out. This is useful in case the script is kicked
        ## off via remote execution/automation (e.g. ansible). We can capture that
        ## error code and exit accordingly
        read \
            -n1 \
            -t${CONFIG[CONFIRM_READ_TIMEOUT_SECONDS]} \
            -e \
            -p "Please provide confirmation to continue (Y): " \
            choice
        retval=${?}



        ## -----------------------------------------------------------------------
        ## Check the return code and act accordingly. This allows us to check
        ## for a non-return code, which is likely due to a timeout. It might be
        ## a wiser move to use a case statement to check for the specific timeout
        ## code (142), among other codes.
        case ${retval} in
            0)  pass ;;
            142)
                echo
                leave script_confirm_prompt_timeout
            ;;
            *)  leave script_general_error ;;
        esac



        ## -----------------------------------------------------------------------
        ## Check to ensure that the user confirmed as expected. Leave the script
        ## if they passed in anything except 'Y'
        case ${choice^^} in
            Y) pass ;;
            *) leave script_confirm_prompt_rejection ;;
        esac
    fi
}




function check_for_do_not_upgrade_flag(){
    ## ---------------------------------------------------------------------------
    ## Function that checks the existence of a do not upgrade flag, in which
    ## case we prematurely exit the script
    debug "Checking for existence of 'do not upgrade' flag: ${CONFIG[DO_NOT_UPGRADE_FILE_LOCATION]}"



    ## ---------------------------------------------------------------------------
    ## Check for the existence of a flag.
    if [[ -f ${CONFIG[DO_NOT_UPGRADE_FILE_LOCATION]} ]]; then
        debug "Found 'do not upgrade' file. Aborting Upgrade"
        leave do_not_upgrade_flag_found
    fi
}






## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
##                                                                               ##
##                      DATABASE REPLICATION FUNCTIONS                           ##
##                                                                               ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##

function _is_primary_replication(){
    ## ---------------------------------------------------------------------------
    ## This function checks for the existence of a secondary replication instance
    local is_primary=1



    ## ---------------------------------------------------------------------------
    ## Check the output of SHOW SLAVE STATUS for any string correlating to
    ## "running". This implies that there is some replication with a running
    ## IO or SQL thread
    if database_connect --vertical --execute="SHOW MASTER STATUS" | grep -sqFie "position"; then
        debug "Primary replication configuration detected"
        is_primary=0



    ## ---------------------------------------------------------------------------
    ## No replication was detected
    else
        debug "No primary replication configuration detected"
    fi



    ## ---------------------------------------------------------------------------
    ## Make this the return code. 0 = true, otherwise it's false
    return ${is_primary}
}




function _is_secondary_replication(){
    ## ---------------------------------------------------------------------------
    ## This function checks for the existence of a secondary replication instance
    local is_secondary=1



    ## ---------------------------------------------------------------------------
    ## Check the output of SHOW SLAVE STATUS for any string correlating to
    ## "running". This implies that there is some replication with a running
    ## IO or SQL thread
    if database_connect --vertical --execute="SHOW SLAVE STATUS" | grep -sqFie "running"; then
        debug "Secondary replication configuration detected"
        is_secondary=0



    ## ---------------------------------------------------------------------------
    ## No replication was detected
    else
        debug "No secondary replication configuration detected"
    fi



    ## ---------------------------------------------------------------------------
    ## Make this the return code. 0 = true, otherwise it's false
    return ${is_secondary}
}




function check_for_replication(){
    ## ---------------------------------------------------------------------------
    ## Function that checks for any type of replication and determines action



    ## ---------------------------------------------------------------------------
    ## Check for primary or secondary replication instances. Here we iterate over
    ## the various types of replication (currently primary or secondary)
    debug "Checking for active replication configurations."
    for replication_type in 'primary' 'secondary'; do



        ## -----------------------------------------------------------------------
        ## Check to see if there is an active replication type detected
        if _is_${replication_type}_replication; then



            ## -------------------------------------------------------------------
            ## If the flag to ignore database replication is not provided, then
            ## exit out the script
            if ! ${CONFIG[DATABASE_REPLICATION_IGNORE]}; then



                ## ---------------------------------------------------------------
                ## Exit the script
                leave database_replication_is_${replication_type}
            fi
        fi
    done
}




## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
##                                                                               ##
##                        DATABASE SERVICE FUNCTIONS                             ##
##                                                                               ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##

function database_service_get_connected_pids(){
    ## ---------------------------------------------------------------------------
    ## Function that obtains a list of PIDs pertaining to processes connected
    ## to the database service socket. These are non-listening processes
    local ss_connected_ports
    local connected_pid_list
    local db_socket



    ## ---------------------------------------------------------------------------
    ## Get a configuration value and set it
    get_loaded_config_value socket
    db_socket=${CONFIG[DATABASE_SERVICE_CONFIG_SEARCH_RESULT]}



    ## ---------------------------------------------------------------------------
    ## Obtain a list of all connections associated with a database service's
    ## unix socket
    readarray -t ss_connected_ports < <(ss --numeric --unix src ${db_socket} | awk 'NR>1{print $(NF-2)}')



    ## ---------------------------------------------------------------------------
    ## Use the ports associated with the connections to build a list of PIDs
    readarray -t connected_pid_list < <(for ss_connected_port in ${ss_connected_ports[*]}; do
                                            ss --processes --numeric --no-header dport = :${ss_connected_port}
                                        done \
                                            | grep -oe 'pid=[0-9]*' \
                                            | cut -d'=' -f2)



    ## ---------------------------------------------------------------------------
    ## Set the configuration for the list of PIDs
    CONFIG[DATABASE_SERVICE_CONNECTED_PIDS]="${connected_pid_list[*]:-NULL}"
}




function database_service_socket_to_pid(){
    ## ---------------------------------------------------------------------------
    ## Function that converts a unix socket assignation to a PID
    local db_service_pid
    local db_socket



    ## ---------------------------------------------------------------------------
    ## Get a configuration value and set it
    get_loaded_config_value socket
    db_socket=${CONFIG[DATABASE_SERVICE_CONFIG_SEARCH_RESULT]}



    ## ---------------------------------------------------------------------------
    ## Obtain the service PID from a list of listers to the unix socket for the
    ## database service
    db_service_pid=$(ss --process --listen --numeric --unix src ${db_socket} | grep -Eo 'pid=[0-9]+' | cut -d'=' -f2)



    ## ---------------------------------------------------------------------------
    ## Set the configuration value
    CONFIG[DATABASE_SERVICE_MAIN_PID]=${db_service_pid:-NULL}
}




function database_wait_for_shutdown(){
    ## ---------------------------------------------------------------------------
    ## Function that waits a certain amount of time for a database service
    ## to shutdown
    local status_string='SUCCESS'
    local remaining_attempts=30
    local iteration_duration_seconds=5



    ## ---------------------------------------------------------------------------
    ## Get the current running service PID
    if [[ ${CONFIG[DATABASE_SERVICE_MAIN_PID]:-NULL} == NULL ]]; then
        database_service_socket_to_pid
    fi



    ## ---------------------------------------------------------------------------
    ## Enter endless loop. We'll conditionalise the exit based off remaining
    ## poll attempts
    debug "Waiting for service to fully shutdown"
    while true; do



        ## -----------------------------------------------------------------------
        ## Check for any of the tell-tale mariadbd processes. Perhaps we
        ## be a little more precise since there could be /interworx/
        ## database services
        # if [[ $(ss -Hlx src /var/lib/mysql/mysql.sock | wc -l) -gt 0 ]]; then
        # if ! ps h -wwwC mariadbd,mariadbd-safemysqld,mysqld_safe -o command >/dev/null 2>&1; then
        if ! ps h --pid ${CONFIG[DATABASE_SERVICE_MAIN_PID]} -o command >/dev/null 2>&1; then



            ## -------------------------------------------------------------------
            ## Break out the service since no process was found
            debug "Service not found in process table; service shut down"
            CONFIG[DATABASE_SERVICE_CURRENTLY_ACTIVE]=false
            break
        fi



        ## -----------------------------------------------------------------------
        ## Decrement remaining attempt counter by one and sleep by given
        ## seconds defining one loop iteration
        remaining_attempts=$[remaining_attempts-1]
        debug "Service not fully shutdown (${remaining_attempts} attempts remaining)"
        debug ">> $(ps h --pid ${CONFIG[DATABASE_SERVICE_MAIN_PID]})"
        sleep ${iteration_duration_seconds}



        ## -----------------------------------------------------------------------
        ## If we've reached this point, the database has not shut down in the
        ## prescribed amount of time. Fail out of the script
        if [[ ${remaining_attempts} -eq 0 ]]; then
            leave database_service_failed_to_shutdown
        fi
    done
}




function database_wait_for_startup(){
    ## ---------------------------------------------------------------------------
    ## Function that waits a certain amount of time for a database service
    ## to activate
    local status_string='SUCCESS'
    local remaining_attempts=30
    local iteration_duration_seconds=5



    ## ---------------------------------------------------------------------------
    ## Enter endless loop. We'll conditionalise the exit based off remaining
    ## poll attempts
    debug "Waiting for service to fully start"
    while true; do



        ## -----------------------------------------------------------------------
        ## Atttempt to connect to the database and execute a query.
        if database_connect --execute="SELECT '${status_string}'" 2>/dev/null | grep -Fwqe "${status_string}"; then



            ## -------------------------------------------------------------------
            ## Break out the service since we were able to connect and
            ## successfully execute a query
            debug "Database connection established; database service started"
            CONFIG[DATABASE_SERVICE_CURRENTLY_ACTIVE]=true
            break
        fi



        ## -----------------------------------------------------------------------
        ## Decrement remaining attempt counter by one and sleep by given
        ## seconds defining one loop iteration
        remaining_attempts=$[remaining_attempts-1]
        debug "Service not fully started (${remaining_attempts} attempts remaining)"
        sleep ${iteration_duration_seconds}



        ## -----------------------------------------------------------------------
        ## If we've reached this point, the database has not activated in the
        ## prescribed amount of time. Fail out of the script
        if [[ ${remaining_attempts} -eq 0 ]]; then
            leave database_service_failed_to_start
        fi
    done

}




## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
##                                                                               ##
##                       DATABASE BACKUP FUNCTIONS                               ##
##                                                                               ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##

function database_check_disk_space(){
    ## ---------------------------------------------------------------------------
    ## Function that compares disk space to thresholds (default or ones provided
    ## on command line
    local datadir
    local disk_percent_usage
    local datadir_size_bytes
    local datadir_partition_bytes_available
    local return_val=0
    local disk_percent_usage_exceeded=false
    local datadir_size_bytes_exceeded=false



    ## ---------------------------------------------------------------------------
    ## Grab the current datadir from in memory. Maybe we failover to
    ## configuration and abstract this out to a different function
    datadir=$(database_connect --execute="SELECT @@global.datadir" | _trim)



    ## ---------------------------------------------------------------------------
    ## Get the current percent usage of the disk on which the data directory lives
    debug "Obtaining disk usage percentage"
    disk_percent_usage=$(df -h --output=pcent ${datadir} | tail -fn1 | sed 's,%,,' | _trim)



    ## ---------------------------------------------------------------------------
    ## Compare the disk usage percentage to the allowed maximum % disk usage as
    ## prescribed by defaults and/or command line. This is most useful for smaller
    ## disks, where the percentage of free disk space is substantial
    debug "Comparing disk usage percentage (${disk_percent_usage}%) to allowed threshold (${CONFIG[DATABASE_BACKUP_MAX_DISK_USAGE_PERCENT]}%)"
    if [[ ${disk_percent_usage} -gt ${CONFIG[DATABASE_BACKUP_MAX_DISK_USAGE_PERCENT]} ]]; then



        ## -----------------------------------------------------------------------
        ## If percent disk usage is exceeded, warn but do not fail out. We can
        ## still perform another check to see what the actual bytes free is.
        disk_percent_usage_exceeded=true
        debug "Disk usage percentage exceeds ${CONFIG[DATABASE_BACKUP_MAX_DISK_USAGE_PERCENT]}%."



        ## -----------------------------------------------------------------------
        ## Obtain datadir usage
        debug "Checking datadir byte usage in relation to available bytes on partition"
        debug "Obtaining datadir byte usage"
        datadir_size_bytes=$(du -s ${datadir} | awk '{print $1}')
        debug "Datadir usage: ${datadir_size_bytes} bytes"



        ## -----------------------------------------------------------------------
        ## Gathering free bytes for the partition on which the datadir lives
        debug "Obtaining datadir partition available (unused) bytes."
        datadir_partition_bytes_available=$(df --output=avail ${datadir} | tail -n1 | _trim)
        debug "Partition holding datadir has available bytes: ${datadir_partition_bytes_available}"



        ## -----------------------------------------------------------------------
        ## Comapare the ratio of datadir size to free bytes on datadir's partition
        ## We're considering whether free_partition_bytes/datadir_size exceeds
        ## a given integer (DATABASE_BACKUP_PARTITION_AVAILABLE_FACTOR). This is
        ## helpful for larger disks, where 10% of a partition could still be a
        ## considerable amount of disk space, relative to the datadir.
        ## debug "Comparing datadir size to available bytes on partition. Backups
        ## rarely equal or exceed the size of the datadir
        if [[ $[datadir_size_bytes*${CONFIG[DATABASE_BACKUP_PARTITION_AVAILABLE_FACTOR]}] -gt ${datadir_partition_bytes_available} ]]; then



            ## -------------------------------------------------------------------
            ## Insufficient factor size. This is the final check. Set the flag that
            ## datadir size is too large
            debug "Datadir size*${CONFIG[DATABASE_BACKUP_PARTITION_AVAILABLE_FACTOR]} exceeds available bytes on partition (${datadir_partition_bytes_available})."
            datadir_size_bytes_exceeded=true



        else
            ## -------------------------------------------------------------------
            ## The factor suffices
            debug "Available partition space exceeds ${CONFIG[DATABASE_BACKUP_PARTITION_AVAILABLE_FACTOR]} times datadir size"
        fi



    ## ---------------------------------------------------------------------------
    ## The percent disk usage is under the given threshold
    else
        debug "Disk space % used under threshold"
    fi



    ## ---------------------------------------------------------------------------
    ## We've failed both disk checks.
    if ${datadir_size_bytes_exceeded} && ${disk_percent_usage_exceeded}; then



        ## -----------------------------------------------------------------------
        ## Since force backup was not provided. We aren't leaving the script
        ## yet since this function returns either a 0 or 1, to the calling function
        ## Though the calling function performs this check, we'll also leave this
        ## here for the time being
        debug "Insufficient disk space for schema backups. Please use '--force-backup' if backups are required"
        return_val=1



    ## ---------------------------------------------------------------------------
    ## There is sufficient disk space. Just inform the user
    else
        debug "Sufficient disk space"
    fi



    ## ---------------------------------------------------------------------------
    ## Return the return value (0 if sufficient disk space, 1 if not)
    return ${return_val}
}




function database_check_backup_success(){
    ## ---------------------------------------------------------------------------
    ## Function that returns the count of schema failure files.
    return $(ls -1 ${CONFIG[DATABASE_BACKUP_DIRECTORY]}failures/* 2>/dev/null| wc -l)
}




function _database_backup_terminate_remaining_processes(){
    ## ---------------------------------------------------------------------------
    ## Function that terminates remaining backup processes
    local processlist_entry
    local terminated_process_count=0
    local remaining_pids=()
    local remaining_schema_name



    ## -----------------------------------------------------------------------
    ## Renew the list of connected PIDs
    database_service_get_connected_pids



    ## ---------------------------------------------------------------------------
    ## Gather a list of all remaining mysqldump processes from the remaining list
    readarray -t remaining_pids < <(ps h --pid ${CONFIG[DATABASE_SERVICE_CURRENTLY_ENABLED]// /,} -wwwo lwp,command 2>/dev/null | awk '/mysqldump/&&/--dump-date/{print $1}')


    ## ---------------------------------------------------------------------------
    ## Iterate over the remaining mysqldump processes to terminate
    for remaining_pid in ${remaining_pids[*]}; do



        ## -----------------------------------------------------------------------
        ## Obtain the name of the schema (assuming that it is the last argument
        ## in the processlist line)
        remaining_schema_name=$(ps h -wwwp ${remaining_pid} 2>/dev/null | awk '{print $NF}')



        ## -----------------------------------------------------------------------
        ## Touch the failure file before terminating the
        debug "Creating failed schema backup file: ${CONFIG[DATABASE_BACKUP_DIRECTORY]}failures/${remaining_schema_name}"
        echo "Terminated" > ${CONFIG[DATABASE_BACKUP_DIRECTORY]}failures/${remaining_schema_name}



        ## -----------------------------------------------------------------------
        ## Inform the user of the process termination, and issue a SIGTERM.
        processlist_entry="$(ps -wwwp ${remaining_pid})"



        ## -----------------------------------------------------------------------
        ## Inform the user of the process termination, and issue a SIGTERM.
        debug "Terminating process with ID ${remaining_pid}:"
        while read line; do
            debug ">> ${line}"
        done < <(ps -wwwp ${remaining_pid})
        kill -TERM ${remaining_pid} 2>/dev/null



        ## -----------------------------------------------------------------------
        ## Increment the terminated process counter by one
        terminated_process_count=$[terminated_process_count+1]
    done



    ## -----------------------------------------------------------------------
    ## The return code ends up being the amount of terminated mysqldump
    ## processes
    return ${terminated_process_count}
}




function _get_backup_wait_iteration_length(){
    ## ---------------------------------------------------------------------------
    ## This function dynamically adjusts the polling interval based off the
    ## defined overall remaining wait time
    local poll_length_seconds=5
    local remaining_time=${1:-NULL}



    ## ---------------------------------------------------------------------------
    ## For remaining time exceeding 600 seconds (10 minutes), adjust the poll
    ## length to sixty seconds (1 minute).
    if [[ ${remaining_time} -gt 600 ]]; then
        poll_length_seconds=60



    ## ---------------------------------------------------------------------------
    ## For remaining time exceeding 300 seconds (5 minutes), adjust the poll
    ## length to thirty seconds.
    elif [[ ${remaining_time} -gt 300 ]]; then
        poll_length_seconds=30



    ## ---------------------------------------------------------------------------
    ## For remaining time between 300 seconds (5 minutes) and sixty seconds
    ## (1 minute), adjust the poll length to 10 seconds
    elif [[ ${remaining_time} -gt 60 ]]; then
        poll_length_seconds=10

    fi



    ## ---------------------------------------------------------------------------
    ## Output the poll length so that it can be captured by the calling service
    printf "${poll_length_seconds}"
}




function database_backup_wait_for_completion(){
    ## ---------------------------------------------------------------------------
    ## Function that waits for all backups to complete
    local return_code=0
    local process_poll_interval
    local remaining_wait_time=${CONFIG[DATABASE_BACKUP_WAIT_TOTAL_TIME_SECONDS]}



    ## ---------------------------------------------------------------------------
    ## Initial sleep value to allow processes to register in the processlist
    sleep 1s



    ## ---------------------------------------------------------------------------
    ## Enter loop that checks processlist. Use --dump-date since that is
    ## explicitly provided on the command line
    while true; do
    # while ps h -C mysqldump -o command | grep -Fqwe '--dump-date'; do



        ## -----------------------------------------------------------------------
        ## Get a list of all connected PIDs
        database_service_get_connected_pids



        ## -----------------------------------------------------------------------
        ## If no more running mysqldumps, then kick out the loop
        if ! ps --pid ${CONFIG[DATABASE_SERVICE_CONNECTED_PIDS]// /,} 2>/dev/null | grep 'mysqldump' | grep -Fqwe '--dump-date'; then
            debug "No more running mysqldumps"
            break
        fi



        ## -----------------------------------------------------------------------
        ## Acquire a dynamic process poll interval, based off the currently
        ## remaining time. This prevents the log file from being hit continually
        ## with smaller interval updates during larger wait intervals
        process_poll_interval=$(_get_backup_wait_iteration_length ${remaining_wait_time})



        ## -----------------------------------------------------------------------
        ## Output that we're still waiting for mysqldumps, provide the number of
        ## processes, and the total remaining time we're waiting, and the next
        ## time we'll update
        debug "${remaining_wait_time} seconds remaining for $(ps h --pid ${CONFIG[DATABASE_SERVICE_CONNECTED_PIDS]// /,} 2>/dev/null | grep mysqldump | grep -Fcwe '--dump-date') mysqldump processes to complete. Next update in ${process_poll_interval} seconds."



        ## -----------------------------------------------------------------------
        ## If the debug level is two (2) or more, then dump the mysqldump
        ## processlists
        if [[ ${CONFIG[DATABASE_SERVICE_CONNECTED_PIDS]} != NULL ]]; then
            while read line; do
                debug ">> ${line}" 2
            done < <(ps h --pid ${CONFIG[DATABASE_SERVICE_CONNECTED_PIDS]// /,} 2>/dev/null | grep mysqldump | grep -Fwe '--dump-date')
        fi



        ## -----------------------------------------------------------------------
        ## Sleep for the amount of seconds that define our interval poll duration
        sleep ${process_poll_interval}s



        ## -----------------------------------------------------------------------
        ## Decrement our total wait time by the amount of time slept
        remaining_wait_time=$[remaining_wait_time-process_poll_interval]



        ## -----------------------------------------------------------------------
        ## We have depleted our remaining allowed wait time
        if [[ ${remaining_wait_time} -le 0 ]]; then



            ## -------------------------------------------------------------------
            ## Inform the user that the maximum wait time for a database
            ## has occurred
            debug "Maximum allowed time for mysqldump completion reached: ${CONFIG[DATABASE_BACKUP_WAIT_TOTAL_TIME_SECONDS]} seconds."



            ## -------------------------------------------------------------------
            ## Terminate the remaining backup processes. The return code
            ## represents the amount of mysqldump processes that were terminated
            ## as a result of exceeding the maximum wait time
            _database_backup_terminate_remaining_processes
            return_code=${?}
        fi
    done



    ## -------------------------------------------------------------------
    ## We pass through the return code representing the amount of
    ## terminated mysql processes
    return ${return_code}
}




function _database_create_backup_directory(){
    ## ---------------------------------------------------------------------------
    ## This function creates a backup directory. In the event that the backup
    ## directory already exists, this function should /recreate/ it, to prevent
    ## previous failures from interfering with current backup results
    local retval



    ## ---------------------------------------------------------------------------
    ## If the directory exists, remove it.  This prevents previous failures
    ## from registering with the current backup process results
    if [[ -d ${CONFIG[DATABASE_BACKUP_DIRECTORY]} ]]; then



        ## -----------------------------------------------------------------------
        ## Remove the current backup directory
        debug "Database backup directory found. Removing: ${CONFIG[DATABASE_BACKUP_DIRECTORY]}"
        rm -rf ${CONFIG[DATABASE_BACKUP_DIRECTORY]}
        retval=${?}



        ## -----------------------------------------------------------------------
        ## Guard against disk write/IO errors
        check_exit_code 0 ${retval} leave error_encountered_directory_creation
    fi



    ## ---------------------------------------------------------------------------
    ## Attempt to create the backup directory and its filetree structure
    debug "Creating database backup directory: ${CONFIG[DATABASE_BACKUP_DIRECTORY]}"
    mkdir -p ${CONFIG[DATABASE_BACKUP_DIRECTORY]}{backups,failures}/
    retval=${?}



    ## ---------------------------------------------------------------------------
    ## Guard against disk write/IO errors
    check_exit_code 0 ${retval} leave error_encountered_directory_creation
}




function database_perform_backups(){
    ## ---------------------------------------------------------------------------
    ## This function may not even be required, since acronis backups will likely be
    ## the fastest way to handle the backups. Nevertheless, the functionality
    ## will be included in the script
    local schemas
    local compression
    local compression_extension=""
    local compression_hierarchy=(
        'bzip2'
        'xz'
        'gzip'
        'cat'
    )



    ## ---------------------------------------------------------------------------
    ## Only attempt backups if the database service is active
    if ${CONFIG[DATABASE_BACKUP_PERFORM]}; then



        ## -----------------------------------------------------------------------
        ## Inform the user
        debug "Database backup option provided."
        debug "Checking for sufficient available disk space"



        ## -----------------------------------------------------------------------
        ## Check for sufficient amount of disk space. If the option is given
        ## to force backups, then skip the the disk space check altogether
        if ${CONFIG[DATABASE_BACKUP_PERFORM_FORCE]}; then
            debug "The option --force-backup was provided. Skipping disk space check."
            pass



        ## -----------------------------------------------------------------------
        ## If the disk space failed, then leave the script since force backup
        ## option was not provided
        elif ! database_check_disk_space; then
            leave file_system_usage_exceeded
        fi



        ## -----------------------------------------------------------------------
        ## Determine compression method (maybe isolate into its own function)
        for compression_method in ${compression_hierarchy[*]}; do



            ## -------------------------------------------------------------------
            ## Conditionalise based off of existence of the command
            debug "Considering compression method: ${compression_method}"
            if type -P ${compression_method} >/dev/null 2>&1; then
                compression=($(type -P ${compression_method}))
                case ${compression_method} in
                    bzip2)
                        compression+=(--compress --quiet --stdout --best)
                        compression_extension=".bz2"
                    ;;
                    xz)
                        compression+=(--compress --quiet --to-stdout)
                        compression_extension=".xz"
                    ;;
                    gzip)
                        compression+=(--quiet --stdout --best)
                        compression_extension=".gz"
                    ;;
                esac



                ## ---------------------------------------------------------------
                ## We found a compression method. Inform the user and break
                debug "Compression method (with options): ${compression[*]}"
                break
            fi



            ## -------------------------------------------------------------------
            ## The compression method is unavailable. Inform user and continue
            ## to the next consideration
            debug "Compression method unavailable: ${compression_method}"
        done



        ## -----------------------------------------------------------------------
        ## List all schemas except for information_schema and performance_schema
        ## Maybe split this out into its own function
        readarray -t schemas < <(
            database_connect \
                --execute="SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME NOT IN('information_schema','performance_schema')"
        )



        ## -----------------------------------------------------------------------
        ## Create the backup directory file tree
        _database_create_backup_directory



        ## -----------------------------------------------------------------------
        ## Iterate over each of the schemas in the list
        for schema in ${schemas[*]}; do


            ## -------------------------------------------------------------------
            ## Dump the schema, and pass through the compression filter. We do
            ## some clever double duty using tee to check for the final line
            ## associated with the --dump-date mysqldump option. Should that not
            ## exist, we touch a failure file, which we will count later on
            debug "Dumping schema: ${schema}"
            mysqldump \
                --defaults-file=${CONFIG[DATABASE_CONNECT_DEFAULTS_FILE]} \
                --defaults-group-suffix=${CONFIG[DATABASE_CONNECT_GROUP_SUFFIX]} \
                --dump-date \
                ${schema} \
                | tee >(grep -Fqe "-- Dump completed on $(LANG=en date +%Y)" \
                    || touch ${CONFIG[DATABASE_BACKUP_DIRECTORY]}failures/${schema}) \
                | ${compression[@]} \
                > ${CONFIG[DATABASE_BACKUP_DIRECTORY]}backups/${schema}.sql${compression_extension} &
        done



        ## -----------------------------------------------------------------------
        ## Wait for all databases to complete their backups. We should probably
        ## place an upper limit on the amount of time that we would like to wait
        database_backup_wait_for_completion



        ## -----------------------------------------------------------------------
        ## Determine if there were any database dump failures
        if ! database_check_backup_success; then



            ## -------------------------------------------------------------------
            ## Backups failures found. Leave the script after informint the user
            debug "There were failures experienced with backups. Please check ${CONFIG[DATABASE_BACKUP_DIRECTORY]}failures/<schema> for list of failed schemas"
            leave database_backup_failure
        fi



        ## -----------------------------------------------------------------------
        ## All backups were successfully taken
        debug "Schema backups completed and available at ${CONFIG[DATABASE_BACKUP_DIRECTORY]}backups/"



    ## ---------------------------------------------------------------------------
    ## We never asked for backups anyway
    else
        debug "Database backup option ('--backup-schemas') was not provided provided. Skipping."
    fi
}




## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
##                                                                               ##
##                      DATABASE CONFIGURATION FUNCTIONS                         ##
##                                                                               ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##

function get_loaded_config_value(){
    ## ---------------------------------------------------------------------------
    ## Pull a configuration value from one of the three loaded configs.
    ## Use live, mysqld binary, recursive hierarchy for interrogating the
    ## configuration
    local return_value
    local found_key=false
    local config_key=${1:-NULL}



    ## ---------------------------------------------------------------------------
    ## First pull from the in-memory source, if it's populated. Also check that
    ## the key exists
    debug "Searching for database configuration value associated with '${config_key}'" 3
    if [[ (${#DBCONFIG_IN_MEMORY[*]} -gt 0) && (${DBCONFIG_IN_MEMORY[${config_key}]:-NOPE} != "NOPE") ]]; then



        ## -----------------------------------------------------------------------
        ## Update the return key and let the user know
        return_value="${DBCONFIG_IN_MEMORY[${config_key}]}"
        found_key=true
        debug "Key found in DBCONFIG_IN_MEMORY: ${return_value}" 3



    ## ---------------------------------------------------------------------------
    ## Second try to pull from the mysqld interrogation
    ## the key exists
    elif [[ (${#DBCONFIG_ON_DISK[*]} -gt 0) && (${DBCONFIG_ON_DISK[${config_key}]:-NOPE} != "NOPE") ]]; then



        ## -----------------------------------------------------------------------
        ## Update the return key and let the user know
        return_value="${DBCONFIG_ON_DISK[${config_key}]}"
        found_key=true
        debug "Key found in DBCONFIG_ON_DISK: ${return_value}" 3



    ## ---------------------------------------------------------------------------
    ## Lastly try to pull from the recursively pulled information from on disk
    ## the key exists
    elif [[ (${#DBCONFIG_RECURSIVE_ON_DISK[*]} -gt 0) ]]; then



        ## ---------------------------------------------------------------------------
        ## Lastly try to pull from the recursively pulled information from on disk
        return_value=$(
            for i in $(echo "${!DB_CONFIG[*]}" | grep -oe "[^ ]*socket[^ ]*"); do
                echo ${DB_CONFIG[${i}]} | _trim LEFT_RIGHT
            done | sort -u
        )



        ## ---------------------------------------------------------------------------
        ## Make sure that we haev one unique value for everything
        if [[ $(echo "${return_value}" | wc -l) -eq 1 ]]; then



            ## -----------------------------------------------------------------------
            ## Update the return key and let the user know
            return_value="${DBCONFIG_IN_MEMORY[${config_key}]}"
            found_key=true
            debug "Key found in DBCONFIG_RECURSIVE_ON_DISK: ${return_value}" 3
        fi
    fi



    ## -------------------------------------------------------------------------------
    ## Print the return key value
    if ${found_key}; then
        CONFIG[DATABASE_SERVICE_CONFIG_SEARCH_RESULT]="${return_value}"
    fi
}




function check_target_config_database_values(){
    ## ---------------------------------------------------------------------------
    ## Ensure that w dont' have unexpected database configuration values
    ## These come from https://mariadb.com/docs/server/server-management/install-and-upgrade-mariadb/upgrading/upgrading-between-major-mariadb-versions#requirements-for-doing-an-upgrade-between-major-versions



    ## ---------------------------------------------------------------------------
    ## Iterate over the acquired configurations
    debug "Checking on-disk database configuration values"
    for config_key in ${!DBCONFIG_RECURSIVE_ON_DISK[*]}; do
        case ${config_key} in



            ## -------------------------------------------------------------------
            ## Innodb fast shutdown should not be equal to a value of two (2)
            mariadb_10.6::AND::innodb_fast_shutdown|\
            mysqld::AND::innodb_fast_shutdown)
                if $(compare_values "${DBCONFIG_RECURSIVE_ON_DISK[config_key]}" '-eq' 2); then
                    leave invalid_database_config_innodb_fast_shutdown
                fi
            ;;



            ## -------------------------------------------------------------------
            ## Innodb force recovery level should be below three (3)
            mariadb_10.6::AND::innodb_force_recovery|\
            mysqld::AND::innodb_force_recovery)
                if $(compare_values "${DBCONFIG_RECURSIVE_ON_DISK[config_key]}" '-ge' 3); then
                    leave invalid_database_config_innodb_force_recovery
                fi
            ;;
        esac
    done
}




function database_get_config_live(){
    ## ---------------------------------------------------------------------------
    ## Pull the in-memory configuration from the running server.



    ## ---------------------------------------------------------------------------
    ## Only perform this if the database server is active
    if ${CONFIG[DATABASE_SERVICE_INITIALLY_ACTIVE]}; then



        ## -----------------------------------------------------------------------
        ## Pull the information from the live service
        debug "Obtaining configuration from live server"
        eval "$(database_connect --skip-table \
                                 --skip-column-names \
                                 --batch \
                                 --execute="SHOW GLOBAL VARIABLES" \
                                 | awk '
                                        NF==1{
                                            configuration[$1]="N/A"
                                        }

                                        NF>1{
                                            gsub(/\x09/," ",$0);
                                            sub(/ /,"::DELIMITER::",$0);
                                            split($0,a,"::DELIMITER::");
                                            configuration[a[1]]=a[2]
                                        }

                                        END{
                                            for(key in configuration){
                                                printf "DBCONFIG_IN_MEMORY[%s]=\x27%s\x27\n",key,configuration[key]
                                            }
                                        }
                                   ')"



    ## -----------------------------------------------------------------------
    ## The service is not live. Inform the user
    else
        debug "Database service not active. Skipping live configuration"
    fi
}




function database_get_config_on_disk(){
    ## ---------------------------------------------------------------------------
    ## Pull the on-disk configuration, as seen from mysqld binary using --help.
    ## This will pull the configuration for all mariadb current version, plus any
    ## arguments provided
    local defaults_file=${1:-NULL}



    ## ---------------------------------------------------------------------------
    ## Use the mysqld binary to interrogate the current version of the database
    ## configuration
    debug "Obtaining configuration from on disk using mysqld binary"
    eval "$(mysqld --defaults-file=${defaults_file} \
                   --verbose \
                   --help \
                   | awk '
                              BEGIN {
                                   start_processing=0
                              }

                              start_processing && NF>0{
                                  gsub(/  */," ",$0);
                                  sub(/ /,"::DELIMITER::",$0);
                                  split($0,a,"::DELIMITER::");
                                  configuration[a[1]]=a[2]
                              }

                              NF==2 && $1~/^--*$/ && $2~/^--+$/{
                                  start_processing=1
                              }

                              start_processing && NF==0{
                                  start_processing=0
                              }

                              END{
                                  for(key in configuration){
                                      printf "DBCONFIG_ON_DISK[%s]=\x27%s\x27\n",key,configuration[key]
                                  }
                              }
                     ')"
}




function database_check_in_memory_values(){
    ## ---------------------------------------------------------------------------
    ## This might not be useful since the service will be shut down prior to
    ## performing the upgrade
    ## These come from https://mariadb.com/docs/server/server-management/install-and-upgrade-mariadb/upgrading/upgrading-between-major-mariadb-versions#requirements-for-doing-an-upgrade-between-major-versions
    if ${CONFIG[DATABASE_SERVICE_CURRENTLY_ACTIVE]}; then
        debug "Checking database configuration values loaded in memory"



        ## -----------------------------------------------------------------------
        ## Innodb fast shutdown should not be equal to a value of two (2)
        if $(compare_values "$(database_connect --execute='SELECT @@global.innodb_force_recovery')" '-ge' 3); then
            leave invalid_database_config_innodb_force_recovery



        ## -----------------------------------------------------------------------
        ## Innodb force revery level should be below three (3)
        elif $(compare_values "$(database_connect --execute='SELECT @@global.innodb_fast_shutdown')" '-eq' 2); then
            leave invalid_database_config_innodb_fast_shutdown
        fi



    ## ---------------------------------------------------------------------------
    ## If the service isn't active, skip the in-memory directive check
    else
        debug "Service is not active. Skipping in-memory directive check"
    fi
}




function database_connect(){
    ## ---------------------------------------------------------------------------
    ## Connect to the database and perform passed in actions
    local additional_options=(
        --silent
        --skip-column-names
        --skip-table
        --batch
    )



    ## ---------------------------------------------------------------------------
    ## Make sure that the configuration file exists. Perhaps this check should be
    ## "factored out" and evaluated before most other dependent functions
    if [[ ! -f ${CONFIG[DATABASE_CONNECT_DEFAULTS_FILE]} ]]; then
        leave invalid_defaults_file
    fi



    ## ---------------------------------------------------------------------------
    ## Perform the mysql query execution
    mysql \
        --defaults-file=${CONFIG[DATABASE_CONNECT_DEFAULTS_FILE]} \
        --defaults-group-suffix=${CONFIG[DATABASE_CONNECT_GROUP_SUFFIX]} \
        ${additional_options[*]} \
        "${@}"
}




function database_service_status(){
    ## ---------------------------------------------------------------------------
    ## Function that actions database servie status
    local action=${1:-NULL}



    ## ---------------------------------------------------------------------------
    ## Conditionalise actions based off the function argument
    case ${action^^} in



        ## -----------------------------------------------------------------------
        ## Start thes service
        ACTIVATE)



            ## -------------------------------------------------------------------
            ## Only perform if the service is currently inactive
            if ! ${CONFIG[DATABASE_SERVICE_CURRENTLY_ACTIVE]}; then



                ## ---------------------------------------------------------------
                ## Start the database service
                debug "Activating database service."
                systemctl start ${CONFIG[DATABASE_SERVICE_NAME]} --quiet



                ## ---------------------------------------------------------------
                ## Wait for the database service to become reachable
                database_wait_for_startup



            ## -------------------------------------------------------------------
            ## Do nothing since the service was already active. Simply inform
            ## the user
            else
                debug "Database service already activated."
            fi
        ;;



        ## -----------------------------------------------------------------------
        ## Stop the service
        DEACTIVATE)



            ## -------------------------------------------------------------------
            ## Only perform if the service is currently active
            if ${CONFIG[DATABASE_SERVICE_CURRENTLY_ACTIVE]}; then



                ## ---------------------------------------------------------------
                ## Terminate the database service
                debug "Deactivating database service."
                systemctl stop ${CONFIG[DATABASE_SERVICE_NAME]} --quiet



                ## ---------------------------------------------------------------
                ## Wait for the database service to terminate
                database_wait_for_shutdown



            ## -------------------------------------------------------------------
            ## Do nothing since the service was already inactive. Simply inform
            ## the user
            else
                debug "Database service already deactivated."
            fi
        ;;



        ## -----------------------------------------------------------------------
        ## Obtain the current activation and enabled statuses
        GET)



            ## -------------------------------------------------------------------
            ## Obtain the activation status
            systemctl is-active ${CONFIG[DATABASE_SERVICE_NAME]} --quiet
            case ${?} in
                0) CONFIG[DATABASE_SERVICE_INITIALLY_ACTIVE]=true ;;
                *) CONFIG[DATABASE_SERVICE_INITIALLY_ACTIVE]=false ;;
            esac



            ## -------------------------------------------------------------------
            ## Obtain the enabled status
            systemctl is-enabled ${CONFIG[DATABASE_SERVICE_NAME]} --quiet
            case ${?} in
                0) CONFIG[DATABASE_SERVICE_INITIALLY_ENABLED]=true ;;
                *) CONFIG[DATABASE_SERVICE_INITIALLY_ENABLED]=false ;;
            esac
        ;;



        ## -----------------------------------------------------------------------
        ## Restore the activation and enabled statuses to a previously state
        RESTORE)




            ## -------------------------------------------------------------------
            ## Iterate over both the enabled and activation statuses
            for check in enabled active; do



                ## ---------------------------------------------------------------
                ## The check was set to true
                if ${CONFIG[DATABASE_SERVICE_INITIALLY_${check^^}]}; then



                        ## -------------------------------------------------------
                        ## Conditionalise based off the checks
                        case ${check} in



                            ## ---------------------------------------------------
                            ## The check = enabled. At this point we've determined
                            ## the service was enabled previously so re-enable it
                            enabled)
                                debug "Service was previously enabled. Re-enabling service"
                                systemctl enable ${CONFIG[DATABASE_SERVICE_NAME]} --quiet
                            ;;



                            ## ---------------------------------------------------
                            ## The check = active. At this point we've determined
                            ## the service was activated previously so re-activate
                            active)
                                debug "Service was previously activated. Re-activating service"
                                systemctl start ${CONFIG[DATABASE_SERVICE_NAME]} --quiet
                                database_wait_for_startup
                            ;;
                        esac



                ## ---------------------------------------------------------------
                ## The check was set to false
                else



                        ## -------------------------------------------------------
                        ## Conditionalise based off the checks
                        case ${check} in



                            ## ---------------------------------------------------
                            ## The check = enabled. At this point we've determined
                            ## the service was disabled previously, so return the
                            ## service to that state (disabled)
                            enabled)
                                debug "Service was previously disabled. Disabling service"
                                systemctl disable ${CONFIG[DATABASE_SERVICE_NAME]} --quiet
                            ;;



                            ## ---------------------------------------------------
                            ## The check = active. At this point we've determined
                            ## the service was deactivated previously, so return
                            ## the service to that state (deactivated)
                            active)
                                debug "Service was previously deactivated. Deactivating service"
                                systemctl stop ${CONFIG[DATABASE_SERVICE_NAME]} --quiet
                                database_wait_for_shutdown
                            ;;
                        esac
                fi
            done
        ;;

        NULL)   leave missing_service_action ;;
        *)      leave invalid_service_action ;;
    esac
}




function database_upgrade(){
    ## ---------------------------------------------------------------------------
    ## Function that determises if the database requires an upgrade.
    local needs_upgrade



    ## ---------------------------------------------------------------------------
    ## Run the mariadb-upgrade check to determine if an upgrade is required. From
    ## the man page, mariadb-upgrade's return code is sufficient to use here
    debug "Checking if upgrade is needed"
    needs_upgrade=$(mariadb-upgrade --check-if-upgrade-is-needed --silent)



    ## ---------------------------------------------------------------------------
    ## An upgrade is needed
    if [[ ${needs_upgrade} -eq 0 ]]; then



        ## -----------------------------------------------------------------------
        ## Inform the user, perform the upgrade and redirect output to the log
        debug 'Upgrade required! Beginning mariadb upgrade.'
        mariadb-upgrade \
            --defaults-file=${CONFIG[DATABASE_CONNECT_DEFAULTS_FILE]} \
            --defaults-group-suffix=${CONFIG[DATABASE_CONNECT_GROUP_SUFFIX]} \
                >> ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]} \
                2>&1

        debug "Upgrade complete."



    ## ---------------------------------------------------------------------------
    ## No upgrade is required
    else
        debug 'No upgrade required; skipping mysql_upgrade.'
    fi
}




## ----------------------------------------------------------------------------- ##
## PACKAGE FUNCTIONS
## ----------------------------------------------------------------------------- ##
function packages_compare_source_target_versions(){
    ## ---------------------------------------------------------------------------
    ## Function that compares the currently installed database package versions
    ## to the target versions
    local installed_version
    local target_version
    local found_differing_version=false
    local return_code=0



    ## ---------------------------------------------------------------------------
    ## Iterate over the currently installed package list
    for installed_package in ${DB_PACKAGE_LIST[*]}; do
        debug "Comparing installed and source versions for ${installed_package}"



        ## -----------------------------------------------------------------------
        ## Get the current Major.Min version. We force the format since
        ## there's no guarantee that the 'rpm' command will always return
        ## an similar semantic version string
        installed_version=$(rpm \
                                --query \
                                --all \
                                --queryformat '%{VERSION}' \
                                ${installed_package} | \
                                    awk -F'.' '{printf "%s.%s",$1,$2}')



        ## -----------------------------------------------------------------------
        ## Make sure that the 'rpm' command didn't fail out for some reason
        check_exit_code 0 ${?} error_encountered_rpm_package_list



        ## -----------------------------------------------------------------------
        ## Find something that is more robust than repoquery? Or should we just
        ## make sure that repoquery is installed? Either way, pull the available
        ## package versions, and force the Maj.Min string composition since we
        ## aren't guaranteed to have coincidental package version string formats
        ## between 'rpm' and 'repoquery'
        target_version=$(repoquery \
                            --all \
                            --disablerepo=* \
                            --queryformat '%{VERSION}' \
                            --enablerepo=${REPOSITORY[target]} \
                            ${installed_package} | \
                                awk -F'.' '{printf "%s.%s",$1,$2}')



        ## -----------------------------------------------------------------------
        ## Make sure that the 'repoquery' command didn't fail out for some reason
        check_exit_code 0 ${?} error_encountered_rpm_package_list



        ## -----------------------------------------------------------------------
        ## Determine if the installed package and target package versions are
        ## different. If so, increment the counter (which is also the return code)
        debug "Installed package ${installed_package}: v${installed_version} -> v${target_version}"
        if ! $(compare_values "${installed_version}" '==' "${target_version}"); then
            found_differing_version=true
            return_code=$[return_code+1]
        fi
    done




    ## ---------------------------------------------------------------------------
    ## Inform the user of the amount of differing installed/target package
    ## versions, and return that amount as the function return code
    debug "Found ${return_code} of ${#DB_PACKAGE_LIST[*]} packages with differing source/target versions"
    return ${return_code}

}




function packages_verify(){
    ## ---------------------------------------------------------------------------
    ## Package list should not be empty. This would imply that
    ## MariaDB is not installed.
    if [[ ${#DB_PACKAGE_LIST[*]} -eq 0 ]]; then
        leave package_list_empty
    fi
}




function packages_get_installed(){
    ## ---------------------------------------------------------------------------
    ## Get a listing of all MariaDB packages that are installed on
    ## the system
    local package_name="MariaDB"
    local package_list
    local rpm_query_retval



    ## ---------------------------------------------------------------------------
    ## Read the list and store into the DB_PACKAGE_LIST array
    readarray -t DB_PACKAGE_LIST < <(rpm --query --all MariaDB* --queryformat='%{NAME}\n')



    ## ---------------------------------------------------------------------------
    ## Ensure that the RPM command was successful
    rpm_query_retval=${?}
    check_exit_code 0 ${rpm_query_retval} error_encountered_rpm_package_list



    ## ---------------------------------------------------------------------------
    ## Print out the package list
    debug "Existing RPM Package Listing: ${DB_PACKAGE_LIST[*]}"
}




function packages_action(){
    ## ---------------------------------------------------------------------------
    ## Function that determines actions to be taken for packages
    local action=${1:-NULL}
    local package_action_retval
    local yum_options=(
        '--assumeyes'
    )



    ## ---------------------------------------------------------------------------
    ## Make sure that we have a given action to perform, otherwise exit the script
    if [[ ${action} == NULL ]]; then
        leave missing_package_action
    fi



    ## ---------------------------------------------------------------------------
    ## If a --disable-repo option was provided
    if [[ ${REPOSITORY[disable]:-NULL} != NULL ]]; then



        ## -----------------------------------------------------------------------
        ## Conditionalise based off of the values provided
        case ${REPOSITORY[disable]} in
            all) yum_options+=('--disablerepo=*') ;;
            *)   yum_options+=("--disablerepo=${REPOSITORY[disable]}") ;;
        esac
    fi



    ## ---------------------------------------------------------------------------
    ## If a --enable-repo option was provided
    if [[ ${REPOSITORY[enable]:-NULL} != NULL ]]; then



        ## -----------------------------------------------------------------------
        ## Conditionalise based off of the values provided
        case ${REPOSITORY[enable]} in
            all) yum_options+=('--enablerepo=*') ;;
            *)   yum_options+=("--enablerepo=${REPOSITORY[enable]}") ;;
        esac
    fi



    ## ---------------------------------------------------------------------------
    ## Determine the package action options
    case ${action^^} in



        ## -----------------------------------------------------------------------
        ## Installing the package.
        INSTALL)



            ## -------------------------------------------------------------------
            ## Install the package using YUJM
            debug "Installing packages: ${DB_PACKAGE_LIST[*]}"
            yum \
                --disablerepo=*mariadb* \
                --enablerepo=${REPOSITORY[target]} \
                ${yum_options[*]} \
                install \
                ${DB_PACKAGE_LIST[*]} \
                    >> ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]} \
                    2>&1

            ## -------------------------------------------------------------------
            ## Ensure that nothing errored during the installation
            package_action_retval=${?}
            check_exit_code 0 ${package_action_retval} error_encountered_package_installation
        ;;



        ## -----------------------------------------------------------------------
        ## Removing the package
        REMOVE)



            ## --------------------------------------------------------------------
            ## Installing the package.
            ## Use RPM rather than YUM/DNF since we don't want to remove
            ## installed/required dependencies (for exmaple, postfix)
            debug "Removing installed packages: ${DB_PACKAGE_LIST[*]}"
            rpm \
                --nodeps \
                --erase \
                --verbose \
                ${DB_PACKAGE_LIST[*]} \
                    >> ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]} \
                    2>&1



            ## -------------------------------------------------------------------
            ## Ensure that nothing errored during the package removal
            package_action_retval=${?}
            check_exit_code 0 ${package_action_retval} error_encountered_package_removal
        ;;
    esac
}




## ----------------------------------------------------------------------------- ##
## CONFIGURATION FUNCTIONS
## ----------------------------------------------------------------------------- ##
function review_overrides(){
    pass
}




function review_configuration(){
    pass
}




function config_file_preserve(){
    ## ---------------------------------------------------------------------------
    ## Function that performs some action for/to the main configuration file
    local action=${1:-NULL}



    ## ---------------------------------------------------------------------------
    ## Conditionalise the actions
    case ${action^^} in



        ## -----------------------------------------------------------------------
        ## Perform a backup of the current main configuration file. Run check
        ## in case there is a disk/IO error
        PRESERVE|BACKUP|ARCHIVE)
            debug "Backing up configuration file ${CONFIG[DATABASE_MAIN_DEFAULTS_FILE]} -> ${CONFIG[DATABASE_MAIN_DEFAULTS_FILE]}${CONFIG[BACKUP_EXTENSION]}"
            cp --verbose --archive ${CONFIG[DATABASE_MAIN_DEFAULTS_FILE]}{,${CONFIG[BACKUP_EXTENSION]}} >> ${CONFIG[LOG_FILE]}${CONFIG[LOG_FILE_EXTENSION]} 2>&1
            check_exit_code 0 ${?} error_encountered_defaults_file_backup
        ;;



        ## -----------------------------------------------------------------------
        ## Perform a restoration of the current main configuration file, from a
        ## previously archived file. Run check in case there is a disk/IO error
        RESTORE)
            debug "Restoring configuration file from ${CONFIG[DATABASE_MAIN_DEFAULTS_FILE]}${CONFIG[BACKUP_EXTENSION]}"
            cat ${CONFIG[DATABASE_MAIN_DEFAULTS_FILE]}${CONFIG[BACKUP_EXTENSION]} > ${CONFIG[DATABASE_MAIN_DEFAULTS_FILE]}
            check_exit_code 0 ${?} error_encountered_defaults_file_restoration
        ;;
    esac
}




function check_required_options(){
    ## ---------------------------------------------------------------------------
    ## Function that determines whether necessary configuration options are
    ## populated



    ## ---------------------------------------------------------------------------
    ## We require the source repository
    if   [[ ${REPOSITORY[source]:-NULL} == NULL ]]; then
        leave missing_option_source_repo



    ## ---------------------------------------------------------------------------
    ## We require the target repository
    elif [[ ${REPOSITORY[target]:-NULL} == NULL ]]; then
        leave missing_option_target_repo



    ## ---------------------------------------------------------------------------
    ## We require that the upgrade confirmation is provided. If it was not
    ## provied as a command line switch, then inform the user. There will be a
    ## later prompt for the user
    elif ! ${CONFIG[UPGRADE_CONFIRM]}; then
        debug "Command line switch '--confirm-upgrade' or '--yes' or '-y' not provided. Upgrade will not continue unless future confirmation provided."
    fi
}



function parse_configuration_files(){
    ## ---------------------------------------------------------------------------
    ## Recursive search through multiple configuration files and parse.
    ## This will populate ${DBCONFIG_RECURSIVE_ON_DISK} in the following manner
    ##  $ echo "[${key%::AND::*}] ${key#*::AND::} ${DBCONFIG_RECURSIVE_ON_DISK[${key}]}"
    ##
    ##   [mysqld]         innodb_buffer_pool_size              128M
    ##   [mariadb-10.2]   innodb_buffer_pool_instances         12
    ##   [mariadb-10.1]   innodb_buffer_pool_instances         12
    ##   [mariadb-10.4]   innodb_buffer_pool_instances         12
    ##   [mariadb-10.5]   innodb_buffer_pool_instances         12
    ##   [mariadb-10.3]   innodb_buffer_pool_instances         12
    local CONFIG_CURRENT_STACK=(${1:-NULL})
    local CONFIG_CURRENT_INDEX=0
    local CONFIG_SECTION
    local CONFIG_DIRECTIVE
    local CONFIG_VALUE
    local CONFIG_INCLUDE
    local CONFIG_KEY



    ## ---------------------------------------------------------------------------
    ## Ensure that the configuration file variable is populated
    if [[ ${CURRENT_CONFIG} == "NULL" ]]; then
        leave invalid_config_file
    fi



    ## ---------------------------------------------------------------------------
    ## Start out parsing the initial configuration file
    debug "Parsing configuration file: ${CONFIG_CURRENT_STACK[CONFIG_CURRENT_INDEX]}"



    ## ---------------------------------------------------------------------------
    ## Start an endless loop. We'll conditionalise the exit of the loop based
    ## upon the position of the CONFIG_CURRENT_STACK array
    while true; do



        ## -----------------------------------------------------------------------
        ## Ensure the file exists
        if [[ -f ${CONFIG_CURRENT_STACK[CONFIG_CURRENT_INDEX]} ]]; then




            ## -------------------------------------------------------------------
            ## Define the new configuration file
            CURRENT_CONFIG=${CONFIG_CURRENT_STACK[CONFIG_CURRENT_INDEX]}
            debug "Current configuration file: ${CURRENT_CONFIG}"



            ## -------------------------------------------------------------------
            ## Iterate over the lines of the current configuration file
            while read line; do



                ## ---------------------------------------------------------------
                ## This denotes a new configuration section within the current
                ## configuration file
                if printf "${line}" | grep -Eq '^\[[a-zA-Z0-9\.\_\-]+\] *$'; then
                    CONFIG_SECTION=$(echo "${line}" | cut -d'[' -f2 | cut -d']' -f1)



                ## ---------------------------------------------------------------
                ## This is a line that contains a config directive and value
                elif printf "${line}" | grep -Eq '^ *[^[ ]+ *= *[^ ].*$'; then
                    CONFIG_DIRECTIVE=$(echo "${line}" | sed 's, *=.*$,,' | _trim LEFT_RIGHT)
                    CONFIG_VALUE=$(echo "${line}" | sed -e 's,^ *[^=]* *=,,' | _trim LEFT_RIGHT)
                    CONFIG_KEY="${CONFIG_SECTION}::AND::${CONFIG_DIRECTIVE}"
                    DBCONFIG_RECURSIVE_ON_DISK[${CONFIG_KEY}]="${CONFIG_VALUE}"



                ## ---------------------------------------------------------------
                ## This is a line that contains just a configuration directive
                elif printf "${line}" | grep -Eq '^ *[^[ ]+ *$'; then
                    CONFIG_DIRECTIVE=$(echo "${line}" | sed 's, *=.*$,,' | _trim LEFT_RIGHT)
                    CONFIG_VALUE=1
                    CONFIG_KEY="${CONFIG_SECTION}::AND::${CONFIG_DIRECTIVE}"
                    DBCONFIG_RECURSIVE_ON_DISK[${CONFIG_KEY}]="${CONFIG_VALUE}"



                ## ---------------------------------------------------------------
                ## This is a line that includes another file
                elif printf "${line}" | grep -Eq '^ *!include  *.*$'; then
                    CONFIG_INCLUDE=$(echo "${line}" | sed -e 's,^ *!include *,,' | _trim LEFT_RIGHT)
                    CONFIG_CURRENT_STACK+=("${CONFIG_INCLUDE}")
                    debug "Configuration include file found: ${CONFIG_INCLUDE}"



                ## ---------------------------------------------------------------
                ## Placeholder
                elif true; then
                    pass
                fi


            done < <(cat ${CURRENT_CONFIG})



        ## -----------------------------------------------------------------------
        ## The file does not exist, skip it
        else
            debug "Configuration file does not exist... skipping: ${CONFIG_CURRENT_STACK[CONFIG_CURRENT_INDEX]}"
        fi



        ## -----------------------------------------------------------------------
        ## If we are at the last file in the array, break out the array
        CONFIG_CURRENT_INDEX=$[CONFIG_CURRENT_INDEX+1]
        if [[ ${CONFIG_CURRENT_INDEX} -ge ${#CONFIG_CURRENT_STACK[*]} ]]; then
            break
        fi
    done

    return ${EXIT_CODE[script_success]}
}




## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
##                                                                               ##
##                               MAIN FUNCTION                                   ##
##                                                                               ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##
## +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ##

function main(){
    ## ---------------------------------------------------------------------------
    ## Main function from which all other functions are called.



    ## ---------------------------------------------------------------------------
    ## Parse all command line options
    parse_options "${@}"



    ## ---------------------------------------------------------------------------
    ## Verify that all required options are present on command line
    check_required_options



    ## ---------------------------------------------------------------------------
    ## Verify that necessary applications are installed
    check_for_required_binaries ${REQUIRED_BINARIES[*]}



    ## ---------------------------------------------------------------------------
    ## If we pass only cleanup flag 'cleanup-only'. Just call the
    ## leave function since that already call
    if ${CONFIG[CLEANUP_ONLY]}; then
        leave script_success
    fi



    ## ---------------------------------------------------------------------------
    ## Check for do not upgrade flag
    check_for_do_not_upgrade_flag



    ## ---------------------------------------------------------------------------
    ## Get the current status of the database service
    database_service_status GET



    ## ---------------------------------------------------------------------------
    ## Parse the configuration files and print
    parse_configuration_files ${CONFIG[DATABASE_MAIN_DEFAULTS_FILE]}
    database_get_config_on_disk ${CONFIG[DATABASE_MAIN_DEFAULTS_FILE]}
    database_get_config_live



    ## ---------------------------------------------------------------------------
    ## Print the parse configuration file to log
    _print_parsed_configuration



    ## ---------------------------------------------------------------------------
    ## Obtain a list of current DB package
    packages_get_installed



    ## ---------------------------------------------------------------------------
    ## Verify that there was an installed database instance
    packages_verify



    ## ---------------------------------------------------------------------------
    ## Make sure target version is not already installed
    if packages_compare_source_target_versions; then
        leave already_upgraded
    fi



    ## ---------------------------------------------------------------------------
    ## Ensure that the user has confirmed the upgrade, and if not, attempt to
    ## get confirmation from the user via a prompt
    confirm_upgrade



    ## ---------------------------------------------------------------------------
    ## Activate service for the purpose of upgrades
    database_service_status ACTIVATE



    ## ---------------------------------------------------------------------------
    ## Check on-disk database values
    check_target_config_database_values



    ## ---------------------------------------------------------------------------
    ## Only check these if the service is already up and running
    database_check_in_memory_values



    ## ---------------------------------------------------------------------------
    ## Check for any active database replication configurations
    check_for_replication



    ## ---------------------------------------------------------------------------
    ## Create backups
    database_perform_backups



    ## ---------------------------------------------------------------------------
    ## Stop the database service
    database_service_status DEACTIVATE



    ## ---------------------------------------------------------------------------
    ## Back up the main configuration file (even though it is also moved to
    ## .rpmsave during the uninstallation phrase
    config_file_preserve BACKUP



    ## ---------------------------------------------------------------------------
    ## Remove the existing packages
    packages_action REMOVE



    ## ---------------------------------------------------------------------------
    ## Install the new packages
    packages_action INSTALL



    ## ---------------------------------------------------------------------------
    ## Reinstall the original configuration file
    config_file_preserve RESTORE



    ## ---------------------------------------------------------------------------
    ## Start the database service for the purpose of the upgrade. The
    ## status will be restored later
    database_service_status ACTIVATE



    ## ---------------------------------------------------------------------------
    ## Perform upgrade on the database
    database_upgrade



    ## ---------------------------------------------------------------------------
    ## Restore the previous status of the database service
    database_service_status RESTORE



    ## ---------------------------------------------------------------------------
    ## End the program successfully
    leave script_success
}


## -------------------------------------------------------------------------------
## Run the main function and pass all command line options to the function
main "${@}"



## ----------------------------------------------------------------------------- ##
## Function catalogue
## grep ^function %:p | cut -d'(' -f1 | cut -d' ' -f2 | sort | sed 's,^,\#\# ## ,'
## ----------------------------------------------------------------------------- ##
## upgrade.sh _database_backup_terminate_remaining_processes
## upgrade.sh _database_create_backup_directory
## upgrade.sh _get_backup_wait_iteration_length
## upgrade.sh _is_primary_replication
## upgrade.sh _is_secondary_replication
## upgrade.sh _print_parsed_configuration
## upgrade.sh _trap_leave
## upgrade.sh _trim
## upgrade.sh check_exit_code
## upgrade.sh check_for_do_not_upgrade_flag
## upgrade.sh check_for_replication
## upgrade.sh check_for_required_binaries
## upgrade.sh check_required_options
## upgrade.sh check_target_config_database_values
## upgrade.sh compare_values
## upgrade.sh config_file_preserve
## upgrade.sh confirm_upgrade
## upgrade.sh database_backup_wait_for_completion
## upgrade.sh database_check_backup_success
## upgrade.sh database_check_disk_space
## upgrade.sh database_check_in_memory_values
## upgrade.sh database_connect
## upgrade.sh database_get_config_live
## upgrade.sh database_get_config_on_disk
## upgrade.sh database_perform_backups
## upgrade.sh database_service_get_connected_pids
## upgrade.sh database_service_socket_to_pid
## upgrade.sh database_service_status
## upgrade.sh database_upgrade
## upgrade.sh database_upgrade_cleanup
## upgrade.sh database_wait_for_shutdown
## upgrade.sh database_wait_for_startup
## upgrade.sh debug
## upgrade.sh get_loaded_config_value
## upgrade.sh help
## upgrade.sh leave
## upgrade.sh main
## upgrade.sh packages_action
## upgrade.sh packages_compare_source_target_versions
## upgrade.sh packages_get_installed
## upgrade.sh packages_verify
## upgrade.sh parse_configuration_files
## upgrade.sh parse_options
## upgrade.sh pass
## upgrade.sh review_configuration
## upgrade.sh review_overrides
## ----------------------------------------------------------------------------- ##

## vim:syntax=sh:ft=sh:ai:et:nu:sts=4:ts=4:sw=4:
