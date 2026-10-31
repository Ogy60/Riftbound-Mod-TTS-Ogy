"""Builds the playable save and the release zip.

    python tools/build.py

1. Checks src/Global.lua (block/bracket balance) and the table layout.
2. Writes dist/Riftbound by Ogy.json: save/Riftbound by Ogy.json with the
   script from src/Global.lua put in.
3. Writes dist/riftbound-by-ogy-v<version>.zip with the save, the images,
   README, LICENSE and NOTICE.

The version comes from MOD_VERSION in src/Global.lua.
"""
import json
import pathlib
import re
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "Global.lua"
TEMPLATE = ROOT / "save" / "Riftbound by Ogy.json"
DIST = ROOT / "dist"


def run(tool, *args):
    r = subprocess.run([sys.executable, str(ROOT / "tools" / tool), *map(str, args)],
                       capture_output=True, text=True)
    print(r.stdout.strip())
    if r.returncode != 0:
        print(r.stderr.strip())
        sys.exit(f"{tool} failed")
    return r.stdout


def main():
    lua = SRC.read_text(encoding="utf-8")
    m = re.search(r'MOD_VERSION\s*=\s*"([^"]+)"', lua)
    if not m:
        sys.exit("MOD_VERSION not found in src/Global.lua")
    version = m.group(1)
    if "OWNER/" in lua:
        print("WARNING: REPO_URL in src/Global.lua still says OWNER - set your GitHub name.")

    run("lualint.py", SRC)
    audit = run("audit_layout.py", SRC)
    real = [l for l in audit.splitlines() if l.startswith(" - ") and "banish is never used" not in l]
    if real:
        sys.exit("Layout problems - fix them before releasing.")

    save = json.loads(TEMPLATE.read_text(encoding="utf-8"))
    save["LuaScript"] = lua
    DIST.mkdir(exist_ok=True)
    out_save = DIST / "Riftbound by Ogy.json"
    out_save.write_text(json.dumps(save, indent=2, ensure_ascii=False), encoding="utf-8")

    out_zip = DIST / f"riftbound-by-ogy-v{version}.zip"
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(out_save, out_save.name)
        for f in ("assets/card_back.png", "assets/playmat.png", "assets/battlefield_mat.png",
                  "README.md", "LICENSE", "NOTICE", "CHANGELOG.md"):
            z.write(ROOT / f, pathlib.Path(f).name)
    print(f"Built v{version}: {out_save.relative_to(ROOT)} and {out_zip.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
