#!/usr/bin/env bash

if [ $# -ne 4 ] && [ $# -ne 5 ] && [ $# -ne 6 ]; then
    echo "Usage: replset.sh <server_version> <config rs #> <shard rs #> <n shards> --debug? --quiet?"
    echo "    server_version assumes server exists in /opt/mongodb-osx-x86_64-<version>/bin"
    echo "    --debug doesn't run anything, just prints the mongo and mongod commands that would be run"
    echo "    --quiet pipes the server output to dev/null (warning, could miss errors then)"
    exit
fi

SERVER_VERSION="/opt/mongodb-osx-x86_64-"$1"/bin"
RS=$2
SRS=$3
N_SHARDS=$4
echo $N_SHARDS
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
            configsvr: true,
            members: [
                {_id: 0, host: 'localhost:$C_PORT'},
                {_id: 1, host: 'localhost:$(($C_PORT+1))'},
                {_id: 2, host: 'localhost:$(($C_PORT+2))'}
            ]
        }"
        port=$C_PORT
    else
        cfg="{
            _id: 'rs-shard$SRS-$2',
            members: [
                {_id: 0, host: 'localhost:$(($S_PORT+$3))'},
                {_id: 1, host: 'localhost:$(($S_PORT+1+$3))'},
                {_id: 2, host: 'localhost:$(($S_PORT+2+$3))'}
            ]
        }"
        port=$(($S_PORT+$3))
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
       $@ &
    elif [[ "$1" = "quiet" ]]; then
       shift 1
       $@ > /dev/null &
    else
       $@
    fi
}

trap clean_up SIGHUP SIGINT SIGTERM


debug rm -rf $DBPATH
debug mkdir -p "$CPATH/configdb-0" "$CPATH/configdb-1" "$CPATH/configdb-2"

for shardCount in `seq 0 $(($N_SHARDS - 1))`;
  do
      debug mkdir -p "$SPATH/rs$RS-$shardCount-0" "$SPATH/rs$RS-$shardCount-1" "$SPATH/rs$RS-$shardCount-2"
  done


# Start config repl set
debug 'quiet' $SERVER_VERSION/mongod --configsvr --replSet="rs$RS" --port $C_PORT --dbpath="$CPATH/configdb-0"
PIDS[${#PIDS[@]}]="$!"
debug 'quiet' $SERVER_VERSION/mongod --configsvr --replSet="rs$RS" --port $(($C_PORT+1)) --dbpath="$CPATH/configdb-1"
PIDS[${#PIDS[@]}]="$!"
debug 'quiet' $SERVER_VERSION/mongod --configsvr --replSet="rs$RS" --port $(($C_PORT+2)) --dbpath="$CPATH/configdb-2"
PIDS[${#PIDS[@]}]="$!"

debug "skip" sleep 2

mongo_cmd 'config'

for n in `seq 0 $(($N_SHARDS - 1))`;
  do
      calcPort=$((3*$n))
      # Start replset shard
      debug 'quiet' $SERVER_VERSION/mongod --shardsvr --replSet="rs-shard$SRS-$n" --port $(($S_PORT+$calcPort)) --dbpath="$SPATH/rs$RS-$n-0"
      PIDS[${#PIDS[@]}]="$!"
      debug 'quiet' $SERVER_VERSION/mongod --shardsvr --replSet="rs-shard$SRS-$n" --port $(($S_PORT+$calcPort+1)) --dbpath="$SPATH/rs$RS-$n-1"
      PIDS[${#PIDS[@]}]="$!"
      debug 'quiet' $SERVER_VERSION/mongod --shardsvr --replSet="rs-shard$SRS-$n" --port $(($S_PORT+$calcPort+2)) --dbpath="$SPATH/rs$RS-$n-2"
      PIDS[${#PIDS[@]}]="$!"
      mongo_cmd 'shard' $n $calcPort
  done

# Start mongos
debug 'quiet' $SERVER_VERSION/mongos --configdb "rs$RS/localhost:$C_PORT,localhost:$(($C_PORT+1)),localhost:$(($C_PORT+2))" --port $PORT
PIDS[${#PIDS[@]}]="$!"

debug "skip" sleep 2


debug "skip" sleep 10
for n in `seq 0 $(($N_SHARDS - 1))`;
  do
    calcPort=$((3*$n))
    debug $SERVER_VERSION/mongo --port $PORT --eval "JSON.stringify(sh.addShard(\"rs-shard$SRS-$n/localhost:$(($S_PORT+$calcPort))\"))"
  done

debug $SERVER_VERSION/mongo --port $PORT --eval "JSON.stringify(sh.enableSharding('test'))"

debug "skip" cat

