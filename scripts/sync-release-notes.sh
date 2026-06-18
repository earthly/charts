#!/usr/bin/env bash
#
# sync-release-notes.sh — mirror each chart's CHANGELOG.md into its GitHub
# release notes.
#
# The changelog is the single source of truth. For every
# charts/<chart>/CHANGELOG.md, each "## [X.Y.Z] - DATE" section is matched to
# the release tagged "<chart>-X.Y.Z" (the tag chart-releaser publishes). When
# the release exists and its body differs from the changelog section, the body
# is replaced with that section. Releases with no matching changelog section
# (e.g. pre-1.0 history the changelog intentionally omits) are left untouched.
#
# Idempotent: a second run with no changelog edits makes no changes. Safe to
# run on every release, which keeps notes self-healing if a changelog entry is
# corrected after the fact.
#
# Usage:
#   scripts/sync-release-notes.sh [--repo OWNER/REPO] [--chart NAME]
#                                 [--version X.Y.Z] [--dry-run]
#
# Defaults: --repo $GITHUB_REPOSITORY (falls back to earthly/charts); all
# charts; all versions. Requires an authenticated `gh` and `awk`.

set -euo pipefail

REPO="${GITHUB_REPOSITORY:-earthly/charts}"
ONLY_VERSION=""
ONLY_CHART=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    REPO="$2"; shift 2 ;;
    --chart)   ONLY_CHART="$2"; shift 2 ;;
    --version) ONLY_VERSION="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '3,22p' "$0" | sed 's/^#\{0,1\} \{0,1\}//'
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Repo root = parent of this script's dir, so it works from any CWD.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Print the changelog section body for a version: the lines between its
# "## [ver]" header and the next "## [" header, with trailing whitespace and
# leading/trailing blank lines trimmed. $1 = version, $2 = changelog path.
extract_section() {
  awk -v ver="$1" '
    index($0, "## [" ver "]") == 1 { flag = 1; next }
    flag && index($0, "## [") == 1 { flag = 0 }
    flag { lines[++n] = $0 }
    END {
      s = 1; while (s <= n && lines[s] == "") s++
      e = n; while (e >= s && lines[e] == "") e--
      for (i = s; i <= e; i++) { line = lines[i]; sub(/[ \t]+$/, "", line); print line }
    }
  ' "$2"
}

# Normalize a body for comparison: strip CR, trailing whitespace, and
# leading/trailing blank lines. Reads stdin.
normalize() {
  awk '
    { sub(/\r$/, ""); sub(/[ \t]+$/, ""); lines[++n] = $0 }
    END {
      s = 1; while (s <= n && lines[s] == "") s++
      e = n; while (e >= s && lines[e] == "") e--
      for (i = s; i <= e; i++) print lines[i]
    }
  '
}

checked=0; changed=0; missing=0

for changelog in "$ROOT"/charts/*/CHANGELOG.md; do
  [ -e "$changelog" ] || continue
  chart="$(basename "$(dirname "$changelog")")"
  [ -z "$ONLY_CHART" ] || [ "$ONLY_CHART" = "$chart" ] || continue

  versions="$(awk -F'[][]' '/^## \[/ { print $2 }' "$changelog")"

  for version in $versions; do
    [ -z "$ONLY_VERSION" ] || [ "$ONLY_VERSION" = "$version" ] || continue
    tag="${chart}-${version}"

    if ! gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
      echo "skip  $tag — no matching release"
      missing=$((missing + 1))
      continue
    fi
    checked=$((checked + 1))

    desired="$(extract_section "$version" "$changelog")"
    if [ -z "$desired" ]; then
      echo "skip  $tag — empty changelog section"
      continue
    fi

    current="$(gh release view "$tag" --repo "$REPO" --json body --jq .body)"
    if [ "$(printf '%s' "$current" | normalize)" = "$(printf '%s' "$desired" | normalize)" ]; then
      echo "ok    $tag — already in sync"
      continue
    fi

    if [ "$DRY_RUN" = 1 ]; then
      echo "would update $tag:"
      printf '%s\n' "$desired" | sed 's/^/    | /'
    else
      printf '%s\n' "$desired" | gh release edit "$tag" --repo "$REPO" --notes-file -
      echo "edit  $tag — notes synced from changelog"
    fi
    changed=$((changed + 1))
  done
done

echo "---"
echo "checked=$checked changed=$changed missing=$missing"
