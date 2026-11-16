import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import upstream


class UpdaterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        source = self.root / 'vendor/nethack'
        for file in ('dat/license', 'include/winprocs.h', 'sys/libnh/libnhmain.c', 'src/allmain.c'):
            p = source / file
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('original')
        license_text = (upstream.ROOT / 'LICENSE').read_bytes()
        (source / 'dat/license').write_bytes(license_text)
        (self.root / 'LICENSE').write_bytes(license_text)
        self.lock = {'tag': 'old', 'tree_sha256': upstream.tree_hash(source)}
        (self.root / 'upstream.lock.json').write_text(json.dumps(self.lock))
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode='w:gz') as archive:
            archive.add(source, arcname='release')
        self.archive = buffer.getvalue()

    def remote(self, url):
        if url.endswith('/releases/latest'):
            return json.dumps({'tag_name': 'new', 'draft': False, 'prerelease': False}).encode()
        if '/git/ref/' in url:
            return json.dumps({'object': {'type': 'commit', 'sha': 'abc'}}).encode()
        return self.archive

    def test_check_does_not_mutate(self):
        with patch.object(upstream, 'fetch', side_effect=self.remote):
            upstream.run(self.root, 'check')
        self.assertEqual(json.loads((self.root / 'upstream.lock.json').read_text()), self.lock)

    def test_import_validates_before_replacing(self):
        with patch.object(upstream, 'fetch', side_effect=self.remote), patch.object(upstream.subprocess, 'run') as check:
            upstream.run(self.root, 'import')
        check.assert_called_once()
        lock = json.loads((self.root / 'upstream.lock.json').read_text())
        self.assertEqual(lock['tag'], 'new')
        self.assertEqual(lock['archive_sha256'], hashlib.sha256(self.archive).hexdigest())

    def test_failed_checks_preserve_source_and_lock(self):
        with patch.object(upstream, 'fetch', side_effect=self.remote), patch.object(upstream.subprocess, 'run', side_effect=RuntimeError('conflict')):
            with self.assertRaises(RuntimeError):
                upstream.run(self.root, 'import')
        self.assertEqual(upstream.tree_hash(self.root / 'vendor/nethack'), self.lock['tree_sha256'])
        self.assertEqual(json.loads((self.root / 'upstream.lock.json').read_text()), self.lock)

    def test_download_failure_preserves_state(self):
        with patch.object(upstream, 'fetch', side_effect=OSError('offline')):
            with self.assertRaises(OSError):
                upstream.run(self.root, 'import')
        self.assertEqual(json.loads((self.root / 'upstream.lock.json').read_text()), self.lock)

    def test_modified_vendor_rejected(self):
        (self.root / 'vendor/nethack/src/allmain.c').write_text('local edit')
        with patch.object(upstream, 'fetch', side_effect=self.remote):
            with self.assertRaisesRegex(ValueError, 'Local vendor'):
                upstream.run(self.root, 'import')

    def test_archive_traversal_rejected(self):
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode='w:gz') as archive:
            entry = tarfile.TarInfo('release/../../escape')
            entry.size = 1
            archive.addfile(entry, io.BytesIO(b'x'))
        with self.assertRaises(ValueError):
            upstream.extract(buffer.getvalue(), self.root / 'extract')


if __name__ == '__main__':
    unittest.main()
