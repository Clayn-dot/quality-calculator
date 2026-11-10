"""Builds the mod zip: dist/for-<game version>/<name>_<version>.zip (inside a <name>_<version>/ folder).
Run: python tools/build.py [2.1|2.0|all]  (default 2.1, as in src/.../info.json)
The 2.0 build uses the same sources and changes only factorio_version and dependencies in info.json."""
import json, pathlib, sys, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE_VERSIONS = {"2.0": "2.0.0", "2.1": "2.1.0"}


def build(game=None):
    mods = [p for p in (ROOT / "src").iterdir() if (p / "info.json").is_file()]
    if len(mods) != 1:
        raise SystemExit(f"Expected exactly one mod in src, found: {len(mods)}")
    src = mods[0]
    info = json.loads((src / "info.json").read_text(encoding="utf-8"))
    name, ver = info["name"], info["version"]
    game = game or info["factorio_version"]
    if game not in BASE_VERSIONS:
        raise SystemExit(f"Unknown game version: {game}")
    if game != info["factorio_version"]:
        info["factorio_version"] = game
        info["dependencies"] = [d.replace(info_base(d), BASE_VERSIONS[game]) if info_base(d) else d
                                for d in info["dependencies"]]
    out_dir = ROOT / "dist" / f"for-{game}"
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{name}_{ver}.zip"
    if out.exists():
        out.unlink()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(src.rglob("*")):
            if not p.is_file():
                continue
            arc = f"{name}_{ver}/{p.relative_to(src).as_posix()}"
            if p == src / "info.json":
                z.writestr(arc, json.dumps(info, ensure_ascii=False, indent=2) + "\n")
            else:
                z.write(p, arc)
    return name, ver, out


def info_base(dep):
    """Version after ">=" in a dependency like "base >= 2.1.0", otherwise an empty string."""
    parts = dep.split(">=")
    return parts[1].strip() if len(parts) == 2 else ""


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else None
    for g in (["2.1", "2.0"] if arg == "all" else [arg]):
        print(build(g)[2])
