#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

cd /opt/cabot/docker/home/.ros/log/

if [[ ! -z $1 ]]; then
    log=$1
fi

logs=($(ls -d cabot*/ | tail -$num | sed "s'/''" ))

nanoseconds=0
if [ -f ./$log/ros2_topics/metadata.yaml ]; then
    nanoseconds=$(cat ./$log/ros2_topics/metadata.yaml | grep -m 1 nanoseconds: | awk '{print $2}')
else
    read date time < <(echo $log | sed -E 's/cabot_([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2}-[0-9]{2}-[0-9]{2})/\1 \2/')
    timestamp=$(date -d "$date ${time//-/:}" "+%s")
    if [ -n "$time" ]; then
        log_list=($(ls -d cabot*/ | sed "s'/''" | grep cabot_$date))
        dummy_log=$(date -d "$date +1 day" '+cabot_%Y-%m-%d-00-00-00')
        log_list+=($dummy_log)
        for same_date_log in ${log_list[@]}
        do
            read ref_date ref_time < <(echo $same_date_log | sed -E 's/cabot_([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2}-[0-9]{2}-[0-9]{2})/\1 \2/')
            ref_timestamp=$(date -d "$ref_date ${ref_time//-/:}" "+%s")
            current_timestamp=$(date "+%s")
            if [ "$current_timestamp" -lt "$ref_timestamp" ]; then
                ref_timestamp=$current_timestamp
            fi

            if (( timestamp < ref_timestamp )); then
                nanoseconds=$((($ref_timestamp - $timestamp)*1000000000))
                break
            fi
        done
    fi
fi
echo -n $nanoseconds
