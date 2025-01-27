#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

cabotdir="/opt/cabot"
logdir="$cabotdir/docker/home/.ros/log"

ssid=`iwgetid -r`
can_upload=0
METRIC=50

COUNT_FILE="$scriptdir/timer_count"
if [ ! -f "$COUNT_FILE" ]; then
    echo 0 > $COUNT_FILE
fi

timer_count=$(cat "$COUNT_FILE")
((timer_count+=1))

source $scriptdir/.env

if [ -z "$ssid" ]; then
    bash $scriptdir/notification.sh "timer起動"$timer_count"回目"
    echo $timer_count > $COUNT_FILE
    if [ "$timer_count" -gt 3 ]; then
        systemctl --user stop submit_report.timer
        rm $COUNT_FILE
    fi
    exit
elif [ $ssid == $SSID ]; then
    if [ -n "$DROUTE" ]; then
        nmcli con modify "$SSID" ipv4.routes "0.0.0.0/0 $DROUTE $METRIC"
        nmcli con down "$SSID" && nmcli con up "$SSID"
        sleep 10
    fi
    can_upload=1
else
    bash $scriptdir/notification.sh $CABOT_NAME" M-lab以外接続時にtimerが終了するか確認通知"
    systemctl --user stop submit_report.timer
    rm $COUNT_FILE
fi

upload() {
    local item=$1

    cd $logdir
    SIZE=`du -d 0 $item | cut -f 1`

    FILE1="${item}_log.tar"
    tar --exclude="ros2_topics" --exclude="image_topics" -cvf $FILE1 $item
    tars=($FILE1)
    if [ $SIZE -gt 13000000 ]; then
        PARTS=(${item}_ros2_topics_part_*)
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

    cd $scriptdir

    output=$(python3 get_folder_url.py -f $item 2>/dev/null)
    IFS=',' read -r folder_id folder_url <<< "$output"
    log_name+=($item)
    url+=($folder_url)

    for upload_item in "${tars[@]}"
    do
        echo start uploading $upload_item
        bash $scriptdir/notification.sh "start uploading ${upload_item}"
        echo folder_id = $folder_id
        python3 upload.py -f $upload_item -s $folder_id  > stdout.log 2> stderr.log
        if [ $? -eq 1 ]; then
            python3 notice_error.py log -e "$(cat stderr.log)" -u "$upload_item"
            url+=("None")
            all_upload=0
        else
            url+=($(cat stdout.log | tail -n 1))
        fi
        
        log_name+=($upload_item)
    done
}

cp_log() {
    local log=$1
    read date time < <(echo $log | sed -E 's/cabot_([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2}-[0-9]{2}-[0-9]{2})/\1 \2/')

    timestamp=$(date -d "${time//-/:}" "+%s")

    cd /opt/cabot-ble-server/log

    server_log_list=($(ls | grep $date))

    for server_log in ${server_log_list[@]}
    do
        i_time=$(echo $server_log | sed -E 's/cabot-ble-server_[0-9]{4}-[0-9]{2}-[0-9]{2}-([0-9]{2}-[0-9]{2}-[0-9]{2})\.log/\1/')
        i_timestamp=$(date -d "${i_time//-/:}" "+%s")
        if (( timestamp < i_timestamp )); then
            break
        fi
        select=$server_log
    done

    if [ -n "$select" ]; then
        cp $select $logdir/$log
    fi
}

while getopts "u:" opt; do
    case $opt in
      u)
        upload $OPTARG
        exit
        ;;
    esac
done
shift $((OPTIND-1))

failed=0
while read line
do
    title_file_name=`echo $line | cut -d ',' -f 1`
    body_file_name=`echo $line | cut -d ',' -f 2`
    log=`echo $line | cut -d ',' -f 3`
    if [[ -n $log && ("$line" != *ALL_UPLOAD* || "$line" != *REPORTED*) ]]; then
        list=($log)
        url=()
        log_name=()
        all_upload=0

        mkdir -p $scriptdir/content
        mkdir -p $scriptdir/error

        title_path=$scriptdir/content/$title_file_name
        file_path=$scriptdir/content/$body_file_name
        notification=0
        source $scriptdir/.env

        if [[ "$line" =~ REPORTED=([0-9]+) ]]; then
            num=${BASH_REMATCH[1]}
            result=`python3 make_issue.py -c -i $num`

            if [ "$result" = "closed" ]; then
                continue
            fi
        fi

        if [ ! `awk 'NF' $title_path` ]; then
            continue
        fi

        if [ $can_upload -eq 1 ]; then
            all_upload=1
            for item in "${list[@]}"
            do
                bash $scriptdir/notification.sh $CABOT_NAME"の${item}のアップロードを開始します。"
                cp_log $item
                upload $item
            done
            ((notification+=$all_upload))
        fi

        label=()
        label+=($CABOT_NAME)
        if [[ $all_upload -eq 0 ]]; then
            label+=("未アップロード")
        fi

        make_issue=1

        if [[ "$line" =~ REPORTED=([0-9]+) ]]; then
            num=${BASH_REMATCH[1]}
            python3 make_issue.py -t $title_path -f $file_path -u ${url[@]} -l ${log_name[@]} -i $num -L ${label[@]} > stdout.log 2> stderr.log

            if [ $? -ne 0 ]; then
                response=$(cat stderr.log)
                python3 notice_error.py issue -e "$response" -i "update log link #$num"
                make_issue=0
            else
                response=$(cat stdout.log)
            fi
        else
            python3 make_issue.py -t $title_path -f $file_path -u ${url[@]} -l ${log_name[@]} -L ${label[@]} > stdout.log 2> stderr.log

            if [ $? -ne 0 ]; then
                response=$(cat stderr.log)
                python3 notice_error.py issue -e "$response" -i "$line"
                make_issue=0
            else
                response=$(cat stdout.log)
                issue_num=$(cat stdout.log | tail -n 1)
                sed -i "s/\(.*$log\)/\1,REPORTED=$issue_num/" $scriptdir/issue_list.txt
            fi
        fi

        echo $response
        ((notification+=$make_issue))

        if [ $notification -eq 2 ]; then
            if [[ $all_upload -eq 1 && "$line" != *ALL_UPLOAD* ]]; then
                sed -i "s/\(.*$log\)/\1,ALL_UPLOAD/" $scriptdir/issue_list.txt
            fi
            bash $scriptdir/notification.sh $CABOT_NAME"の${log}のアップロードが終了しました。\nhttps://github.com/${REPO_OWNER}/${REPO_NAME}/issues/${num}"
        elif [ $can_upload -eq 1 ]; then
            bash $scriptdir/notification.sh $CABOT_NAME"の${log}のアップロードに失敗しました。"
            failed=1
        fi
    fi
done < issue_list.txt

if [ $failed -eq 1 ]; then
    bash $scriptdir/notification.sh $CABOT_NAME"の再アップロードをします。"
elif [ $can_upload -eq 1 ]; then
    bash $scriptdir/notification.sh $CABOT_NAME"の自動アップロードを終了します。"
    systemctl --user stop submit_report.timer
    rm $COUNT_FILE
    if [ -n "$DROUTE" ]; then
        nmcli con modify "$SSID" ipv4.routes ""
        nmcli con down "$SSID" && nmcli con up "$SSID"
    fi
fi

[ -f stdout.log ] && rm stdout.log
[ -f stderr.log ] && rm stderr.log