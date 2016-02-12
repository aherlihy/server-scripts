
if [ $# -ne 3 ]; then
    echo "Usage: replset.sh <server_version> <config rs #> <shard rs #>"
    exit
fi

SERVER_VERSION="/opt/mongodb-osx-x86_64-"$1"/bin"
RS=$2
SRS=$3
DBPATH="rscsdata$RS"
CPATH="$DBPATH/config"
SPATH="$DBPATH/shards"
P0=$((3 * $RS))
C_PORT=$((37017+$P0))
S_PORT=$((47017+$P0))
PORT=$((27017+$P0))

function clean_up {
    kill $S1 $S2 $S3 $S4 $S5 $S6 $S7
    exit
}

trap clean_up SIGHUP SIGINT SIGTERM


rm -rf $DBPATH && mkdir -p "$CPATH/configdb-0" "$CPATH/configdb-1" "$CPATH/configdb-2" "$SPATH/rs$RS-0" "$SPATH/rs$RS-1" "$SPATH/rs$RS-2"

# Start config repl set
$SERVER_VERSION/mongod --port $C_PORT --dbpath=$CPATH"/configdb-0" --replSet="rs"$RS --configsvr &> /dev/null &
S1=$!
$SERVER_VERSION/mongod --port $(($C_PORT+1)) --dbpath=$CPATH"/configdb-1" --replSet="rs"$RS --configsvr &> /dev/null &
S2=$!
$SERVER_VERSION/mongod --port $(($C_PORT+2)) --dbpath=$CPATH"/configdb-2" --replSet="rs"$RS --configsvr &> /dev/null &
S3=$!

echo "S1=$S1 S2=$S2 S3=$S3"

sleep 2

cfg="{
    _id: \"rs$RS\",
    members: [
        {_id: 0, host: 'mongodb-4.local:$C_PORT'},
        {_id: 1, host: 'mongodb-4.local:$(($C_PORT+1))'},
        {_id: 2, host: 'mongodb-4.local:$(($C_PORT+2))'}
    ],
    configsvr:true
}"
echo "Initiating config with $cfg"
$SERVER_VERSION/mongo --port $C_PORT --eval "JSON.stringify(rs.initiate($cfg))"
sleep 2

# Start mongos
$SERVER_VERSION/mongos --port $PORT --configdb mongodb-4.local:$C_PORT,mongodb-4.local:$(($C_PORT+1)),mongodb-4.local:$(($C_PORT+2)) &> /dev/null &
S4=$!
echo "S4=$S4"

# Start replset shard
$SERVER_VERSION/mongod --port $S_PORT --dbpath=$SPATH/rs$RS-0 --replSet=rs$SRS &> /dev/null &
S5=$!
$SERVER_VERSION/mongod --port $(($S_PORT+1)) --dbpath=$SPATH/rs$RS-1 --replSet=rs$SRS &> /dev/null &
S6=$!
$SERVER_VERSION/mongod --port $(($S_PORT+2)) --dbpath=$SPATH/rs$RS-2 --replSet=rs$SRS &> /dev/null &
S7=$!

echo "S5=$S1 S6=$S2 S7=$S3"

sleep 2

cfg="{
    _id: \"rs$SRS\",
    members: [
        {_id: 0, host: 'mongodb-4.local:$S_PORT'},
        {_id: 1, host: 'mongodb-4.local:$(($S_PORT+1))'},
        {_id: 2, host: 'mongodb-4.local:$(($S_PORT+2))'}
    ]
}"
echo "Initiating repl shard with $cfg"
$SERVER_VERSION/mongo --port $S_PORT --eval "JSON.stringify(rs.initiate($cfg))"

sleep 10
$SERVER_VERSION/mongo --port $PORT --eval "JSON.stringify(sh.addShard(\"rs$SRS/mongodb-4.local:$(($S_PORT))\"))"

cat