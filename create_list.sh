#!/bin/bash

cabotdir="/opt/cabot"
logdir="$cabotdir/docker/home/.ros/log"

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`
list=$scriptdir/issue_list.txt

set -e

title=$1
file=$3

date=`date +%Y%m%d%H%M`
body_file_name="report_$date.txt"
issue_list="$title,$body_file_name,$file"

echo -e "$2" > $scriptdir/content/$body_file_name
echo $issue_list >> $list