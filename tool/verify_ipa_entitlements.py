"""Checks a built IPA for an entitlement, in both places iOS looks.

  python -I tool/verify_ipa_entitlements.py path/to/App.ipa \
      [--key com.apple.developer.applesignin]

1. The app binary's signed entitlements — what the app actually requests at
   runtime. Read straight from the Mach-O code signature (LC_CODE_SIGNATURE ->
   SuperBlob -> entitlements blob), so no macOS `codesign` is needed.
2. Payload/*.app/embedded.mobileprovision — what the provisioning profile
   allows. Decoded with `openssl smime -verify -noverify` when openssl is on
   PATH, else by reading the plist out of the CMS envelope.

A capability works only when BOTH contain the key. Exit 0 if they do.
Born from OurGarage 1.0.7, whose profile allowed Sign in with Apple but whose
binary was never signed with it (ASAuthorizationError 1000 on device).
"""
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import zipfile

CS_MAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CS_MAGIC_EMBEDDED_ENTITLEMENTS = 0xFADE7171       # XML plist
CS_MAGIC_EMBEDDED_DER_ENTITLEMENTS = 0xFADE7172   # DER (newer signatures)
LC_CODE_SIGNATURE = 0x1D
FAT_MAGIC = 0xCAFEBABE
MH_MAGIC_64 = 0xFEEDFACF
MH_MAGIC = 0xFEEDFACE


def _slices(binary):
    """Offsets of each Mach-O slice (one for thin, several for fat)."""
    (magic,) = struct.unpack_from('>I', binary, 0)
    if magic == FAT_MAGIC:
        (count,) = struct.unpack_from('>I', binary, 4)
        return [struct.unpack_from('>IIIII', binary, 8 + 20 * i)[2] for i in range(count)]
    return [0]


def signed_entitlements(binary):
    """Entitlement dicts found in every slice's code signature."""
    found = []
    for base in _slices(binary):
        (magic,) = struct.unpack_from('<I', binary, base)
        if magic not in (MH_MAGIC_64, MH_MAGIC):
            raise ValueError(f'not a little-endian Mach-O slice at {base:#x}')
        is64 = magic == MH_MAGIC_64
        ncmds = struct.unpack_from('<I', binary, base + 16)[0]
        offset = base + (32 if is64 else 28)
        sig = None
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from('<II', binary, offset)
            if cmd == LC_CODE_SIGNATURE:
                dataoff, datasize = struct.unpack_from('<II', binary, offset + 8)
                sig = binary[base + dataoff: base + dataoff + datasize]
            offset += cmdsize
        if sig is None:
            found.append(None)  # unsigned slice
            continue
        magic, _length, count = struct.unpack_from('>III', sig, 0)
        if magic != CS_MAGIC_EMBEDDED_SIGNATURE:
            raise ValueError('code signature is not an embedded SuperBlob')
        entitlements = {}
        for i in range(count):
            _type, blob_off = struct.unpack_from('>II', sig, 12 + 8 * i)
            blob_magic, blob_len = struct.unpack_from('>II', sig, blob_off)
            if blob_magic == CS_MAGIC_EMBEDDED_ENTITLEMENTS:
                entitlements = plistlib.loads(sig[blob_off + 8: blob_off + blob_len])
            elif blob_magic == CS_MAGIC_EMBEDDED_DER_ENTITLEMENTS and not entitlements:
                # Keys are UTF8 strings in the DER; enough to test presence.
                der = sig[blob_off + 8: blob_off + blob_len]
                entitlements = {k.decode(): '<DER>' for k in re.findall(rb'[a-z][\w.-]+\.[\w.-]+', der)}
        found.append(entitlements)
    return found


def profile_entitlements(profile_bytes):
    """The Entitlements dict of a .mobileprovision."""
    xml = None
    if shutil.which('openssl'):
        result = subprocess.run(
            ['openssl', 'smime', '-inform', 'der', '-verify', '-noverify'],
            input=profile_bytes, capture_output=True)
        if result.returncode == 0 and result.stdout.lstrip().startswith(b'<?xml'):
            xml = result.stdout
    if xml is None:
        match = re.search(rb'<\?xml.*?</plist>', profile_bytes, re.S)
        if not match:
            raise ValueError('no plist found in embedded.mobileprovision')
        xml = match.group(0)
    plist = plistlib.loads(xml)
    return plist.get('Entitlements', {}), plist


def main(argv):
    if not argv or argv[0].startswith('-'):
        sys.exit(__doc__)
    ipa = argv[0]
    key = argv[argv.index('--key') + 1] if '--key' in argv else 'com.apple.developer.applesignin'

    with zipfile.ZipFile(ipa) as z:
        apps = sorted({n.split('/')[1] for n in z.namelist()
                       if n.startswith('Payload/') and n.split('/')[1].endswith('.app')})
        if len(apps) != 1:
            sys.exit(f'expected one .app in Payload/, found {apps}')
        app = apps[0]
        info = plistlib.loads(z.read(f'Payload/{app}/Info.plist'))
        executable = info['CFBundleExecutable']
        binary = z.read(f'Payload/{app}/{executable}')
        profile = z.read(f'Payload/{app}/embedded.mobileprovision')

    print(f'app: {app}  bundle: {info.get("CFBundleIdentifier")}  '
          f'version: {info.get("CFBundleShortVersionString")} ({info.get("CFBundleVersion")})')

    slices = signed_entitlements(binary)
    ok_binary = bool(slices) and all(s is not None and key in s for s in slices)
    for i, ents in enumerate(slices):
        if ents is None:
            print(f'binary slice {i}: UNSIGNED')
        else:
            print(f'binary slice {i}: signed entitlements = {sorted(ents)}')
            if key in ents:
                print(f'  {key} = {ents[key]}')

    prof_ents, prof = profile_entitlements(profile)
    ok_profile = key in prof_ents
    print(f'profile: "{prof.get("Name")}"  created {prof.get("CreationDate")}  '
          f'expires {prof.get("ExpirationDate")}  '
          f'type: {"development/ad hoc" if "ProvisionedDevices" in prof else "App Store / enterprise"}')
    print(f'profile entitlements = {sorted(prof_ents)}')
    if ok_profile:
        print(f'  {key} = {prof_ents[key]}')

    print()
    print(f'{key} in signed binary entitlements: {"YES" if ok_binary else "NO"}')
    print(f'{key} in embedded.mobileprovision:   {"YES" if ok_profile else "NO"}')
    return 0 if ok_binary and ok_profile else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
