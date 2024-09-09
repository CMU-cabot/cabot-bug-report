#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

cabotdir="/opt/cabot"
logdir="$cabotdir/docker/home/.ros/log"

ssid=`iwgetid -r`
can_upload=0

export $(cat $scriptdir/.env | grep -v "#" | xargs)

if [ -n "$ssid" ] && [ $ssid == $SSID ]; then
    can_upload=1
fi

upload() {
    tars=$1
    name=$2

    cd $scriptdir

    output=$(python3 get_folder_url.py -f $name 2>/dev/null)
    IFS=',' read -r folder_id folder_url <<< "$output"
    log_name+=($name)
    url+=($folder_url)

    for item in "${tars[@]}"
    do
        echo start uploading $item
        echo folder_id = $folder_id
        python3 upload.py -f $item -s $folder_id  > stdout.log 2> stderr.log
        if [ $? -eq 1 ]; then
            python3 notice_error.py log -e "$(cat stderr.log)" -u "$item"
            url+=("None")
            all_upload=0
        else
            url+=($(cat stdout.log | tail -n 1))
        fi
        
        log_name+=($item)
    done
}

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
            bash $scriptdir/notification.sh $CABOT_NAME"の${log}のアップロードを開始します。"
            for item in "${list[@]}"
            do
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
                upload $tars $item
            done
            if [[ $all_upload -eq 1 && "$line" != *ALL_UPLOAD* ]]; then
                sed -i "s/\(.*$log\)/\1,ALL_UPLOAD/" $scriptdir/issue_list.txt
            fi
            ((notification+=$all_upload))
        fi

        label=()
        if [[ $all_upload -eq 0 ]]; then
            label+=($CABOT_NAME)
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
        
        # if [[ "$line" != *UPLOADED* ]]; then
        #     sed -i "s/\(.*$log\)/\1,UPLOADED/" $scriptdir/issue_list.txt
        # fi

        if [ $notification -eq 2 ]; then
            bash $scriptdir/notification.sh $CABOT_NAME"の${log}のアップロードが終了しました。\nhttps://github.com/${REPO_OWNER}/${REPO_NAME}/issues/${num}"
        elif [ $can_upload -eq 1 ]; then
            bash $scriptdir/notification.sh $CABOT_NAME"の${log}のアップロードに失敗しました。"
            failed=1
        fi
    fi
done < issue_list.txt

if [ $failed -eq 1 ]; then
    bash $scriptdir/notification.sh $CABOT_NAME"の再アップロードをしてください。"
fi

[ -f stdout.log ] && rm stdout.log
[ -f stderr.log ] && rm stderr.log