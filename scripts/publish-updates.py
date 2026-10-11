#!/usr/bin/env python3
"""Verify all draft assets before exposing a complete GitHub stable release."""
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.request

spec = importlib.util.spec_from_file_location('channel', Path(__file__).with_name('github-channel.py'))
channel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(channel)


def digest(path):
    with path.open('rb') as stream:
        hashed = hashlib.sha256()
        while chunk := stream.read(1024 * 1024):
            hashed.update(chunk)
        return hashed.hexdigest()


def verify_public(path, url):
    for attempt in range(3):
        try:
            hashed = hashlib.sha256()
            with urllib.request.urlopen(url, timeout=120) as response:
                while chunk := response.read(1024 * 1024):
                    hashed.update(chunk)
            if hashed.hexdigest() != digest(path):
                raise RuntimeError('Public asset hash mismatch: ' + path.name)
            return
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2)


def main():
    tag = os.environ['RELEASE_TAG']
    repository = os.environ['GITHUB_REPOSITORY']
    feed, archives = channel.urls(repository, tag)
    source = Path('dist/updates')
    paths = sorted(path for path in source.iterdir() if path.is_file())
    if not paths or not (source / 'appcast.xml').is_file():
        raise RuntimeError('Signed release assets missing')
    with tempfile.TemporaryDirectory() as temporary:
        subprocess.run(['gh', 'release', 'download', tag, '--repo', repository,
                        '--dir', temporary], check=True)
        downloaded = Path(temporary)
        if {path.name for path in downloaded.iterdir()} != {path.name for path in paths}:
            raise RuntimeError('Draft release asset set mismatch')
        for path in paths:
            if digest(path) != digest(downloaded / path.name):
                raise RuntimeError('Draft asset hash mismatch: ' + path.name)
    subprocess.run(['gh', 'release', 'edit', tag, '--repo', repository,
                    '--draft=false', '--latest'], check=True)
    for path in paths:
        verify_public(path, archives + path.name)
    verify_public(source / 'appcast.xml', feed)
    print('Complete stable GitHub Release published; anonymous assets and latest signed feed verified')


if __name__ == '__main__':
    main()
