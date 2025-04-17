#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`
logdir="/opt/cabot/docker/home/.ros/log"

source $scriptdir/.env

sudo mkdir -p /mnt/smbshare
sudo mount -t cifs -o username=$NAS_USER,password=$NAS_PASSWORD,uid=$HOST_UID,gid=$HOST_GID,file_mode=0664,dir_mode=0755 //$NAS_IP/$NAS_SHARE_DIR /mnt/smbshare

rsync -av $scriptdir /mnt/smbshare/$CABOT_NAME/
date=$(date "+%Y-%m-%d")
items=($(ls $logdir | grep "cabot_${date}" | grep -v .tar))
for item in ${items[@]}
do
    echo $item
    cd $logdir
    SIZE=`du -d 0 $item | cut -f 1`

    FILE1="${item}_log.tar"
    if [ ! -e $FILE1 ]; then
        tar --exclude="ros2_topics" --exclude="image_topics" -cvf $FILE1 $item
    fi
    if [ $SIZE -gt 13000000 ]; then
        PARTS=(${item}_ros2_topics_part_*)
        if [ ! -e "${PARTS[0]}" ]; then
            tar -cvf - $item/ros2_topics | split -b 10G - ${item}_ros2_topics_part_
        fi
    else
        FILE2="${item}_ros2_topics.tar"
        if [ ! -e $FILE2 ]; then
            tar -cvf $FILE2 $item/ros2_topics
        fi
    fi
done
rsync -av $logdir/cabot_${date}*.tar /mnt/smbshare/$CABOT_NAME/log/