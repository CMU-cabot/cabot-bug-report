import sys
import upload
from optparse import OptionParser

parser = OptionParser(usage="""
Example
{0} -f <log zip file>                        # show a list of process whose maximum usage is over 50%
""".format(sys.argv[0]))

parser.add_option('-f', '--folder_name', type=str, help='specify log file name')
parser.add_option('-d', '--dev', type=str, help='specify root folder name in Box')

(options, args) = parser.parse_args()

folder_name = options.folder_name

year = folder_name[6:10]
month = folder_name[11:13]
day = folder_name[14:16]

x = [year, month, day, folder_name]

dev=False
if options.dev:
    x.insert(0, options.dev)
    dev=True

folder_id = upload.get_folder_id(x, dev)

url = upload.get_folder_url(folder_id)
print(f"{folder_id},{url}")