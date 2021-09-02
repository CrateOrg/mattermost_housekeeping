#!/bin/bash
####
# Deletes entries older than x days
# Optimize table afterwards.
####
# @since 2021-05-20
# @author stev leibelt <artodeto@bazzline.net>
####

####
# @param: string <database user name>
# @param: string <database user password>
# [@param: int <days to keep in the past>] #default is keep the last 90 days
####
function do_the_housekeeping ()
{
    #bo: variable declaration
    local EXPECTED_CONFIGURATION_VERSION=1
    local FLAG_BE_VERBOSE_IS_ENABLED=0
    local FLAG_SHOW_HELP_IS_ENABLED=0
    local PATH_OF_THE_CURRENT_SCRIPT_BASH=$(cd $(dirname "${BASH_SOURCE[0]}"); pwd)

    #   bo: flag evaluation
    while true;
    do
        case "${1}" in
            -h | "--help")
                FLAG_SHOW_HELP_IS_ENABLED=1
                shift 1
                ;;
            -v | "--verbose")
                FLAG_BE_VERBOSE_IS_ENABLED=1
                shift 1
                ;;
            *)
                break
                ;;
        esac
    done
    #   eo: flag evaluation

    if [[ ${FLAG_SHOW_HELP_IS_ENABLED} -eq 1 ]];
    then
        _show_help_and_exit
    fi

    #bin: executables, data: dynamic or static data files, source: templates or not executable no data files
    local PATH_TO_THE_LOCAL_CONFIGURATION_FILE="${PATH_OF_THE_CURRENT_SCRIPT_BASH}/../data/local_config.sh"

    if [[ -f "${PATH_TO_THE_LOCAL_CONFIGURATION_FILE}" ]];
    then
        _log_message debug ":: Sourcing configuration file >>${PATH_TO_THE_LOCAL_CONFIGURATION_FILE}<<."
        source "${PATH_TO_THE_LOCAL_CONFIGURATION_FILE}"

        if [[ ${CONFIGURATION_VERSION} -ne ${EXPECTED_CONFIGURATION_VERSION} ]];
        then
            _log_message crit ":: Configuration version is wrong."
            _log_message crit "   Expected >>${EXPECTED_CONFIGURATION_VERSION}<<, found >>${CONFIGURATION_VERSION}<<."

            echo ":: Configuration version is wrong."
            echo "   Expected >>${EXPECTED_CONFIGURATION_VERSION}<<, found >>${CONFIGURATION_VERSION}<<."

            return 2
        fi
    else
        _log_message crit ":: Configuration file not found >>${PATH_TO_THE_LOCAL_CONFIGURATION_FILE}<<!"

        echo ":: No configuration file available."
        echo "   No file in path >>${PATH_TO_THE_LOCAL_CONFIGURATION_FILE}<<."

        return 1
    fi
    #eo: variable declaration

    #bo: housekeeping
    local DATETIME_LIMIT_AS_STRING=$(date -d "now - ${DAYS_TO_KEEP_IN_THE_PAST} days" +%Y-%m-%d_%H:%M:%S)
    local DATETIME_LIMIT_AS_TIMESTAMP=$(date -d "now - ${DAYS_TO_KEEP_IN_THE_PAST} days" +%s)

    local DATETIME_LIMIT_AS_VALUE=$(( ${DATETIME_LIMIT_AS_TIMESTAMP} * 1000 ))

    _log_message info ":: Removing entries older than >>${DATETIME_LIMIT_AS_STRING}<< which is >>${DATETIME_LIMIT_AS_VALUE}<< as value."

    _process_table_posts ${DATETIME_LIMIT_AS_VALUE}
    _process_table_fileInfo ${DATETIME_LIMIT_AS_VALUE}
    #eo: housekeeping
}

####
# @param: <string: database table name>
# @param: <int: datetime limit as timestamp>
####
function _cleanup_database_table ()
{
    local CURRENT_RUN_ITERATOR=1
    local DATABASE_TABLE_NAME="${1}"
    local DATETIME_LIMIT_AS_TIMESTAMP="${2}"
    local NUMBER_OF_ENTRIES_TO_PROCESS=0

    #bo: cleanup
    _log_message debug "bo: cleanup, table >>${DATABASE_TABLE_NAME}<<."
    _log_message debug "   Using deletion limit of >>${NUMBER_OF_ENTRIES_TO_DELETE_PER_RUN}<<."

    while [[ ${CURRENT_RUN_ITERATOR} -le ${NUMBER_OF_RUNS} ]];
    do
        _log_message info "   Run ${CURRENT_RUN_ITERATOR} / ${NUMBER_OF_RUNS} started."
        _log_message debug "      Executing sql statement >>SELECT COUNT(*) FROM \`${DATABASE_NAME}\` WHERE \`${DATABASE_TABLE_NAME}\`.\`CreateAt\` < ${DATETIME_LIMIT_AS_TIMESTAMP};<<."

        NUMBER_OF_ENTRIES_TO_PROCESS = $(mysql -u"${DATABASE_USER_NAME}" -p"${DATABASE_USER_PASSWORD}" -e "SELECT COUNT(*) FROM \`${DATABASE_NAME}\` WHERE \`${DATABASE_TABLE_NAME}\`.\`CreateAt\` < ${DATETIME_LIMIT_AS_TIMESTAMP};" "${DATABASE_NAME}")

        if [[ ${NUMBER_OF_ENTRIES_TO_PROCESS} -eq 0 ]];
        then
            _log_message info "   There are no entries left to process. Exiting the run loop."
            break
        else
            _log_message info "      Executing sql statement >>DELETE FROM \`${DATABASE_TABLE_NAME}\` WHERE \`${DATABASE_TABLE_NAME}\`.\`CreateAt\` < ${DATETIME_LIMIT_AS_TIMESTAMP} LIMIT ${NUMBER_OF_ENTRIES_TO_DELETE_PER_RUN};<<."
            mysql -u"${DATABASE_USER_NAME}" -p"${DATABASE_USER_PASSWORD}" -e "DELETE FROM \`${DATABASE_TABLE_NAME}\` WHERE \`${DATABASE_TABLE_NAME}\`.\`CreateAt\` < ${DATETIME_LIMIT_AS_TIMESTAMP} LIMIT ${NUMBER_OF_ENTRIES_TO_DELETE_PER_RUN};" "${DATABASE_NAME}"
            _log_message info "   Run ${CURRENT_RUN_ITERATOR} / ${NUMBER_OF_RUNS} finished."
            ((++CURRENT_RUN_ITERATOR))
            sleep 10 #a few seconds does not harm us but helps the dbms to fetch some fresh air
        fi
    done

    _log_message debug "eo: cleanup, table >>${DATABASE_TABLE_NAME}<<."
}

function _log_message ()
{
    local LOG_LEVEL="${1}"
    local LOG_MESSAGE="${2}"

    if [[ ${FLAG_BE_VERBOSE_IS_ENABLED} -eq 1 ]];
    then
        echo "[${LOG_LEVEL}]: ${LOG_MESSAGE}"
    fi

    _log_message ${LOG_LEVEL} ${LOG_MESSAGE}
}

####
# @param: <int: datetime limit as timestamp>
####
function _process_table_posts ()
{
    local DATABASE_TABLE_NAME="Posts"
    local DATETIME_LIMIT_AS_TIMESTAMP="${1}"

    _log_message debug ":: Starting table >>${DATABASE_TABLE_NAME}<< cleanup."
    _cleanup_database_table ${DATABASE_TABLE_NAME} ${DATETIME_LIMIT_AS_TIMESTAMP}

    _execute_maintenance ${DATABASE_TABLE_NAME}
    _log_message debug ":: Finished table >>${DATABASE_TABLE_NAME}<< cleanup."
}

####
# @param: <int: datetime limit as timestamp>
####
function _process_table_fileInfo ()
{
    local DATABASE_TABLE_NAME="FileInfo"
    local DATETIME_LIMIT_AS_TIMESTAMP="${1}"

    #bo: file system cleanup
    _log_message debug ":: Starting cleanup of path >>${FILE_SETTINGS_DIRECTORY}<<."
    ##bo: setup
    local TEMPORARY_DIRECTORY_PATH=$(mktemp -d)

    if [[ ! -d "${TEMPORARY_DIRECTORY_PATH}" ]];
    then
        _log_message crit ":: Could not create temporary directory in path >>${TEMPORARY_DIRECTORY_PATH}<<."

        return 3
    fi

    _log_message debug "   Created directory >>${TEMPORARY_DIRECTORY_PATH}<<."

    chown -R mysql:mysql "${TEMPORARY_DIRECTORY_PATH}"

    local LIST_OF_FILE_INFO_PATH="${TEMPORARY_DIRECTORY_PATH}/file_info_-_path"
    local LIST_OF_FILE_INFO_PREVIEWPATH="${TEMPORARY_DIRECTORY_PATH}/file_info_-_previewpath"
    local LIST_OF_FILE_INFO_THUMBNAILPATH="${TEMPORARY_DIRECTORY_PATH}/file_info_-_thumbnailpath"

    local LIST_OF_FILE_PATH_TO_DELETE="${TEMPORARY_DIRECTORY_PATH}/file_path_to_delete"
    ##eo: setup

    ##bo: list creation
    _log_message debug "   Executing sql statenemt >>SELECT \`Path\` FROM \`${DATABASE_TABLE_NAME}\` WHERE \`CreateAt\` < ${DATETIME_LIMIT_AS_TIMESTAMP} INTO OUTFILE '${LIST_OF_FILE_INFO_PATH}' FIELDS TERMINATED BY ',' ENCLOSED BY '' LINES TERMINATED BY '\n';<<"
    mysql -u"${DATABASE_USER_NAME}" -p"${DATABASE_USER_PASSWORD}" -e "SELECT \`Path\` FROM \`${DATABASE_TABLE_NAME}\` WHERE \`CreateAt\` < ${DATETIME_LIMIT_AS_TIMESTAMP} INTO OUTFILE '${LIST_OF_FILE_INFO_PATH}' FIELDS TERMINATED BY ',' ENCLOSED BY '' LINES TERMINATED BY '\n';" "${DATABASE_NAME}"

    _log_message debug "   Executing sql statement >>SELECT \`PreviewPath\` FROM \`${DATABASE_TABLE_NAME}\` WHERE \`CreateAt\` < ${DATETIME_LIMIT_AS_TIMESTAMP} AND length(\`PreviewPath\`) > 0 INTO OUTFILE '${LIST_OF_FILE_INFO_PREVIEWPATH}' FIELDS TERMINATED BY ',' ENCLOSED BY '' LINES TERMINATED BY '\n';<<"
    mysql -u"${DATABASE_USER_NAME}" -p"${DATABASE_USER_PASSWORD}" -e "SELECT \`PreviewPath\` FROM \`${DATABASE_TABLE_NAME}\` WHERE \`CreateAt\` < ${DATETIME_LIMIT_AS_TIMESTAMP} AND length(\`PreviewPath\`) > 0 INTO OUTFILE '${LIST_OF_FILE_INFO_PREVIEWPATH}' FIELDS TERMINATED BY ',' ENCLOSED BY '' LINES TERMINATED BY '\n';" "${DATABASE_NAME}"

    _log_message debug "   Executing sql statement >>SELECT \`ThumbnailPath\` FROM \`${DATABASE_TABLE_NAME}\` WHERE \`CreateAt\` < ${DATETIME_LIMIT_AS_TIMESTAMP} AND length(\`ThumbnailPath\`) > 0 INTO OUTFILE '${LIST_OF_FILE_INFO_THUMBNAILPATH}' FIELDS TERMINATED BY ',' ENCLOSED BY '' LINES TERMINATED BY '\n'<<;"
    mysql -u"${DATABASE_USER_NAME}" -p"${DATABASE_USER_PASSWORD}" -e "SELECT \`ThumbnailPath\` FROM \`${DATABASE_TABLE_NAME}\` WHERE \`CreateAt\` < ${DATETIME_LIMIT_AS_TIMESTAMP} AND length(\`ThumbnailPath\`) > 0 INTO OUTFILE '${LIST_OF_FILE_INFO_THUMBNAILPATH}' FIELDS TERMINATED BY ',' ENCLOSED BY '' LINES TERMINATED BY '\n';" "${DATABASE_NAME}"

    cat "${LIST_OF_FILE_INFO_PATH}" > "${LIST_OF_FILE_PATH_TO_DELETE}"
    cat "${LIST_OF_FILE_INFO_PREVIEWPATH}" >> "${LIST_OF_FILE_PATH_TO_DELETE}"
    cat "${LIST_OF_FILE_INFO_THUMBNAILPATH}" >> "${LIST_OF_FILE_PATH_TO_DELETE}"
    ##eo: list creation

    ##bo: file removing
    while IFS= read -r RELATIVE_FILE_PATH
    do
        local ABSOLUTE_FILE_PATH="${FILE_SETTINGS_DIRECTORY}/${RELATIVE_FILE_PATH}"

        if [[ -f "${ABSOLUTE_FILE_PATH}" ]];
        then
            _log_message debug "   Removing filepath >>${ABSOLUTE_FILE_PATH}<<."
            rm "${ABSOLUTE_FILE_PATH}"
        else
            _log_message info "   Filepath is invalid >>${ABSOLUTE_FILE_PATH}<<."
        fi
    done < "${LIST_OF_FILE_PATH_TO_DELETE}"
    ##eo: file removing

    ##bo: teardown
    _log_message debug "   Removing directory >>${TEMPORARY_DIRECTORY_PATH}<<."
    rm -fr "${TEMPORARY_DIRECTORY_PATH}"
    ##eo: teardown
    _log_message debug ":: Finished cleanup of path >>${FILE_SETTINGS_DIRECTORY}<<."
    #eo: file system cleanup

    _cleanup_database_table ${DATABASE_TABLE_NAME} ${DATETIME_LIMIT_AS_TIMESTAMP}
    _log_message debug ":: Finished table >>${DATABASE_TABLE_NAME}<< cleanup."
}

function _execute_maintenance ()
{
    local DATABASE_TABLE_NAME="${1}"

    #bo: maintenance
    _log_message debug "bo: maintenance, table >>${DATABASE_TABLE_NAME}<<."

    #   check table health
    if [[ ${EXECUTE_DATABASE_CHECK} -eq 1 ]];
    then
        _log_message notice "   Starting >>check<< for database >>${DATABASE_NAME} ${DATABASE_TABLE_NAME}<<"
        mysqlcheck -u"${DATABASE_USER_NAME}" -p"${DATABASE_USER_PASSWORD}" --check --auto-repair "${DATABASE_NAME}" "${DATABASE_TABLE_NAME}"
    else
        _log_message debug "   Skipping >>check<< for database."
    fi

    if [[ ${EXECUTE_DATABASE_OPTIMIZE} -eq 1 ]];
    then
        #   reclaim unused disk space
        _log_message notice "   Starting >>optimize<< for database >>${DATABASE_NAME} ${DATABASE_TABLE_NAME}<<"
        mysqlcheck -u"${DATABASE_USER_NAME}" -p"${DATABASE_USER_PASSWORD}" --optimize "${DATABASE_NAME}" "${DATABASE_TABLE_NAME}"
    else
        _log_message debug "   Skipping >>optimize<< for database."
    fi

    if [[ ${EXECUTE_DATABASE_ANALYZE} -eq 1 ]];
    then
        #   rebuild and optimize indexes
        _log_message notice "   Starting >>analyze<< for database >>${DATABASE_NAME} ${DATABASE_TABLE_NAME}<<"
        mysqlcheck -u"${DATABASE_USER_NAME}" -p"${DATABASE_USER_PASSWORD}" --analyze "${DATABASE_NAME}" "${DATABASE_TABLE_NAME}"
    else
        _log_message debug "   Skipping >>analyze<< for database."
    fi
    _log_message debug "eo: maintenance, table >>${DATABASE_TABLE_NAME}<<."
    #eo: maintenance
}

function _show_help_and_exit ()
{
    echo ":: Usage"
    echo "   do_the_housekeeping.sh [-h|--help] [-v|--verbose]"

    exit;
}

do_the_housekeeping ${@}
