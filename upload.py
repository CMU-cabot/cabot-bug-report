import sys
import os
from optparse import OptionParser
from boxsdk import Client, CCGAuth
from dotenv import load_dotenv
load_dotenv()

auth = CCGAuth(
client_id = os.environ.get('CLIENT_ID'),
client_secret = os.environ.get('CLIENT_SECRET'),
enterprise_id = os.environ.get('ENTERPRISE_ID')
)

client = Client(auth)

def check_folder(folder_id, check_name):
    items = client.folder(folder_id).get_items()
    for item in items:
        if item.type != "folder":
            continue
        if item.name == check_name:
            return item.id

    return None

def get_file_url(file_id):
    shared_link = client.file(file_id).get_shared_link()
    return shared_link

def get_folder_url(folder_id):
    url = client.folder(folder_id).get_url()
    return url

def get_folder_id(elements):
    folder_id = os.environ.get('FOLDER_ID')
    for num in elements:
        if  subfolder_id := check_folder(folder_id, num):
            folder_id = subfolder_id
            continue
        else:
            subfolder = client.folder(folder_id).create_subfolder(num)
            folder_id = subfolder.id
    
    return folder_id

if __name__ == "__main__":

    parser = OptionParser(usage="""
    Example
    {0} -f <log zip file>                        # show a list of process whose maximum usage is over 50%
    """.format(sys.argv[0]))

    parser.add_option('-f', '--file', type=str, help='bag file to upload')
    parser.add_option('-s', '--split', type=str, help='bag file to upload')

    (options, args) = parser.parse_args()

    if not options.file:
        parser.print_help()
        sys.exit(0)

    file_name = options.file

    split = False
    zip_name = ""
    if options.split:
        split = True
        zip_name = options.split


    file_path = '/opt/cabot/docker/home/.ros/log/'


    year = file_name[6:10]
    month = file_name[11:13]
    day = file_name[14:16]
    file_path = file_path + file_name

    x = [year, month, day]
    if split:
        x.append(zip_name)

    folder_id = get_folder_id(x)

    try:
        chunked_uploader = client.folder(folder_id).get_chunked_uploader(file_path=file_path, file_name=file_name)
        uploaded_file = chunked_uploader.start()
        sys.stdout.write(get_file_url(uploaded_file.id))
    except Exception as e:
        if e.status == 409:
            sys.stdout.write(get_file_url(e.context_info["conflicts"]["id"]))
            sys.exit(0)
        else:
            sys.stdout.write(e.message)
            sys.exit(1)

