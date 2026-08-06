#!/bin/bash

terminating=0

cleanup() {
    echo "Caught signal, cleaning up..."
    terminating=1
    sleep 1
    rm ${tars[@]}
    exit 1
}
trap cleanup SIGINT SIGTERM SIGHUP

rsync_error_msg() {
  case "$1" in
    1)  echo "一般エラー" ;;
    2)  echo "プロトコル不一致" ;;
    11) echo "ファイルI/Oエラー: ディレクトリ作成失敗など" ;;
    12) echo "ディレクトリ読み込み失敗" ;;
    23) echo "部分的転送: 権限問題やファイル欠落など" ;;
    24) echo "ソース消失" ;;
    30) echo "I/Oタイムアウト" ;;
    35) echo "接続切断" ;;
    *)  echo "不明($1)" ;;
  esac
}

create_ros2_topics_archives() {
    local item="$1"
    local archive_mode="$2"
    local source_bag_dir="$logdir/$item/ros2_topics"
    local host_logdir="${HOST_LOGDIR:-/opt/cabot/docker/home/.ros/log}"
    local host_user="${CABOT_HOST_USER:-${USER:-cabot}}"
    local ssh_id_file="${CABOT_SSH_ID_FILE:-/home/developer/.ssh/ssh_key_cabot}"
    local host_fix_bag_script="${HOST_FIX_BAG_SCRIPT:-/opt/cabot/tools/fix_bag.sh}"
    local needs_filter=0

    if python3 - "$source_bag_dir" <<'PY'
from pathlib import Path
import sqlite3
import sys

bag_dir = Path(sys.argv[1])
for db_path in sorted(bag_dir.glob("*.db3")):
    conn = sqlite3.connect(str(db_path))
    try:
        row = conn.execute(
            "SELECT 1 FROM topics WHERE name LIKE '%image_raw/compressed%' LIMIT 1"
        ).fetchone()
    finally:
        conn.close()
    if row is not None:
        raise SystemExit(0)
raise SystemExit(1)
PY
    then
        needs_filter=1
    fi

    if [[ $needs_filter -eq 0 ]]; then
        if [[ "$archive_mode" == "split" ]]; then
            PARTS=(${item}_ros2_topics_part_*)
            if [ ! -e "${PARTS[0]}" ]; then
                tar -cvf - "$item/ros2_topics" | split -b 10G - "${item}_ros2_topics_part_"
            fi
            ls | grep "${item}_ros2_topics_part_"
        else
            FILE2="${item}_ros2_topics.tar"
            if [ ! -e "$FILE2" ]; then
                tar -cvf "$FILE2" "$item/ros2_topics" 1>&2
            fi
            echo "$FILE2"
        fi
        return
    fi

    if [[ ! -f "$ssh_id_file" ]]; then
        echo "ssh identity file was not found: $ssh_id_file" >&2
        return 1
    fi

    local stage_root
    stage_root=$(mktemp -d "$logdir/.upload_ros2_topics_${item}.XXXXXX")
    local stage_rel=${stage_root#"$logdir"/}
    local host_stage_bag_dir="$host_logdir/$stage_rel/$item/ros2_topics"

    mkdir -p "$stage_root/$item" || {
        rm -rf "$stage_root"
        return 1
    }
    cp -a "$source_bag_dir" "$stage_root/$item/" || {
        rm -rf "$stage_root"
        return 1
    }

    if ! python3 - "$stage_root/$item/ros2_topics" <<'PY'
from pathlib import Path
import sqlite3
import sys

bag_dir = Path(sys.argv[1])
db_paths = sorted(bag_dir.glob("*.db3"))
if not db_paths:
    raise SystemExit(f"no db3 files were found in {bag_dir}")

for db_path in db_paths:
    conn = sqlite3.connect(str(db_path))
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute(
            """
DELETE FROM messages
  WHERE topic_id IN (
    SELECT id FROM topics WHERE name LIKE '%image_raw/compressed%'
  )
"""
        )
        conn.execute("DELETE FROM topics WHERE name LIKE '%image_raw/compressed%'")
        conn.commit()
        conn.execute("VACUUM")
    finally:
        conn.close()
PY
    then
        rm -rf "$stage_root"
        return 1
    fi

    rm -f "$stage_root/$item/ros2_topics/metadata.yaml" || {
        rm -rf "$stage_root"
        return 1
    }
    printf -v remote_command 'bash %q -f %q' "$host_fix_bag_script" "$host_stage_bag_dir"
    if ! ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$ssh_id_file" \
        "$host_user@localhost" \
        "$remote_command" 1>&2; then
        rm -rf "$stage_root"
        return 1
    fi

    rm -f "${item}_ros2_topics.tar"
    rm -f "${item}"_ros2_topics_part_*

    if [[ "$archive_mode" == "split" ]]; then
        tar -C "$stage_root" -cvf - "$item/ros2_topics" | split -b 10G - "${item}_ros2_topics_part_" || {
            rm -rf "$stage_root"
            return 1
        }
        rm -rf "$stage_root"
        ls | grep "${item}_ros2_topics_part_"
    else
        FILE2="${item}_ros2_topics.tar"
        tar -C "$stage_root" -cvf "$FILE2" "$item/ros2_topics" 1>&2 || {
            rm -rf "$stage_root"
            return 1
        }
        rm -rf "$stage_root"
        echo "$FILE2"
    fi
}

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`
logdir=/log

source $scriptdir/.env

# Parse options
while getopts "d:h" opt; do
    case $opt in
        d) date=$OPTARG ;;
        h) 
            echo "Usage: $0 [-d date] [-h]"
            echo "  -d date   Specify the date in YYYY-MM-DD format (default: today's date)"
            echo "  -h        Show this help message"
            exit 0
            ;;
        *) 
            echo "Invalid option. Use -h for help."
            exit 1
            ;;
    esac
done


sudo mkdir -p /mnt/smbshare

success=0
IFS=',' read -ra items <<< "$NAS_IPS"
for item in "${items[@]}"; do
    echo "trying to mount $item"
    if sudo mount -t cifs -o username=$NAS_USER,password=$NAS_PASSWORD,uid=$HOST_UID,gid=$HOST_GID,cache=none,file_mode=0664,dir_mode=0755 //$item/$NAS_SHARE_DIR /mnt/smbshare; then
	bash $scriptdir/notification.sh "sudo mount $item"
	success=1
	break
    fi
done
if [[ $success -eq 0 ]]; then
    bash $scriptdir/notification.sh "mount failure"
fi

# Default to today's date if not specified
if [ -z "$date" ]; then
    date=$(date "+%Y-%m-%d")
fi

bash $scriptdir/notification.sh "start upload ${item} from ${CABOT_NAME} to NAS"

mkdir -p $logdir/tmp
sudo mkdir -p /mnt/smbshare/$CABOT_NAME/

# only make issue
WIFI_SSID="dummy" $scriptdir/submit_report.sh

items=($(ls $logdir | grep "cabot_${date}" | grep -v .tar | grep -v _part_))
for item in ${items[@]}
do
    echo $item
    cd $logdir
    $scriptdir/submit_report.sh -c $item
    SIZE=`du -d 0 $item | cut -f 1`

    FILE1="${item}_log.tar"
    if [ ! -e $FILE1 ]; then
        tar --exclude="ros2_topics" --exclude="image_topics" -cvf $FILE1 $item
    fi
    tars=($FILE1)
    ros2_tars=()
    if [ $SIZE -gt 13000000 ]; then
        archive_mode=split
    else
        archive_mode=single
    fi
    helper_stderr=$(mktemp)
    if ! ros2_tar_output=$(create_ros2_topics_archives "$item" "$archive_mode" 2> "$helper_stderr"); then
        echo "failed to create filtered ros2_topics archive for $item"
        cat "$helper_stderr"
        rm -f "$helper_stderr"
        continue
    fi
    rm -f "$helper_stderr"
    ros2_tars=($ros2_tar_output)
    tars+=("${ros2_tars[@]}")
    echo ${tars[@]}
    echo rsync start
    bash $scriptdir/notification.sh "uploading ${tars[*]}"
    rsync -av --size-only "${tars[@]}" /mnt/smbshare/$CABOT_NAME/log/ 
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "rsync error: $item → $(rsync_error_msg "$status")"
	continue
    fi
    if [[ $terminating -eq 1 ]]; then
        break
    fi
    rm ${tars[@]}
    mv $item $logdir/tmp/
done

rsync -av $scriptdir/content /mnt/smbshare/$CABOT_NAME/
rsync -av $scriptdir/issue_list.txt /mnt/smbshare/$CABOT_NAME/

bash $scriptdir/notification.sh "finish upload from ${CABOT_NAME} to NAS"
