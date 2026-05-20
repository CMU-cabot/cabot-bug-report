#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`
list=$scriptdir/issue_list.txt

if [[ $# -lt 4 ]]; then
    echo "Usage $0 <title> <content> <log> <report_id> [submit]"
    exit 1
fi
set -e

title=$1
detail=$2
log=$3
report_id=$4

if [[ ! "$report_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "invalid report_id" >&2
    exit 1
fi

mkdir -p "$scriptdir/content"
touch "$list"

title_file_name="webui_title_${report_id}.txt"
body_file_name="webui_report_${report_id}.txt"
issue_list="$title_file_name,$body_file_name,$log,SOURCE=webui,REPORT_ID=$report_id"
existing_line=$(awk -F',' -v report_id="$report_id" 'index($0, "REPORT_ID=" report_id) > 0 { print; exit }' "$list")

if [[ "$existing_line" == *ALL_UPLOAD* || "$existing_line" == *UPLOADED* ]]; then
    exit 0
fi

existing_tags=$(awk -F',' -v report_id="$report_id" '
    index($0, "REPORT_ID=" report_id) > 0 {
        for (i = 6; i <= NF; i++) {
            print $i
        }
        exit
    }
' "$list")

while IFS= read -r tag; do
    if [[ -n "$tag" ]]; then
        issue_list="$issue_list,$tag"
    fi
done <<< "$existing_tags"

echo -e "$title" > "$scriptdir/content/$title_file_name"
echo -e "$detail" > "$scriptdir/content/$body_file_name"

tmp_file=$(mktemp)
awk -F',' -v report_id="$report_id" -v issue_list="$issue_list" '
    index($0, "REPORT_ID=" report_id) == 0 {
        print
    }
    END {
        print issue_list
    }
' "$list" > "$tmp_file"
cp "$tmp_file" "$list"
rm "$tmp_file"
