#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`
[[ "$scriptdir" != */ ]] && scriptdir="$scriptdir/"
logdir="/opt/cabot/docker/home/.ros/log/"

source $scriptdir/.env

mkdir -p /mnt/smbshare
sudo mount -t cifs -o username=$NAS_USER,password=$NAS_PASSWORD //$NAS_IP/$NAS_SHARE_DIR /mnt/smbshare

rsync -avzP $scriptdir /mnt/smbshare/$CABOT_NAME/
rsync -avzP $logdir /mnt/smbshare/$CABOT_NAME/log/