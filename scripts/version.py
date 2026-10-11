#!/usr/bin/env python3
"""One version source for local builds, release tags and appcast validation."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent

def version():
    value = json.loads((ROOT / "Version.json").read_text())
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", value["version"]):
        raise ValueError("Stable version must be X.Y.Z without prerelease suffix")
    if type(value["build"]) is not int or not 1 <= value["build"] <= 9999:
        raise ValueError("Build must be an increasing integer in 1...9999")
    return value

def update_configuration():
    feed = os.environ.get("UPDATE_FEED_URL", "")
    key = os.environ.get("SPARKLE_PUBLIC_KEY", "")
    if not feed and not key:
        return {}
    parsed = urlparse(feed)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Update feed must be an HTTPS URL without credentials/query/fragment")
    if len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError("Sparkle public key must encode exactly 32 bytes")
    return {"SUFeedURL": feed, "SUPublicEDKey": key, "SUEnableAutomaticChecks": True,
            "SUAutomaticallyUpdate": False, "SUScheduledCheckInterval": 86400,
            "SUVerifyUpdateBeforeExtraction": True, "SURequireSignedFeed": True}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["check", "plist", "show", "bump"])
    parser.add_argument("--tag")
    parser.add_argument("--path")
    parser.add_argument("--version")
    parser.add_argument("--build", type=int)
    args = parser.parse_args()
    value = version()
    if args.command == "bump":
        if not args.version or args.build is None or args.build <= value["build"]:
            raise ValueError("Supply a new version and strictly increasing --build")
        if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", args.version):
            raise ValueError("Version must be X.Y.Z")
        if tuple(map(int, args.version.split('.'))) <= tuple(map(int, value["version"].split('.'))) or args.build > 9999:
            raise ValueError("Version must increase and build must be <=9999")
        (ROOT / "Version.json").write_text(json.dumps({"version": args.version, "build": args.build}, indent=2) + "\n")
        value = version()
    if args.tag and args.tag != "v" + value["version"]:
        raise ValueError("Tag and Version.json disagree")
    if args.command == "plist":
        path = Path(args.path)
        data = plistlib.loads(path.read_bytes())
        data.update(CFBundleShortVersionString=value["version"], CFBundleVersion=str(value["build"]))
        data.update(update_configuration())
        path.write_bytes(plistlib.dumps(data))
    elif args.command == "show":
        print(value["version"])
    else:
        print(f"Validated version {value['version']}, build {value['build']}")

if __name__ == "__main__":
    main()
