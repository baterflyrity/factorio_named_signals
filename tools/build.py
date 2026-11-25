"""Сборка мода: python tools/build.py [--install ПАПКА_MODS]

Собирает dist/named-signals_<версия>.zip (версия берётся из info.json;
внутри архива папка named-signals_<версия>, как требует Factorio).
С --install кладёт архив в папку mods и удаляет оттуда старые версии мода,
чтобы игра не видела две копии.

Папка mods в Windows по умолчанию: %APPDATA%\\Factorio\\mods
"""
import argparse
import json
import pathlib
import shutil
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOD = ROOT / "named-signals"
DIST = ROOT / "dist"


def build():
    info = json.loads((MOD / "info.json").read_text(encoding="utf-8"))
    folder = f"{info['name']}_{info['version']}"
    DIST.mkdir(exist_ok=True)
    out = DIST / f"{folder}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(MOD.rglob("*")):
            if f.is_file():
                z.write(f, f"{folder}/{f.relative_to(MOD).as_posix()}")
    print(f"built {out.relative_to(ROOT)}")
    return info["name"], out


def install(name, archive, mods):
    mods = pathlib.Path(mods).expanduser()
    for old in mods.glob(f"{name}_*.zip"):
        if old.name != archive.name:
            old.unlink()
            print(f"removed {old.name}")
    shutil.copy2(archive, mods / archive.name)
    print(f"installed {archive.name} -> {mods}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--install", metavar="MODS_DIR", help="папка mods Factorio")
    args = parser.parse_args()
    name, archive = build()
    if args.install:
        install(name, archive, args.install)
