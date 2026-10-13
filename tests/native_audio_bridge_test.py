"""Exercise the real Windows audio backend using a silent WAV outside the game."""
from pathlib import Path
import time
import wave
from lupa.lua54 import LuaRuntime, LuaError

module_dir = Path(__file__).resolve().parents[1] / "audio_bridge" / "bin"
clip = module_dir / "bridge_silence.wav"
with wave.open(str(clip), "wb") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(24000)
    f.writeframes(bytes(24000 * 2 * 2))
runtime = LuaRuntime(unpack_returned_tuples=True)
load = runtime.eval("function(path) local f,e=package.loadlib(path,'luaopen_audio_bridge'); assert(f,e); return f() end")
audio = load(str(module_dir / "audio_bridge.dll"))
assert audio.mode() == "closed"
assert audio.play("bridge_silence.wav") is True
time.sleep(0.05)
assert audio.mode() == "playing"
assert audio.pause() is True
assert audio.mode() == "paused"
assert audio.resume() is True
assert audio.mode() == "playing"
assert audio.stop() is True and audio.mode() == "closed"
print("PASS: native WAV playback, pause, resume and stop")
ok, message = audio.play("missing-cue.wav")
assert ok is False and message and audio.mode() == "closed"
print("PASS: missing audio reports a recoverable error")
for bad in ("../other.wav", "C:\\other.wav", 'bad"name.wav'):
    try:
        audio.play(bad)
        raise AssertionError("bad path accepted")
    except LuaError:
        pass
print("PASS: clip paths remain relative to the module")
assert audio.play("bridge_silence.wav") is True
assert audio.play("bridge_silence.wav") is True
assert audio.stop() is True
print("PASS: replacing a cue closes the preceding sound device")
assert audio.play("bridge_silence.wav") is True
deadline = time.monotonic() + 4
while audio.mode() == "playing" and time.monotonic() < deadline:
    time.sleep(0.05)
assert audio.mode() == "stopped"
assert audio.stop() is True and audio.mode() == "closed"
print("PASS: a completed clip reports stopped and releases its sound device")
