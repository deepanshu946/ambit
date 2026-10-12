#!/usr/bin/env python3
"""Download the wallpapers listed in manifest.json into Wallpapers/images/ and verify them.

  ./fetch.py            download missing files, verify width >= 3840 (via sips) and sha256 if pinned
  ./fetch.py --pin      also write the sha256 of every file back into manifest.json
  ./fetch.py deep-1 ... only these ids
"""
import hashlib, json, subprocess, sys, time, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "manifest.json"
IMAGES = HERE / "images"
UA = {"User-Agent": "FlowMacApp/0.1 (open-source wallpaper fetch; https://github.com/)"}

def pixel_width(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", str(path)], capture_output=True, text=True).stdout
    return int(out.split("pixelWidth:")[1].split()[0])

def main():
    pin = "--pin" in sys.argv
    only = {a for a in sys.argv[1:] if not a.startswith("--")}
    items = json.loads(MANIFEST.read_text())
    IMAGES.mkdir(exist_ok=True)
    bad = 0
    for it in items:
        if only and it["id"] not in only: continue
        dest = IMAGES / f'{it["id"]}.jpg'
        if not dest.exists():
            for attempt in range(3):
                try:
                    data = urllib.request.urlopen(urllib.request.Request(it["url"], headers=UA), timeout=120).read()
                    dest.write_bytes(data); break
                except Exception as e:
                    print(f'  retry {it["id"]}: {e}'); time.sleep(5 * (attempt + 1))
            else:
                print(f'FAIL {it["id"]}'); bad += 1; continue
            time.sleep(1)
        digest = hashlib.sha256(dest.read_bytes()).hexdigest()
        width = pixel_width(dest)
        problems = []
        if width < 3840: problems.append(f"only {width}px wide")
        if it.get("sha256") and it["sha256"] != digest: problems.append("sha256 mismatch")
        if pin: it["sha256"] = digest
        print(f'{"BAD " if problems else "ok  "} {it["id"]:11} {width}px {dest.stat().st_size/1e6:5.1f}MB {", ".join(problems)}')
        bad += bool(problems)
    if pin: MANIFEST.write_text(json.dumps(items, indent=1, ensure_ascii=False) + "\n")
    sys.exit(1 if bad else 0)

main()
