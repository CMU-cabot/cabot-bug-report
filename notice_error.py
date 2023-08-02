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
REPO_OWNER = os.environ.get('REPO_OWNER_FOR_ERROR')
REPO_NAME = os.environ.get('REPO_NAME_FOR_ERROR')

def make_github_issue(title, body=None):
    '''Create an issue on github.com using the given parameters.'''
    # Our url to create issues via POST
    url = 'https://api.github.com/repos/%s/%s/issues' % (REPO_OWNER, REPO_NAME)
    # Create an authenticated session to create the issue
    session = requests.session()
    session.auth = (USERNAME, PASSWORD)
    # Create our issue
    issue = {'title': title,
             'body': body}
    # Add the issue to our repository
    r = session.post(url, json.dumps(issue))
    if r.status_code == 201:
        print ('Successfully created Issue "%s"' % title)
    else:
        print ('Could not create Issue "%s"' % title)
        print ('Response:', r.content)


parser = argparse.ArgumentParser(description='Make github issue with Error Log.')
parser.add_argument('run', type=str, choices=['log', 'issue'])
parser.add_argument('-e', '--error_message', action='store')
parser.add_argument('-u', '--upload_file', action='store')
parser.add_argument('-i', '--issue_contents', action='store')

args = parser.parse_args()

title = "Notice! There is an error in auto_upload"
text = "An error occurred while "

if args.run == "log":
    text += "uploading " + args.upload_file
elif args.run == "issue":
    text += "making issue ({})".format(args.issue_contents)


body = text + "\n" + args.error_message

make_github_issue(title, body)
