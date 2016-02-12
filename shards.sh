
if [ $# -ne 2 ]; then
    echo "Usage: replset.sh <server_version> <rs #>"
    exit
fi

if [ $1 -ge 3.2 ]; then
    echo "If using server version >= 3.2, config servers must be replica sets. Use rscs_shards.sh"
    exit
fi

SERVER_VERSION="/opt/mongodb-osx-x86_64-"$1"/bin"
RS=$2
DBPATH="sharddata$RS"
P0=$((3 * $RS))
PORT=$((27017+$P0))

function clean_up {
    kill $S1 $S2 $S3
    exit
}

trap clean_up SIGHUP SIGINT SIGTERM


rm -rf $DBPATH && mkdir -p $DBPATH/config $DBPATH/data

$SERVER_VERSION/mongod -configsvr --port $PORT --dbpath=$DBPATH/config &
S1=$!
sleep 1
$SERVER_VERSION/mongos --configdb mongodb-4.local:$PORT --port $(($PORT+1)) &
S2=$!
$SERVER_VERSION/mongod --dbpath=$DBPATH/data --port $(($PORT+2)) &
S3=$!

echo "S1=$S1 S2=$S2 S3=$S3"

sleep 2

mongo --port $(($PORT+1)) --eval "JSON.stringify(sh.addShard(\"mongodb-4.local:$(($PORT+2))\"))"

echo "Sharded cluster $RS initiated"
cat
