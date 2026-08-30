#!/usr/bin/env python3
"""Static repository checks for OctoTweaks. Standard library only."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "OctoTweaks"
TOC = ADDON / "OctoTweaks.toc"

REQUIRED = [
    ROOT / "AGENTS.md",
    ROOT / "README.md",
    ROOT / "ARCHITECTURE.md",
    ROOT / "CHANGELOG.md",
    ROOT / "addon_update.bat",
    ROOT / "docs" / "INDEX.md",
    ROOT / "docs" / "CURRENT_STATE.md",
    ROOT / "docs" / "ROADMAP.md",
    ROOT / "docs" / "architecture" / "documentation-policy.md",
    ROOT / "docs" / "architecture" / "delta-delivery-policy.md",
    TOC,
]


def result(ok: bool, label: str, detail: str = "") -> bool:
    prefix = "[PASS]" if ok else "[FAIL]"
    suffix = f" - {detail}" if detail else ""
    print(f"{prefix} {label}{suffix}")
    return ok


def check_required() -> bool:
    missing = [str(p.relative_to(ROOT)) for p in REQUIRED if not p.exists()]
    return result(not missing, "required repository files", ", ".join(missing))


def toc_lua_entries() -> list[str]:
    entries: list[str] = []
    for raw in TOC.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("##"):
            continue
        if line.lower().endswith(".lua"):
            entries.append(line.replace("\\", "/"))
    return entries


def check_toc_sources() -> bool:
    missing = []
    for entry in toc_lua_entries():
        if not (ADDON / entry).is_file():
            missing.append(entry)
    return result(not missing, "TOC source paths", ", ".join(missing))


def lua_files() -> list[Path]:
    return sorted(ADDON.rglob("*.lua"))


def check_module_ids() -> bool:
    pattern = re.compile(r'\bid\s*=\s*"([a-z0-9_]+\.[a-z0-9_]+)"')
    found: dict[str, Path] = {}
    duplicates: list[str] = []

    for path in lua_files():
        text = path.read_text(encoding="utf-8")
        for module_id in pattern.findall(text):
            if module_id in found:
                duplicates.append(module_id)
            else:
                found[module_id] = path

    ok = bool(found) and not duplicates
    detail = f"{len(found)} module id(s)" if ok else ("duplicates: " + ", ".join(duplicates) if duplicates else "none found")
    return result(ok, "unique module ids", detail)


def check_lua50_guardrails() -> bool:
    failures: list[str] = []
    forbidden_patterns = [
        (re.compile(r"\btable\.unpack\b"), "table.unpack"),
        (re.compile(r"\bgoto\b"), "goto"),
        (re.compile(r"\bcontinue\b"), "continue"),
    ]

    for path in lua_files():
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        for pattern, name in forbidden_patterns:
            if pattern.search(text):
                failures.append(f"{rel}: {name}")

        for lineno, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("--"):
                continue
            if re.search(r"(^|[=(,\s])#[A-Za-z_(]", line):
                failures.append(f"{rel}:{lineno}: # length operator")

    return result(not failures, "Lua 5.0 guardrails", "; ".join(failures))


def check_module_docs() -> bool:
    current = (ROOT / "docs" / "CURRENT_STATE.md").read_text(encoding="utf-8")
    missing: list[str] = []
    pattern = re.compile(r'\bid\s*=\s*"([a-z0-9_]+\.[a-z0-9_]+)"')

    for path in lua_files():
        for module_id in pattern.findall(path.read_text(encoding="utf-8")):
            if module_id not in current:
                missing.append(module_id)

    return result(not missing, "module ids documented in CURRENT_STATE", ", ".join(missing))


def check_no_third_party_payloads() -> bool:
    forbidden_roots = {"pfUI", "pfQuest", "Aegis_Exchange"}
    found = [p.name for p in ROOT.iterdir() if p.is_dir() and p.name in forbidden_roots]
    return result(not found, "no top-level third-party addon payloads", ", ".join(found))


def check_delta_gitignore() -> bool:
    text = (ROOT / ".gitignore").read_text(encoding="utf-8")
    required = {"delete_files.bat", "get_paths.bat", "delta_changes.zip"}
    missing = sorted(item for item in required if item not in text.splitlines())
    return result(not missing, "temporary delta helpers ignored by Git", ", ".join(missing))


def check_deployment_contract() -> bool:
    text = (ROOT / "addon_update.bat").read_text(encoding="utf-8")
    requirements = {
        "repository validation": "tools\\check.py",
        "clean remove": "rmdir /S /Q",
        "copy": "robocopy",
        "TOC verification": "OctoTweaks.toc",
    }
    missing = [label for label, needle in requirements.items() if needle not in text]
    return result(not missing, "addon_update deployment contract", ", ".join(missing))


def main() -> int:
    checks = [
        check_required(),
        check_toc_sources(),
        check_module_ids(),
        check_lua50_guardrails(),
        check_module_docs(),
        check_no_third_party_payloads(),
        check_delta_gitignore(),
        check_deployment_contract(),
    ]

    if all(checks):
        print("\nAll static checks passed.")
        return 0

    print("\nStatic checks failed.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
