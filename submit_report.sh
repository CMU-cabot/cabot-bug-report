#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

cabotdir="/opt/cabot"
logdir="$cabotdir/docker/home/.ros/log"

ssid=`iwgetid -r`

export $(cat $scriptdir/.env | grep -v "#" | xargs)

if [ -z "$ssid" ] || [ $ssid != $SSID ]; then
	notify-send "Upload System" "set wifi to $SSID"
	exit
fi

upload() {
    FILE=$1
    cd $scriptdir
        text=`python3 upload.py -f $FILE`
        if [ $? -eq 1 ]; then
            python3 notice_error.py log -e "$text" -u "$FILE"
            url+=($FILE)
            continue
        else
            url+=($text)
        fi
}

upload_split() {
    zips=$1
    name=$2
    cd $scriptdir
    for item in "${zips[@]}"
    do
        text=`python3 upload.py -f $item -s $name`
        if [ $? -eq 1 ]; then
            python3 notice_error.py log -e "$text" -u "$item"
            url+=($item)
        else
            url+=($text)
        fi
    done
}

cat issue_list.txt | grep -v "UPLOADED" | while read line
do
    title_file_name=`echo $line | cut -d ',' -f 1`
    body_file_name=`echo $line | cut -d ',' -f 2`
    log=`echo $line | cut -d ',' -f 3`
    list=($log)
    url=()

    for item in "${list[@]}"
    do
        cd $logdir

        FILE="$item.zip"
        SIZE=`du -d 0 $item | cut -f 1`
        if [ $SIZE -gt 13000000 ]; then
            if [ ! -e $FILE ]; then
                zip -r -s 10G $item.zip $item
            fi
            zips=(`ls | grep $item.`)
            echo ${zips[@]}
            upload_split $zips $item
        else
            if [ ! -e $FILE ]; then
                zip -r $FILE $item
            fi
            upload $FILE
        fi
    done

    mkdir -p $scriptdir/content
    mkdir -p $scriptdir/error

    title_path=$scriptdir/content/$title_file_name
    file_path=$scriptdir/content/$body_file_name
    response=`python3 make_issue.py -t $title_path -f $file_path -u ${url[@]}`

    if [ $? -ne 0 ]; then
        head=`head -n1 $scriptdir/issue_list.txt`
        python3 notice_error.py issue -e "$response" -i "$head"
        echo $head >> $scriptdir/error/issue_list.txt
        cat $title_path > $scriptdir/error/$title_file_name
        cat $file_path > $scriptdir/error/$body_file_name
    fi

    echo $responce
    
    sed -i "s/\(.*$log\)/\1,UPLOADED/" $scriptdir/issue_list.txt
done
