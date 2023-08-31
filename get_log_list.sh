#!/bin/bash

cd /opt/cabot/docker/home/.ros/log/

num=10
if [[ ! -z $1 ]]; then
    num=$1
fi

logs=($(ls -d cabot*/ | tail -$num | sed "s'/''" ))

echo ${logs[@]}
