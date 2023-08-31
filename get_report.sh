#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`
list=$scriptdir/issue_list.txt

if [[ -z $1 ]]; then
    exit
fi
log=$1
line=$(grep $log $list)
if [[ -z $line ]]; then
    exit
fi

title_file_name=`echo $line | cut -d ',' -f 1`
body_file_name=`echo $line | cut -d ',' -f 2`
title_path=$scriptdir/content/$title_file_name
file_path=$scriptdir/content/$body_file_name

echo "1"
echo $(echo $line | grep UPLOADED | wc -l)
cat $title_path
cat $file_path
