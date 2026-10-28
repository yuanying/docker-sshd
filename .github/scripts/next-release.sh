#!/bin/bash
# Decides whether the weekly release has anything to release.
#
# Usage: next-release.sh [--bots-only] PATH...
#
# The latest tag is the highest vX.Y.Z by version; tags of any other shape
# are not releases. When one of PATHs has changed between that tag and HEAD,
# the next patch version is released. Prints release=true|false and
# version=vX.Y.(Z+1) (empty when not releasing), and appends the same to
# $GITHUB_OUTPUT when it is set.
#
# With --bots-only, used when a vulnerability fix is merged, the release is
# also held back unless every commit since that tag, merge commits aside, was
# written by Renovate or the vulnerability responder. The commits that held
# it back, and the command to release by hand, are appended to
# $GITHUB_STEP_SUMMARY when it is set.
set -euo pipefail

# The authors, by email, whose commits may be released without a person
# having looked at the result first.
BOTS=(
  '29139614+renovate[bot]@users.noreply.github.com'
  '348762456+fraction-vuln-responder[bot]@users.noreply.github.com'
)

bots_only=false
if [[ "${1:-}" == --bots-only ]]; then
  bots_only=true
  shift
fi

if (( $# == 0 )); then
  echo "usage: $0 [--bots-only] PATH..." >&2
  exit 2
fi

latest="$(git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)"
if [[ -z "$latest" ]]; then
  echo "no vX.Y.Z tag to raise the version from" >&2
  exit 1
fi

if git diff --quiet "$latest" HEAD -- "$@"; then
  echo "nothing in $* has changed since $latest" >&2
  release=false
  version=
else
  IFS=. read -r major minor patch <<< "${latest#v}"
  release=true
  version="v${major}.${minor}.$((patch + 1))"
  echo "$* changed since $latest; releasing $version" >&2
fi

if [[ "$release" == true && "$bots_only" == true ]]; then
  held=()
  while IFS=$'\t' read -r sha email line; do
    is_bot=false
    for bot in "${BOTS[@]}"; do
      [[ "$email" == "$bot" ]] && is_bot=true
    done
    [[ "$is_bot" == true ]] || held+=("$sha $line")
  done < <(git log --no-merges --format=$'%h\t%ae\t%an: %s' "$latest..HEAD")

  if (( ${#held[@]} > 0 )); then
    echo "commits since $latest not written by a bot; not releasing $version:" >&2
    printf '  %s\n' "${held[@]}" >&2
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      {
        echo "## $version was not released"
        echo
        echo "These commits since $latest were not written by Renovate or the vulnerability responder:"
        echo
        printf -- '- %s\n' "${held[@]}"
        echo
        echo "Once they have been checked, release by hand with the weekly release:"
        echo
        echo '```'
        echo "gh workflow run release.yml --repo ${GITHUB_REPOSITORY:-OWNER/REPO} --ref master"
        echo '```'
      } >> "$GITHUB_STEP_SUMMARY"
    fi
    release=false
    version=
  fi
fi

result="release=${release}"$'\n'"version=${version}"
echo "$result"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "$result" >> "$GITHUB_OUTPUT"
fi
