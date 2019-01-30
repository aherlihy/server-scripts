#!/usr/bin/env bash

if [ $# -ne 3 ] && [ $# -ne 4 ] && [ $# -ne 5 ]; then
    echo "Usage: replset.sh <server_version> <config rs #> <shard rs #> --debug? --quiet?"
    echo "    server_version assumes server exists in /opt/mongodb-osx-x86_64-<version>/bin"
    echo "    --debug doesn't run anything, just runs the mongo and mongod commands that would be run"
    echo "    --quiet pipes the server output to dev/null (warning, could miss errors then)"
    exit
fi

SERVER_VERSION="/opt/mongodb-osx-x86_64-"$1"/bin"
RS=$2
SRS=$3
DBPATH="data-rcsc$RS"
CPATH="$DBPATH/config"
SPATH="$DBPATH/shards"
P0=$((3 * $RS))
C_PORT=$((37017+$P0))
S_PORT=$((47017+$P0))
PORT=$((27017+$P0))
PIDS=()

shift 3 # TODO: eventually can check first 3 args for right format

while test $# -gt 0
do
    case "$1" in
        --debug) DEBUG='true'
            ;;
        --quiet) QUIET='true'
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

function mongo_cmd {

    if [[ "$1" = "config" ]]; then
        cfg="{
           _id: 'rs$RS',
            members: [
                {_id: 0, host: 'localhost:$C_PORT'},
                {_id: 1, host: 'localhost:$(($C_PORT+1))'},
                {_id: 2, host: 'localhost:$(($C_PORT+2))'}
            ],
            configsvr: true
        }"
        port=$C_PORT
    else
        cfg="{
            _id: 'rs$SRS',
            members: [
                {_id: 0, host: 'localhost:$S_PORT'},
                {_id: 1, host: 'localhost:$(($S_PORT+1))'},
                {_id: 2, host: 'localhost:$(($S_PORT+2))'}
            ]
        }"
        port=$S_PORT
    fi


    if [[ "$DEBUG" ]]; then
        echo "$SERVER_VERSION/mongo --port $port --eval \"JSON.stringify(rs.initiate($cfg))\""
    else
        echo "Initiating repl shard with $cfg on port $port"
        sleep 2
        $SERVER_VERSION/mongo --port $port --eval "JSON.stringify(rs.initiate($cfg))"
        sleep 2
    fi
}

function debug {
    if [[ "$DEBUG" ]] && [[ "$1" = "skip" ]]; then :
    elif [[ "$DEBUG" ]] && [[ "$1" = "quiet" ]]; then
        shift 1
        echo "$@"
    elif [[ "$DEBUG" ]]; then
        echo "$@"
    elif [[ "$1" = "skip" ]]; then
       shift 1
       $@
    elif [[ -z "$QUIET" ]] && [[ "$1" = "quiet" ]]; then
       shift 1
       $@
    elif [[ "$1" = "quiet" ]]; then
       shift 1
       $@ > /dev/null &
    else
        echo "HERE@!" "$@"
       $@
    fi
}

trap clean_up SIGHUP SIGINT SIGTERM


debug rm -rf $DBPATH
debug mkdir -p "$CPATH/configdb-0" "$CPATH/configdb-1" "$CPATH/configdb-2" "$SPATH/rs$RS-0" "$SPATH/rs$RS-1" "$SPATH/rs$RS-2"

# Start config repl set
debug 'quiet' $SERVER_VERSION/mongod --port $C_PORT --dbpath=$CPATH"/configdb-0" --replSet="rs"$RS --configsvr
PIDS[${#PIDS[@]}]="$!"
debug 'quiet' $SERVER_VERSION/mongod --port $(($C_PORT+1)) --dbpath=$CPATH"/configdb-1" --replSet="rs"$RS --configsvr
PIDS[${#PIDS[@]}]="$!"
debug 'quiet' $SERVER_VERSION/mongod --port $(($C_PORT+2)) --dbpath=$CPATH"/configdb-2" --replSet="rs"$RS --configsvr
PIDS[${#PIDS[@]}]="$!"

debug "skip" sleep 2

mongo_cmd 'config'

# Start mongos
debug 'quiet' $SERVER_VERSION/mongos --port $PORT --configdb "rs"$RS/localhost:$C_PORT,localhost:$(($C_PORT+1)),localhost:$(($C_PORT+2))
PIDS[${#PIDS[@]}]="$!"

# Start replset shard
debug 'quiet' $SERVER_VERSION/mongod --port $S_PORT --shardsvr --dbpath=$SPATH/rs$RS-0 --replSet=rs$SRS
PIDS[${#PIDS[@]}]="$!"
debug 'quiet' $SERVER_VERSION/mongod --port $(($S_PORT+1)) --shardsvr --dbpath=$SPATH/rs$RS-1 --replSet=rs$SRS
PIDS[${#PIDS[@]}]="$!"
debug 'quiet' $SERVER_VERSION/mongod --port $(($S_PORT+2)) --shardsvr --dbpath=$SPATH/rs$RS-2 --replSet=rs$SRS
PIDS[${#PIDS[@]}]="$!"

debug "skip" sleep 2

mongo_cmd 'shard'

debug "skip" sleep 10
debug $SERVER_VERSION/mongo --port $PORT --eval "JSON.stringify(sh.addShard(\"rs$SRS/localhost:$(($S_PORT))\"))"

debug "skip" cat
