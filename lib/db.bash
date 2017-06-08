if [ -z $ODOO_HELPER_LIB ]; then
    echo "Odoo-helper-scripts seems not been installed correctly.";
    echo "Reinstall it (see Readme on https://github.com/katyukha/odoo-helper-scripts/)";
    exit 1;
fi

if [ -z $ODOO_HELPER_COMMON_IMPORTED ]; then
    source $ODOO_HELPER_LIB/common.bash;
fi

# ----------------------------------------------------------------------------------------

set -e; # fail on errors

#-----------------------------------------------------------------------------------------
# functions prefix: odoo_db_*
#-----------------------------------------------------------------------------------------

# odoo_db_create [options] <name> [odoo_conf_file]
function odoo_db_create {
    local usage="Usage:

        $SCRIPT_NAME db create [options]  <name> [odoo_conf_file]

        Creates database named <name>

        Options:
           --demo         - load demo-data (default: no demo-data)
           --lang <lang>  - specified language for this db.
                            <lang> is language code like 'en_US'...
           --help         - display this help message
    ";

    # Parse options
    local demo_data='False';
    local db_lang="en_US";
    while [[ $# -gt 0 ]]
    do
        local key="$1";
        case $key in
            --demo)
                demo_data='True';
                shift;
            ;;
            --lang)
                db_lang=$2;
                shift; shift;
            ;;
            -h|--help|help)
                echo "$usage";
                exit 0;
            ;;
            *)
                break;
            ;;
        esac
    done

    local db_name=$1;
    local conf_file=${2:-$ODOO_CONF_FILE};
    
    if [ -z $db_name ]; then
        echo -e "${REDC} dbname not specified!!!${NC}";
        return 1;
    fi

    echov "Creating odoo database $db_name using conf file $conf_file";

    local python_cmd="import lodoo; cl=lodoo.Client(['-c', '$conf_file']);";
    python_cmd="$python_cmd cl.db.create_database(cl._server.tools.config['admin_passwd'], '$db_name', '$demo_data', '$db_lang');"

    run_python_cmd "$python_cmd";
    
    echo -e "${GREENC}Database $db_name created successfuly!${NC}";
}

# odoo_db_drop <name> [odoo_conf_file]
function odoo_db_drop {
    local db_name=$1;
    local conf_file=${2:-$ODOO_CONF_FILE};

    local python_cmd="import lodoo; cl=lodoo.Client(['-c', '$conf_file']);";
    python_cmd="$python_cmd cl.db.drop(cl._server.tools.config['admin_passwd'], '$db_name');"
    
    run_python_cmd "$python_cmd";
    
    echo -e "${GREENC}Database $db_name dropt successfuly!${NC}";
}

# odoo_db_list [odoo_conf_file]
function odoo_db_list {
    local conf_file=${1:-$ODOO_CONF_FILE};

    local python_cmd="import lodoo; cl=lodoo.Client(['-c', '$conf_file', '--logfile', '/dev/null']);";
    python_cmd="$python_cmd print '\n'.join(['%s'%d for d in cl.db.list()]);";
    
    run_python_cmd "$python_cmd";
}

# odoo_db_exists <dbname> [odoo_conf_file]
function odoo_db_exists {
    local db_name=$1;
    local conf_file=${2:-$ODOO_CONF_FILE};

    local python_cmd="import lodoo; cl=lodoo.Client(['-c', '$conf_file', '--logfile', '/dev/null']);";
    python_cmd="$python_cmd exit(int(not(cl.db.db_exist('$db_name'))));";
    
    if run_python_cmd "$python_cmd"; then
        echov "Database named '$db_name' exists!";
        return 0;
    else
        echov "Database '$db_name' does not exists!";
        return 1;
    fi
}

# odoo_db_rename <old_name> <new_name> [odoo_conf_file]
function odoo_db_rename {
    local old_db_name=$1;
    local new_db_name=$2;
    local conf_file=${3:-$ODOO_CONF_FILE};

    local python_cmd="import lodoo; cl=lodoo.Client(['-c', '$conf_file']);";
    python_cmd="$python_cmd cl.db.rename(cl._server.tools.config['admin_passwd'], '$old_db_name', '$new_db_name');"
    
    if run_python_cmd "$python_cmd"; then
        echo -e "${GREENC}Database $old_db_name renamed to $new_db_name successfuly!${NC}";
    else
        echo -e "${REDC}Cannot rename databse $old_db_name to $new_db_name!${NC}";
    fi
}

# odoo_db_dump <dbname> <file-path> [format [odoo_conf_file]]
# dump database to specified path
function odoo_db_dump {
    local db_name=$1;
    local db_dump_file=$2;
    local conf_file=$ODOO_CONF_FILE;

    # determine 3-d and 4-th arguments (format and odoo_conf_file)
    if [ -f "$3" ]; then
        conf_file=$3;
    elif [ ! -z $3 ]; then
        local format=$3;
        local format_opt=", '$format'";

        if [ -f "$4" ]; then
            conf_file=$4;
        fi
    fi

    local python_cmd="import lodoo; cl=lodoo.Client(['-c', '$conf_file']);";
    python_cmd="$python_cmd dump=cl.db.dump(cl._server.tools.config['admin_passwd'], '$db_name' $format_opt).decode('base64');";
    python_cmd="$python_cmd open('$db_dump_file', 'wb').write(dump);";
    
    if run_python_cmd "$python_cmd"; then
        echov "Database named '$db_name' dumped to '$db_dump_file'!";
        return 0;
    else
        echo "Database '$db_name' fails on dump!";
        return 1;
    fi
}


# odoo_db_backup <dbname> [format [odoo_conf_file]]
# if second argument is file and it exists, then it used as config filename
# in other cases second argument is treated as format, and third (if passed) is treated as conf file
function odoo_db_backup {
    if [ -z $BACKUP_DIR ]; then
        echo "Backup dir is not configured. Add 'BACKUP_DIR' variable to your 'odoo-helper.conf'!";
        return 1;
    fi

    local FILE_SUFFIX=`date -I`.`random_string 4`;
    local db_name=$1;
    local db_dump_file="$BACKUP_DIR/db-backup-$db_name-$FILE_SUFFIX";

    # if format is passed and format is 'zip':
    if [ ! -z $2 ] && [ "$2" == "zip" ]; then
        db_dump_file="$db_dump_file.zip";
    else
        db_dump_file="$db_dump_file.backup";
    fi

    odoo_db_dump $db_name $db_dump_file $2 $3;
    echo $db_dump_file
}

# odoo_db_backup_all [format [odoo_conf_file]]
# backup all databases available for this server
function odoo_db_backup_all {
    local conf_file=$ODOO_CONF_FILE;

    # parse args
    if [ -f "$1" ]; then
        conf_file=$1;
    elif [ ! -z $1 ]; then
        local format=$1;
        local format_opt=", '$format'";

        if [ -f "$2" ]; then
            conf_file=$2;
        fi
    fi

    # dump databases
    for dbname in $(odoo_db_list $conf_file); do
        echo -e "${LBLUEC}backing-up database: $dbname${NC}";
        odoo_db_backup $dbname $format $conf_file;
    done
}

# odoo_db_restore <dbname> <dump_file> [odoo_conf_file]
function odoo_db_restore {
    local db_name=$1;
    local db_dump_file=$2;
    local conf_file=${3:-$ODOO_CONF_FILE};

    local python_cmd="import lodoo; cl=lodoo.Client(['-c', '$conf_file']);";
    python_cmd="$python_cmd res=cl.db.restore(cl._server.tools.config['admin_passwd'], '$db_name', open('$db_dump_file', 'rb').read().encode('base64'));";
    python_cmd="$python_cmd exit(0 if res else 1);";
    
    if run_python_cmd "$python_cmd"; then
        echov "Database named '$db_name' restored from '$db_dump_file'!";
        return 0;
    else
        echov "Database '$db_name' fails on restore from '$db_dump_file'!";
        return 1;
    fi
}

# Command line args processing
function odoo_db_command {
    local usage="Usage:

        $SCRIPT_NAME db list [odoo_conf_file]
        $SCRIPT_NAME db exists <name> [odoo_conf_file]
        $SCRIPT_NAME db create <name> [odoo_conf_file]
        $SCRIPT_NAME db create --help
        $SCRIPT_NAME db drop <name> [odoo_conf_file]
        $SCRIPT_NAME db rename <old_name> <new_name> [odoo_conf_file]
        $SCRIPT_NAME db dump <name> <dump_file_path> [format [odoo_conf_file]]
        $SCRIPT_NAME db backup <name> [format [odoo_conf_file]]
        $SCRIPT_NAME db backup-all [format [odoo_conf_file]]
        $SCRIPT_NAME db restore <name> <dump_file_path> [odoo_conf_file]

    ";

    if [[ $# -lt 1 ]]; then
        echo "$usage";
        exit 0;
    fi

    while [[ $# -gt 0 ]]
    do
        local key="$1";
        case $key in
            list)
                shift;
                odoo_db_list "$@";
                exit;
            ;;
            create)
                shift;
                odoo_db_create "$@";
                exit;
            ;;
            drop)
                shift;
                odoo_db_drop "$@";
                exit;
            ;;
            dump)
                shift;
                odoo_db_dump "$@";
                exit;
            ;;
            backup)
                shift;
                odoo_db_backup "$@";
                exit;
            ;;
            backup-all)
                shift;
                odoo_db_backup_all "$@";
                exit;
            ;;
            restore)
                shift;
                odoo_db_restore "$@";
                exit;
            ;;
            exists)
                shift;
                odoo_db_exists "$@";
                exit;
            ;;
            rename)
                shift;
                odoo_db_rename "$@";
                exit;
            ;;
            -h|--help|help)
                echo "$usage";
                exit 0;
            ;;
            *)
                echo "Unknown option / command $key";
                exit 1;
            ;;
        esac
        shift
    done
}
