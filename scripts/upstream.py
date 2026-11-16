#!/usr/bin/env python3
"""Manually check or import an official, stable NetHack release."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import tarfile
import tempfile
import urllib.request
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
API = 'https://api.github.com/repos/NetHack/NetHack'


def fetch(url):
    headers = {'User-Agent': 'nethack-mobile-updater', 'Accept': 'application/vnd.github+json'}
    if os.environ.get('GITHUB_TOKEN') and url.startswith(API + '/'):
        headers['Authorization'] = 'Bearer ' + os.environ['GITHUB_TOKEN']
    context = ssl.create_default_context()
    # python.org's macOS installer may not have its optional CA bundle installed.
    # Use the OS bundle when the interpreter has no trusted roots; never disable TLS verification.
    if not context.get_ca_certs() and Path('/etc/ssl/cert.pem').is_file():
        context.load_verify_locations('/etc/ssl/cert.pem')
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60, context=context) as response:
        return response.read()


def tree_hash(root):
    h = hashlib.sha256()
    for path in sorted(root.rglob('*')):
        if path.is_file() and '__pycache__' not in path.relative_to(root).parts:
            h.update(path.relative_to(root).as_posix().encode() + b'\0')
            h.update(path.read_bytes())
    return h.hexdigest()


def extract(data, dest):
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        for member in archive.getmembers():
            parts = Path(member.name).parts[1:]
            if not parts:
                continue
            if member.issym() or member.islnk() or member.isdev() or '..' in parts:
                raise ValueError('Unsafe archive member: ' + member.name)
            member.name = str(Path(*parts))
            archive.extract(member, dest, filter='data')


def validate(source):
    for name in ('dat/license', 'include/winprocs.h', 'sys/libnh/libnhmain.c', 'src/allmain.c'):
        if not (source / name).is_file():
            raise ValueError('Release missing ' + name)
    if not (source / 'dat/license').read_text().startswith('                    NETHACK GENERAL PUBLIC LICENSE'):
        raise ValueError('Upstream license changed; review before importing')


def run(root, command):
    lock_path = root / 'upstream.lock.json'
    old = json.loads(lock_path.read_text())
    if command == 'verify':
        if tree_hash(root / 'vendor/nethack') != old['tree_sha256']:
            raise ValueError('Vendored NetHack differs from its lock file')
        validate(root / 'vendor/nethack')
        print('Verified ' + old['tag'])
        return
    release = json.loads(fetch(API + '/releases/latest'))
    if release['draft'] or release['prerelease']:
        raise ValueError('Refusing a draft or prerelease')
    tag = release['tag_name']
    print(f"Pinned: {old['tag']}\nLatest stable: {tag}")
    if command == 'check' or tag == old['tag']:
        return
    if tree_hash(root / 'vendor/nethack') != old['tree_sha256']:
        raise ValueError('Local vendor modifications; import aborted')
    ref = json.loads(fetch(API + '/git/ref/tags/' + urllib.parse.quote(tag, safe='')))['object']
    while ref['type'] == 'tag':
        ref = json.loads(fetch(ref['url']))['object']
    if ref['type'] != 'commit':
        raise ValueError('Tag did not resolve to a commit')
    data = fetch(API + '/tarball/' + ref['sha'])
    with tempfile.TemporaryDirectory(prefix='upstream-', dir=root) as tmp:
        stage = Path(tmp)
        source = stage / 'source'
        source.mkdir()
        extract(data, source)
        validate(source)
        if (source / 'dat/license').read_bytes() != (root / 'LICENSE').read_bytes():
            raise ValueError('License changed; review required')
        patched = stage / 'patched'
        shutil.copytree(source, patched)
        for patch in sorted((root / 'patches').glob('*.patch')):
            subprocess.run(['patch', '--batch', '--forward', '-p1', '-i', str(patch)], cwd=patched, check=True)
        # Compile and smoke-test staging before accepting the new source.
        subprocess.run(['python3', str(root / 'scripts/build.py'), 'check-upstream', '--source', str(source)], cwd=root, check=True)
        lock = dict(old, tag=tag, commit=ref['sha'], archive_sha256=hashlib.sha256(data).hexdigest(), tree_sha256=tree_hash(source))
        (stage / 'lock.json').write_text(json.dumps(lock, indent=2) + '\n')
        backup = stage / 'previous'
        (root / 'vendor/nethack').rename(backup)
        try:
            source.rename(root / 'vendor/nethack')
            os.replace(stage / 'lock.json', lock_path)
        except BaseException:
            if (root / 'vendor/nethack').exists():
                shutil.rmtree(root / 'vendor/nethack')
            backup.rename(root / 'vendor/nethack')
            raise
    print('Imported ' + tag + '. Review save compatibility and the diff before committing or shipping.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('check', 'import', 'verify'))
    args = parser.parse_args()
    try:
        run(ROOT, args.command)
    except Exception as error:
        parser.exit(1, f'upstream: {error}\n')
