#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

cabotdir="/opt/cabot"
logdir="$cabotdir/docker/home/.ros/log"

ssid=`iwgetid -r`

export $(cat $scriptdir/.env | grep -v "#" | xargs)

# if [ -z "$ssid" ] || [ $ssid != $SSID ]; then
# 	notify-send "Upload System" "set wifi to $SSID"
# 	exit
# fi

upload() {
    FILE=$1
    log_name+=($FILE)
    cd $scriptdir
        echo start uploading $FILE
        python3 upload.py -f $FILE > stdout.log 2> stderr.log
        if [ $? -eq 1 ]; then
            python3 notice_error.py log -e "$(cat stderr.log)" -u "$FILE"
            url+=("None")
            all_upload=0
        else
            url+=($(cat stdout.log | tail -n 1))
        fi
}

upload_split() {
    zips=$1
    name=$2

    cd $scriptdir

    output=$(python3 get_folder_url.py -f $name 2>/dev/null)
    IFS=',' read -r folder_id folder_url <<< "$output"
    log_name+=($name)
    url+=($folder_url)

    for item in "${zips[@]}"
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

cat issue_list.txt | while read line
do
    title_file_name=`echo $line | cut -d ',' -f 1`
    body_file_name=`echo $line | cut -d ',' -f 2`
    log=`echo $line | cut -d ',' -f 3`
    if [[ -n $log && ("$line" != *ALL_UPLOAD* || "$line" != *REPORTED*) ]]; then
        list=($log)
        url=()
        log_name=()
        all_upload=1

        if [[ "$line" =~ REPORTED=([0-9]+) ]]; then
            num=${BASH_REMATCH[1]}
            result=`python3 make_issue.py -c -i $num`

            if [ "$result" = "closed" ]; then
                continue
            fi
        fi

        if [ -n "$ssid" ] && [ $ssid == $SSID ]; then
            for item in "${list[@]}"
            do
                cd $logdir
                SIZE=`du -d 0 $item | cut -f 1`
                if [ $SIZE -gt 13000000 ]; then
                    FILE=(${item}_part_*)
                    if [ ! -e "${FILE[0]}" ]; then
                        tar -cvf - $item | split -b 10G - ${item}_part_
                    fi
                    zips=(`ls | grep ${item}_part_`)
                    echo ${zips[@]}
                    upload_split $zips $item
                else
                    FILE="$item.tar"
                    if [ ! -e $FILE ]; then
                        tar -cvf $FILE $item
                    fi
                    upload $FILE
                fi
            done
            if [[ $all_upload -eq 1 && "$line" != *ALL_UPLOAD* ]]; then
                sed -i "s/\(.*$log\)/\1,ALL_UPLOAD/" $scriptdir/issue_list.txt
            fi
        fi

        mkdir -p $scriptdir/content
        mkdir -p $scriptdir/error

        title_path=$scriptdir/content/$title_file_name
        file_path=$scriptdir/content/$body_file_name
        if [ `awk 'NF' $title_path` ]; then
            if [[ "$line" =~ REPORTED=([0-9]+) ]]; then
                num=${BASH_REMATCH[1]}
                python3 make_issue.py -t $title_path -f $file_path -u ${url[@]} -l ${log_name[@]} -i $num > stdout.log 2> stderr.log

                if [ $? -ne 0 ]; then
                    response=$(cat stderr.log)
                    python3 notice_error.py issue -e "$response" -i "update log link #$num"
                else
                    response=$(cat stdout.log)
                fi
            else
                python3 make_issue.py -t $title_path -f $file_path -u ${url[@]} -l ${log_name[@]} > stdout.log 2> stderr.log

                if [ $? -ne 0 ]; then
                    response=$(cat stderr.log)
                    python3 notice_error.py issue -e "$response" -i "$line"
                else
                    response=$(cat stdout.log)
                    issue_num=$(cat stdout.log | tail -n 1)
                    sed -i "s/\(.*$log\)/\1,REPORTED=$issue_num/" $scriptdir/issue_list.txt
                fi
            fi
        fi

        echo $response
        
        # if [[ "$line" != *UPLOADED* ]]; then
        #     sed -i "s/\(.*$log\)/\1,UPLOADED/" $scriptdir/issue_list.txt
        # fi
    fi
done

[ -f stdout.log ] && rm stdout.log
[ -f stderr.log ] && rm stderr.log