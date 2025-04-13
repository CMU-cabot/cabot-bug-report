#!/bin/bash

if [ $(id -u) -eq 0 ]; then
   echo "please do not run as root: $0"
   exit
fi

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

SKIP_INSTALL=false
while getopts "s" opt; do
  case $opt in
    s)
      SKIP_INSTALL=true
      ;;
    *)
      ;;
  esac
done

## install report-submitter
sudo rm -rf /opt/report-submitter
sudo ln -sf $scriptdir /opt/report-submitter
docker compose build --build-arg UID=$(id -u)

if [ "$SKIP_INSTALL" = false ]; then
  ## install submit_report.service and submit_report.timer
  INSTALL_DIR=$HOME/.config/systemd/user
  mkdir -p $INSTALL_DIR
  cp $scriptdir/submit_report.service $INSTALL_DIR
  cp $scriptdir/submit_report.timer $INSTALL_DIR
  systemctl --user daemon-reload
  systemctl --user enable submit_report.service
  systemctl --user enable submit_report.timer
fi

