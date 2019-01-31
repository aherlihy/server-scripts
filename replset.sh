#!/usr/bin/env bash

if [ $# -lt 2 ] || [ $# -gt 5 ]; then
    echo "Usage: replset.sh <server_version> <config rs #> --new? --debug --quiet?"
    echo "    server_version assumes server exists in /opt/mongodb-osx-x86_64-<version>/bin"
    echo "    config rs# is the port number, offset from 27017"
    echo "    --new creates new DB directories, otherwise uses testdata<rs#>/rs<rs#>"
    echo "    --debug doesn't run anything, just prints the mongo and mongod commands that would be run"
    echo "    --quiet pipes the server output to dev/null (warning, could miss errors then)"
    echo "    --auth turns on auth, and expects 'mongodb-keyfile' to be in the directory"
    exit
fi

SERVER_VERSION="/opt/mongodb-osx-x86_64-"$1"/bin"
echo "using server version $SERVER_VERSION"

RS=$2
DBPATH="testdata$RS/rs$RS"
P0=$((3 * $RS))
PORT=$((27017+$P0))
PIDS=()

shift 2 # TODO: eventually can check first 2 args for right format

while test $# -gt 0
do
    case "$1" in
        --debug) DEBUG='true'
            ;;
        --quiet) QUIET='true'
            ;;
        --new) NEW='true'
            ;;
        --auth) AUTH='true'
            ;;
        *):
            ;;
    esac
    shift
done


function clean_up {
    echo "PIDS" ${PIDS[@]}
    kill ${PIDS[@]}
    exit
}

trap clean_up SIGHUP SIGINT SIGTERM

A=""
if [ "$AUTH" ]; then
    echo "WITH AUTH"
    A="--auth --keyFile ./mongodb-keyfile"
fi

if [ "$NEW" ]; then
    if [[ -z "$DEBUG" ]]; then
        echo 'STARTING NEW REPLSET'
        rm -rf "testdata$RS" && mkdir -p "$DBPATH-0" "$DBPATH-1" "$DBPATH-2"
    else
        echo rm -rf "testdata$RS"
        echo mkdir -p "$DBPATH-0" "$DBPATH-1" "$DBPATH-2"
    fi
fi

function debug {
    if [[ "$DEBUG" ]] && [[ "$1" = "quiet" ]]; then
        shift 1
        echo "$@"
    elif [[ "$DEBUG" ]]; then
        echo "$@"
    elif [[ -z "$QUIET" ]] && [[ "$1" = "quiet" ]]; then
       shift 1
       $@ &
    elif [[ "$1" = "quiet" ]]; then
       shift 1
       $@ > /dev/null &
    else
       $@ &
    fi
}

function mongo_cmd {
    cfg="{
        _id: 'rs$RS',
        members: [
            {_id: 0, host: 'localhost:$PORT'},
            {_id: 1, host: 'localhost:$(($PORT+1))'},
            {_id: 2, host: 'localhost:$(($PORT+2))'}
        ]
    }"

    if [[ "$DEBUG" ]]; then
        echo "$SERVER_VERSION/mongo --port $PORT --eval \"JSON.stringify(rs.initiate($cfg))\""
    else
        echo "Initiating repl with $cfg on port $PORT"
        sleep 2
        $SERVER_VERSION/mongo --port $PORT --eval "JSON.stringify(rs.initiate($cfg))"
        sleep 2
    fi
}

debug "quiet" $SERVER_VERSION/mongod --port $PORT --dbpath="$DBPATH-0" --replSet="rs$RS" $A
PIDS[${#PIDS[@]}]="$!"
debug "quiet" $SERVER_VERSION/mongod --port $(($PORT+1)) --dbpath="$DBPATH-1" --replSet="rs$RS" $A
PIDS[${#PIDS[@]}]="$!"
debug "quiet" $SERVER_VERSION/mongod --port $(($PORT+2)) --dbpath="$DBPATH-2" --replSet="rs$RS" $A
PIDS[${#PIDS[@]}]="$!"

if [[ "$NEW" ]]; then
    mongo_cmd
fi

if [[ -z "$DEBUG" ]]; then
 $SERVER_VERSION/mongo --port $PORT --eval "JSON.stringify(rs.status())"
 cat
fi
