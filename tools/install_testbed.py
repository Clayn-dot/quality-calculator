"""Installs the test bed tests/testbed/qc-testbed into the game mods folder (zip). Only while the game is closed.
To remove the test bed: delete qc-testbed_*.zip from the mods folder.
Run: python -X utf8 tools/install_testbed.py [--mods-dir FOLDER]"""
import argparse, json, os, pathlib, subprocess, sys, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "tests" / "testbed" / "qc-testbed"


def game_running():
    try:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq factorio.exe"], capture_output=True, check=True).stdout
        return b"factorio.exe" in out.lower()
    except Exception:
        return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mods-dir", default=os.path.join(os.environ.get("APPDATA", ""), "Factorio", "mods"))
    a = ap.parse_args()
    mods = pathlib.Path(a.mods_dir)
    if game_running():
        sys.exit("The game is running: nothing copied. Close Factorio and run again.")
    info = json.loads((SRC / "info.json").read_text(encoding="utf-8"))
    name = f"{info['name']}_{info['version']}"
    for old in mods.glob(f"{info['name']}_*.zip"):
        old.unlink()
    dst = mods / f"{name}.zip"
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(SRC.rglob("*")):
            if p.is_file():
                z.write(p, f"{name}/{p.relative_to(SRC).as_posix()}")
    print("installed:", dst)


if __name__ == "__main__":
    main()
