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
logdir=$LOGDIR

source $scriptdir/.env

sudo mkdir -p /mnt/smbshare
if sudo mount -t cifs -o username=$NAS_USER,password=$NAS_PASSWORD,uid=$HOST_UID,gid=$HOST_GID,cache=none,file_mode=0664,dir_mode=0755 //$NAS_IP_WIRED/$NAS_SHARE_DIR /mnt/smbshare; then
    bash $scriptdir/notification.sh "sudo mount Ether"
elif sudo mount -t cifs -o username=$NAS_USER,password=$NAS_PASSWORD,uid=$HOST_UID,gid=$HOST_GID,cache=none,file_mode=0664,dir_mode=0755 //$NAS_IP/$NAS_SHARE_DIR /mnt/smbshare; then
    bash $scriptdir/notification.sh "sudo mount wireless"
else
    bash $scriptdir/notification.sh "mount failure"
fi

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

bash $scriptdir/notification.sh "start upload ${item} from ${CABOT_NAME} to NAS"

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
    bash $scriptdir/notification.sh "uploading ${tars[*]}"
    rsync -av --size-only "${tars[@]}" /mnt/smbshare/$CABOT_NAME/log/ 
    if [[ $terminating -eq 1 ]]; then
        break
    fi
    rm ${tars[@]}
done

# only make issue
SSID="dummy" $scriptdir/submit_report.sh

rsync -av $scriptdir/content /mnt/smbshare/$CABOT_NAME/
rsync -av $scriptdir/issue_list.txt /mnt/smbshare/$CABOT_NAME/

bash $scriptdir/notification.sh "finish upload from ${CABOT_NAME} to NAS"