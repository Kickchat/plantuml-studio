import base64
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
def load(name, file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module
version=load('version','version.py')
appcast=load('appcast','validate-appcast.py')
channel=load('channel','github-channel.py')
publisher=load('publisher','publish-updates.py')

class ReleaseTests(unittest.TestCase):
    def test_github_stable_feed_and_immutable_archives(self):
        feed, archive = channel.urls('Kickchat/plantuml-studio', 'v0.4.0')
        self.assertEqual(feed, 'https://github.com/Kickchat/plantuml-studio/releases/latest/download/appcast.xml')
        self.assertEqual(archive, 'https://github.com/Kickchat/plantuml-studio/releases/download/v0.4.0/')
        for repository, tag in [('owner/repo/extra', 'v0.4.0'), ('owner/repo', 'v0.4.0-beta'), ('https://github.com/repo', 'v0.4.0')]:
            with self.assertRaises(ValueError): channel.urls(repository, tag)

    def test_draft_mismatch_prevents_publication(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            source=root/'dist/updates';source.mkdir(parents=True)
            (source/'appcast.xml').write_bytes(b'signed feed')
            calls=[]
            def command(arguments, **kwargs):
                calls.append(arguments)
                (Path(arguments[arguments.index('--dir')+1])/'appcast.xml').write_bytes(b'wrong feed')
            previous=Path.cwd()
            try:
                os.chdir(root)
                with patch.dict(os.environ, {'RELEASE_TAG':'v0.4.0','GITHUB_REPOSITORY':'Kickchat/plantuml-studio'}), patch.object(publisher.subprocess,'run',side_effect=command):
                    with self.assertRaisesRegex(RuntimeError,'hash mismatch'): publisher.main()
            finally: os.chdir(previous)
            self.assertEqual(len(calls),1)
            self.assertEqual(calls[0][2],'download')

    def test_release_version_matches_plist(self):
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'Info.plist'
            path.write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.plantuml.studio'}))
            subprocess.run(['python3',str(ROOT/'scripts/version.py'),'plist','--path',str(path)],check=True,env={k:v for k,v in os.environ.items() if k not in ['UPDATE_FEED_URL','SPARKLE_PUBLIC_KEY']})
            data=plistlib.loads(path.read_bytes())
            self.assertEqual(data['CFBundleShortVersionString'],version.version()['version'])
            self.assertEqual(data['CFBundleVersion'],str(version.version()['build']))
            self.assertEqual(data['CFBundleIdentifier'],'local.plantuml.studio')
    def test_wrong_tag_is_rejected(self):
        result=subprocess.run(['python3',str(ROOT/'scripts/version.py'),'check','--tag','v999.0.0'],capture_output=True)
        self.assertNotEqual(result.returncode,0)
    def test_missing_configuration_is_disabled(self):
        with patch.dict(os.environ,{},clear=True): self.assertEqual(version.update_configuration(),{})
    def test_insecure_or_incomplete_feed_is_rejected(self):
        for feed,key in [('http://example.com/appcast.xml',base64.b64encode(bytes(32)).decode()),('https://example.com/appcast.xml',''),('https://user:password@example.com/appcast.xml',base64.b64encode(bytes(32)).decode())]:
            with patch.dict(os.environ,{'UPDATE_FEED_URL':feed,'SPARKLE_PUBLIC_KEY':key},clear=True):
                with self.assertRaises(ValueError): version.update_configuration()
    def test_signed_feed_and_manual_install_required(self):
        with patch.dict(os.environ,{'UPDATE_FEED_URL':'https://updates.example.org/stable/appcast.xml','SPARKLE_PUBLIC_KEY':base64.b64encode(bytes(32)).decode()},clear=True):
            config=version.update_configuration()
            self.assertTrue(config['SURequireSignedFeed'])
            self.assertTrue(config['SUVerifyUpdateBeforeExtraction'])
            self.assertFalse(config['SUAutomaticallyUpdate'])
    def test_invalid_appcast_metadata_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive=Path(temporary)/'PlantUMLStudio.zip';archive.write_bytes(b'archive')
            feed=Path(temporary)/'appcast.xml'
            expected=version.version()
            base='https://updates.example.org/stable/'
            root=ET.Element('rss');item=ET.SubElement(ET.SubElement(root,'channel'),'item')
            enclosure=ET.SubElement(item,'enclosure',{'url':base+archive.name,'length':str(archive.stat().st_size),appcast.SPARKLE+'version':str(expected['build']),appcast.SPARKLE+'shortVersionString':expected['version'],appcast.SPARKLE+'edSignature':base64.b64encode(bytes(64)).decode()})
            def write(): ET.ElementTree(root).write(feed)
            write();appcast.validate(feed,archive,base,expected)
            for attribute,value in [('url','https://attacker.example/archive.zip'),('length','1'),(appcast.SPARKLE+'version','999'),(appcast.SPARKLE+'edSignature','')]:
                original=enclosure.get(attribute);enclosure.set(attribute,value);write()
                with self.assertRaises(ValueError): appcast.validate(feed,archive,base,expected)
                enclosure.set(attribute,original)
            ET.SubElement(item,appcast.SPARKLE+'channel').text='beta';write()
            with self.assertRaises(ValueError):appcast.validate(feed,archive,base,expected)
    def test_real_eddsa_signature_rejects_tampering(self):
        tool=ROOT/'.build/artifacts/sparkle/Sparkle/bin/sign_update'
        self.assertTrue(tool.exists(),'Resolve pinned Sparkle before running release tests')
        with tempfile.TemporaryDirectory() as temporary:
            private=Path(temporary)/'test.key'
            private.write_bytes(base64.b64encode(os.urandom(32)));private.chmod(0o600)
            archive=Path(temporary)/'test.zip';archive.write_bytes(b'signed archive fixture')
            def run(*args):return subprocess.run([str(tool),'--ed-key-file',str(private),*args],capture_output=True,text=True)
            signed=run('-p',str(archive))
            self.assertEqual(signed.returncode,0)
            signature=signed.stdout.strip()
            self.assertEqual(run('--verify',str(archive),signature).returncode,0)
            archive.write_bytes(b'corrupted archive fixture')
            self.assertNotEqual(run('--verify',str(archive),signature).returncode,0)
            self.assertNotEqual(run('--verify',str(archive),base64.b64encode(bytes(64)).decode()).returncode,0)
    def test_public_key_must_match_private_seed(self):
        # Public RFC 8032 test vector; never used for production signing.
        seed=bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')
        public=bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'vector.key';path.write_bytes(base64.b64encode(seed));path.chmod(0o600)
            for key,valid in [(public,True),(bytes(32),False)]:
                result=subprocess.run(['swift','-module-cache-path',str(ROOT/'.build/ModuleCache'),str(ROOT/'scripts/verify-key.swift'),str(path)],env={**os.environ,'SPARKLE_PUBLIC_KEY':base64.b64encode(key).decode()},capture_output=True)
                self.assertEqual(result.returncode==0,valid,result.stderr.decode())

if __name__=='__main__':unittest.main()
