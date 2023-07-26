#!/bin/bash

if [ $(id -u) -eq 0 ]; then
   echo "please do not run as root: $0"
   exit
fi

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

## uninstall submit_report.service
systemctl --user disable --now submit_report.service
systemctl --user disable --now submit_report.timer
INSTALL_DIR=$HOME/.config/systemd/user
rm $INSTALL_DIR/submit_report.service
rm $INSTALL_DIR/submit_report.timer

## uninstall cabot-ble-server
sudo rm /opt/report-submitter
