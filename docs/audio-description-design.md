# Movie audio description

The opening has timed descriptions of otherwise inaccessible video content,
using an authorized narration voice.
Only information visible in the current scene belongs in narration.

The described movies are the OP3 main opening (2717 frames) and OP2
post-tutorial opening (2557 frames), both at 30 fps. The live game has no subtitle
asset or USM subtitle channels for these movies. Each has separate 1K, 2K and 4K
files; the resolution is part of the movie's filename. Their matching scene
timelines must be verified before sharing a narration track across resolutions.
Use successfully decoded game footage, or a recording of actual game playback
aligned to the native clock, as the visual source. Review the footage in Descript
and cross-check its suggestions against dense source frames. Write concise timed
descriptions around dialogue.
Use an approved local narration voice without pitch/speed
modification. Validate each generated cue before deployment.

Playback extends the existing screen-reader poll. The visible movie material must
match its native CRI player. Source basename, frame rate, and total frames must
match the description manifest. Poll current frame and pause state on the game
thread. Do not launch descriptions from a title, gallery label, timer guess, or
unattached movie object. An unknown film has no invented description.

Use a separate small Lua 5.4 audio module for asynchronous local WAV playback,
with pause/resume and stop. A Lua cue scheduler owns scene timing. It skips cues
already missed after a seek, stops on identity change, disappearance, end or skip,
and never queues old narration behind current scenes. Menu speech continues
through the existing speech bridge. Narration errors must not silence UI text.

Validation: cue start/end boundaries, late attachment, replay, pause/resume, skip,
missing/mismatched source, invalid clock, failed sound device, map transitions,
and native-module playback outside the game before live deployment. No online
gameplay changes, save changes, or hidden/future data reads are needed.

The original OP3 track contains 19 checked local voice clips. Each
clip has exact-word recognition, a checked sentence ending, and at least 0.3
seconds of timing headroom. The clip builder verifies hashes and scene windows,
then converts the original 24-bit renders to 16-bit PCM without changing pitch,
speed, or duration. Only narration clips are deployed; reference recordings and
captured or extracted game footage remain in local research. The builder accepts
one reviewed source folder per movie and validates all movies before writing its
manifest. Resolution aliases can only name the same movie; frame count and frame
rate still have to match at runtime. Movie recognition never depends on a guessed
duration alone.

The live native clock was verified over a complete 90.567-second playback.
Source review used Descript and a local dense-frame shot log.
Descript's sparse first draft was not used
unchanged. Performance overlays and the transient Skip prompt are excluded
from the movie script. Live candidate 10 played all 19 cues without skips or
backend errors, then returned to the speaking main menu. Process-only loopback
recordings detected all 19 waveforms, about 27–39 ms after each play call. Ten
passed a strict 0.85 correlation threshold; all correlations were 0.73–0.94
against the music mix. A separate speech-recognition pass found 17 exact
sentences and two minor differences ("a/the" and "turns/terms"). The dry renders
have exact words for all 19 cues. User listening feedback remains the authority
for audibility and balance. Other movie identities report that no description
is installed when the player requests F6.

The scheduler uses each clip's measured duration: a late poll can still start
it if the entire clip fits the current scene; otherwise it logs a skipped cue.
It pauses on a paused/stalled movie clock. Native stopped/error states and
disappearing movie surfaces stop playback. Unrelated focus-reader recovery
does not reset movie narration. The player identity is the stable full-path
string returned by `movie_reader`, never a transient UObject wrapper.
