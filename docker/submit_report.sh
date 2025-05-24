#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

source $scriptdir/.env

logdir=/log
rundir=$scriptdir
ssid=`iwgetid -r`
can_upload=0
WIFI_METRIC=50

COUNT_FILE="$scriptdir/timer_count"
if [ ! -f "$COUNT_FILE" ]; then
    echo 0 > $COUNT_FILE
fi

timer_count=$(cat "$COUNT_FILE")
((timer_count+=1))

if [ -z "$ssid" ]; then
    timer_status=$(systemctl --user is-active submit_report.timer)
    if [ "active" == "$timer_status" ]; then
        bash $scriptdir/notification.sh "timer起動"$timer_count"回目"
        echo $timer_count > $COUNT_FILE
        if [ "$timer_count" -gt 3 ]; then
            systemctl --user stop submit_report.timer
            rm $COUNT_FILE
        fi
        exit
    fi
elif [ $ssid == "$WIFI_SSID" ]; then
    if [ -n "$WIFI_DROUTE" ]; then
        sudo nmcli con modify "$WIFI_SSID" ipv4.routes "0.0.0.0/0 $WIFI_DROUTE $WIFI_METRIC"
        sudo nmcli con down "$WIFI_SSID" && sudo nmcli con up "$WIFI_SSID"
        sleep 10
    fi
    can_upload=1
else
    bash $scriptdir/notification.sh $CABOT_NAME" M-lab以外接続時にtimerが終了するか確認通知"
    systemctl --user stop submit_report.timer
    rm $COUNT_FILE
fi

tar_skip=0

show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -u <item>   Upload the specified item."
    echo "  -t          Skip tar creation and use existing tar files."
    echo "  -h          Show this help message."
}

upload() {
    local item=$1

    cd $logdir
    SIZE=`du -d 0 $item | cut -f 1`

    if [ $tar_skip -eq 1 ]; then
        tars=($(ls | grep ${item}_))
    else
        FILE1="${item}_log.tar"
        if [ ! -e $FILE1 ]; then
            tar --exclude="ros2_topics" --exclude="image_topics" -cvf $FILE1 $item
        fi
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
        python3 upload.py -f $upload_item -s $folder_id -p $logdir > stdout.log 2> stderr.log
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

    cd $logdir
    if [ ! -d "./$log" ]; then
        return 0
    fi

    nanosecond=$(bash $script/get_duration.sh $log)
    duration=$((nanosecond / (10**9)))

    server_log_list=($(ls | grep ^$date))
    select=()
    for server_log in ${server_log_list[@]}
    do
        i_time=$(echo $server_log | sed -E 's/.*[0-9]{4}-[0-9]{2}-[0-9]{2}-([0-9]{2}-[0-9]{2}-[0-9]{2}).*/\1/')
        i_timestamp=$(date -d "${i_time//-/:}" "+%s")
        if (( timestamp + duration < i_timestamp )); then
            break
        fi
        select+=($server_log)
    done

    for select_item in ${select[@]}
    do
        cp -r $select_item $logdir/$log
    done
}

while getopts "u:th" opt; do
    case $opt in
      u)
        upload $OPTARG
        if [ -n "$WIFI_DROUTE" ]; then
            sudo nmcli con modify "$WIFI_SSID" ipv4.routes ""
            sudo nmcli con down "$WIFI_SSID" && nmcli con up "$WIFI_SSID"
        fi
        exit
        ;;
      t)
        tar_skip=1
        ;;
      h)
        show_help
        exit
        ;;
      *)
        show_help
        exit 1
        ;;
    esac
done
shift $((OPTIND-1))

failed=0
cp $rundir/issue_list.txt while.txt
while read line
do
    echo $line
    title_file_name=`echo $line | cut -d ',' -f 1`
    body_file_name=`echo $line | cut -d ',' -f 2`
    log=`echo $line | cut -d ',' -f 3`
    if [[ -n $log && ("$line" != *ALL_UPLOAD* || "$line" != *REPORTED*) ]]; then
        list=($log)
        url=()
        log_name=()
        all_upload=0

        mkdir -p $rundir/content
        mkdir -p $rundir/error

        title_path=$rundir/content/$title_file_name
        file_path=$rundir/content/$body_file_name
        notification=0

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

        if [[ "$line" =~ CABOT_LAUNCH_IMAGE_TAG=([^,]+) ]]; then
            label+=(${BASH_REMATCH[1]})
        else
            cabot_launch_image_tag=$(grep '^CABOT_LAUNCH_IMAGE_TAG=' $logdir/$log/env-file | awk -F= '{print $2}')
            label+=($cabot_launch_image_tag)
            sed "s/\(.*$log\)/\1,CABOT_LAUNCH_IMAGE_TAG=$cabot_launch_image_tag/" $rundir/issue_list.txt > tmp_file \
                && cp tmp_file $rundir/issue_list.txt \
                && rm tmp_file
        fi

        if [[ "$line" =~ CABOT_SITE_VERSION=([^,]+) ]]; then
            label+=(${BASH_REMATCH[1]})
        else
            cabot_site_version=$(grep '^CABOT_SITE_VERSION=' $logdir/$log/env-file | awk -F= '{print $2}')
            label+=($cabot_site_version)
            sed "s/\(.*$log\)/\1,CABOT_SITE_VERSION=$cabot_site_version/" $rundir/issue_list.txt > tmp_file \
                && cp tmp_file $rundir/issue_list.txt \
                && rm tmp_file
        fi

        make_issue=1

        if [[ "$line" =~ REPORTED=([0-9]+) ]]; then
            issue_num=${BASH_REMATCH[1]}
            python3 make_issue.py -t $title_path -f $file_path -u ${url[@]} -l ${log_name[@]} -i $issue_num -L ${label[@]} > stdout.log 2> stderr.log

            if [ $? -ne 0 ]; then
                response=$(cat stderr.log)
                python3 notice_error.py issue -e "$response" -i "update log link #$issue_num"
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
                sed "s/\(.*$log\)/\1,REPORTED=$issue_num/" $rundir/issue_list.txt > tmp_file \
                  && cp tmp_file $rundir/issue_list.txt \
                  && rm tmp_file
            fi
        fi

        echo $response
        ((notification+=$make_issue))

        if [ $notification -eq 2 ]; then
            if [[ $all_upload -eq 1 && "$line" != *ALL_UPLOAD* ]]; then
                sed "s/\(.*$log\)/\1,ALL_UPLOAD/" $rundir/issue_list.txt > tmp_file \
                  && cp tmp_file $rundir/issue_list.txt \
                  && rm tmp_file
            fi
            bash $scriptdir/notification.sh $CABOT_NAME"の${log}のアップロードが終了しました。\nhttps://github.com/${REPO_OWNER}/${REPO_NAME}/issues/${issue_num}"
        elif [ $can_upload -eq 1 ]; then
            bash $scriptdir/notification.sh $CABOT_NAME"の${log}のアップロードに失敗しました。"
            failed=1
        fi
    fi
done < while.txt

rm while.txt

if [ $failed -eq 1 ]; then
    bash $scriptdir/notification.sh $CABOT_NAME"の再アップロードをします。"
elif [ $can_upload -eq 1 ]; then
    bash $scriptdir/notification.sh $CABOT_NAME"の自動アップロードを終了します。"
    systemctl --user stop submit_report.timer
    rm $COUNT_FILE
    if [ -n "$WIFI_DROUTE" ]; then
        sudo nmcli con modify "$WIFI_SSID" ipv4.routes ""
        sudo nmcli con down "$WIFI_SSID" && sudo nmcli con up "$WIFI_SSID"
    fi
fi

[ -f stdout.log ] && rm stdout.log
[ -f stderr.log ] && rm stderr.log
