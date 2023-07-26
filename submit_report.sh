#!/bin/bash

ssid=`iwgetid -r`

if [ $ssid != "M-lab" ]; then
	notify-send "Upload System" "set wifi to M-lab"
	exit
fi

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

cabotdir="/opt/cabot"
logdir="$cabotdir/docker/home/.ros/log"


cat issue_list.txt | while read line
do
    title=`echo $line | cut -d ',' -f 1`
    body_file_name=`echo $line | cut -d ',' -f 2`
    file=`echo $line | cut -d ',' -f 3`
    list=($file)
    url=()

    for item in "${list[@]}"
    do
        cd $logdir

        FILE="$item.zip"
        if [ ! -e $FILE ]; then
            zip -r $FILE $item
        fi

        cd $scriptdir
        text=`python3 upload.py -f $FILE`
        if [ $? -eq 1 ]; then
            notify-send $FILE "$text"
            continue
        else
            url+=($text)
        fi
    done

    if [ ${#url[*]} -eq 0 ]; then
        break
    fi

    file_path=$scriptdir/content/$body_file_name
    python3 make_issue.py -t $title -f $file_path -u ${url[@]}

    if [ $? -eq 0 ]; then
        rm $file_path
        sed -i '1d' $scriptdir/issue_list.txt
    fi
done
