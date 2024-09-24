import json
import requests
import argparse
import os
import sys
import time
from dotenv import load_dotenv
load_dotenv()

# Authentication for user filing issue (must have read/write access to
# repository to add issue to)
USERNAME = os.environ.get('USERNAME')
PASSWORD = os.environ.get('PASSWORD')

# The repository to add this issue to
REPO_OWNER = os.environ.get('REPO_OWNER')
REPO_NAME = os.environ.get('REPO_NAME')

CABOT_NAME = os.environ.get('CABOT_NAME')

def make_github_issue(title, body=None, labels=None):
    '''Create an issue on github.com using the given parameters.'''
    # Our url to create issues via POST
    url = 'https://api.github.com/repos/%s/%s/issues' % (REPO_OWNER, REPO_NAME)
    # Create an authenticated session to create the issue
    session = requests.session()
    session.auth = (USERNAME, PASSWORD)
    # Create our issue
    issue = {'title': title,
             'body': body,
             'labels': labels}
    # Add the issue to our repository
    r = session.post(url, json.dumps(issue))
    if r.status_code == 201:
        print ('Successfully created Issue "%s"' % title)
        print (r.json()['number'])
    else:
        sys.stderr.write(str(r.status_code))
        sys.stderr.write(str(r.json()))
        sys.exit(1)

def update_issue_body(num, body=None, labels=None):
    url = 'https://api.github.com/repos/%s/%s/issues/%s' % (REPO_OWNER, REPO_NAME, num)

    session = requests.session()
    session.auth = (USERNAME, PASSWORD)

    data = {
        "body": body,
        "labels": labels
    }

    r = session.patch(url, json.dumps(data))
    if r.status_code == 200:
        print ('Update Issue "%s" body' % num)
    else:
        sys.stderr.write(str(r.status_code))
        sys.stderr.write(str(r.json()))
        sys.exit(1)

def check_close(num, retry=0, max_retries=5, delay=2):
    url = f'https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/issues/{num}'

    session = requests.session()
    session.auth = (USERNAME, PASSWORD)

    try:
        r = session.get(url)
        if r.status_code == 200:
            print(r.json().get("state"))
            sys.exit(0)
        else:
            if retry < max_retries:
                time.sleep(delay)
                check_close(num, retry=retry+1, max_retries=max_retries, delay=delay)
            else:
                sys.stderr.write(f"Error: {r.status_code} {r.json()}\n")
                sys.exit(1)
    except requests.exceptions.RequestException as e:
        if retry < max_retries:
            time.sleep(delay)
            check_close(num, retry=retry+1, max_retries=max_retries, delay=delay)
        else:
            sys.stderr.write(f"Exception: {str(e)}\n")
            sys.exit(1)

parser = argparse.ArgumentParser(description='Make github issue with AI suitcase Log.')
parser.add_argument('-t', '--title_path', action='store')
parser.add_argument('-f', '--file_path', action='store')
parser.add_argument('-u', '--url', action='store', nargs='*', default=[])
parser.add_argument('-l', '--log_name', action='store', nargs='*', default=[])
parser.add_argument('-i', '--issue_number', action='store')
parser.add_argument('-c', '--close_check', action='store_true')
parser.add_argument('-L', '--labels', action='store', nargs='*', default=[])

args = parser.parse_args()

title = ""
body = ""
dic = dict(zip(args.log_name, args.url))
num = args.issue_number
issue_labels = ['報告']
issue_labels.extend(args.labels)

if args.close_check:
    check_close(num)

if CABOT_NAME:
    body += "CABOT_NAME is " + CABOT_NAME + "\n"

with open(args.title_path, "r") as f:
    title = f.read()

with open(args.file_path, "r") as f:
    text = f.read()
    body += text
    for k,v in dic.items():
        if v == "None":
            body += "\n" + k
        else:
            body += "\n" + "[{}]({})".format(k, v)
        
if num:
    update_issue_body(num, body, issue_labels)
else:
    make_github_issue(title, body, issue_labels)
