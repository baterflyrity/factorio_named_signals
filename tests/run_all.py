"""Все проверки мода одной командой: python tests/run_all.py

Factorio для этого не нужен: код мода выполняется во встроенном Lua (lupa)
на имитации игрового API.

1. Компиляция всех .lua мода.
2. tests.lua      — движок условий, агрегаты, источники, подписи, комбинатор.
3. data_test.lua  — data-стадия: прототипы комбинатора и ЛЭП-реле.
4. relay_test.lua — реле на имитации графа проводов: перенос, удаление, миграция.
5. gui_test.lua   — окно на имитации GUI с правилами движка (зарезервированные
                    имена, spacing только у flow, существующие стили). Имена
                    стилей берутся из wube/factorio-data; если его нет и git
                    недоступен, проверка пропускается.

Зависимость: pip install lupa
"""
import os
import pathlib
import re
import subprocess
import sys
import tempfile

from lupa import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOD = ROOT / "named-signals"
TESTS = ROOT / "tests"
CACHE = ROOT / ".cache"


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f"MOD = '{MOD.as_posix()}'; package.path = MOD .. '/?.lua;' .. package.path")
    return lua


def compile_all():
    lua = LuaRuntime()
    check = lua.eval("function(src, name) local fn, err = load(src, name) return err end")
    for f in sorted(MOD.rglob("*.lua")):
        err = check(f.read_text(encoding="utf-8"), f.name)
        if err:
            sys.exit(f"FAIL compile {f.relative_to(ROOT)}: {err}")
    print("compile: OK")


def run_file(name):
    runtime().execute((TESTS / name).read_text(encoding="utf-8"))


def factorio_data():
    path = os.environ.get("FACTORIO_DATA")
    if path:
        return pathlib.Path(path)
    target = CACHE / "factorio-data"
    if not (target / "core" / "prototypes" / "style.lua").exists():
        try:
            subprocess.run(["git", "clone", "--depth", "1", "--filter=blob:none", "--sparse",
                            "https://github.com/wube/factorio-data.git", str(target)], check=True, capture_output=True)
            subprocess.run(["git", "-C", str(target), "sparse-checkout", "set", "core/prototypes"],
                           check=True, capture_output=True)
        except Exception as e:  # нет сети или git
            print(f"gui: SKIP (factorio-data недоступен: {e})")
            return None
    return target


GUI_FIXTURES = '''
local signals = require("scripts.signals")
local logic = require("scripts.logic")
local G = defines.wire_connector_id.circuit_green
SOURCE_CHEST = { valid = true, type = "container", unit_number = 501, surface = "nauvis", force = "player",
  get_control_behavior = function() return nil end,
  get_inventory = function() return { get_contents = function() return {
    { name = "iron-plate", count = 9, quality = "normal" }, { name = "coal", count = 2, quality = "normal" } } end } end,
  get_circuit_network = function(wid) if wid == G then return { network_id = 10 } end end }
COMBINATOR = { entity = { valid = true, unit_number = 900, status = 1,
    get_circuit_network = function(wid) if wid == 4 then return { network_id = 10,
      signals = { { signal = { type = "item", name = "iron-plate" }, count = 9 } } } end end },
  output = { valid = true, get_or_create_control_behavior = function()
    return { sections_count = 1, get_section = function() return {} end } end },
  members = {} }
'''


def gui_test():
    data = factorio_data()
    if data is None:
        return
    style = (data / "core" / "prototypes" / "style.lua").read_text(encoding="utf-8")
    names = {m.group(1) for m in re.finditer(
        r"^\s*([a-z_0-9]+)\s*=\s*\{[^{}]{0,80}?type\s*=\s*\"([a-z_]+)\"", style, re.M | re.S)}
    styles = "STYLE_TYPES = {" + ",".join(f'["{n}"]=true' for n in sorted(names)) + "}\n"
    mocks = (TESTS / "tests.lua").read_text(encoding="utf-8")
    mocks = mocks[:mocks.index("local pass, fail")]
    with tempfile.TemporaryDirectory() as tmp:
        (pathlib.Path(tmp) / "tests_env.lua").write_text(styles + mocks + GUI_FIXTURES, encoding="utf-8")
        lua = runtime()
        lua.execute(f"TESTS = '{pathlib.Path(tmp).as_posix()}'")
        lua.execute((TESTS / "gui_test.lua").read_text(encoding="utf-8"))


if __name__ == "__main__":
    compile_all()
    for name in ("tests.lua", "data_test.lua", "relay_test.lua"):
        run_file(name)
    gui_test()
    print("ALL OK")
