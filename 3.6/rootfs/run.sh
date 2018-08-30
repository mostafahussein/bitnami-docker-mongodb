#!/bin/bash
. /opt/bitnami/base/functions
. /opt/bitnami/base/helpers

DAEMON=mongod
USER=mongo
EXEC=$(which $DAEMON)
ARGS="--config /opt/bitnami/mongodb/conf/mongodb.conf"

# configure extra command line flags
if [[ -n $MONGODB_EXTRA_FLAGS ]]; then
    ARGS+=" $MONGODB_EXTRA_FLAGS"
fi

# log output to stdout
sed -i 's/path: .*\/mongodb.log/path: /' /opt/bitnami/mongodb/conf/mongodb.conf


# allow running custom initialization scripts
if [[ -n $(find /docker-entrypoint-initdb.d/ -type f -regex ".*\.\(sh\|js\)") ]] && [[ ! -f /opt/bitnami/mongodb/.user_scripts_initialized ]] ; then
    exec gosu ${USER} ${EXEC} ${ARGS} &
    pidfile="/opt/bitnami/mongodb/tmp/mongodb.pid"
    dbpath="/opt/bitnami/mongodb/data/db"

    # check to see that our "mongod" actually did start up
    tries=30
    while true; do
	sleep 1
        if ! { [ -s "$pidfile" ] && ps "$(< "$pidfile")" &> /dev/null; }; then
	    # bail ASAP if "mongod" isn't even running
	    echo >&2
	    echo >&2 "error: ${DAEMON} does not appear to have stayed running -- perhaps it had an error?"
	    echo >&2
	    exit 1
	fi
	if mongo 'admin' --eval 'quit(0)' &> /dev/null; then
	    # success!
	    break
	fi
	(( tries-- ))
	if [ "$tries" -le 0 ]; then
	    echo >&2
	    echo >&2 "error: ${DAEMON} does not appear to have accepted connections quickly enough -- perhaps it had an error?"
	    echo >&2
	    exit 1
	fi
	sleep 1
    done

    echo "==> Loading user files from /docker-entrypoint-initdb.d";
    if [[ -n "$MONGODB_ROOT_PASSWORD" ]]; then
        mongo=( mongo admin --username root --password $MONGODB_ROOT_PASSWORD --host localhost --quiet )
    else
        mongo=( mongo admin --host localhost --quiet )
    fi

    for f in /docker-entrypoint-initdb.d/*; do
        case "$f" in
            *.sh)
                if [ -x "$f" ]; then
                    echo "Executing $f"; "$f"
                else
                    echo "Sourcing $f"; . "$f"
                fi
                ;;
            *.js)   echo "Executing $f"; "${mongo[@]}" "$f"; echo ;;
            *)      echo "Ignoring $f" ;;
        esac
    done
    touch /opt/bitnami/mongodb/.user_scripts_initialized
    if ! gosu "${USER}" "${EXEC}" --dbpath="$dbpath" --pidfilepath="$pidfile" --shutdown || ! rm -f "$pidfile"; then
        echo >&2 'MongoDB init process failed.'
        exit 1
    fi
fi

info "Starting ${DAEMON}..."
exec gosu ${USER} ${EXEC} ${ARGS}
