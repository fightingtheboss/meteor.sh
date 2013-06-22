#!/bin/bash

# IP or URL of the server you want to deploy to
export APP_HOST=example.com

# Uncomment this if your host is an EC2 instance
export EC2_PEM_FILE=path/to/your/file.pem

export APP_NAME=meteorapp
export ROOT_URL=http://$APP_HOST
export APP_DIR=/var/www/$APP_NAME
export APP_LOG_DIR=/var/log/$APP_NAME
export MONGO_URL=mongodb://localhost:27017/$APP_NAME

if [ -z "$EC2_PEM_FILE" ]; then
    export SSH_HOST="root@$APP_HOST" SSH_OPT=""
  else
    export SSH_HOST="ubuntu@$APP_HOST" SSH_OPT="-i $EC2_PEM_FILE"
fi

if [ -d ".meteor/meteorite" ]; then
    export METEOR_CMD=mrt
  else
    export METEOR_CMD=meteor
fi

deploy() {
scp $SSH_OPT bundle.tgz $SSH_HOST:/tmp/ &&
ssh $SSH_OPT $SSH_HOST PORT=9000 MONGO_URL=$MONGO_URL ROOT_URL=$ROOT_URL APP_DIR=$APP_DIR APP_LOG_DIR=$APP_LOG_DIR 'sudo -E bash -s' <<'ENDSSH'
if [ ! -d "$APP_DIR" ]; then
mkdir -p $APP_DIR
chown -R www-data:www-data $APP_DIR
fi
pushd /tmp
tar xfz bundle.tgz
rm bundle.tgz
cd bundle/server/node_modules
rm -rf fibers
npm install fibers
cd $APP_DIR
forever stop bundle/main.js
rm -rf bundle
mv /tmp/bundle $APP_DIR
chown -R www-data:www-data bundle
patch -u bundle/server/server.js <<'ENDPATCH'
@@ -286,6 +286,8 @@
     app.listen(port, function() {
       if (argv.keepalive)
         console.log("LISTENING"); // must match run.js
+      process.setgid('www-data');
+      process.setuid('www-data');
     });

   }).run();
ENDPATCH
if [ ! -d "$APP_LOG_DIR" ]; then
mkdir -p $APP_LOG_DIR
fi
forever start -a -l "$APP_LOG_DIR/production.log" -e "$APP_LOG_DIR/error.log" bundle/main.js
popd
ENDSSH
}

case "$1" in
setup )
echo Preparing the server...
echo Get some coffee, this will take a while.
ssh $SSH_OPT $SSH_HOST DEBIAN_FRONTEND=noninteractive 'sudo -E bash -s' > /dev/null 2>&1 <<'ENDSSH'
apt-get update
apt-get install -y python-software-properties
add-apt-repository ppa:chris-lea/node.js-legacy
apt-get update
apt-get install -y build-essential nodejs npm mongodb
npm install -g forever
ENDSSH
echo Done. You can now deploy your app.
;;

deploy )
echo Starting deploy to $APP_NAME
echo Creating bundle...
$METEOR_CMD bundle bundle.tgz > /dev/null 2>&1 &&

if [ -z "$EC2_PEM_FILE" ]; then
    echo Deploying...
    deploy
  else
    # Need to loop over all running instances
    for instance in `ec2-describe-instances --filter "group-name=www" | grep amazonaws.com | cut -f 4`
    do
      echo "Deploying to $instance"
      export APP_HOST=$instance
      export ROOT_URL=http://$APP_HOST
      export SSH_HOST="ubuntu@$APP_HOST" SSH_OPT="-i $EC2_PEM_FILE"
      deploy
    done
fi

rm bundle.tgz > /dev/null 2>&1 &&
echo Your app is deployed
;;

* )
cat <<'ENDCAT'
./meteor.sh [action]

Available actions:

  setup   - Install a meteor environment on a fresh Ubuntu server
  deploy  - Deploy the app to the server
ENDCAT
;;
esac