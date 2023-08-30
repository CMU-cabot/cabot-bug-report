#!/bin/bash

cd /opt/cabot/docker/home/.ros/log

logs=($(ls | grep ^cabot | grep -v .zip | tail -5))

echo ${logs[@]}
