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
fi
echo -n $nanoseconds
