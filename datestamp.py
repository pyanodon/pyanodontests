import json
import os
import re
from io import open
from datetime import date

INFO_PATH = 'info.json'
CHANGELOG_PATH = 'changelog.txt'

def version_as_str(version: tuple[int]) -> str:
    str_tuple = map(str, version)
    return '.'.join(str_tuple)

def str_as_version(version: str) -> tuple[int]:
    int_map = map(int, version.split('.'))
    return tuple(int_map)

def read_file_content(file_path):
    with open(file_path, 'r', encoding='utf-8', newline='') as read_file:
        return read_file.read()
    
def write_file_content(file_path, content):
    with open(file_path, 'w', encoding='utf-8', newline='') as write_file:
        return write_file.write(content)

def replace_in_file(file_path, regexp, replacement):
        content = read_file_content(file_path)
        result = re.sub(regexp, replacement, content, count=1)
        write_file_content(file_path, result)

def get_changelog_version() -> tuple[int]:
    content = read_file_content(CHANGELOG_PATH)
    result = re.search(r'Version: (?P<version>.*)', content)
    return str_as_version(result.group('version'))

def set_changelog_version(new_version):
    replace_in_file(CHANGELOG_PATH, r'Version: (?P<version>.*)', f'Version: {new_version}')
    
def set_changelog_date():
    cur_date = date.today().isoformat() # YYYY-MM-DD
    replace_in_file(CHANGELOG_PATH, r'Date: (?P<date>.*)', f'Date: {cur_date}')

def get_info_name() -> str:
    with open(INFO_PATH, 'r', encoding='utf-8', newline='') as info:
        parsed_info = json.load(info)
        return parsed_info.get('name')

def get_info_version() -> tuple[int]:
    content = read_file_content(INFO_PATH)
    info = json.loads(content)
    version_str = info.get('version')
    return str_as_version(version_str)

def set_info_version(new_version: tuple[int]):
    new_version_str = version_as_str(new_version)
    content = read_file_content(INFO_PATH)
    info = json.loads(content)
    old_version = info.get('version')
    write_file_content(INFO_PATH, content.replace(old_version, new_version_str))

def set_version_and_date():
    changelog_version = get_changelog_version()
    info_version = get_info_version()
    mod_version = version_as_str(max(changelog_version, info_version)) # Take the latest of the versions between changelog.txt and info.json
    if changelog_version > info_version:
        set_info_version(changelog_version)
    elif info_version > changelog_version: # they could be equal
        set_changelog_version(info_version)
    # Bump the latest date entry in the changelog
    set_changelog_date()
    # Commit will be done in yml so we store the name and version in the env file and exit
    env_path = os.getenv('GITHUB_ENV')
    with open(env_path, 'a') as env_file:
        env_file.write(f"MOD_NAME={get_info_name()}\n")
        env_file.write(f"MOD_VERSION={mod_version}\n")
        env_file.write(f"MOD_ZIP_PATH={get_info_name()}_{mod_version}.zip")
    
set_version_and_date()