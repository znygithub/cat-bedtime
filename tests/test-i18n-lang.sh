#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
I18N_PY="$ROOT_DIR/lib/i18n.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" != "$want" ]]; then
    fail "$label: got '$got', want '$want'"
  fi
}

# ZZZ_LANG override
assert_eq "$(ZZZ_LANG=ja python3 "$I18N_PY" lang)" "ja" "ZZZ_LANG=ja"
assert_eq "$(ZZZ_LANG=zh-Hant python3 "$I18N_PY" lang)" "zh-Hant" "ZZZ_LANG=zh-Hant"

# Catalog lookup follows override
title_ja="$(ZZZ_LANG=ja python3 "$I18N_PY" get notify.winddown.title)"
[[ "$title_ja" == *"ねこ"* ]] || fail "Japanese notify title expected, got: $title_ja"

title_en="$(ZZZ_LANG=en python3 "$I18N_PY" get notify.winddown.title)"
[[ "$title_en" == *"cat"* ]] || fail "English notify title expected, got: $title_en"

# macOS system languages should win over bare LANG=C (launchd-like env)
if [[ "$(uname -s)" == "Darwin" ]]; then
  sys_lang="$(env -u ZZZ_LANG LANG=C LC_ALL=C LC_MESSAGES=C python3 "$I18N_PY" lang)"
  if defaults read -g AppleLanguages 2>/dev/null | grep -qi 'zh-Hans\|zh-CN\|zh_CN'; then
    assert_eq "$sys_lang" "zh-Hans" "system zh-Hans when LANG=C"
  elif defaults read -g AppleLanguages 2>/dev/null | grep -qi 'en'; then
    assert_eq "$sys_lang" "en" "system en when LANG=C"
  fi
fi

echo "OK: i18n language resolution"
