#!/usr/bin/env python3
"""Build an installable OctoTweaks zip. Standard library only."""

from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "OctoTweaks"
TOC = ADDON / "OctoTweaks.toc"
DIST = ROOT / "dist"


def version() -> str:
    text = TOC.read_text(encoding="utf-8")
    match = re.search(r"^## Version:\s*(.+?)\s*$", text, re.MULTILINE)
    if not match:
        raise RuntimeError("OctoTweaks.toc has no ## Version field")
    return match.group(1)


def main() -> int:
    if not ADDON.is_dir():
        print("[FAIL] addon directory not found")
        return 1

    DIST.mkdir(exist_ok=True)
    out = DIST / f"OctoTweaks-v{version()}.zip"

    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(ADDON.rglob("*")):
            if path.is_file():
                arcname = Path("OctoTweaks") / path.relative_to(ADDON)
                zf.write(path, arcname.as_posix())

    print(f"[PASS] package created: {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
