#!/usr/bin/env python3
import base64, os, secrets, subprocess
from pathlib import Path

temp = Path(os.environ['RUNNER_TEMP'])
certificate = temp/'developer-id.p12'
private = temp/'sparkle-private.key'
keychain = temp/'release.keychain-db'
certificate.write_bytes(base64.b64decode(os.environ['CERTIFICATE'], validate=True))
private.write_text(os.environ['SIGNING_KEY'])
certificate.chmod(0o600);private.chmod(0o600)
password = secrets.token_urlsafe(32)
def run(*args):
    result=subprocess.run(args,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    if result.returncode: raise SystemExit('Failed to configure temporary signing keychain; credentials are not logged')
run('security','create-keychain','-p',password,str(keychain))
run('security','set-keychain-settings','-lut','21600',str(keychain))
run('security','unlock-keychain','-p',password,str(keychain))
run('security','import',str(certificate),'-P',os.environ['CERTIFICATE_PASSWORD'],'-k',str(keychain),'-T','/usr/bin/codesign')
run('security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,str(keychain))
existing=subprocess.check_output(['security','list-keychains','-d','user'],text=True)
import shlex
run('security','list-keychains','-d','user','-s',str(keychain),*shlex.split(existing))
certificate.unlink()
print('Signing material imported into temporary runner keychain')
