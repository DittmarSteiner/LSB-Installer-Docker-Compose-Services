#! /usr/bin/env bash

# ------------------------------------------------------------------------------
# ISC License http://opensource.org/licenses/isc-license.txt
# ------------------------------------------------------------------------------
# Copyright (c) 2016, Dittmar Steiner <dittmar.steiner@googlemail.com>
# 
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

# force early
sudo echo -n

EXIT_CODE=0

# we use `which` since the defaut version installed by docker engine does not contain the create command
DOCKER_COMPOSE=`which docker-compose`

INSTALLER=$(readlink -f "$0")
APP_PATH=$(dirname $INSTALLER)
SERVICE_NAME=$(basename $APP_PATH)
SERVICE_SCRIPT=/etc/init.d/$SERVICE_NAME
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')

# will be substituted in docker-compose.yml if present
export CONTAINER_VERSION=$RANDOM;

CD=$(pwd)
cd $APP_PATH

function do_install() {
    if [ ! -f docker-compose.yml ]; then
        echo "Missing file: docker-compose.yml"
        
        return -1
    fi
    
    SCRIPT="service$RANDOM.sh"
    ############################################################################
    # BEGIN PREFACE ------------------------------------------------------------
    echo """#! /bin/bash

set -e

# force early
sudo echo -n

DOCKER_COMPOSE=$DOCKER_COMPOSE
INSTALLER=$INSTALLER
APP_PATH=$APP_PATH
SERVICE_NAME=$SERVICE_NAME
SERVICE_SCRIPT=$SERVICE_SCRIPT

EXIT_CODE=0

### BEGIN INIT INFO
# Provides: $SERVICE_NAME
# Required-Start: \$local_fs \$network \$syslog
# Required-Stop: \$local_fs \$syslog
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: start and stop $SERVICE_NAME Services
### END INIT INFO

# Installation
# install: $ $INSTALLER install
# remove : $ $INSTALLER remove
# Service control
# status : $ sudo service $SERVICE_NAME status
# start  : $ sudo service $SERVICE_NAME start
# stop   : $ sudo service $SERVICE_NAME stop
# restart: $ sudo service $SERVICE_NAME restart
# More details: https://wiki.debian.org/LSBInitScripts
""" > $SCRIPT
    # END PREFACE --------------------------------------------------------------
    ############################################################################

    ############################################################################
    # BEGIN TEMPLATE -----------------------------------------------------------
cat <<'EOF'>> $SCRIPT
for arg in $*;
do
    [ "-e" == "$arg" ] && printenv=1
    [ "--env" == "$arg" ] && printenv=1
done

if [ "1" == "$printenv" ]; then
    echo '# Generated environment'
    echo "DOCKER_COMPOSE: $DOCKER_COMPOSE"
    echo "INSTALLER     : $INSTALLER"
    echo "APP_PATH      : $APP_PATH"
    echo "SERVICE_NAME  : $SERVICE_NAME"
    echo "SERVICE_SCRIPT: $SERVICE_SCRIPT"
fi

CD=`pwd`;
cd $APP_PATH;

EXIT_CODE=0;

case "$1" in
    status)
        `which docker-compose` ps
        EXIT_CODE=$?
    ;;
    
    start)
        nohup $SERVICE_SCRIPT startnow >> $APP_PATH/rc.log 2>&1 &
        EXIT_CODE=$?
    ;;
    
    startnow)
        `which docker-compose` up -d
        `which docker-compose` ps
        EXIT_CODE=$?
    ;;
    
    stop)
        $SERVICE_SCRIPT stopnow >> $APP_PATH/rc.log 2>&1
        
        #  the asyc call will never be executed in Ubuntu 15.10 for unknown reasons :-(
        #nohup $SERVICE_SCRIPT stopnow >> $APP_PATH/rc.log 2>&1 &
        EXIT_CODE=$?
    ;;
    
    stopnow)
        `which docker-compose` stop
        `which docker-compose` ps
        EXIT_CODE=$?
    ;;
    
    restart)
        nohup $SERVICE_SCRIPT restartnow >> $APP_PATH/rc.log 2>&1 &
        EXIT_CODE=$?
    ;;
    
    restartnow)
        `which docker-compose` stop
        `which docker-compose` up -d
        `which docker-compose` ps
        EXIT_CODE=$?
    ;;
    
    *)
        echo;
        echo "Usage:";
        echo "    \$ sudo service $SERVICE_NAME [OPTIONS] {start|stop|restart|status}";
        echo "        -e, --env: also print generated environment.";
        echo;
        EXIT_CODE=1;
    ;;
esac

cd $CD;

exit $EXIT_CODE
EOF
    # END TEMPLATE -----------------------------------------------------------------
    ################################################################################

    sudo chmod +x $SCRIPT;
    sudo mv $SCRIPT $SERVICE_SCRIPT;
    
    ln -s $SERVICE_SCRIPT .
    
    cd $APP_PATH
    `which docker-compose` create
    
    cd /etc/init.d/
    sudo update-rc.d $SERVICE_NAME defaults
    sudo service $SERVICE_NAME status;
    
    EXIT_CODE=$?;
}

function do_remove() {
    sudo service $SERVICE_NAME stop;
    
    if [ -f docker-compose.yml ]; then
        `which docker-compose` stop;
        export REMOVING=1;
        do_backup;
        `which docker-compose` rm -f --all;
    fi
    
    sudo rm -f $SERVICE_NAME;
    
    cd /etc/init.d/
    sudo update-rc.d -f $SERVICE_NAME remove
    
    sudo rm -f $SERVICE_SCRIPT;

    EXIT_CODE=$?;
}

function do_backup() {
    local running=$(`which docker-compose` ps | grep -c ' Up ');
    
    [ $running != 0 ] && `which docker-compose` stop;
    
    local CONTAINERS=$(`which docker-compose` ps -q)
    [ "" != "$CONTAINERS" ] && mkdir -p logs_bak;
    
    for C in $CONTAINERS ; do 
        local cname=$(sudo docker inspect --format '{{ .Name }}' $C)
        cname=`basename $cname`
        local c="$APP_PATH/logs_bak/$TIMESTAMP""_$cname.log.gz"
        echo "    Logs backup: $c"
        sudo docker logs $C | gzip -9 &> $c
    done
    
    if [ -d logs_bak ]; then
        local memyselandi=$USER
        sudo chown -R $memyselandi logs_bak
    fi
    
    if [ $running != 0 ]; then
        [[ $REMOVING != 1 && $UPDATING != 1 ]] && `which docker-compose` start;
    fi
    
    EXIT_CODE=$?;
}

function do_update() {
    if [ ! -f docker-compose.yml ]; then
        echo "Missing file: docker-compose.yml"
        
        return -1
    fi
    
    export UPDATING=1;
    local running=$(`which docker-compose` ps | grep -c ' Up ');
    
    do_backup;
    
    `which docker-compose` pull;
    EXIT_CODE=$?;
    
    if [ $running != 0 ]; then 
        `which docker-compose` up -d;
        EXIT_CODE=$?;
    fi
}

case "$1" in
    install)
        do_install;
    ;;
    
    remove)
        do_remove;
    ;;
    
    backup)
        do_backup;
    ;;
    
    update)
        do_update;
    ;;
    
    *)
        echo "Usage:"
        echo "    \$ $0 {install|remove} # the system service"
        echo "    \$ $0 {update}  # maintain the service"
        echo
        echo "Note:"
        echo "    'remove' will keep all data external to the container(s) and all logs."
        echo
        EXIT_CODE=1;
    ;;
esac

cd $CD

exit $EXIT_CODE

