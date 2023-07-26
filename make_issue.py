import json
import requests
import argparse
import os
from dotenv import load_dotenv
load_dotenv()

# Authentication for user filing issue (must have read/write access to
# repository to add issue to)
USERNAME = os.environ.get('USERNAME')
PASSWORD = os.environ.get('PASSWORD')

# The repository to add this issue to
REPO_OWNER = os.environ.get('REPO_OWNER')
REPO_NAME = os.environ.get('REPO_NAME')

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
    else:
        print ('Could not create Issue "%s"' % title)
        print ('Response:', r.content)


parser = argparse.ArgumentParser(description='Make github issue with AI suitcase Log.')
parser.add_argument('-t', '--title', action='store')
parser.add_argument('-f', '--file_path', action='store')
parser.add_argument('-u', '--url', action='store', nargs='+')

args = parser.parse_args()

body = ""

with open(args.file_path, "r") as f:
    text = f.read()
    body = text
    for item in args.url:
        body += "\n" + item

make_github_issue(args.title, body, ['バグ'])
