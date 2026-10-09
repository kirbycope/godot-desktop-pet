"""Fetches NobodyWho, the phone's local LLM, into addons/nobodywho: python tools/fetch_nobodywho.py

NobodyWho (https://github.com/nobodywho-ooo/nobodywho, EUPL-1.2) is a GDExtension and is not
committed, like GUT. The release is pinned below and taken as published, less the iOS builds and
the Windows debug symbols, which nothing loads. Run it once after cloning, and before exporting the
Android app.
"""
import io
import pathlib
import shutil
import sys
import urllib.request
import zipfile

VERSION = "12.1.0"
URL = f"https://github.com/nobodywho-ooo/nobodywho/releases/download/nobodywho-godot-v{VERSION}/nobodywho-godot-nobodywho-godot-v{VERSION}.zip"
PREFIX = "bin/addons/nobodywho/"
SKIPPED = ("-ios-", ".pdb")


def main() -> int:
    target = pathlib.Path(__file__).resolve().parent.parent / "addons" / "nobodywho"
    print(f"Downloading NobodyWho {VERSION} (about 340 MB)...")
    with urllib.request.urlopen(URL) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    kept = 0
    for entry in archive.infolist():
        name = entry.filename
        if not name.startswith(PREFIX) or entry.is_dir() or any(skip in name for skip in SKIPPED):
            continue
        relative = name[len(PREFIX):]
        if "/" in relative or ".." in relative:
            continue
        (target / relative).write_bytes(archive.read(entry))
        kept += 1
    print(f"Wrote {kept} files to {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
