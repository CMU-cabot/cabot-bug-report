import sys
import os
from optparse import OptionParser
from boxsdk import Client, CCGAuth
from dotenv import load_dotenv
load_dotenv()

parser = OptionParser(usage="""
Example
{0} -f <log zip file>                        # show a list of process whose maximum usage is over 50%
""".format(sys.argv[0]))

parser.add_option('-f', '--file', type=str, help='bag file to upload')

(options, args) = parser.parse_args()

if not options.file:
    parser.print_help()
    sys.exit(0)

file_name = options.file


auth = CCGAuth(
  client_id = os.environ.get('CLIENT_ID'),
  client_secret = os.environ.get('CLIENT_SECRET'),
  enterprise_id = os.environ.get('ENTERPRISE_ID')
)

client = Client(auth)

folder_id = os.environ.get('FOLDER_ID')
file_path = '/opt/cabot/docker/home/.ros/log/'


year = file_name[6:10]
month = file_name[11:13]
day = file_name[14:16]
file_path = file_path + file_name


def check_folder(folder_id, check_name):
    items = client.folder(folder_id).get_items()
    for item in items:
        if item.type != "folder":
            continue
        if item.name == check_name:
            return item.id

    return None

def get_url(file_id):
    shared_link = client.file(file_id).get_shared_link()
    return shared_link

for num in [year, month, day]:
    if  subfolder_id := check_folder(folder_id, num):
        folder_id = subfolder_id
        continue
    else:
        subfolder = client.folder(folder_id).create_subfolder(num)
        folder_id = subfolder.id

try:
    chunked_uploader = client.folder(folder_id).get_chunked_uploader(file_path=file_path, file_name=file_name)
    uploaded_file = chunked_uploader.start()
    sys.stdout.write(get_url(uploaded_file.id))
except Exception as e:
    if e.status == 409:
        sys.stdout.write(get_url(e.context_info["conflicts"]["id"]))
        sys.exit(0)
    else:
        sys.stdout.write(e.message)
        sys.exit()

