#!/usr/bin/env python3
"""Sign nested native code from the inside out. Never use ad-hoc for releases."""
import os
from pathlib import Path
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
identity = os.environ.get("DEVELOPER_ID_APPLICATION", "")
if not identity.startswith("Developer ID Application:"):
    raise SystemExit("Developer ID Application identity is required")
def sign(path, java=False):
    command = ["codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity]
    if java:
        command += ["--entitlements", str(Path(__file__).parent / "java.entitlements.plist")]
    subprocess.run(command + [str(path)], check=True)

native = []
bundles = []
for path in app.rglob('*'):
    if path.is_symlink():
        continue
    if path.is_dir() and (path.suffix in ['.app', '.xpc', '.framework'] or (path/'Contents/Info.plist').is_file()):
        bundles.append(path)
    elif path.is_file():
        with path.open('rb') as stream:
            magic = stream.read(4)
        if magic in [b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf']:
            native.append(path)
for path in sorted(native, key=lambda p: len(p.parts), reverse=True):
    sign(path, java=path.name == 'java' and 'Runtime' in path.parts)
for path in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
    sign(path)
sign(app)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
