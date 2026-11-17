import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import package_release


class ReleaseNoticeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.notices = {
            'NETHACK_LICENSE': 'LICENSE',
            'ANDROID_CPP_LICENSES': 'third_party/ANDROID_CPP_LICENSES.txt',
            'GODOT_LICENSE': 'vendor/godot-cpp/LICENSE.md',
            'LUA_LICENSE': 'godot/data/LUA_LICENSE',
            'NOTICE': 'NOTICE',
        }
        for name, path in self.notices.items():
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('Exact notice for ' + name)

    def archive(self, prefix, rename=False, tamper=False):
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as archive:
            for name, path in self.notices.items():
                packaged = 'license' if rename and name == 'NETHACK_LICENSE' else name
                contents = (self.root / path).read_bytes()
                if tamper and name == 'NOTICE':
                    contents += b'changed'
                archive.writestr(prefix + packaged, contents)
        output.seek(0)
        return zipfile.ZipFile(output)

    def test_apk_and_aab_retain_exact_notices(self):
        for prefix in ('assets/data/', 'assetPackInstallTime/assets/data/'):
            with self.archive(prefix) as archive, patch.object(package_release, 'ROOT', self.root):
                package_release.verify_notices(archive, prefix)

    def test_case_mismatch_is_rejected_on_any_host_filesystem(self):
        with self.archive('assets/data/', rename=True) as archive, patch.object(package_release, 'ROOT', self.root):
            with self.assertRaisesRegex(SystemExit, 'NETHACK_LICENSE'):
                package_release.verify_notices(archive, 'assets/data/')

    def test_notice_content_must_match_source(self):
        with self.archive('assets/data/', tamper=True) as archive, patch.object(package_release, 'ROOT', self.root):
            with self.assertRaisesRegex(SystemExit, 'NOTICE'):
                package_release.verify_notices(archive, 'assets/data/')


if __name__ == '__main__':
    unittest.main()
