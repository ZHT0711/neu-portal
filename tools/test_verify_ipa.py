import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

from verify_ipa import verify_ipa


class VerifyIpaTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'test.ipa'
        self.entries = {
            'Payload/Runner.app/Info.plist': plistlib.dumps({
                'CFBundleIdentifier': 'cn.edu.neu.neuPortal',
                'CFBundleExecutable': 'Runner', 'CFBundleVersion': '6',
                'CFBundleShortVersionString': '1.0.0',
                'MinimumOSVersion': '15.0', 'CFBundlePackageType': 'APPL',
            }, fmt=plistlib.FMT_BINARY),
            'Payload/Runner.app/Runner': b'\xcf\xfa\xed\xfe' + bytes(32),
            'Payload/Runner.app/Frameworks/App.framework/App': b'\xca\xfe\xba\xbe' + bytes(32),
            'Payload/Runner.app/Frameworks/Flutter.framework/Flutter': b'\xcf\xfa\xed\xfe' + bytes(32),
            'Payload/Runner.app/Frameworks/App.framework/flutter_assets/AssetManifest.bin': b'assets',
        }

    def write_ipa(self):
        with zipfile.ZipFile(self.path, 'w') as archive:
            for name, data in self.entries.items():
                archive.writestr(name, data)

    def test_valid(self):
        self.write_ipa()
        result = verify_ipa(self.path)
        self.assertEqual(result['entries'], 5)
        self.assertEqual(len(result['sha256']), 64)

    def test_truncated_download(self):
        self.write_ipa()
        self.path.write_bytes(self.path.read_bytes()[:-22])
        with self.assertRaisesRegex(ValueError, 'Missing ZIP end'):
            verify_ipa(self.path)

    def test_error_page_saved_as_ipa(self):
        self.path.write_text('<html>Bad Gateway</html>')
        with self.assertRaisesRegex(ValueError, 'not an IPA'):
            verify_ipa(self.path)

    def test_bad_crc(self):
        self.write_ipa()
        self.path.write_bytes(self.path.read_bytes().replace(b'assets', b'broken', 1))
        with self.assertRaisesRegex(ValueError, 'ZIP CRC failed'):
            verify_ipa(self.path)

    def test_missing_framework(self):
        del self.entries['Payload/Runner.app/Frameworks/Flutter.framework/Flutter']
        self.write_ipa()
        with self.assertRaisesRegex(ValueError, 'Missing executable'):
            verify_ipa(self.path)

    def test_invalid_executable(self):
        self.entries['Payload/Runner.app/Runner'] = b'not a binary'
        self.write_ipa()
        with self.assertRaisesRegex(ValueError, 'Invalid Mach-O'):
            verify_ipa(self.path)

    def test_outer_zip_is_not_ipa(self):
        self.entries = {'download.ipa': b'an inner IPA'}
        self.write_ipa()
        with self.assertRaisesRegex(ValueError, 'inside Payload'):
            verify_ipa(self.path)


if __name__ == '__main__':
    unittest.main()
