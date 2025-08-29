## Usage

~~~
Usage: ./upgrade.sh <repoopts> [opts]
---

+ ------------------------------------------------------------------------------------------------------------- +
| Required options (source and target repo names)                                                               |
+ ============================ + == + ======= + =============================================================== +
| --source-repo                | -s | string  | A repo name corresponding to the currently installed            |
|                              |    |         | database version (e.g. mariadb_10_5)                            |
+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
| --target-repo                | -t | string  | A repo name corresponding to the upgrade target database        |
|                              |    |         | version (e.g. mariadb_10_11)                                    |
+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +


+ ------------------------------------------------------------------------------------------------------------- +
| Options with values                                                                                           |
+ ============================ + == + ======= + =============================================================== +
| --backup-directory           | -D | string  | Directory path that will be used to house schema backups        |
+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
| --backup-max-wait-seconds    | -w | integer | Max duration of time (in seconds) allowed for backups to        |
|                              |    |         | complete.                                                       |
+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
| --log-file                   | -l | string  | Path to log file (for script output)                            |
+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
| --do-not-upgrade-file        | -X | string  | Path to file indicating that an upgrade should not occur        |
|                              |    |         | (this supercedes/ignores the '--force-backup' option)           |
+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
| --disable-repo               | -d | string  | Comma-delimited list of repository names that should be         |
|                                               disabled during yum operations. Also accepts 'all'              |
+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
| --enable-repo                | -e | string  | Comma-delimited list of repository names that should be         |
|                              |    |         | enabled during yum operations. Also accepts 'all'               |
+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
| --max-disk-usage-percent     | -P | integer | An integer representing the maximum allowed disk usage          |
|                              |    |         | percentage before initial consideration that there is           |
|                              |    |         | insufficient disk space to make backups. This is a              |
|                              |    |         | particularly useful control for smaller disks, where            |
|                              |    |         | backups could eat into a larger percentage of overall           |
|                              |    |         | disk space.                                                     |
|                              |    |         |                                                                 |
|                              |    |         | For example: With a value of 70, and a                          |
|                              |    |         | disk size of 10G, overall database backup size can NOT          |
|                              |    |         | exceed 3G.                                                      |
+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +
| --disk-datadir-size-ratio    | -R | integer | An integer describing the ratio of total free disk space        |
|                              |    |         | to datadir size. Should the ratio exceed this value, in         |
|                              |    |         | addition to the value of max-disk-usage-percent being           |
|                              |    |         | exceeded, the script will determine that there is               |
|                              |    |         | insufficient space to perform backups. This directive           |
|                              |    |         | is particularly useful for /larger/ disks, where                |
|                              |    |         | max-disk-usage-percent does not accurately describe the         |
|                              |    |         | overall available disk space.                                   |
|                              |    |         |                                                                 |
|                              |    |         | For example: With a value of 4, and a datadir size of 50G       |
|                              |    |         | it would be necessary for at LEAST 200G of disk space to        |
|                              |    |         | be free in order for backups to occur                           |
+ ---------------------------- + -- + ------- + --------------------------------------------------------------- +


+ ------------------------------------------------------------------------------------------------- +
| Flags                                                                                             |
+ ========================= + == + ================================================================ +
| --help                    | -h | Show this help file                                              |
+ ------------------------- + -- + ---------------------------------------------------------------- +
| --debug                   | -v | Enable debugging to stdout and log files. Use multiple times to  |
|                           |    | increase the debug level.                                        |
+ ------------------------- + -- + ---------------------------------------------------------------- +
| --confirm-upgrade / --yes | -y | Confirm automatically that any changes will be performed by the  |
|                           |    | script. This is useful when executing the script in an automated |
|                           |    | fashion, such as via ansible. If not provided, a summary of      |
|                           |    | changes will be presented on screen, along with a confirmation   |
|                           |    | prompt.                                                          |
+ ------------------------- + -- + ---------------------------------------------------------------- +
| --colour/--color          | -c | Output to stdout (and log file) in colour.                       |
+ ------------------------- + -- + ---------------------------------------------------------------- +
| --cleanup                 | -o | Perform cleanup after upgrade                                    |
+ ------------------------- + -- + ---------------------------------------------------------------- +
| --cleanup-only            | -O | Only perform cleanup steps                                       |
+ ------------------------- + -- + ---------------------------------------------------------------- +
| --backup-schemas          | -b | Make a backup of all schemas prior to upgrade                    |
+ ------------------------- + -- + ---------------------------------------------------------------- +
| --ignore-replication      | -i | Ignore the fact that there is an active primary/secondary        |
|                           |    | replication array, and proceed with the upgrade. The default     |
|                           |    | behaviour is to halt execution if replication is detected        |
+ ------------------------- + -- + ---------------------------------------------------------------- +
| --force-backup            | -f | Force database backups to occur, even if the script deems        |
|                           |    | that there is insufficient disk space, as determined through the |
|                           |    | combination of 'max-disk-usage-percent' and                      |
|                           |    | 'disk-datadir-size-ratio'                                        |
|                           |    |                                                                  |
|                           |    | Note: This does NOT override the presence of the                 |
|                           |    |       --do-not-upgrade-file option                               |
+ ------------------------- + -- + ---------------------------------------------------------------- +
| --print-config            | -p | Print the overall configuration found by recursing               |
|                           |    | /etc/my.cnf and all included files                               |
+ ------------------------- + -- + ---------------------------------------------------------------- +

Examples
 $ ./bin/upgrade.sh --source-repo=mariadb_105 --target-repo=mariadb_106 --log-file=/var/log/syseng-mariadb-upgrade --backup-directory=/var/lib/database_backups/ --max-disk-usage-percent=70 --disk-datadir-size-ratio=4 --debug --backup-schemas --cleanup --colour --print-config
 $ ./bin/upgrade.sh -s mariadb_105 -t mariadb_106 -l /var/log/syseng-mariadb-upgrade -D /var/lib/database_backups/ -w 20 -P 70 -R 4 -v -v -b -c
 $ ./bin/upgrade.sh --source-repo mariadb_105 --target-repo mariadb_106 --log-file /var/log/syseng-mariadb-upgrade --backup-directory /var/lib/database_backups/ --backup-max-wait-seconds 20 --max-disk-usage-percent 70 --disk-datadir-size-ratio 4 --debug --debug --backup-schemas --colour
~~~

