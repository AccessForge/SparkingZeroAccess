"""Exercise narration packaging with temporary PCM fixtures, never real voice data."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import wave

BUILDER = Path(__file__).resolve().parents[1] / 'helpers' / 'Build-Descriptions.py'


class DescriptionBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.output = self.root / 'output'

    def tearDown(self):
        self.temporary.cleanup()

    def film(self, number=2, fps=30, frames=2557):
        folder = self.root / ('op' + str(number))
        (folder / 'narration').mkdir(parents=True)
        cue_id = f'op{number}-01'
        wav = folder / 'narration' / (cue_id + '.wav')
        # 200 ms PCM24 fixture. This only tests build integrity, not recognition.
        with wave.open(str(wav), 'wb') as audio:
            audio.setparams((1, 3, 24000, 0, 'NONE', 'not compressed'))
            audio.writeframes(b'\x00' * 4800 * 3)
        record = {'text': 'Fixture narration.',
                  'wave_sha256': hashlib.sha256(wav.read_bytes()).hexdigest(),
                  'checks': {'exact': True, 'failures': []}}
        wav.with_suffix('.json').write_text(json.dumps(record), encoding='utf-8')
        script = {'movie': f'Korat_OP{number}_1K_CP.usm', 'fps': fps, 'totalFrames': frames,
                  'aliases': [f'Korat_OP{number}_2K_CP.usm', f'Korat_OP{number}_4K_CP.usm'],
                  'cues': [{'id': cue_id, 'start': 1, 'end': 2, 'text': record['text']}]}
        self.save(folder, script)
        return folder, script

    def save(self, folder, script):
        (folder / 'opening-cues.json').write_text(json.dumps(script), encoding='utf-8')

    def run_build(self, *folders, extra=()):
        args = [sys.executable, str(BUILDER), '--output', str(self.output)]
        for folder in folders:
            args.extend(['--source', str(folder)])
        return subprocess.run(args + list(extra), capture_output=True, text=True)

    def test_multiple_movies_keep_their_own_metadata_and_clips(self):
        op2, _ = self.film(2, 30, 2557)
        op3, _ = self.film(3, 24, 2400)
        result = self.run_build(op2, op3)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        sheet = json.loads((self.output / 'AudioDescription' / 'cue-sheet.json').read_text())
        self.assertEqual([(f['fps'], f['totalFrames']) for f in sheet['films']], [(30, 2557), (24, 2400)])
        manifest = (self.output / 'description_manifest.lua').read_text()
        self.assertIn('fps = 24, totalFrames = 2400', manifest)
        for film in sheet['films']:
            for alias in film['aliases']:
                self.assertIn(f'films["{alias.lower()}"] = films["{film["movie"].lower()}"]', manifest)
            for row in film['cues']:
                p = self.output / row['file']
                self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(), row['sha256'])
                with wave.open(str(p)) as audio:
                    self.assertEqual((audio.getnchannels(), audio.getsampwidth()), (1, 2))
                    self.assertEqual(audio.getnframes() / audio.getframerate(), row['duration'])
        self.assertNotIn(str(self.root), manifest + json.dumps(sheet))

    def test_single_movie_preserves_existing_cue_sheet_shape(self):
        folder, _ = self.film(3)
        result = self.run_build(folder)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        sheet = json.loads((self.output / 'AudioDescription' / 'cue-sheet.json').read_text())
        self.assertEqual(sheet['cues'][0]['id'], 'op3-01')
        self.assertNotIn('films', sheet)

    def test_different_movie_cannot_be_an_alias(self):
        folder, script = self.film()
        script['aliases'] = ['Korat_OP3_4K_CP.usm']
        self.save(folder, script)
        result = self.run_build(folder)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('same movie', result.stderr)
        self.assertFalse(self.output.exists())

    def test_duplicate_identity_is_rejected_before_output(self):
        folder, _ = self.film()
        result = self.run_build(folder, folder)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Duplicate movie', result.stderr)
        self.assertFalse(self.output.exists())

    def test_changed_audio_or_text_cannot_use_an_old_check(self):
        folder, script = self.film()
        script['cues'][0]['text'] = 'Changed narration.'
        self.save(folder, script)
        result = self.run_build(folder)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('changed after checking', result.stdout)
        self.assertFalse(self.output.exists())

    def test_audio_must_fit_with_polling_headroom(self):
        folder, script = self.film()
        script['cues'][0]['end'] = 1.3
        self.save(folder, script)
        result = self.run_build(folder)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exceeds', result.stdout)
        self.assertFalse(self.output.exists())

    def test_invalid_movie_or_scene_time_is_rejected(self):
        folder, script = self.film()
        for field, value in [('fps', 0), ('totalFrames', 0.5)]:
            with self.subTest(field=field):
                invalid = {**script, field: value}
                self.save(folder, invalid)
                self.assertNotEqual(self.run_build(folder).returncode, 0)
        script['cues'][0]['start'] = float('nan')
        self.save(folder, script)
        result = self.run_build(folder)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('invalid scene timing', result.stdout)
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
