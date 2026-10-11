#!/usr/bin/env python3
import os
import urllib.request
import urllib.error
import importlib.util
import json
import re
import subprocess
from pathlib import Path

names = ['DEVELOPER_ID_APPLICATION','APPLE_ID','APPLE_TEAM_ID','APPLE_APP_PASSWORD',
         'CERTIFICATE','CERTIFICATE_PASSWORD','SIGNING_KEY','SPARKLE_PUBLIC_KEY',
         'UPDATE_BASE_URL','UPDATE_BUCKET','AWS_DEFAULT_REGION','AWS_ACCESS_KEY_ID',
         'AWS_SECRET_ACCESS_KEY','GH_TOKEN','GITHUB_REPOSITORY','RELEASE_TAG']
missing = [name for name in names if not os.environ.get(name)]
if missing: raise SystemExit('Missing release configuration: ' + ', '.join(missing))
spec=importlib.util.spec_from_file_location('version',Path(__file__).with_name('version.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
os.environ['UPDATE_FEED_URL']=os.environ['UPDATE_BASE_URL'].rstrip('/')+'/stable/appcast.xml'
module.update_configuration()
current = module.version()
for tag in subprocess.check_output(['git', 'tag', '--list', 'v*'], text=True).splitlines():
    if tag == os.environ['RELEASE_TAG'] or not re.fullmatch(r'v\d+\.\d+\.\d+', tag): continue
    if tuple(map(int, tag[1:].split('.'))) >= tuple(map(int, current['version'].split('.'))):
        raise SystemExit('Stable version must be newer than existing stable tags')
    old = subprocess.run(['git', 'show', tag + ':Version.json'], capture_output=True, text=True)
    if old.returncode == 0 and current['build'] <= json.loads(old.stdout)['build']:
        raise SystemExit('Build number must be newer than existing tagged builds')
url='https://api.github.com/repos/'+os.environ['GITHUB_REPOSITORY']+'/releases/tags/'+os.environ['RELEASE_TAG']
req=urllib.request.Request(url,headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],'User-Agent':'PlantUMLStudio-release'})
try:
    urllib.request.urlopen(req)
except urllib.error.HTTPError as error:
    if error.code != 404: raise
else:
    raise SystemExit('A release for this version already exists; do not overwrite it')
print('Release configuration validated; version has not been published')
