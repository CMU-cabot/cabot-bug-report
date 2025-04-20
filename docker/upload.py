import sys
import os
import traceback
from functools import wraps
from typing import Any
from optparse import OptionParser
from boxsdk import Client, CCGAuth, OAuth2
from boxsdk.network.default_network import DefaultNetwork
from boxsdk.network.network_interface import NetworkResponse
from boxsdk.session.session import AuthorizedSession
from dotenv import load_dotenv
load_dotenv()
import re

def error_handler(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except Exception as e:
            # エラーメッセージとスタックトレースを出力
            sys.stderr.write(f"Exception occurred: {str(e)}\n")
            traceback.print_exc()
            
            # status属性を持つかどうか確認し、持っていれば処理
            if hasattr(e, 'status') and e.status == 409:
                file_id = e.context_info["conflicts"]["id"]
                file_url = get_file_url(file_id)
                if func.__name__ == "chunked_upload":
                    file_info = client.file(file_id).get()
                    file_path=args[1]
                    file_name=args[2]
                    if file_info["size"] != os.path.getsize(file_path):
                        update_contents(file_id, file_path, file_name)
                sys.stdout.write(file_url)
                sys.exit(0)
            else:
                # status属性がない場合や、他のエラーの場合の処理
                sys.stderr.write(str(e))
                sys.exit(1)
    return wrapper

class CustomNetwork(DefaultNetwork):
     def request(self, method: str, url: str, access_token: str, **kwargs: Any) -> NetworkResponse:
        if 'upload_sessions' in url and method.upper() == 'PUT':
            timeout = (60, 1800)
        else:
            timeout = (10, 30)
        return super().request(method, url, access_token, timeout=timeout, **kwargs)
     
class CustomAutorizedSession(AuthorizedSession):
    def __init__(self, oauth: OAuth2, network_layer=None):
        network_layer = network_layer or CustomNetwork()
        super().__init__(oauth, network_layer=network_layer)

auth = CCGAuth(
client_id = os.environ.get('CLIENT_ID'),
client_secret = os.environ.get('CLIENT_SECRET'),
enterprise_id = os.environ.get('ENTERPRISE_ID')
)

custom_session = CustomAutorizedSession(auth)
client = Client(auth, session=custom_session)

@error_handler
def check_folder(folder_id, check_name):
    items = client.folder(folder_id).get_items()
    for item in items:
        if item.type != "folder":
            continue
        if item.name == check_name:
            return item.id

    return None

@error_handler
def get_file_url(file_id):
    shared_link = client.file(file_id).get_shared_link()
    return shared_link

@error_handler
def get_folder_url(folder_id):
    app_endpoint = client.folder(folder_id).get_shared_link()
    m = re.match(r'(.*\.com)\/.*', app_endpoint)
    web_endpoint = m.group(1) + "/folder/" + folder_id

    return web_endpoint

@error_handler
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

@error_handler
def chunked_upload(folder_id, file_path, file_name):
    try:
        chunked_uploader = client.folder(folder_id).get_chunked_uploader(file_path=file_path, file_name=file_name)
        uploaded_file = chunked_uploader.start()
    except Exception as e:
        if hasattr(e, 'code') and e.code == "file_size_too_small":
            uploaded_file = upload(folder_id, file_path, file_name)
        else:
            raise

    return uploaded_file

@error_handler
def upload(folder_id, file_path, file_name):
    uploaded_file = client.folder(folder_id).upload(file_path=file_path, file_name=file_name)

    return uploaded_file

@error_handler
def update_contents(file_id, file_path, file_name):
    client.file(file_id).update_contents(file_path=file_path, file_name=file_name)

if __name__ == "__main__":

    parser = OptionParser(usage="""
    Example
    {0} -f <log zip file>                        # show a list of process whose maximum usage is over 50%
    """.format(sys.argv[0]))

    parser.add_option('-f', '--file', type=str, help='bag file to upload')
    parser.add_option('-s', '--split', type=str, help='bag file to upload')
    parser.add_option('-p', '--path', type=str, help='bag file to upload')

    (options, args) = parser.parse_args()

    if not options.file:
        parser.print_help()
        sys.exit(0)

    file_name = options.file
    file_path = options.path


    year = file_name[6:10]
    month = file_name[11:13]
    day = file_name[14:16]
    file_path = file_path + "/" + file_name

    x = [year, month, day]
    folder_id = ""
    if options.split:
        folder_id = options.split
    else:
        folder_id = get_folder_id(x)

    uploaded_file = chunked_upload(folder_id, file_path, file_name)
    sys.stdout.write(get_file_url(uploaded_file.id))
