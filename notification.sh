#!/bin/bash

scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

source $scriptdir/.env

text=$1

echo $text

if [ -z $SLACK_TOKEN ]; then
    exit
fi

SLACK_WEBHOOK_URL=$SLACK_TOKEN

now=$(date +"%Y-%m-%d %H:%M")

SLACK_MESSAGE=$(cat <<EOF
{
    "text": "$now  $text",
    "username": "通知ボット",
    "icon_emoji": ":robot_face:"
}
EOF
)

# Slackに通知を送信
curl -X POST -H 'Content-type: application/json' --data "${SLACK_MESSAGE}" "${SLACK_WEBHOOK_URL}"

