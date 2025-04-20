# Report Submitter

### Prerequisites
- set link cabot directory
```
sudo ln -sf $cabotdir /opt/cabot
```

- prepare account for using Box API
  - Authentication is Client Credentials Grant

## Make .env file
- **Required settings**
  ```
  GIT_USERNAME        # github account name
  GIT_PASSWORD        # github access token
  REPO_OWNER      # owner of repository where issue is created
  REPO_NAME       # repository where issue is created
  BOX_CLIENT_ID       # your client_id to use Box API
  BOX_CLIENT_SECRET   # your client_secret to use Box API
  BOX_ENTERPRISE_ID   # your enterprise_id to use Box API
  BOX_FOLDER_ID       # folder_id of root folder to upload logs
  WIFI_SSID            # This system works only when connected to the WIFI_SSID
  ```

- Optional settings for notice
  ```
  REPO_OWNER_FOR_ERROR      # owner of repository where issue is created if you want notifications for failure to upload or make issue
  REPO_NAME_FOR_ERROR       # repository where issue is created if you want notifications for failure to upload or make issue
  SLACK_TOKEN     # slack api token (incoming-webhook)
  ```

- Optional settings for network priority
  ```
  WIFI_DROUTE          # default via IP of WIFI_SSID
  WIFI_METRIC          # default is 50
  ```

- Others
  ```
  CABOT_NAME      # robot name used to identify the machine ex) as issue label
  ```

## Install

```
./install.sh
```

## Uninstall

```
./uninstall.sh
```

## Others
### create_list.sh
- requires thress positional arguments
  1. issue title
  2. issue body text
  3. logs (1 or more)
    - if you specify more than one, separate them with spaces.
- example in python
```
import subprocess

title = "title"
body = "body"
logs = "cabot_yyyy-MM-dd-hh-mm-ss cabot_yyyy-MM-dd-hh-mm-ss"

command = ["./create_list.sh", title, body, logs]
subprocess.call(command)
```