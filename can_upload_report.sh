#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

ssid=`iwgetid -r`

if [[ ! -e .env ]]; then
    exit 1
fi

export $(cat $scriptdir/.env | grep -v "#" | xargs)

if [[ $ssid != $SSID ]]; then
    exit 1
fi
