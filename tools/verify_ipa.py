"""Verify a Flutter device IPA before uploading or releasing it (stdlib only)."""

import argparse
import hashlib
import plistlib
import struct
import zipfile
from pathlib import Path, PurePosixPath


def verify_ipa(path):
    path = Path(path)
    # Require the classic ZIP end record used by sideloading tools. The nightly
    # IPA is small enough that ZIP64 and multi-disk archives are unnecessary.
    with path.open('rb') as stream:
        stream.seek(0, 2)
        size = stream.tell()
        stream.seek(max(0, size - 65557))
        tail = stream.read()
    offset = tail.rfind(b'PK\x05\x06')
    if offset < 0 or len(tail) - offset < 22:
        raise ValueError('Missing ZIP end of central directory: incomplete download or not an IPA')
    _, disk, start_disk, count, total, directory_size, directory_offset, comment_size = struct.unpack_from(
        '<4s4H2LH', tail, offset
    )
    end_offset = size - len(tail) + offset
    if (disk or start_disk or count != total or total == 65535
            or directory_offset + directory_size != end_offset
            or offset + 22 + comment_size != len(tail)):
        raise ValueError('Invalid ZIP central directory or truncated archive')

    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate entries in IPA')
        if any(PurePosixPath(n).is_absolute() or '..' in PurePosixPath(n).parts
               or '\\' in n for n in names):
            raise ValueError('Unsafe entry path in IPA')
        bad = archive.testzip()
        if bad:
            raise ValueError(f'ZIP CRC failed: {bad}')
        apps = [n for n in names if n.startswith('Payload/')
                and n.endswith('.app/Info.plist') and n.count('/') == 2]
        if len(apps) != 1:
            raise ValueError('Expected one app directly inside Payload/')
        app = apps[0].removesuffix('Info.plist')
        info = plistlib.loads(archive.read(apps[0]))
        for key in ('CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleVersion',
                    'CFBundleShortVersionString', 'MinimumOSVersion'):
            if not isinstance(info.get(key), str) or not info[key] or '$(' in info[key]:
                raise ValueError(f'Missing or unresolved {key}')
        if info.get('CFBundlePackageType') != 'APPL':
            raise ValueError('Payload is not an application bundle')
        executable = info['CFBundleExecutable']
        if '/' in executable or '\\' in executable:
            raise ValueError('Invalid CFBundleExecutable')
        # Device Mach-O, fat Mach-O, or 64-bit fat Mach-O headers.
        magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
                 b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
                 b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}
        for name in (executable, 'Frameworks/App.framework/App',
                     'Frameworks/Flutter.framework/Flutter'):
            entry = app + name
            if entry not in names:
                raise ValueError(f'Missing executable: {entry}')
            with archive.open(entry) as stream:
                if stream.read(4) not in magic:
                    raise ValueError(f'Invalid Mach-O: {entry}')
        assets = app + 'Frameworks/App.framework/flutter_assets/AssetManifest.bin'
        if assets not in names or not archive.getinfo(assets).file_size:
            raise ValueError('Missing Flutter assets')

    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return {'file': path.name, 'bytes': size, 'entries': total, 'sha256': digest}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    args = parser.parse_args()
    try:
        result = verify_ipa(args.ipa)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        parser.exit(1, f'IPA validation failed: {error}\n')
    print(f"IPA OK: {result['bytes']} bytes, {result['entries']} entries")
    print(f"{result['sha256']}  {result['file']}")
