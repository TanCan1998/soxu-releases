#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LATEST="$ROOT/scripts/latest.sh"

assert_eq() {
  local got="$1" expected="$2" msg="$3"
  if [ "$got" != "$expected" ]; then
    echo "FAIL: $msg (got='$got', expected='$expected')" >&2
    exit 1
  fi
  echo "PASS: $msg"
}

assert_eq "$("$LATEST" is-newest-local "" "v0.1.0")" "true" "empty repo sets Latest"
assert_eq "$("$LATEST" is-newest-local "v0.1.9" "v0.1.10")" "true" "semver sort places v0.1.10 above v0.1.9"
assert_eq "$("$LATEST" is-newest-local "v0.1.10" "v0.1.9")" "false" "older rerun v0.1.9 never steals Latest from v0.1.10"
assert_eq "$("$LATEST" is-newest-local "v0.2.0" "v0.2.0")" "true" "republishing current highest version keeps Latest"
echo "All latest.sh tests passed."
