# Report Submitter

### Prerequisites
- set link cabot directory
```
sudo ln -sf $cabotdir /opt/cabot
```

- prepare account for using Box API
  - Authentication is Client Credentials Grant

## Make .env file
- `.env` file is ignored because it has private information
- Set the following environment variables
```
USERNAME        # github account name
PASSWORD        # github access token
REPO_OWNER      # owner of repository where issue is created
REPO_NAME       # repository where issue is created
CLIENT_ID       # your client_id to use Box API
CLIENT_SECRET   # your client_secret to use Box API
ENTERPRISE_ID   # your enterprise_id to use Box API
FOLDER_ID       # folder_id of root folder to upload logs
SSID            # This system works only when connected to the SSID
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

