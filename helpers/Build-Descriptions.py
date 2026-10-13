"""Validate reviewed narration and prepare game-ready PCM16 clips and Lua manifest.

Only generated narration is copied. Reference voice recordings and game footage
stay in the local research directory.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import wave


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, action="append", required=True,
                        help="Reviewed movie folder; repeat for multiple movies")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--margin", type=float, default=0.3,
                        help="Headroom for the 250 ms game-thread polling interval")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    if not math.isfinite(args.margin) or args.margin < 0.3:
        raise ValueError("Polling margin must be at least 0.3 seconds")
    films, problems, names, cue_ids = [], [], set(), set()
    for source_folder in args.source:
        script = json.loads((source_folder / "opening-cues.json").read_text(encoding="utf-8-sig"))
        match = re.fullmatch(r"korat_(op[123])_[124]k_cp\.usm", script["movie"].lower())
        if not match:
            raise ValueError("Unexpected movie name: " + script["movie"])
        aliases = script.get("aliases", [])
        for name in [script["movie"], *aliases]:
            if not re.fullmatch(r"korat_" + match[1] + r"_[124]k_cp\.usm", name.lower()):
                raise ValueError("A resolution alias must identify the same movie: " + name)
            if name.lower() in names:
                raise ValueError("Duplicate movie or alias: " + name)
            names.add(name.lower())
        fps, frames = script["fps"], script["totalFrames"]
        if not all(isinstance(v, (int, float)) and math.isfinite(v) and v > 0 for v in (fps, frames)):
            raise ValueError("Invalid movie timing")
        if int(frames) != frames:
            raise ValueError("Frame count must be an integer")
        rows = validate_cues(script, source_folder, match[1], args.margin, cue_ids, problems)
        if not rows:
            problems.append(script["movie"] + ": no narration cues")
        films.append({"movie": script["movie"], "aliases": aliases,
                      "title": script.get("title", "Opening movie"), "fps": fps,
                      "totalFrames": frames, "polling_margin": args.margin, "cues": rows})
    if problems:
        print(json.dumps({"ready": False, "problems": problems}, indent=2))
        return 1
    count = sum(len(film["cues"]) for film in films)
    if args.check_only:
        print(json.dumps({"ready": True, "movies": len(films), "cues": count, "polling_margin": args.margin}))
        return 0
    clips = args.output / "AudioDescription"
    clips.mkdir(parents=True, exist_ok=True)
    for film in films:
        for row in film["cues"]:
            source = row.pop("_source")
            target = args.output / row["file"]
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source),
                            "-c:a", "pcm_s16le", str(target)], check=True)
            with wave.open(str(target), "rb") as wav:
                assert wav.getsampwidth() == 2 and wav.getnchannels() == 1
                assert abs(wav.getnframes() / wav.getframerate() - row["duration"]) < 0.001
            row["sha256"] = sha(target)
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    lines = ["-- Generated from reviewed opening-cues.json and checked local voice renders.",
             "local films = {"]
    for film in films:
        lines.extend(["    [" + quote(film["movie"].lower()) + "] = {",
                      "        title = " + quote(film["title"]) + ", fps = " + str(film["fps"])
                      + ", totalFrames = " + str(film["totalFrames"]) + ",", "        cues = {"])
        for row in film["cues"]:
            lines.append("            {at = " + str(row["start"]) + ", untilTime = " + str(row["end"])
                         + ", duration = " + str(row["duration"])
                         + ", file = " + quote(row["file"]) + ", text = " + quote(row["text"]) + "},")
        lines.extend(["        },", "    },"])
    lines.append("}")
    for film in films:
        for alias in film["aliases"]:
            lines.append("films[" + quote(alias.lower()) + "] = films[" + quote(film["movie"].lower()) + "]")
    lines.extend(["return films", ""])
    (args.output / "description_manifest.lua").write_text("\n".join(lines), encoding="utf-8")
    # Retain the original single-movie cue-sheet shape when building one movie.
    sheet = films[0] if len(films) == 1 else {"films": films}
    (clips / "cue-sheet.json").write_text(json.dumps(sheet, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ready": True, "movies": len(films), "cues": count, "output": str(args.output)}))
    return 0


def validate_cues(script, source_folder, prefix, margin, cue_ids, problems):
    total = script["totalFrames"] / script["fps"]
    rows, previous_end = [], 0
    for cue in script["cues"]:
        cue_id = cue["id"]
        if not re.fullmatch(prefix + r"-\d{2}", cue_id) or cue_id in cue_ids:
            raise ValueError("Unexpected cue ID: " + cue_id)
        cue_ids.add(cue_id)
        source = source_folder / "narration" / (cue_id + ".wav")
        record_path = source.with_suffix(".json")
        if not source.is_file() or not record_path.is_file():
            problems.append(cue_id + ": missing render")
            continue
        record = json.loads(record_path.read_text(encoding="utf-8-sig"))
        checks = record["checks"]
        if record["text"] != cue["text"] or record["wave_sha256"] != sha(source):
            problems.append(cue_id + ": text or audio changed after checking")
        if checks["failures"] or not checks.get("exact"):
            problems.append(cue_id + ": voice checks failed: " + str(checks["failures"]))
        with wave.open(str(source), "rb") as wav:
            duration = wav.getnframes() / wav.getframerate()
            if wav.getnchannels() != 1 or duration <= 0:
                problems.append(cue_id + ": expected nonempty mono narration")
        if not all(isinstance(cue[v], (int, float)) and math.isfinite(cue[v]) for v in ("start", "end")):
            problems.append(cue_id + ": invalid scene timing")
            continue
        if not previous_end <= cue["start"] < cue["end"] <= total:
            problems.append(cue_id + ": invalid or overlapping scene window")
        if duration + margin > cue["end"] - cue["start"] + 0.001:
            problems.append(f"{cue_id}: {duration:.3f}s audio plus {margin}s polling margin "
                            f"exceeds {cue['end'] - cue['start']:.3f}s scene")
        previous_end = cue["end"]
        rows.append({**cue, "duration": duration, "source_sha256": sha(source),
                     "file": "AudioDescription/" + cue_id + ".wav", "_source": source})
    return rows


if __name__ == "__main__":
    raise SystemExit(main())
