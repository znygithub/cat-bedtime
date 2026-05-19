#!/usr/bin/env bash
# Shared macOS codesigning helpers for release artifacts.

DEFAULT_SIGNING_ACCOUNT="1339975893@qq.com"

macos_find_codesign_identity() {
  if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$CODE_SIGN_IDENTITY"
    return 0
  fi

  if [ -n "${SIGNING_IDENTITY:-}" ]; then
    printf '%s\n' "$SIGNING_IDENTITY"
    return 0
  fi

  local account="${APPLE_SIGNING_ACCOUNT:-$DEFAULT_SIGNING_ACCOUNT}"
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  local identity
  identity="$(printf '%s\n' "$identities" | awk -F '"' '/"Developer ID Application: / { print $2; exit }')"
  if [ -n "$identity" ]; then
    printf '%s\n' "$identity"
    return 0
  fi

  identity="$(printf '%s\n' "$identities" | awk -F '"' -v account="$account" 'index($2, "Apple Development: " account) == 1 { print $2; exit }')"
  if [ -n "$identity" ]; then
    printf '%s\n' "$identity"
    return 0
  fi

  identity="$(printf '%s\n' "$identities" | awk -F '"' '/"Apple Development: / { print $2; exit }')"
  if [ -n "$identity" ]; then
    printf '%s\n' "$identity"
    return 0
  fi

  return 1
}

macos_find_developer_id_identity() {
  if [ -n "${DEVELOPER_ID_IDENTITY:-}" ]; then
    printf '%s\n' "$DEVELOPER_ID_IDENTITY"
    return 0
  fi

  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/"Developer ID Application: / { print $2; exit }'
}

macos_codesign_target() {
  local target="$1"

  if [ "${SKIP_CODESIGN:-0}" = "1" ]; then
    echo "Skipping codesign for $target (SKIP_CODESIGN=1)"
    return 0
  fi

  local identity
  identity="$(macos_find_codesign_identity || true)"
  if [ -z "$identity" ]; then
    echo "No macOS codesigning identity found; leaving unsigned: $target"
    echo "Set CODE_SIGN_IDENTITY or install a Developer ID Application certificate for distribution."
    return 0
  fi

  if [ "${REQUIRE_DEVELOPER_ID:-0}" = "1" ] && [[ "$identity" != Developer\ ID\ Application:* ]]; then
    echo "Public distribution requires a Developer ID Application certificate."
    echo "Current identity is not suitable for public website downloads: $identity"
    return 1
  fi

  local sign_args=(--force --sign "$identity" --options runtime)
  if [[ "$identity" == Developer\ ID\ Application:* ]]; then
    sign_args+=(--timestamp)
  fi
  if [ -d "$target" ] && [[ "$target" == *.app ]]; then
    sign_args+=(--deep)
  fi

  echo "Signing $target with: $identity"
  codesign "${sign_args[@]}" "$target"

  local verify_args=(--verify --verbose=2)
  if [ -d "$target" ] && [[ "$target" == *.app ]]; then
    verify_args+=(--deep --strict)
  fi
  codesign "${verify_args[@]}" "$target"
}
