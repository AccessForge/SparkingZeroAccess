"""
Update-CharaNames.py — Pulls character IDs from the community Google Sheet
and generates the chara_names.lua lookup table with DP costs.

Usage:  uv run scripts/Update-CharaNames.py

Source: https://docs.google.com/spreadsheets/d/177M1Uro7EtHebWKhYr8-P4D62jLuhEl7JLCVHirWFbE
DP data: ScreenRant + Fandom wiki (manually maintained in this script)
"""

# /// script
# requires-python = ">=3.10"
# dependencies = ["httpx"]
# ///

import csv
import io
import sys
from pathlib import Path

import httpx

SHEET_ID = "177M1Uro7EtHebWKhYr8-P4D62jLuhEl7JLCVHirWFbE"
CSV_URL = f"https://docs.google.com/spreadsheets/d/{SHEET_ID}/export?format=csv&gid=0"

OUTPUT_PATH = Path(
    r"C:\Program Files (x86)\Steam\steamapps\common\DRAGON BALL Sparking! ZERO"
    r"\SparkingZERO\Binaries\Win64\Mods\SparkingZeroAccess\Scripts\chara_names.lua"
)

# DP costs by character ID — from ScreenRant + Fandom wiki
# Update this when new DLC drops
DP_BY_ID = {
    # DP 1
    "0180_00": 1,
    # DP 2
    "0190_00": 2, "0540_00": 2, "0420_00": 2, "0130_00": 2, "0760_00": 2,
    "0140_00": 2, "0141_00": 2, "0210_00": 2, "0330_00": 2, "3130_00": 2,
    # DP 3
    "0320_00": 3, "0030_00": 3, "0060_00": 3, "0050_00": 3, "0340_00": 3,
    "0360_00": 3, "0350_00": 3, "0351_00": 3, "0370_00": 3, "0390_00": 3,
    "0400_00": 3, "0410_00": 3, "0163_00": 3, "0490_00": 3, "0230_00": 3,
    "0002_50": 3,
    # DP 4
    "0000_00": 4, "0040_00": 4, "0070_00": 4, "0020_00": 4, "0380_00": 4,
    "0040_20": 4, "0031_00": 4, "0080_00": 4, "0430_00": 4, "0470_00": 4,
    "0480_00": 4, "0032_00": 4, "0032_10": 4, "0090_00": 4, "0082_00": 4,
    "0561_00": 4, "0570_00": 4, "0580_00": 4, "0590_00": 4, "0660_00": 4,
    "0310_00": 4, "3000_00": 4, "0240_00": 4, "3050_00": 4, "3060_00": 4,
    "3070_00": 4,
    # DP 5
    "0023_00": 5, "0003_51": 5, "0000_10": 5, "0150_00": 5, "0151_00": 5,
    "0152_00": 5, "0020_10": 5, "0450_00": 5, "0460_00": 5, "0440_00": 5,
    "0040_10": 5, "0080_10": 5, "0160_00": 5, "0161_00": 5, "0000_20": 5,
    "0020_30": 5, "0090_01": 5, "0082_01": 5, "0032_30": 5, "0000_40": 5,
    "0020_60": 5, "0890_00": 5, "0080_30": 5, "0800_00": 5, "0810_00": 5,
    "1190_00": 5, "0900_00": 5, "0910_00": 5, "1321_00": 5, "1331_00": 5,
    "1341_00": 5, "0620_00": 5, "0550_00": 5, "0630_00": 5, "0650_00": 5,
    "0553_00": 5, "3010_00": 5, "0002_30": 5, "0680_00": 5, "3050_01": 5,
    "3060_01": 5, "3110_00": 5, "3160_00": 5,
    # DP 6
    "0000_11": 6, "0153_00": 6, "0031_01": 6, "0020_11": 6, "0021_20": 6,
    "0080_01": 6, "0153_10": 6, "0080_11": 6, "0081_20": 6, "0162_00": 6,
    "0000_21": 6, "0000_22": 6, "0032_01": 6, "0020_31": 6, "0020_32": 6,
    "0120_00": 6, "0500_00": 6, "0170_00": 6, "0171_00": 6, "0172_00": 6,
    "0032_31": 6, "0000_41": 6, "0020_61": 6, "0153_20": 6, "0881_00": 6,
    "0890_01": 6, "0080_31": 6, "0450_10": 6, "0912_00": 6, "0950_00": 6,
    "0920_00": 6, "0591_00": 6, "0600_00": 6, "0670_00": 6, "3000_01": 6,
    "3010_01": 6, "0002_31": 6, "0240_01": 6, "0680_01": 6, "3060_02": 6,
    # DP 7
    "0154_00": 7, "0031_02": 7, "0162_01": 7, "0000_23": 7, "0032_02": 7,
    "0032_20": 7, "0100_00": 7, "0120_01": 7, "0020_40": 7, "0172_10": 7,
    "0172_11": 7, "0173_00": 7, "0001_42": 7, "0022_62": 7, "0890_02": 7,
    "0940_00": 7, "0900_02": 7, "0911_00": 7, "0920_01": 7, "0601_00": 7,
    "0600_10": 7, "0621_00": 7, "0551_00": 7, "0631_00": 7, "0651_00": 7,
    "0554_00": 7, "0110_00": 7, "3020_00": 7, "3030_00": 7, "0002_32": 7,
    "0680_02": 7, "0681_00": 7, "0700_00": 7, "3060_03": 7, "3050_14": 7,
    "3100_03": 7, "3140_00": 7, "3080_00": 7,
    # DP 8
    "0100_01": 8, "0120_02": 8, "0000_43": 8, "0020_63": 8, "0155_00": 8,
    "0870_00": 8, "0800_01": 8, "0810_01": 8, "0941_00": 8, "0930_00": 8,
    "0000_50": 8, "0920_02": 8, "1500_00": 8, "0110_04": 8, "0110_01": 8,
    "3000_02": 8, "3011_00": 8, "3012_00": 8, "0000_33": 8, "0020_50": 8,
    "0700_01": 8, "3120_04": 8, "3150_00": 8,
    # DP 9
    "0811_00": 9, "0931_00": 9, "0000_51": 9, "0552_00": 9, "0555_00": 9,
    "3000_03": 9, "3040_00": 9,
    # DP 10
    "0100_02": 10, "0780_00": 10, "0790_00": 10, "0110_03": 10, "0110_02": 10,
}


def fetch_csv() -> str:
    print("Downloading character list from Google Sheets...")
    resp = httpx.get(CSV_URL, follow_redirects=True, timeout=30)
    resp.raise_for_status()
    return resp.text


def parse_csv(raw: str) -> list[tuple[str, str]]:
    reader = csv.reader(io.StringIO(raw))
    header = next(reader)

    name_col = None
    id_col = None
    for i, col in enumerate(header):
        if "NAME" in col.upper():
            name_col = i
        if "ID" in col.upper():
            id_col = i
    if name_col is None or id_col is None:
        print(f"ERROR: Could not find NAME and ID columns in header: {header}")
        sys.exit(1)

    entries = []
    for row in reader:
        if len(row) <= max(name_col, id_col):
            continue
        name = row[name_col].strip()
        char_id = row[id_col].strip()
        if name and char_id:
            entries.append((char_id, name))

    return entries


def generate_lua(entries: list[tuple[str, str]]) -> str:
    lines = [
        '--[[',
        '    chara_names.lua — Character ID to display name + DP cost lookup table',
        f'    Auto-generated by Update-CharaNames.py ({len(entries)} entries)',
        f'    Source: https://docs.google.com/spreadsheets/d/{SHEET_ID}',
        '    DP data: ScreenRant + Fandom wiki',
        '',
        '    IDs match texture pattern: T_UI_ChThumbP1_XXXX_YY_ZZ',
        '    where XXXX_YY is the character ID used as key here.',
        ']]',
        '',
        'local CharaNames = {}',
        '',
        '-- {name, dp} per character ID',
        'CharaNames.Data = {',
    ]

    missing_dp = []
    for char_id, name in entries:
        escaped = name.replace('"', '\\"')
        dp = DP_BY_ID.get(char_id)
        if dp is not None:
            lines.append(f'    ["{char_id}"] = {{"{escaped}", {dp}}},')
        else:
            # No DP data — store nil for DP
            lines.append(f'    ["{char_id}"] = {{"{escaped}", nil}},')
            if not char_id[0] in "789":
                missing_dp.append(f"{char_id} = {name}")

    lines.extend([
        '}',
        '',
        '--- Look up character name by ID. Returns name or nil.',
        'function CharaNames.GetName(charaId)',
        '    local data = CharaNames.Data[charaId]',
        '    return data and data[1] or nil',
        'end',
        '',
        '--- Look up DP cost by ID. Returns number or nil.',
        'function CharaNames.GetDP(charaId)',
        '    local data = CharaNames.Data[charaId]',
        '    return data and data[2] or nil',
        'end',
        '',
        '--- Extract character ID from a texture full name string.',
        '--- Input: "Texture2D /Game/.../T_UI_ChThumbP1_0000_00_00.T_UI_ChThumbP1_0000_00_00"',
        '--- Returns: "0000_00" or nil',
        'function CharaNames.ExtractIdFromTexture(texFullName)',
        '    return texFullName:match("T_UI_ChThumb[^_]+_(%d+_%d+)_%d+")',
        'end',
        '',
        'return CharaNames',
        '',
    ])

    if missing_dp:
        print(f"WARNING: {len(missing_dp)} playable characters missing DP:")
        for m in missing_dp:
            print(f"  {m}")

    return '\n'.join(lines)


def main():
    raw = fetch_csv()
    entries = parse_csv(raw)
    print(f"Parsed {len(entries)} characters")

    lua = generate_lua(entries)

    OUTPUT_PATH.write_text(lua, encoding="utf-8")
    print(f"Written to: {OUTPUT_PATH}")
    print("Done!")


if __name__ == "__main__":
    main()
