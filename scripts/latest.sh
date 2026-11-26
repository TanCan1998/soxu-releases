#!/usr/bin/env bash
# Enforce monotonic Latest release tag across concurrent release jobs.
# Modeled after yetone/magpie-releases/scripts/latest.sh.
set -euo pipefail

newest() {
  gh release list -R "$1" -L 100 --exclude-drafts --exclude-pre-releases --json tagName -q '.[].tagName' |
    { grep -E '^v[0-9]+(\.[0-9]+)*$' || true; } | sort -V | tail -1
}

is_newest() {
  local top="$1"
  local tag="$2"
  if [ -z "$top" ] || [ "$(printf '%s\n%s\n' "$top" "$tag" | sort -V | tail -1)" = "$tag" ]; then
    echo true
  else
    echo false
  fi
}

case "${1:-}" in
newest)
  newest "$2"
  ;;
is-newest)
  top=$(newest "$2")
  is_newest "$top" "$3"
  ;;
is-newest-local)
  is_newest "$2" "$3"
  ;;
mark)
  top=$(newest "$2")
  [ -n "$top" ] || { echo "no published release in $2"; exit 0; }
  now=$(gh api "repos/$2/releases/latest" -q .tag_name 2>/dev/null || true)
  if [ "$now" = "$top" ]; then
    echo "$top is Latest in $2"
  else
    echo "Latest in $2 was ${now:-none}: giving the mark to $top"
    gh release edit "$top" -R "$2" --latest >/dev/null
  fi
  ;;
*)
  echo "usage: $0 newest|is-newest|is-newest-local|mark ARGS..." >&2
  exit 2
  ;;
esac
