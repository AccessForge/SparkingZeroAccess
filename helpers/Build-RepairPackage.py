"""Build the standalone, tested loader layout without writing to a game install."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path, PurePosixPath

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True, help='New or empty output directory')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
output = args.output.resolve()
archive_path = output.with_suffix('.zip')
if archive_path.exists() or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
    parser.error('Choose an empty output directory without an existing ZIP beside it.')
output.mkdir(parents=True, exist_ok=True)
payload = output / 'Win64'

for dependency in ['ue4ss-tested-1152.zip', 'utoc-bypass.zip']:
    with zipfile.ZipFile(root / 'deps' / dependency) as archive:
        for member in archive.infolist():
            name = PurePosixPath(member.filename.replace('\\', '/'))
            if member.is_dir() or name.as_posix() == 'FILE-HASHES.json':
                continue
            if name.is_absolute() or '..' in name.parts or ':' in name.as_posix():
                raise ValueError(f'Unsafe dependency entry: {member.filename}')
            destination = payload.joinpath(*name.parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(archive.read(member))

runtime = payload / 'ue4ss/Mods/SparkingZeroAccess/Scripts'
shutil.copytree(root / 'SparkingZeroAccess', runtime)
assert (runtime / 'audio_bridge.dll').is_file()
assert len(list((runtime / 'AudioDescription').glob('*.wav'))) == 37
(payload / 'ue4ss/Mods/mods.txt').write_text('SparkingZeroAccess : 1\n', encoding='utf-8')
for name in ['Install.cmd', 'Install-Repair.ps1', 'Game-Install-Location.ps1']:
    shutil.copy2(root / 'helpers' / name, output / name)
(output / 'README.md').write_text('''# SparkingZeroAccess standalone repair

Close Sparking! ZERO, extract the entire ZIP, and run Install.cmd.
The installer finds Steam libraries automatically, offers a numbered choice for
multiple installs or a Windows file picker if needed, preserves other mods,
backs up replaced files, and refuses a running game. Keep every file together.

This build includes the tested UE4SS 3.0.1-1152 loader and configuration, speech
dependencies, the accessibility reader, and 37 authorized synthetic narration
clips. It was exercised on game version 3022.021.003.012.015; other builds are
unverified. Settings and saves remain under the game's control.

F6 reads the screen, F7/F8 review individual items, and F9 toggles automatic
subtitle speech. F9 off also mutes text-only story lines in recognized dialogue
windows; F6 still reviews them. Tutorial instructions repeat every 20 seconds,
and the skill guide reads once per ki-charge hold with F6 repeat available.

Source, tests and known limits:
https://github.com/AccessForge/SparkingZeroAccess
''', encoding='utf-8')
records = []
for path in sorted(output.rglob('*')):
    if path.is_file():
        data = path.read_bytes()
        records.append({'path': path.relative_to(output).as_posix(), 'bytes': len(data),
                        'sha256': hashlib.sha256(data).hexdigest().upper()})
(output / 'FILE-HASHES.json').write_text(json.dumps(records, indent=2) + '\n', encoding='utf-8')
with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(output.rglob('*')):
        if path.is_file():
            archive.write(path, path.relative_to(output).as_posix())
with zipfile.ZipFile(archive_path) as archive:
    assert archive.testzip() is None
    for record in records:
        data = archive.read(record['path'])
        assert len(data) == record['bytes']
        assert hashlib.sha256(data).hexdigest().upper() == record['sha256']
print(f'Built {archive_path.name}: {len(records)} verified files')
