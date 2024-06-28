#!/bin/bash

cabotdir="/opt/cabot"
logdir="$cabotdir/docker/home/.ros/log"

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`
list=$scriptdir/issue_list.txt

if [[ $# -lt 3 ]]; then
    echo "Usage $0 <title> <content> <log>"
    exit
fi
set -e

log=$3

if [[ $(grep $log $list | wc -l) -eq 1 ]]; then
    line=$(grep $log $list)
    title_file_name=`echo $line | cut -d ',' -f 1`
    body_file_name=`echo $line | cut -d ',' -f 2`
    title_path=$scriptdir/content/$title_file_name
    file_path=$scriptdir/content/$body_file_name
    echo -e "$1" > $title_path
    echo -e "$2" > $file_path
else
    date=`date +%Y%m%d%H%M%S`
    title_file_name="title_$date.txt"
    body_file_name="report_$date.txt"
    issue_list="$title_file_name,$body_file_name,$log"

    mkdir -p $scriptdir/content

    echo -e "$1" > $scriptdir/content/$title_file_name
    echo -e "$2" > $scriptdir/content/$body_file_name
    echo $issue_list >> $list
fi

