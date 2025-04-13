#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`
[[ "$scriptdir" != */ ]] && scriptdir="$scriptdir/"
logdir="/opt/cabot/docker/home/.ros/log/"

source $scriptdir/.env

sudo mkdir -p /mnt/smbshare
sudo mount -t cifs -o username=$NAS_USER,password=$NAS_PASSWORD,uid=1000,gid=1000,file_mode=0664,dir_mode=0755 //$NAS_IP/$NAS_SHARE_DIR /mnt/smbshare

rsync -av $scriptdir /mnt/smbshare/$CABOT_NAME/
date=$(date "+%Y-%m-%d")
rsync -av $logdir/cabot_$date* /mnt/smbshare/$CABOT_NAME/log/