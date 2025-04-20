#!/bin/bash

terminating=0

cleanup() {
    echo "Caught signal, cleaning up..."
    terminating=1
    sleep 1
    rm ${tars[@]}
    exit 1
}
trap cleanup SIGINT SIGTERM SIGHUP

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`
logdir="/opt/cabot/docker/home/.ros/log"

source $scriptdir/.env

sudo mkdir -p /mnt/smbshare
sudo mount -t cifs -o username=$NAS_USER,password=$NAS_PASSWORD,uid=$HOST_UID,gid=$HOST_GID,cache=none,file_mode=0664,dir_mode=0755 //$NAS_IP/$NAS_SHARE_DIR /mnt/smbshare

# Parse options
while getopts "d:h" opt; do
    case $opt in
        d) date=$OPTARG ;;
        h) 
            echo "Usage: $0 [-d date] [-h]"
            echo "  -d date   Specify the date in YYYY-MM-DD format (default: today's date)"
            echo "  -h        Show this help message"
            exit 0
            ;;
        *) 
            echo "Invalid option. Use -h for help."
            exit 1
            ;;
    esac
done

# Default to today's date if not specified
if [ -z "$date" ]; then
    date=$(date "+%Y-%m-%d")
fi

items=($(ls $logdir | grep "cabot_${date}" | grep -v .tar | grep -v _part_))
for item in ${items[@]}
do
    echo $item
    cd $logdir
    SIZE=`du -d 0 $item | cut -f 1`

    FILE1="${item}_log.tar"
    if [ ! -e $FILE1 ]; then
        tar --exclude="ros2_topics" --exclude="image_topics" -cvf $FILE1 $item
    fi
    tars=($FILE1)
    if [ $SIZE -gt 13000000 ]; then
        PARTS=($(ls $logdir | grep ${item}_ros2_topics_part_))
        if [ ! -e "${PARTS[0]}" ]; then
            tar -cvf - $item/ros2_topics | split -b 10G - ${item}_ros2_topics_part_
        fi
        tars+=(`ls | grep ${item}_ros2_topics_part_`)
    else
        FILE2="${item}_ros2_topics.tar"
        if [ ! -e $FILE2 ]; then
            tar -cvf $FILE2 $item/ros2_topics
        fi
        tars+=($FILE2)
    fi
    echo ${tars[@]}
    echo rsync start
    rsync -av --size-only "${tars[@]}" /mnt/smbshare/$CABOT_NAME/log/ 
    if [[ $terminating -eq 1 ]]; then
        break
    fi
    rm ${tars[@]}
done

rsync -av $scriptdir/content /mnt/smbshare/$CABOT_NAME/
rsync -av $scriptdir/issue_list.txt /mnt/smbshare/$CABOT_NAME/