import sys
import os
import traceback
import requests
from functools import wraps
from optparse import OptionParser
from boxsdk import Client, CCGAuth
from boxsdk.network.default_network import DefaultNetwork
from dotenv import load_dotenv
load_dotenv()

class CustomNetwork(DefaultNetwork):
    def request(self, method, url, access_token, **kwargs):
        # `chunked_upload`に関連する操作の場合、タイムアウトを長く設定
        if 'chunked_upload' in url:
            kwargs['timeout'] = 6000  # 6000秒（20分）のタイムアウト
        else:
            kwargs['timeout'] = 30  # 通常の操作は30秒

        return super().request(method, url, access_token, **kwargs)

auth = CCGAuth(
client_id = os.environ.get('CLIENT_ID'),
client_secret = os.environ.get('CLIENT_SECRET'),
enterprise_id = os.environ.get('ENTERPRISE_ID')
)

client = Client(auth, network_layer=CustomNetwork())

# カスタムのリトライデコレーター
def retry_on_exception(max_retries=3, exceptions=(requests.exceptions.Timeout,)):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            retries = 0
            while retries < max_retries:
                try:
                    return func(*args, **kwargs)
                except exceptions as e:
                    retries += 1
                    print(f"Exception: {e}. Retry {retries}/{max_retries}.")
                except Exception as e:
                    print(f"An unexpected error occurred: {e}")
                    break
            else:
                print(f"Operation failed after {max_retries} retries.")
                return None  # リトライがすべて失敗した場合にはNoneを返す
        return wrapper
    return decorator

@retry_on_exception
def check_folder(folder_id, check_name):
    items = client.folder(folder_id).get_items()
    for item in items:
        if item.type != "folder":
            continue
        if item.name == check_name:
            return item.id

    return None

@retry_on_exception
def get_file_url(file_id):
    shared_link = client.file(file_id).get_shared_link()
    return shared_link

@retry_on_exception
def get_folder_url(folder_id):
    shared_link = client.folder(folder_id).get_shared_link()
    return shared_link

@retry_on_exception
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
    file_path = '/opt/cabot/docker/home/.ros/log/'


    year = file_name[6:10]
    month = file_name[11:13]
    day = file_name[14:16]
    file_path = file_path + file_name

    x = [year, month, day]
    folder_id = ""
    if options.split:
        folder_id = options.split
    else:
        folder_id = get_folder_id(x)

    try:
        chunked_uploader = client.folder(folder_id).get_chunked_uploader(file_path=file_path, file_name=file_name)
        uploaded_file = chunked_uploader.start()
        sys.stdout.write(get_file_url(uploaded_file.id))
    except requests.exceptions.Timeout as e:
        print(f"Exception: {e}.")
    except Exception as e:
        # エラーメッセージとスタックトレースを出力
        sys.stdout.write(f"Exception occurred: {str(e)}\n")
        traceback.print_exc()
        
        # status属性を持つかどうか確認し、持っていれば処理
        if hasattr(e, 'status') and e.status == 409:
            sys.stdout.write(get_file_url(e.context_info["conflicts"]["id"]))
            sys.exit(0)
        else:
            # status属性がない場合や、他のエラーの場合の処理
            sys.stdout.write(str(e))
            sys.exit(1)
