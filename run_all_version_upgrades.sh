#!/bin/bash



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
        --max-disk-usage-percent 70 \
        --disk-datadir-size-ratio 4 \
        --confirm-upgrade \
        --backup-schemas \
        --backup-max-wait-seconds 1800
        --debug \
        --debug \
        --colour


    ## Test that the upgrade was successful. If not, exit
    retval=${?}
    if [[ ${retval} -ne 0 ]]; then
      exit
    fi
done



## vim:syntax=sh:ft=sh:ai:et:ts=4:sts=4:sw=4:nu:
