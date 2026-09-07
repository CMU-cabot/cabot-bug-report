#!/bin/bash

pwd=`pwd`
scriptdir=`dirname $0`
cd $scriptdir
scriptdir=`pwd`

source $scriptdir/.env

logdir=/log
rundir=$scriptdir
ssid=`iwgetid -r`
can_upload=0
WIFI_METRIC=50
used_wifi_connection=0
upload_folder_id=""

log_skip_upload() {
    local target_log="$1"
    local reason="$2"

    if [ -n "$target_log" ]; then
        echo "skip upload for ${target_log}: ${reason}"
    else
        echo "skip upload: ${reason}"
    fi
}

required_upload_network() {
    local wifi_label=""
    local wired_label=""

    if [ -n "$WIFI_SSID" ]; then
        wifi_label="connect \"$WIFI_SSID\""
    fi

    if [ -n "$WIRED_DEV" ] && [ -n "$WIRED_GATEWAY" ]; then
        wired_label="connect wired \"$WIRED_DEV via $WIRED_GATEWAY\""
    fi

    if [ -n "$wifi_label" ] && [ -n "$wired_label" ]; then
        echo "$wifi_label or $wired_label"
    elif [ -n "$wifi_label" ]; then
        echo "$wifi_label"
    elif [ -n "$wired_label" ]; then
        echo "$wired_label"
    else
        echo "connect the configured upload network"
    fi
}

wifi_connected=0
if [ -n "$ssid" ] && [ -n "$WIFI_SSID" ] && [ "$ssid" = "$WIFI_SSID" ]; then
    wifi_connected=1
fi

wired_connected=0
if [ -n "$WIRED_DEV" ] && [ -n "$WIRED_GATEWAY" ]; then
    if ip -4 route show default | grep -F "default via $WIRED_GATEWAY dev $WIRED_DEV" >/dev/null 2>&1; then
        wired_connected=1
    fi
fi

COUNT_FILE="$scriptdir/timer_count"
if [ ! -f "$COUNT_FILE" ]; then
    echo 0 > $COUNT_FILE
fi

timer_count=$(cat "$COUNT_FILE")
((timer_count+=1))

if [ $wifi_connected -eq 1 ]; then
    if [ -n "$WIFI_DROUTE" ]; then
        sudo nmcli con modify "$WIFI_SSID" ipv4.routes "0.0.0.0/0 $WIFI_DROUTE $WIFI_METRIC"
        sudo nmcli con down "$WIFI_SSID" && sudo nmcli con up "$WIFI_SSID"
        sleep 10
    fi
    used_wifi_connection=1
    can_upload=1
elif [ $wired_connected -eq 1 ]; then
    can_upload=1
else
    timer_status=$(systemctl --user is-active submit_report.timer)
    if [ "active" == "$timer_status" ]; then
        if [ -z "$ssid" ]; then
            bash $scriptdir/notification.sh "timer起動"$timer_count"回目"
            echo $timer_count > $COUNT_FILE
            if [ "$timer_count" -gt 3 ]; then
                systemctl --user stop submit_report.timer
                rm $COUNT_FILE
            fi
            exit
        else
            bash $scriptdir/notification.sh $CABOT_NAME" M-lab以外接続時にtimerが終了するか確認通知"
            systemctl --user stop submit_report.timer
            rm $COUNT_FILE
        fi
    fi
    log_skip_upload "" "no upload network available; $(required_upload_network)"
fi

tar_skip=0
dev=0

show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -u <item>   Upload the specified item."
    echo "  -t          Skip tar creation and use existing tar files."
    echo "  -h          Show this help message."
}

issue_list_append_tag() {
    local source_type="$1"
    local report_id="$2"
    local target_log="$3"
    local tag="$4"
    local tmp_file=$(mktemp)

    awk -F',' -v source_type="$source_type" -v report_id="$report_id" -v target_log="$target_log" -v tag="$tag" '
        function is_webui(line) {
            return index(line, "SOURCE=webui") > 0
        }
        function matches(line) {
            split(line, fields, ",")
            if (source_type == "webui") {
                return report_id != "" && index(line, "REPORT_ID=" report_id) > 0
            }
            return fields[3] == target_log && !is_webui(line)
        }
        function tag_key(value) {
            return index(value, "=") > 0 ? substr(value, 1, index(value, "=")) : value
        }
        {
            if (matches($0)) {
                count = split($0, fields, ",")
                prefix = tag_key(tag)
                line = fields[1]
                for (i = 2; i <= count; i++) {
                    if (prefix != tag) {
                        if (index(fields[i], prefix) == 1) {
                            continue
                        }
                    } else if (fields[i] == tag) {
                        continue
                    }
                    line = line "," fields[i]
                }
                $0 = line "," tag
            }
            print
        }
    ' "$rundir/issue_list.txt" > "$tmp_file" \
        && cp "$tmp_file" "$rundir/issue_list.txt" \
        && rm "$tmp_file"
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
    if ! ssh -n \
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

upload() {
    local item=$1
    # initialize
    log_name=()
    url=()
    upload_folder_id=""

    cd $logdir
    SIZE=`du -d 0 $item | cut -f 1`

    if [ $tar_skip -eq 1 ]; then
        tars=($(ls | grep ${item}_))
    else
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
            python3 "$scriptdir/notice_error.py" log --error-file "$helper_stderr" -u "${item}/ros2_topics"
            rm -f "$helper_stderr"
            all_upload=0
            cd "$scriptdir"
            return
        fi
        rm -f "$helper_stderr"
        ros2_tars=($ros2_tar_output)
        tars+=("${ros2_tars[@]}")
    fi
    echo ${tars[@]}

    cd $scriptdir

    local cmd=(python3 get_folder_url.py -f "$item")
    if [ $dev -eq 1 ]; then
        cmd+=(-d "$CABOT_NAME")
    fi
    output=$("${cmd[@]}" 2>/dev/null)
    IFS=',' read -r folder_id folder_url <<< "$output"
    log_name+=("$item")
    if [[ -n "$folder_id" && -n "$folder_url" ]]; then
        upload_folder_id="$folder_id"
        url+=("$folder_url")
    else
        url+=("None")
        all_upload=0
    fi

    for upload_item in "${tars[@]}"
    do
        echo start uploading $upload_item
        bash $scriptdir/notification.sh "start uploading ${upload_item}"
        echo folder_id = $folder_id
        python3 upload.py -f "$upload_item" -s "$folder_id" -p "$logdir" > stdout.log 2> stderr.log
        if [ $? -ne 0 ]; then
            python3 notice_error.py log -e "$(cat stderr.log)" -u "$upload_item"
            url+=("None")
            all_upload=0
        else
            url+=("$(tail -n 1 stdout.log)")
        fi
        
        log_name+=("$upload_item")
    done
}

upload_attachments() {
    local item=$1
    local attachment_dir="$logdir/$item/mobile_attachments"
    local manifest_path="$attachment_dir/manifest.json"
    local folder_id="$upload_folder_id"

    if [ ! -f "$manifest_path" ]; then
        return
    fi

    if [ -z "$folder_id" ]; then
        local cmd=(python3 get_folder_url.py -f "$item")
        if [ $dev -eq 1 ]; then
            cmd+=(-d "$CABOT_NAME")
        fi
        output=$("${cmd[@]}" 2>/dev/null)
        IFS=',' read -r folder_id folder_url <<< "$output"
    fi

    while IFS=$'\t' read -r file_name original_name
    do
        if [ -z "$file_name" ]; then
            continue
        fi

        echo start uploading $file_name
        bash $scriptdir/notification.sh "start uploading ${file_name}"
        python3 upload.py --image -f "$file_name" -s "$folder_id" -p "$attachment_dir" > stdout.log 2> stderr.log
        if [ $? -ne 0 ]; then
            python3 notice_error.py log -e "$(cat stderr.log)" -u "$file_name"
            url+=("None")
            all_upload=0
        else
            file_id=$(tail -n 1 stdout.log)
            url+=("https://app.box.com/file/$file_id")
        fi

        log_name+=("$original_name")
    done < <(
        python3 - "$manifest_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r") as manifest_file:
    manifest = json.load(manifest_file)

attachments = sorted(
    manifest.get("attachments", []),
    key=lambda attachment: (int(attachment.get("order", 0)), attachment.get("file_name", ""))
)

for attachment in attachments:
    file_name = str(attachment.get("file_name", "")).strip()
    original_name = str(attachment.get("original_name", file_name))
    if file_name:
        print(f"{file_name}\t{original_name}")
PY
    )
}

upload_webui_attachments() {
    local item=$1
    local report_id=$2
    local attachment_dir="$logdir/$item/webui_reports/$report_id"
    local manifest_path="$attachment_dir/manifest.json"
    local folder_id="$upload_folder_id"

    if [ ! -f "$manifest_path" ]; then
        return
    fi

    if [ -z "$folder_id" ]; then
        local cmd=(python3 get_folder_url.py -f "$item")
        if [ $dev -eq 1 ]; then
            cmd+=(-d "$CABOT_NAME")
        fi
        output=$("${cmd[@]}" 2>/dev/null)
        IFS=',' read -r folder_id folder_url <<< "$output"
    fi

    while IFS=$'\t' read -r file_name original_name
    do
        if [ -z "$file_name" ]; then
            continue
        fi

        echo start uploading $file_name
        bash $scriptdir/notification.sh "start uploading ${file_name}"
        python3 upload.py --image -f "$file_name" -s "$folder_id" -p "$attachment_dir" > stdout.log 2> stderr.log
        if [ $? -ne 0 ]; then
            python3 notice_error.py log -e "$(cat stderr.log)" -u "$file_name"
            url+=("None")
            all_upload=0
        else
            file_id=$(tail -n 1 stdout.log)
            url+=("https://app.box.com/file/$file_id")
        fi

        log_name+=("$original_name")
    done < <(
        python3 - "$manifest_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r") as manifest_file:
    manifest = json.load(manifest_file)

attachments = sorted(
    manifest.get("attachments", []),
    key=lambda attachment: (int(attachment.get("order", 0)), attachment.get("file_name", ""))
)

for attachment in attachments:
    file_name = str(attachment.get("file_name", "")).strip()
    original_name = str(attachment.get("original_name", file_name))
    if file_name:
        print(f"{file_name}\t{original_name}")
PY
    )
}

cp_log() {
    local log=$1
    read date time < <(echo $log | sed -E 's/cabot_([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2}-[0-9]{2}-[0-9]{2})/\1 \2/')

    timestamp=$(date -d "${time//-/:}" "+%s")

    cd $logdir
    if [ ! -d "./$log" ]; then
        return 0
    fi

    nanosecond=$(bash $scriptdir/get_duration.sh $log)
    duration=$((nanosecond / (10**9)))

    server_log_list=($(ls | grep ^$date))
    select=()
    for server_log in ${server_log_list[@]}
    do
        i_time=$(echo $server_log | sed -E 's/.*[0-9]{4}-[0-9]{2}-[0-9]{2}-([0-9]{2}-[0-9]{2}-[0-9]{2}).*/\1/')
        i_timestamp=$(date -d "${i_time//-/:}" "+%s")
        if (( timestamp + duration < i_timestamp )); then
            break
        fi
        select+=($server_log)
    done

    candump_dir=/opt/cabot_candump
    candump_list=($(ls $candump_dir | grep $date))
    tmp_select=""
    for candump in ${candump_list[@]}
    do
        i_time=$(echo $candump | sed -E 's/candump-[0-9]{4}-[0-9]{2}-[0-9]{2}_([0-9]{6}).*/\1/')
        i_timestamp=$(date -d "${i_time:0:2}:${i_time:2:2}:${i_time:4:2}" "+%s")
        if (( timestamp + duration < i_timestamp )); then
            break
        fi

        if (( timestamp > i_timestamp )); then
            tmp_select="${candump_dir}/${candump}"
            continue
        fi

        select+=($tmp_select)
        tmp_select="${candump_dir}/${candump}"
    done
    select+=($tmp_select)

    plugin_dir=/opt/cabot/log
    plugin_list=($(ls $plugin_dir | grep $date | sort))
    tmp_select=""
    for plugin in ${plugin_list[@]}
    do
        i_time=$(echo $plugin | sed -E 's/cabot_plugins_[0-9]{4}-[0-9]{2}-[0-9]{2}-([0-9]{2}-[0-9]{2}-[0-9]{2})/\1/')
        i_timestamp=$(date -d "${i_time//-/:}" "+%s")
        if (( timestamp + duration < i_timestamp )); then
            break
        fi

        if (( timestamp > i_timestamp )); then
            tmp_select="${plugin_dir}/${plugin}"
            continue
        fi

        select+=($tmp_select)
        tmp_select="${plugin_dir}/${plugin}"
    done
    select+=($tmp_select)

    for select_item in ${select[@]}
    do
        cp -r $select_item $logdir/$log
    done
}

while getopts "c:u:dth" opt; do
    case $opt in
      c)
        cp_log $OPTARG
        exit
        ;;
      u)
        upload $OPTARG
        if [ -n "$WIFI_DROUTE" ] && [ $used_wifi_connection -eq 1 ]; then
            sudo nmcli con modify "$WIFI_SSID" ipv4.routes ""
            sudo nmcli con down "$WIFI_SSID" && nmcli con up "$WIFI_SSID"
        fi
        exit
        ;;
      d)
        dev=1
        ;;
      t)
        tar_skip=1
        ;;
      h)
        show_help
        exit
        ;;
      *)
        show_help
        exit 1
        ;;
    esac
done
shift $((OPTIND-1))

failed=0
today=$(TZ=Asia/Tokyo date -d "$(TZ=Asia/Tokyo date +%F)" +%s)
retention_period=$((14*24*60*60))  #two weeks
cp $rundir/issue_list.txt while.txt
while read line
do
    echo $line
    title_file_name=`echo $line | cut -d ',' -f 1`
    body_file_name=`echo $line | cut -d ',' -f 2`
    log=`echo $line | cut -d ',' -f 3`
    source_type="app"
    report_id=""
    if [[ "$line" =~ SOURCE=([^,]+) ]]; then
        source_type=${BASH_REMATCH[1]}
    fi
    if [[ "$line" =~ REPORT_ID=([^,]+) ]]; then
        report_id=${BASH_REMATCH[1]}
    fi
    if [[ "$source_type" == "webui" && -z "$report_id" ]]; then
        log_skip_upload "$log" "invalid webui issue line: missing REPORT_ID"
        continue
    fi
    if [[ "$line" =~ cabot_([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        target_date=${BASH_REMATCH[1]}
        target_time=$(TZ=Asia/Tokyo date -d "$target_date 00:00:00" +%s)
        if (( today - target_time > retention_period )); then
            log_skip_upload "$log" "issue entry expired by retention policy; removing from issue_list"
            sed "\|^$line\$|d" $rundir/issue_list.txt > tmp_file \
                && cp tmp_file $rundir/issue_list.txt \
                && rm tmp_file
            continue
        fi
    fi
    if [[ -n $log && ("$line" != *ALL_UPLOAD* || "$line" != *REPORTED*) ]]; then
        list=($log)
        url=()
        log_name=()
        all_upload=0

        mkdir -p $rundir/content
        mkdir -p $rundir/error

        title_path=$rundir/content/$title_file_name
        file_path=$rundir/content/$body_file_name
        notification=0

        label=()
        label+=($CABOT_NAME)
        target="未アップロード"
        issue_num=""
        report_key=""
        report_key_was_present=0

        if [[ "$line" =~ REPORT_KEY=([^,]+) ]]; then
            report_key=${BASH_REMATCH[1]}
            report_key_was_present=1
        elif [[ "$line" != *REPORTED=* ]]; then
            report_key=$(python3 -c 'import uuid; print(uuid.uuid4())')
            issue_list_append_tag "$source_type" "$report_id" "$log" "REPORT_KEY=$report_key"
        fi

        if [[ "$line" =~ REPORTED=([0-9]+) ]]; then
            issue_num=${BASH_REMATCH[1]}
        elif [[ $report_key_was_present -eq 1 ]]; then
            recovered_issue_num=$(python3 make_issue.py --search_report_key "$report_key")
            search_status=$?
            if [[ $search_status -eq 0 && "$recovered_issue_num" =~ ^[0-9]+$ ]]; then
                issue_num=$recovered_issue_num
                issue_list_append_tag "$source_type" "$report_id" "$log" "REPORTED=$issue_num"
            elif [[ $search_status -ne 2 ]]; then
                log_skip_upload "$log" "failed to search GitHub issue for REPORT_KEY=$report_key"
                continue
            fi
        fi

        if [[ -n "$issue_num" ]]; then
            read -r state labels_csv log_name_csv url_csv < <(python3 make_issue.py -c -i "$issue_num")
            IFS=',' read -r -a labels <<< "$labels_csv"
            IFS=',' read -r -a log_names <<< "$log_name_csv"
            IFS=',' read -r -a urls <<< "$url_csv"
            echo "state = $state"
            echo "labels = ${labels[*]}"
            echo "log_names = ${log_names[*]}"
            echo "urls = ${urls[*]}"
            label+=("${labels[@]}")
            log_name+=("${log_names[@]}")
            url+=("${urls[@]}")

            all_upload=1
            for l_item in "${label[@]}"; do
                if [[ "$l_item" == "$target" ]]; then
                    all_upload=0
                    break
                fi
            done

            if [ "$state" = "closed" ]; then
                log_skip_upload "$log" "issue #$issue_num is already closed"
                continue
            fi
        fi

        if ! grep -q '[^[:space:]]' "$title_path"; then
            log_skip_upload "$log" "title file is empty: $title_path"
            continue
        fi

        if [ $can_upload -eq 1 ]; then
            all_upload=1
            for item in "${list[@]}"
            do
                bash $scriptdir/notification.sh $CABOT_NAME"の${item}のアップロードを開始します。"
                cp_log $item
                upload $item
                if [[ "$source_type" == "webui" ]]; then
                    upload_webui_attachments "$item" "$report_id"
                else
                    upload_attachments "$item"
                fi
            done
            ((notification+=$all_upload))
        else
            log_skip_upload "$log" "upload is disabled because no allowed network route is active"
        fi

        if [[ $all_upload -eq 0 ]]; then
            label+=($target)
        else
            tmp=()
            for e in "${label[@]}"; do
                [[ $e == "$target" ]] || tmp+=("$e")
            done
            label=("${tmp[@]}")
        fi

        if [[ "$line" =~ CABOT_LAUNCH_IMAGE_TAG=([^,]+) ]]; then
            label+=(${BASH_REMATCH[1]})
        else
            cabot_launch_image_tag=$(grep '^CABOT_LAUNCH_IMAGE_TAG=' $logdir/$log/env-file | awk -F= '{print $2}')
            label+=($cabot_launch_image_tag)
            issue_list_append_tag "$source_type" "$report_id" "$log" "CABOT_LAUNCH_IMAGE_TAG=$cabot_launch_image_tag"
        fi

        if [[ "$line" =~ CABOT_SITE_VERSION=([^,]+) ]]; then
            label+=(${BASH_REMATCH[1]})
        else
            cabot_site_version=$(grep '^CABOT_SITE_VERSION=' $logdir/$log/env-file | awk -F= '{print $2}')
            label+=($cabot_site_version)
            issue_list_append_tag "$source_type" "$report_id" "$log" "CABOT_SITE_VERSION=$cabot_site_version"
        fi

        make_issue=1
        issue_args=(-t "$title_path" -f "$file_path" -u "${url[@]}" -l "${log_name[@]}" -L "${label[@]}")
        if [[ -n "$report_key" ]]; then
            issue_args+=(-k "$report_key")
        fi

        if [[ ${#log_name[@]} -ne ${#url[@]} ]]; then
            response="link entry count mismatch: names=${#log_name[@]}, urls=${#url[@]}"
            echo "$response" > stderr.log
            python3 notice_error.py issue -e "$response" -i "$line"
            make_issue=0
        elif [[ -n "$issue_num" ]]; then
            python3 make_issue.py "${issue_args[@]}" -i "$issue_num" > stdout.log 2> stderr.log

            if [ $? -ne 0 ]; then
                response=$(cat stderr.log)
                python3 notice_error.py issue -e "$response" -i "update log link #$issue_num"
                make_issue=0
            else
                response=$(cat stdout.log)
            fi
        else
            python3 make_issue.py "${issue_args[@]}" > stdout.log 2> stderr.log

            if [ $? -ne 0 ]; then
                response=$(cat stderr.log)
                python3 notice_error.py issue -e "$response" -i "$line"
                make_issue=0
            else
                response=$(cat stdout.log)
                issue_num=$(cat stdout.log | tail -n 1)
                issue_list_append_tag "$source_type" "$report_id" "$log" "REPORTED=$issue_num"
            fi
        fi

        echo $response
        ((notification+=$make_issue))

        if [ $notification -eq 2 ]; then
            if [[ $all_upload -eq 1 && "$line" != *ALL_UPLOAD* ]]; then
                issue_list_append_tag "$source_type" "$report_id" "$log" "ALL_UPLOAD"
            fi
            bash $scriptdir/notification.sh $CABOT_NAME"の${log}のアップロードが終了しました。\nhttps://github.com/${REPO_OWNER}/${REPO_NAME}/issues/${issue_num}"
        elif [ $can_upload -eq 1 ]; then
            bash $scriptdir/notification.sh $CABOT_NAME"の${log}のアップロードに失敗しました。"
            failed=1
        fi
    fi
done < while.txt

rm while.txt

if [ $failed -eq 1 ]; then
    bash $scriptdir/notification.sh $CABOT_NAME"の再アップロードをします。"
elif [ $can_upload -eq 1 ]; then
    bash $scriptdir/notification.sh $CABOT_NAME"の自動アップロードを終了します。"
    systemctl --user stop submit_report.timer
    rm $COUNT_FILE
    if [ -n "$WIFI_DROUTE" ] && [ $used_wifi_connection -eq 1 ]; then
        sudo nmcli con modify "$WIFI_SSID" ipv4.routes ""
        sudo nmcli con down "$WIFI_SSID" && sudo nmcli con up "$WIFI_SSID"
    fi
fi

[ -f stdout.log ] && rm stdout.log
[ -f stderr.log ] && rm stderr.log
