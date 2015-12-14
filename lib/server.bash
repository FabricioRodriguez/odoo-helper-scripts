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



# Prints server script name
# (depends on ODOO_BRANCH environment variable,
#  which should be placed in project config)
# Now it simply returns openerp-server
function get_server_script {
    check_command odoo.py openerp-server openerp-server.py;
}

# Function to check server run status;
# Function echo:
#   pid - server running process <pid>
#   -1  - server stopped
#   -2  - pid file points to unexistent process
#
# server_is_running
function server_get_pid {
    if [ -f "$ODOO_PID_FILE" ]; then
        local pid=`cat $ODOO_PID_FILE`;
        if is_process_running $pid; then
            echo "$pid";
        else
            echo "-2";
        fi
    else
        echo "-1";
    fi
}

# Internal function to run odoo server
function run_server_impl {
    local SERVER=`get_server_script`;
    echo -e "${LBLUEC}Running server${NC}: $SERVER $@";
    export OPENERP_SERVER=$ODOO_CONF_FILE;
    execu $SERVER "$@";
    unset OPENERP_SERVER;
}

# server_run <arg1> .. <argN>
# all arguments will be passed to odoo server
function server_run {
    run_server_impl "$@";
}

function server_start {
    # Check if server process is already running
    if [ $(server_get_pid) -gt 0 ]; then
        echo -e "${REDC}Server process already running.${NC}";
        exit 1;
    fi

    run_server_impl --pidfile=$ODOO_PID_FILE "$@" &
    local pid=$!;
    sleep 2;
    echo -e "${GREENC}Odoo started!${NC}";
    echo -e "PID File: ${YELLOWC}$ODOO_PID_FILE${NC}."
    echo -e "Process ID: ${YELLOWC}$pid${NC}";
}

function server_stop {
    local pid=$(server_get_pid);
    if [ $pid -gt 0 ]; then
        if kill $pid; then
            # wait until server is stopped
            for stime in 1 2 3 4; do
                if is_process_running $pid; then
                    # if process alive, wait a little time
                    echov "Server still running. sleeping for $stime seconds";
                    sleep $stime;
                else
                    break;
                fi
            done

            # if process still alive, it seems that it is frozen, so force kill it
            if is_process_running $pid; then
                kill -SIGKILL $pid;
                sleep 1;
            fi

            echo "Server stopped.";
            rm -f $PID_FILE;
        else
            echo "Cannot kill process.";
        fi
    else
        echo "Server seems not to be running!"
        echo "Or PID file $ODOO_PID_FILE was removed";
    fi
}

function server_status {
    local pid=$(server_get_pid);
    if [ $pid -gt 0 ]; then
        echo -e "${GREENC}Server process already running. PID=${pid}.${NC}";
    elif [ $pid -eq -2 ]; then
        echo -e "${YELLOWC}Pid file points to unexistent process.${NC}";
    elif [ $pid -eq -1 ]; then
        echo "Server stopped";
    fi
}

# server [options] <command> <args>
# server [options] start <args>
# server [options] stop <args>
function server {
    local usage="
    Usage 

        $SCRIPT_NAME server [options] [command] [args]

    args - arguments that usualy will be passed forward to openerp-server script

    Commands:
        run             - run the server. if no command supply, this one will be used
        start           - start server in background
        stop            - stop background running server
        restart         - restart background server
        status          - status of background server
        log             - open server log
        -h|--help|help  - display this message

    Options:
        --use-test-conf     - Use test configuration file for server
    ";

    while [[ $# -gt 0 ]]
    do
        key="$1";
        case $key in
            -h|--help|help)
                echo "$usage";
                exit 0;
            ;;
            --use-test-conf)
                ODOO_CONF_FILE=$ODOO_TEST_CONF_FILE;
                echo -e "${YELLOWC}NOTE${NC}: Using test configuration file: $ODOO_TEST_CONF_FILE";
            ;;
            run)
                shift;
                server_run "$@";
                exit;
            ;;
            start)
                shift;
                server_start "$@";
                exit;
            ;;
            stop)
                shift;
                server_stop "$@";
                exit;
            ;;
            restart)
                shift;
                server_stop;
                server_start "$@";
                exit;
            ;;
            status)
                shift;
                server_status "$@";
                exit
            ;;
            log)
                shift;
                # TODO: remove backward compatability from this code
                less ${LOG_FILE:-$LOG_DIR/odoo.log};
                exit;
            ;;
            *)
                # all nex options have to be passed to the server
                break;
            ;;
        esac;
        shift;
    done;
    server_run "$@";
    exit;
}

# odoo_py <args>
function odoo_py {
    echov -e "${LBLUEC}Running odoo.py with arguments${NC}:  $@";
    export OPENERP_SERVER=$ODOO_CONF_FILE;
    execu odoo.py "$@";
    unset OPENERP_SERVER;
}

