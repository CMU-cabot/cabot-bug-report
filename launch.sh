#!/bin/bash

stop_launch() {
    docker compose down log
    exit 0
}

trap 'stop_launch' SIGINT SIGTERM

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

source $scriptdir/.env

docker compose up

