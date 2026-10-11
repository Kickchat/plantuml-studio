#!/usr/bin/env python3
import argparse
import base64
import importlib.util
from pathlib import Path
import xml.etree.ElementTree as ET
from urllib.parse import urlparse

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
def validate(feed, archive, base_url, expected):
    base = urlparse(base_url)
    if base.scheme != 'https' or not base.hostname or base.username or base.password or base.query or base.fragment:
        raise ValueError('Public update base URL must use HTTPS without credentials')
    root = ET.parse(feed).getroot()
    item = root.find('./channel/item')
    if item is None or item.find(SPARKLE + 'channel') is not None:
        raise ValueError('Stable feed must contain a default-channel release')
    enclosure = item.find('enclosure')
    if enclosure is None:
        raise ValueError('Missing update enclosure')
    def field(name):
        return enclosure.get(SPARKLE + name) or item.findtext(SPARKLE + name)
    if field('version') != str(expected['build']) or field('shortVersionString') != expected['version']:
        raise ValueError('Appcast version does not match Version.json')
    if enclosure.get('url') != base_url.rstrip('/') + '/' + archive.name:
        raise ValueError('Unexpected archive URL')
    if int(enclosure.get('length', '0')) != archive.stat().st_size:
        raise ValueError('Archive length mismatch')
    if len(base64.b64decode(enclosure.get(SPARKLE + 'edSignature', ''), validate=True)) != 64:
        raise ValueError('Missing or malformed archive EdDSA signature')
    return enclosure.get(SPARKLE + 'edSignature')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('feed', type=Path)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--base-url', required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('version', Path(__file__).with_name('version.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    signature = validate(args.feed, args.archive, args.base_url, module.version())
    import os, subprocess
    key = os.environ.get('SPARKLE_PRIVATE_KEY_FILE')
    if not key: raise ValueError('Release verification needs a signing key file')
    subprocess.run([str(Path(__file__).resolve().parent.parent / '.build/artifacts/sparkle/Sparkle/bin/sign_update'), '--verify', '--ed-key-file', key, str(args.archive), signature], check=True)
    print('Appcast version, URL, size and archive signature verified')

if __name__ == '__main__': main()
