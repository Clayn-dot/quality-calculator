"""Builds the mod and puts it into the game mods folder, removing old zips of the same mod.
Does not install while the game is running (replacing a zip in a running game breaks loading).
Run: python tools/install.py [--mods-dir FOLDER]  (default %APPDATA%/Factorio/mods)"""
import argparse, hashlib, os, pathlib, shutil, subprocess, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from build import build


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()[:12]


def game_running():
    # tasklist output on a Russian Windows is not utf-8: read bytes and look for the process name. If the check fails,
    # assume the game MAY be running (safer not to copy)
    try:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq factorio.exe"], capture_output=True, check=True).stdout
        return b"factorio.exe" in out.lower()
    except Exception:
        return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mods-dir", default=os.path.join(os.environ.get("APPDATA", ""), "Factorio", "mods"))
    ap.add_argument("--force-running", action="store_true", help="for tests only")
    a = ap.parse_args()
    mods = pathlib.Path(a.mods_dir)
    if not mods.is_dir():
        sys.exit(f"No mods folder: {mods}")
    if game_running() and not a.force_running:
        sys.exit("The game is running: nothing copied. Close Factorio and run again.")
    name, ver, zipfile_ = build()
    for old in mods.glob(f"{name}_*.zip"):
        old.unlink()
        print("removed old:", old.name)
    dst = mods / zipfile_.name
    shutil.copy2(zipfile_, dst)
    ok = sha(zipfile_) == sha(dst)
    print(("installed: " if ok else "COPY ERROR: ") + str(dst), sha(dst))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
