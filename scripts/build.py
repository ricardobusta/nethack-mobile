#!/usr/bin/env python3
"""Reproducible host tools, native engine, and Android builds."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def call(*args, cwd=ROOT):
    subprocess.run([str(x) for x in args], cwd=cwd, check=True)


def prepare(source):
    work = ROOT / 'build/upstream'
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(source, work)
    (work / 'include/nhlua.h').write_text('#include "lua.h"\n#include "lualib.h"\n#include "lauxlib.h"\n')
    for patch in sorted((ROOT / 'patches').glob('*.patch')):
        call('patch', '--batch', '--forward', '-p1', '-i', patch, cwd=work)
    tools = ROOT / 'build/tools'
    call('cmake', '-S', ROOT, '-B', tools, '-G', 'Ninja', '-DNH_TOOLS_ONLY=ON', '-DNH_SOURCE=' + str(work))
    call('cmake', '--build', tools, '--target', 'makedefs', '-j', '8')
    for option in ('p', 'o', 'd', 'r', 'h', '1', '2', '3'):
        call(tools / 'makedefs', '-' + option, cwd=work / 'util')
    call('cmake', '--build', tools, '--target', 'tilemap', '-j', '8')
    call(tools / 'tilemap', cwd=work / 'util')
    data = ROOT / 'godot/data'
    data.mkdir(parents=True, exist_ok=True)
    # DLB also supports loose data files. Ship them all to avoid a platform-specific archive.
    for p in (work / 'dat').iterdir():
        if p.is_file():
            shutil.copy2(p, data / p.name)
    # Revision-1 DLB format, as documented in upstream src/dlb.c.
    files = sorted(p for p in (work / 'dat').iterdir() if p.is_file() and p.name != 'nhdat')
    names = ['__directory__'] + [p.name for p in files]
    directory_size = 40 + sum(11 + len(name) for name in names)
    offset = directory_size
    directory = f' __directory__ {0:8d}\n'
    content = bytearray()
    for file in files:
        directory += f' {file.name} {offset:8d}\n'
        blob = file.read_bytes()
        content.extend(blob)
        offset += len(blob)
    header = f'{1:3d} {len(names):8d} {sum(len(n) + 1 for n in names):8d} {directory_size:8d} {offset:8d}\n'
    assert len((header + directory).encode()) == directory_size
    (data / 'nhdat').write_bytes((header + directory).encode() + content)
    (data / 'sysconf').write_text('WIZARDS=*\nEXPLORERS=*\nOPTIONS=!legacy,autopickup,travel,!news\n')
    for name, path in [('LICENSE', ROOT / 'LICENSE'), ('NOTICE', ROOT / 'NOTICE'),
                       ('GODOT_LICENSE', ROOT / 'vendor/godot-cpp/LICENSE.md'),
                       ('LUA_README.html', ROOT / 'vendor/lua/doc/readme.html')]:
        shutil.copy2(path, data / name)
    call(sys.executable, ROOT / 'scripts/tiles.py', work / 'win/share', data / 'tiles.png')
    (data / 'files.json').write_text(json.dumps(sorted(p.name for p in data.iterdir() if p.is_file() and p.name != 'files.json')))
    return work


def build(target, work, godot=True):
    folder = ROOT / 'build' / target
    flags = ['-DNH_SOURCE=' + str(work), '-DNH_GODOT=' + ('ON' if godot else 'OFF'), '-DCMAKE_BUILD_TYPE=RelWithDebInfo']
    if target.startswith('android-'):
        ndk = os.environ.get('ANDROID_NDK_HOME')
        if not ndk:
            raise RuntimeError('Set ANDROID_NDK_HOME to an installed NDK (r27 or later)')
        flags += ['-DCMAKE_TOOLCHAIN_FILE=' + ndk + '/build/cmake/android.toolchain.cmake',
                  '-DANDROID_ABI=' + target.removeprefix('android-'), '-DANDROID_PLATFORM=android-26', '-DANDROID_STL=c++_static']
    call('cmake', '-S', ROOT, '-B', folder, '-G', 'Ninja', *flags)
    call('cmake', '--build', folder, '-j', '8')
    return folder


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', choices=('prepare', 'host', 'android-arm64-v8a', 'android-x86_64', 'check-upstream'))
    parser.add_argument('--source', type=Path, default=ROOT / 'vendor/nethack')
    parser.add_argument('--skip-prepare', action='store_true')
    parser.add_argument('--engine-only', action='store_true')
    args = parser.parse_args()
    work = ROOT / 'build/upstream' if args.skip_prepare else prepare(args.source)
    if args.target != 'prepare':
        folder = build('host' if args.target == 'check-upstream' else args.target, work, not args.engine_only and args.target != 'check-upstream')
        if args.target in ('host', 'check-upstream'):
            with tempfile.TemporaryDirectory(prefix='nh-smoke-') as tmp:
                game = Path(tmp) / 'game'
                shutil.copytree(ROOT / 'godot/data', game)
                (game / 'save').mkdir()
                call(folder / 'nh_smoke', game)
