#!/usr/bin/env bash
# Cat Bedtime i18n — follows system locale (see lib/i18n.py)

_I18N_PY="${_I18N_PY:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/i18n.py}"

zzz_lang() {
  python3 "$_I18N_PY" lang 2>/dev/null || echo "en"
}

# msg KEY [printf-args...]
msg() {
  local key="$1"
  shift
  if (( $# > 0 )); then
    python3 "$_I18N_PY" fmt "$key" "$@"
  else
    python3 "$_I18N_PY" get "$key"
  fi
}
