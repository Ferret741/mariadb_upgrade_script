#!/bin/bash



## Variables
declare -A CONFIG
CONFIG[flag_take_backup]=false
CONFIG[flag_backup_once]=false
CONFIG[flag_backup_all]=false
upgrade_script_backup_options=()



## Iterate over the command line switches
while [[ ${#} -gt 0 ]]; do
    case "${1}" in
        ## Only  perform a backup once per iteration of this
        ## wrapper script (as opposed to once every upgrade step)
        --backup-once|-1)
            CONFIG[flag_take_backup]=true
            CONFIG[flag_backup_once]=true
            CONFIG[flag_backup_all]=false
            upgrade_script_backup_options=(
                --backup-schemas
                --backup-max-wait-seconds 1800
                --max-disk-usage-percent 70
                --disk-datadir-size-ratio 4 )
        ;;



        ## Perform a backup during each upgrade step
        --backup-all|-a)
            CONFIG[flag_take_backup]=true
            CONFIG[flag_backup_once]=false
            CONFIG[flag_backup_all]=true
            upgrade_script_backup_options=(
                --backup-schemas
                --backup-max-wait-seconds 1800
                --max-disk-usage-percent 70
                --disk-datadir-size-ratio 4 )
        ;;
    esac



    ## Final shift
    shift
done



## Iterate over the major versions
for source_target_version in 105to106 106to1011 1011to114; do



    ## Split and form source and target version variables
    version_split=(${source_target_version/to/ })
    source_version=${version_split[0]}
    target_version=${version_split[1]}



    ## Perform the upgrade using the source and target versions
    ./bin/upgrade.sh \
        --source-repo mariadb_${source_version} \
        --target-repo mariadb_${target_version} \
        --log-file /var/log/syseng-mariadb-upgrade \
        --backup-directory /var/lib/database_backups/ \
        --confirm-upgrade \
        --debug \
        --debug \
        --colour \
        ${upgrade_script_backup_options[*]}



    ## Test that the upgrade was successful. If not, exit
    retval=${?}
    if [[ ${retval} -ne 0 ]]; then
      exit
    fi



    ## Test if once backup was performed. If the take backup flag
    ## is true, and the the once backup flag is also true, check
    ## to see if the upgrade_script_backup_options with backup was provided.
    ## If this is the case, then assume a backup was taken, since we
    ## have already made it past the point of obtaining the exit
    ## code for the upgrade script. Blank out the upgrade options
    if ${CONFIG[flag_take_backup]}; then
        if ${CONFIG[flag_backup_once]}; then
            if [[ ${#upgrade_script_backup_options[*]} -gt 0 ]]; then
                upgrade_script_backup_options=()
            fi
        fi
    fi

done



## vim:syntax=sh:ft=sh:ai:et:ts=4:sts=4:sw=4:nu:
