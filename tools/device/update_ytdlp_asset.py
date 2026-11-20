#!/usr/bin/env python
"""Bundle a current yt-dlp inside the app.

youtubedl-android 0.18.1 ships yt-dlp 2025.11.12, which YouTube no longer serves well (1080p
files fail part-way with HTTP 403). This script packs a newer yt-dlp from PyPI (yt-dlp's
official package) into android/app/src/main/assets/ytdlp/ as the same kind of file the
library's updater downloads from GitHub: a Python zip application named `yt-dlp`, plus
`version.txt`. ExtractorChannel installs it on the phone when it is newer than the copy there.

Usage (from the repo root):  python tools/device/update_ytdlp_asset.py [VERSION]
Without VERSION the newest release on PyPI is used. Needs pip and network access to PyPI.
Only pure-Python packages are packed (yt_dlp and the yt_dlp_ejs challenge scripts it pins);
the library's own Python already has the native extras (Cryptodome, mutagen, sqlite3).
"""
import email.parser
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'assets', 'ytdlp')
VERSION_RE = re.compile(r'^\d{4}\.\d{1,2}\.\d{1,2}(\.\d+)?$')


def latest_version():
    with urllib.request.urlopen('https://pypi.org/pypi/yt-dlp/json', timeout=30) as r:
        return json.load(r)['info']['version']


def download_wheel(spec, dest):
    subprocess.run([sys.executable, '-m', 'pip', 'download', spec, '--no-deps', '--only-binary=:all:',
                    '-d', dest, '-q'], check=True)
    wheels = [f for f in os.listdir(dest) if f.endswith('.whl')]
    name = spec.split('==')[0].replace('-', '_').lower()
    for w in wheels:
        if w.lower().startswith(name + '-'):
            return os.path.join(dest, w)
    raise SystemExit('wheel for %s not found in %s' % (spec, wheels))


def wheel_metadata(path):
    with zipfile.ZipFile(path) as z:
        meta = next(n for n in z.namelist() if n.endswith('.dist-info/METADATA'))
        return email.parser.Parser().parsestr(z.read(meta).decode('utf-8'))


def pinned_ejs(meta):
    for req in meta.get_all('Requires-Dist') or []:
        m = re.match(r'^yt-dlp-ejs\s*==\s*([0-9.]+)', req)
        if m and 'default' in req:
            return m.group(1)
    return None


def add_package(zout, wheel, top):
    with zipfile.ZipFile(wheel) as z:
        for n in z.namelist():
            if n.startswith(top + '/') and '__pycache__' not in n:
                zout.writestr(n, z.read(n))


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else latest_version()
    if not VERSION_RE.match(version):
        raise SystemExit('unexpected yt-dlp version: %r' % version)
    tmp = tempfile.mkdtemp(prefix='ytdlp-asset-')
    try:
        wheel = download_wheel('yt-dlp==' + version, tmp)
        meta = wheel_metadata(wheel)
        if meta['Version'] != version:
            raise SystemExit('wheel says %s, asked for %s' % (meta['Version'], version))
        ejs = pinned_ejs(meta)
        ejs_wheel = download_wheel('yt-dlp-ejs==' + ejs, tmp) if ejs else None

        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('__main__.py', "import yt_dlp\n\nif __name__ == '__main__':\n    yt_dlp.main()\n")
            add_package(z, wheel, 'yt_dlp')
            if ejs_wheel:
                add_package(z, ejs_wheel, 'yt_dlp_ejs')
        os.makedirs(OUT_DIR, exist_ok=True)
        with open(os.path.join(OUT_DIR, 'yt-dlp'), 'wb') as f:
            f.write(b'#!/usr/bin/env python3\n')
            f.write(buf.getvalue())
        with open(os.path.join(OUT_DIR, 'version.txt'), 'w', encoding='ascii', newline='\n') as f:
            f.write(version + '\n')
        size = os.path.getsize(os.path.join(OUT_DIR, 'yt-dlp'))
        print('bundled yt-dlp %s (%s) -> %s, %d bytes' % (version, 'with yt_dlp_ejs ' + ejs if ejs else 'no ejs', OUT_DIR, size))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    main()
