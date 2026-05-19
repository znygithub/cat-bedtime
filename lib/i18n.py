#!/usr/bin/env python3
"""Cat Bedtime message catalog — resolves system locale and formats strings."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

SUPPORTED = ("zh-Hans", "zh-Hant", "en", "ja", "ko")
DEFAULT_LANG = "en"

_CATALOG: dict[str, Any] | None = None
_LANG: str | None = None


def _catalog_paths() -> list[Path]:
    paths: list[Path] = []
    lib_dir = Path(__file__).resolve().parent
    paths.append(lib_dir.parent / "locales" / "messages.json")
    paths.append(lib_dir / "locales" / "messages.json")
    home = Path.home() / ".timetosleep" / "locales" / "messages.json"
    paths.append(home)
    zzz_root = os.environ.get("ZZZ_ROOT", "")
    if zzz_root:
        paths.append(Path(zzz_root) / "locales" / "messages.json")
    return paths


def _load_catalog() -> dict[str, Any]:
    global _CATALOG
    if _CATALOG is not None:
        return _CATALOG
    for path in _catalog_paths():
        if path.is_file():
            with path.open(encoding="utf-8") as fh:
                _CATALOG = json.load(fh)
            return _CATALOG
    raise FileNotFoundError("messages.json not found in locales/")


def resolve_lang() -> str:
    """Pick best supported language from macOS / Unix locale env."""
    candidates: list[str] = []
    for key in ("LC_ALL", "LC_MESSAGES", "LANG"):
        raw = os.environ.get(key, "").strip()
        if not raw or raw == "C":
            continue
        tag = raw.split(".")[0].replace("_", "-")
        candidates.append(tag)

    # macOS preferred languages (when launched from GUI / app bundle)
    for key in ("AppleLanguages",):
        raw = os.environ.get(key, "").strip()
        if raw:
            for part in raw.replace(",", " ").split():
                candidates.append(part.replace("_", "-"))

    for tag in candidates:
        norm = tag.lower()
        if norm.startswith("zh-hant") or norm in ("zh-tw", "zh-hk", "zh-mo"):
            return "zh-Hant"
        if norm.startswith("zh-hans") or norm in ("zh-cn", "zh-sg"):
            return "zh-Hans"
        if norm == "zh" or norm.startswith("zh-"):
            # generic zh → simplified
            return "zh-Hans"
        if norm.startswith("ja"):
            return "ja"
        if norm.startswith("ko"):
            return "ko"
        if norm.startswith("en"):
            return "en"

    return DEFAULT_LANG


def current_lang() -> str:
    global _LANG
    if _LANG is None:
        override = os.environ.get("ZZZ_LANG", "").strip()
        _LANG = override if override in SUPPORTED else resolve_lang()
    return _LANG


def get_string(key: str, lang: str | None = None) -> str:
    catalog = _load_catalog()
    entry = catalog.get("strings", {}).get(key)
    if not entry:
        return key
    lang = lang or current_lang()
    if lang in entry:
        return entry[lang]
    if DEFAULT_LANG in entry:
        return entry[DEFAULT_LANG]
    for code in SUPPORTED:
        if code in entry:
            return entry[code]
    return key


def format_string(key: str, *args: Any, lang: str | None = None) -> str:
    template = get_string(key, lang=lang)
    if not args:
        return template
    try:
        return template % args
    except (TypeError, ValueError):
        return template


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "lang":
        print(current_lang())
        return
    if cmd == "get":
        key = sys.argv[2]
        lang = sys.argv[3] if len(sys.argv) > 3 else None
        print(get_string(key, lang=lang))
        return
    if cmd == "fmt":
        key = sys.argv[2]
        args = sys.argv[3:]
        print(format_string(key, *args))
        return
    sys.exit(1)


if __name__ == "__main__":
    main()
