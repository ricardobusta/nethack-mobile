#!/usr/bin/env python3
"""Reproducible host tools, native engine, and Android builds."""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import selectors
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def call(*args, cwd=ROOT):
    subprocess.run([str(x) for x in args], cwd=cwd, check=True)


def prepare(source, workspace, data):
    work = workspace / 'upstream'
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(source, work)
    (work / 'include/nhlua.h').write_text('#include "lua.h"\n#include "lualib.h"\n#include "lauxlib.h"\n')
    for patch in sorted((ROOT / 'patches').glob('*.patch')):
        call('patch', '--batch', '--forward', '-p1', '-i', patch, cwd=work)
    tools = workspace / 'tools'
    call('cmake', '-S', ROOT, '-B', tools, '-G', 'Ninja', '-DNH_TOOLS_ONLY=ON', '-DNH_SOURCE=' + str(work))
    call('cmake', '--build', tools, '--target', 'makedefs', '-j', '8')
    for option in ('p', 'o', 'd', 'r', 'h', '1', '2', '3'):
        call(tools / 'makedefs', '-' + option, cwd=work / 'util')
    call('cmake', '--build', tools, '--target', 'tilemap', '-j', '8')
    call(tools / 'tilemap', cwd=work / 'util')
    if data.exists():
        shutil.rmtree(data)
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
    version_header = (work / 'include/patchlevel.h').read_text()
    versions = [re.search(r'^#define\s+' + key + r'\s+(\d+)', version_header, re.M).group(1) for key in ('VERSION_MAJOR', 'VERSION_MINOR', 'PATCHLEVEL', 'EDITLEVEL')]
    version = '.'.join(versions[:3])
    revision = (ROOT / 'SOURCE_REVISION').read_text().strip() if (ROOT / 'SOURCE_REVISION').exists() else subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() if (ROOT / '.git').exists() else 'unversioned'
    (data / 'build.json').write_text(json.dumps({'engine_version': version, 'save_namespace': version + '-' + versions[3] + '-mobile1', 'port_version': '0.1.0', 'source_revision': revision}, indent=2))
    for name, path in [('NETHACK_LICENSE', ROOT / 'LICENSE'), ('NOTICE', ROOT / 'NOTICE'),
                       ('ANDROID_CPP_LICENSES', ROOT / 'third_party/ANDROID_CPP_LICENSES.txt'),
                       ('GODOT_LICENSE', ROOT / 'vendor/godot-cpp/LICENSE.md'),
                       ('LUA_README.html', ROOT / 'vendor/lua/doc/readme.html')]:
        shutil.copy2(path, data / name)
    lua_header = (ROOT / 'vendor/lua/src/lua.h').read_text()
    license_block = lua_header[lua_header.rfind('/***'):].split('*/', 1)[0]
    (data / 'LUA_LICENSE').write_text('\n'.join(line.lstrip('/* ') for line in license_block.splitlines()).strip() + '\n')
    from tiles import convert
    tile_count = convert(work / 'win/share', data / 'tiles.png')
    expected_tiles = int(re.search(r'total_tiles_used = (\d+)', (work / 'src/tile.c').read_text()).group(1))
    if tile_count < expected_tiles:
        raise RuntimeError(f'Incomplete tileset: {tile_count} tiles for {expected_tiles} mapped tiles')
    info = json.loads((data / 'build.json').read_text())
    info['tile_count'] = tile_count
    assets = hashlib.sha256()
    for file in sorted(data.iterdir()):
        if file.is_file() and file.name != 'build.json':
            assets.update(file.name.encode() + b'\0')
            assets.update(file.read_bytes())
    info['assets_sha256'] = assets.hexdigest()
    (data / 'build.json').write_text(json.dumps(info, indent=2))
    (data / 'files.json').write_text(json.dumps(sorted(p.name for p in data.iterdir() if p.is_file() and p.name != 'files.json')))
    return work


def build(target, work, godot=True, workspace=ROOT / 'build'):
    folder = workspace / target
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
    with contextlib.ExitStack() as stack:
        workspace = Path(stack.enter_context(tempfile.TemporaryDirectory(prefix='nh-upstream-check-'))) if args.target == 'check-upstream' else ROOT / 'build'
        workspace.mkdir(parents=True, exist_ok=True)
        data = workspace / 'data' if args.target == 'check-upstream' else ROOT / 'godot/data'
        work = workspace / 'upstream' if args.skip_prepare else prepare(args.source, workspace, data)
        if args.target != 'prepare':
            folder = build('host' if args.target == 'check-upstream' else args.target, work, not args.engine_only and args.target != 'check-upstream', workspace)
            if args.target in ('host', 'check-upstream'):
                with tempfile.TemporaryDirectory(prefix='nh-smoke-') as tmp:
                    game = Path(tmp) / 'game'
                    shutil.copytree(data, game)
                    (game / 'save').mkdir()
                    call(folder / 'nh_smoke', game)
                    with (workspace / 'crash-test.log').open('w') as log:
                        process = subprocess.Popen([str(folder / 'nh_smoke'), str(game), '--checkpoint'], stdout=subprocess.PIPE, stderr=log, text=True)
                        try:
                            with selectors.DefaultSelector() as ready:
                                ready.register(process.stdout, selectors.EVENT_READ)
                                if not ready.select(60) or process.stdout.readline().strip() != 'CHECKPOINT_READY':
                                    raise RuntimeError('Crash test did not reach a safe checkpoint')
                        finally:
                            process.kill()
                            process.wait()
                    call(folder / 'nh_smoke', game)
                    print('Process-death checkpoint recovery passed.')
                    call(folder / 'nh_smoke', game, '--save-failure')
                    print('Save-failure reporting and recovery passed.')
