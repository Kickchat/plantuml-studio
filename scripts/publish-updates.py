#!/usr/bin/env python3
"""Mirror private GitHub release assets to public S3-compatible HTTPS hosting."""
import hashlib, os, subprocess, tempfile, urllib.request
from pathlib import Path

source=Path('dist/updates')
base=os.environ['UPDATE_BASE_URL'].rstrip('/')+'/stable/'
prefix=os.environ.get('UPDATE_PREFIX','').strip('/')
destination='s3://'+os.environ['UPDATE_BUCKET']+'/'+(prefix+'/' if prefix else '')+'stable/'
def upload(path, cache):
    subprocess.run(['aws','s3','cp',str(path),destination+path.name,'--cache-control',cache,
                    '--content-type','application/xml' if path.suffix=='.xml' else 'application/octet-stream','--only-show-errors'],check=True,
                   env={key:value for key,value in os.environ.items() if key != 'AWS_ENDPOINT_URL' or value})
def verify_public(path):
    digest=hashlib.sha256()
    with urllib.request.urlopen(base+path.name,timeout=120) as response:
        while chunk:=response.read(1024*1024): digest.update(chunk)
    if digest.hexdigest()!=hashlib.sha256(path.read_bytes()).hexdigest():
        raise RuntimeError('Public asset hash mismatch: '+path.name)

for path in source.iterdir():
    if path.name=='appcast.xml': continue
    upload(path,'public, max-age=31536000, immutable')
    verify_public(path)
feed=source/'appcast.xml'
upload(feed,'public, max-age=60, must-revalidate')
verify_public(feed)
print('Public assets verified; signed appcast published last')
