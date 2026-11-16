#!/usr/bin/env python3
"""Bundle matching committed source, binary checksums, and release metadata."""
import hashlib
import gzip
import io
import json
from pathlib import Path
import subprocess
import zipfile
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]

if __name__ == '__main__':
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip():
        raise SystemExit('Commit the milestone before creating its matching source release.')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dist = ROOT / 'dist'
    info = json.loads((ROOT / 'godot/data/build.json').read_text())
    if info['source_revision'] != revision:
        raise SystemExit('Rebuild from the current commit before packaging.')
    apk = dist / 'nethack-mobile-debug.apk'
    if apk.exists():
        with zipfile.ZipFile(apk) as archive:
            embedded = json.loads(archive.read('assets/data/build.json'))
            if embedded != info:
                raise SystemExit('APK metadata differs from the current build; export it again.')
            for name in archive.namelist():
                if name.endswith('/libnethack_mobile.so') and ('nethack-mobile-source:' + revision).encode() not in archive.read(name):
                    raise SystemExit('APK native bridge is stale; rebuild it before packaging.')
    aab = dist / 'nethack-mobile-release.aab'
    if aab.exists():
        with zipfile.ZipFile(aab) as archive:
            candidates = [p for p in archive.namelist() if p.endswith('/assets/data/build.json')]
            if not candidates or json.loads(archive.read(candidates[0])) != info:
                raise SystemExit('AAB metadata differs from the current build; export it again.')
            for name in archive.namelist():
                if name.endswith('/libnethack_mobile.so') and ('nethack-mobile-source:' + revision).encode() not in archive.read(name):
                    raise SystemExit('AAB native bridge is stale; rebuild both ABIs before packaging.')
    archive = dist / ('nethack-mobile-' + info['port_version'] + '-source.tar.gz')
    with tempfile.TemporaryFile() as source:
        subprocess.run(['git', 'archive', '--format=tar', '--prefix=nethack-mobile/', 'HEAD'], cwd=ROOT, stdout=source, check=True)
        source.seek(0)
        expected = {'nethack': json.loads((ROOT / 'upstream.lock.json').read_text())['tree_sha256']}
        expected.update({name: dep['tree_sha256'] for name, dep in json.loads((ROOT / 'dependencies.lock.json').read_text()).items()})
        with tarfile.open(fileobj=source, mode='r:') as snapshot:
            members = sorted((m for m in snapshot.getmembers() if m.isfile()), key=lambda m: m.name)
            for name, checksum in expected.items():
                prefix = 'nethack-mobile/vendor/' + name + '/'
                digest = hashlib.sha256()
                for member in members:
                    if member.name.startswith(prefix):
                        relative = member.name[len(prefix):]
                        if Path(relative).name == '.DS_Store' or '__pycache__' in Path(relative).parts:
                            continue
                        digest.update(relative.encode() + b'\0')
                        digest.update(snapshot.extractfile(member).read())
                if digest.hexdigest() != checksum:
                    raise SystemExit('Committed vendor snapshot differs from lock: ' + name + '. Include original files ignored by upstream before packaging.')
        source.seek(0)
        with tarfile.open(fileobj=source, mode='a') as tar:
            entry = tarfile.TarInfo('nethack-mobile/SOURCE_REVISION')
            contents = (revision + '\n').encode(); entry.size = len(contents)
            tar.addfile(entry, io.BytesIO(contents))
        source.seek(0)
        with archive.open('wb') as output, gzip.GzipFile(fileobj=output, mode='wb', mtime=0) as compressed:
            import shutil
            shutil.copyfileobj(source, compressed)
    release = dict(info, upstream=json.loads((ROOT / 'upstream.lock.json').read_text()), signing='APK uses debug key; AAB is unsigned unless exported with --signed', publication='Not published')
    (dist / 'release.json').write_text(json.dumps(release, indent=2) + '\n')
    checksums = []
    for file in sorted(dist.iterdir()):
        if file.is_file() and file.name != 'SHA256SUMS':
            checksums.append(hashlib.sha256(file.read_bytes()).hexdigest() + '  ' + file.name)
    (dist / 'SHA256SUMS').write_text('\n'.join(checksums) + '\n')
    print('Packaged source and checksums for ' + revision)
