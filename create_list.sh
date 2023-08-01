#!/bin/bash

cabotdir="/opt/cabot"
logdir="$cabotdir/docker/home/.ros/log"

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`
list=$scriptdir/issue_list.txt

set -e

log=$3

date=`date +%Y%m%d%H%M%S`
title_file_name="title_$date.txt"
body_file_name="report_$date.txt"
issue_list="$title_file_name,$body_file_name,$log"

echo -e "$1" > $scriptdir/content/$title_file_name
echo -e "$2" > $scriptdir/content/$body_file_name
echo $issue_list >> $list