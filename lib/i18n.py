#!/usr/bin/env python3
"""Cat Bedtime message catalog — resolves system locale and formats strings."""

from __future__ import annotations

import json
import os
import plistlib
import subprocess
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


def _normalize_tag(tag: str) -> str:
    return tag.strip().replace("_", "-")


def _match_supported(tag: str) -> str | None:
    """Map a BCP-47 tag to a supported catalog language (mirrors L10n.swift)."""
    norm = _normalize_tag(tag).lower()
    if norm.startswith("zh-hant") or norm in ("zh-tw", "zh-hk", "zh-mo"):
        return "zh-Hant"
    if norm.startswith("zh-hans") or norm in ("zh-cn", "zh-sg"):
        return "zh-Hans"
    if norm == "zh" or norm.startswith("zh-"):
        return "zh-Hans"
    if norm.startswith("ja"):
        return "ja"
    if norm.startswith("ko"):
        return "ko"
    if norm.startswith("en"):
        return "en"
    return None


def _macos_preferred_language_tags() -> list[str]:
    """Read macOS UI language list (same source as Locale.preferredLanguages)."""
    tags: list[str] = []
    prefs = Path.home() / "Library/Preferences/.GlobalPreferences.plist"
    if prefs.is_file():
        try:
            with prefs.open("rb") as fh:
                data = plistlib.load(fh)
            langs = data.get("AppleLanguages")
            if isinstance(langs, list):
                tags.extend(_normalize_tag(str(item)) for item in langs if str(item).strip())
        except (OSError, plistlib.InvalidFileException, TypeError, ValueError):
            pass

    if tags:
        return tags

    try:
        out = subprocess.check_output(
            ["defaults", "read", "-g", "AppleLanguages"],
            text=True,
            timeout=2,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError):
        return tags

    for line in out.splitlines():
        line = line.strip().strip(",").strip('"').strip()
        if line and line not in ("(", ")"):
            tags.append(_normalize_tag(line))
    return tags


def _preferred_language_tags() -> list[str]:
    """Ordered language candidates — system UI first, then Unix locale env."""
    tags: list[str] = []
    seen: set[str] = set()

    def add(raw: str) -> None:
        tag = _normalize_tag(raw)
        if not tag or tag in seen:
            return
        seen.add(tag)
        tags.append(tag)

    for tag in _macos_preferred_language_tags():
        add(tag)

    raw = os.environ.get("AppleLanguages", "").strip()
    if raw:
        for part in raw.replace(",", " ").split():
            add(part)

    for key in ("LC_ALL", "LC_MESSAGES", "LANG"):
        raw = os.environ.get(key, "").strip()
        if not raw or raw == "C":
            continue
        add(raw.split(".")[0])

    return tags


def resolve_lang() -> str:
    """Pick best supported language — aligned with Swift L10n / system UI."""
    for tag in _preferred_language_tags():
        matched = _match_supported(tag)
        if matched:
            return matched
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
