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
    is_report_submitted=$(grep $log $list | wc -l)
    is_uploaded_to_box=$(grep $log $list | grep UPLOADED | wc -l)
    nanoseconds="None"
    if [ -f ./$log/ros2_topics/metadata.yaml ]; then
        nanoseconds=$(cat ./$log/ros2_topics/metadata.yaml | grep -m 1 nanoseconds: | awk '{print $2}')
    fi
    echo "$log,$is_report_submitted,$is_uploaded_to_box,$nanoseconds"
done
