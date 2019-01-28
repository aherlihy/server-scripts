
if [ $# -lt 2 ]; then
    echo "Usage: replset.sh <server_version> <rs #> <new?> <auth?>"
    exit
fi

SERVER_VERSION="/opt/mongodb-osx-x86_64-"$1"/bin"
echo "using server version $SERVER_VERSION"

RS=$2
DBPATH="testdata$RS/rs$RS"
P0=$((3 * $RS))
PORT=$((27017+$P0))
NEW=$3
AUTH=$4

function clean_up {
    echo "killing processes"
    kill $S1 $S2 $S3
    exit
}

trap clean_up SIGHUP SIGINT SIGTERM

A=""
if [ "$AUTH" = 'auth' ]; then
    echo "WITH AUTH"
    A="--auth --keyFile ./mongodb-keyfile"
fi

if [ "$NEW" = 'new' ]; then
    echo 'STARTING NEW REPLSET'
    rm -rf testdata$RS && mkdir -p $DBPATH"-0" $DBPATH"-1" $DBPATH"-2"
fi

$SERVER_VERSION/mongod --port $PORT --dbpath=$DBPATH"-0" --replSet="rs"$RS $A &
S1=$!
$SERVER_VERSION/mongod --port $(($PORT+1)) --dbpath=$DBPATH"-1" --replSet="rs"$RS $A  &
S2=$!
$SERVER_VERSION/mongod --port $(($PORT+2)) --dbpath=$DBPATH"-2" --replSet="rs"$RS $A  &
S3=$!

echo "S1=$S1 S2=$S2 S3=$S3"

sleep 2

cfg="{
    _id: rs$RS,
    members: [
        {_id: 0, host: 'localhost:$PORT'},
        {_id: 1, host: 'localhost:$(($PORT+1))'},
        {_id: 2, host: 'localhost:$(($PORT+2))'}
    ]
}"
if [ "$NEW" = 'new' ]; then
    echo "Initiating config with $cfg"
    $SERVER_VERSION/mongo --port $PORT --eval "JSON.stringify(rs.initiate({ _id: 'rs$RS', members: [ {_id: 0, host: 'localhost:$PORT'}, {_id: 1, host: 'localhost:$(($PORT+1))'}, {_id: 2, host: 'localhost:$(($PORT+2))'} ] }))"
fi

echo "ReplSet rs$RS started successfully on $PORT, +1 and +2"
cat
