"""Run the standalone reader regressions with isolated Lua 5.4 runtimes."""
import os
from pathlib import Path

from lupa.lua54 import LuaRuntime

root = Path(__file__).resolve().parents[1]
os.chdir(root)
tests = sorted((root / 'tests').glob('*_test.lua'))
for path in tests:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(path.read_text(encoding='utf-8-sig'))
    print(f'Completed Lua 5.4: {path.name}', flush=True)
modules = sorted((root / 'SparkingZeroAccess').glob('*.lua'))
for path in modules:
    LuaRuntime().execute('assert(loadfile(...))', path.as_posix())
print(f'All {len(tests)} Lua 5.4 suites and {len(modules)} module syntax checks passed', flush=True)
