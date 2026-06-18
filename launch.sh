#!/bin/bash

stop_launch() {
    docker compose down
    exit 0
}

trap 'stop_launch' SIGINT SIGTERM

scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

source $scriptdir/.env

if [ $# -gt 0 ]; then
    docker compose run --rm bug-report ./submit_report.sh "$@"
else
    docker compose up
fi
