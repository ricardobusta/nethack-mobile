#!/usr/bin/env python3
"""Export a test APK or unsigned release AAB; signing is an explicit option."""
import argparse
import os
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('format', choices=('apk', 'aab'))
    parser.add_argument('--signed', action='store_true', help='Sign an AAB using GODOT_ANDROID_KEYSTORE_RELEASE_* environment variables')
    args = parser.parse_args()
    version = subprocess.check_output(['godot', '--version'], text=True).strip()
    if not version.startswith('4.7.1.'):
        parser.error('Install the pinned Godot 4.7.1 engine and export templates')
    if args.signed:
        if args.format != 'aab':
            parser.error('--signed applies to release AAB exports; APK exports use a debug key')
        missing = [key for key in ('GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD') if not os.environ.get(key)]
        if missing:
            parser.error('Missing signing environment variables: ' + ', '.join(missing))
    (ROOT / 'dist').mkdir(exist_ok=True)
    if args.format == 'aab':
        build = ROOT / 'godot/android/build'
        if not (build / 'build.gradle').exists():
            templates = Path(os.environ.get('GODOT_EXPORT_TEMPLATES', Path.home() / 'Library/Application Support/Godot/export_templates/4.7.1.stable'))
            build.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(templates / 'android_source.zip') as archive:
                archive.extractall(build)
            (build.parent / '.build_version').write_text('4.7.1.stable\n')
            (build / 'gradlew').chmod(0o755)
        sdk = os.environ.get('NETHACK_ANDROID_SDK', os.environ.get('ANDROID_HOME', ''))
        if sdk:
            (build / 'local.properties').write_text('sdk.dir=' + sdk.replace('\\', '\\\\') + '\n')
    cfg = ROOT / 'godot/export_presets.cfg'
    original = cfg.read_text()
    try:
        if args.signed:
            cfg.write_text(original.replace('package/signed=false', 'package/signed=true'))
        command = ['godot', '--headless', '--path', str(ROOT / 'godot'), '--editor']
        if args.format == 'aab':
            command += ['--export-release', 'Android AAB', str(ROOT / 'dist/nethack-mobile-release.aab')]
        else:
            command += ['--export-debug', 'Android APK', str(ROOT / 'dist/nethack-mobile-debug.apk')]
        subprocess.run(command, cwd=ROOT, check=True)
    finally:
        if cfg.read_text() != original:
            cfg.write_text(original)
