#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`
list=$scriptdir/issue_list.txt

cd /opt/cabot/docker/home/.ros/log/

num=10
if [[ ! -z $1 ]]; then
    num=$1
fi

logs=($(ls -d cabot*/ | tail -$num | sed "s'/''" ))

for log in ${logs[@]}
do
    matched_lines=$(grep "$log" "$list" | grep -v 'SOURCE=webui' || true)
    is_report_submitted=$(echo "$matched_lines" | awk 'NF' | wc -l)
    is_uploaded_to_box=$(echo "$matched_lines" | grep UPLOADED | wc -l)
    nanoseconds=$(bash $scriptdir/get_duration.sh $log)
    echo "$log,$is_report_submitted,$is_uploaded_to_box,$nanoseconds"
done
