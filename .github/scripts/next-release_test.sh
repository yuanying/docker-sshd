#!/bin/bash
# Tests for next-release.sh. Each case builds a throwaway repository,
# runs the script in it, and compares what it reports.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/next-release.sh"
failures=0

# Runs git in the repository DIR: at DIR git ARGS...
at() { local dir="$1"; shift 2; (cd "$dir" && git "$@"); }

new_repo() {
  dir="$(mktemp -d)"
  at "$dir" git init -q -b master
  at "$dir" git config user.email test@example.com
  at "$dir" git config user.name test
  at "$dir" git config commit.gpgsign false
  at "$dir" git config tag.gpgsign false
  echo "$dir"
}

commit() {
  local dir="$1" file="$2"
  mkdir -p "$dir/$(dirname "$file")"
  echo "$RANDOM" >> "$dir/$file"
  at "$dir" git add "$file"
  at "$dir" git commit -q -m "change $file"
}

# run_case NAME DIR EXPECTED: EXPECTED is the script's output (release=..., version=...)
run_case() {
  local name="$1" dir="$2" expected="$3" actual
  actual="$(cd "$dir" && GITHUB_OUTPUT='' "$SCRIPT" Dockerfile entrypoint.sh 2>/dev/null)" || actual="exit=$?"
  if [[ "$actual" == "$expected" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    echo "  expected: $(echo "$expected" | tr '\n' ' ')"
    echo "  actual:   $(echo "$actual" | tr '\n' ' ')"
    failures=$((failures + 1))
  fi
  rm -rf "$dir"
}

# A change to a file of the image since the latest tag is released as the next patch.
d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0; commit "$d" Dockerfile
run_case "Dockerfile changed" "$d" $'release=true\nversion=v0.3.1'

d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0; commit "$d" entrypoint.sh
run_case "entrypoint.sh changed" "$d" $'release=true\nversion=v0.3.1'

# Changes only to workflows and the Renovate config are not released.
d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0
commit "$d" .github/workflows/docker.yml; commit "$d" renovate.json
run_case "only .github and renovate.json changed" "$d" $'release=false\nversion='

d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0
run_case "nothing since the tag" "$d" $'release=false\nversion='

# The latest tag is chosen by version, not by name or date, and only vX.Y.Z counts.
d="$(new_repo)"; commit "$d" Dockerfile
at "$d" git tag v0.10.0; at "$d" git tag v0.9.9; at "$d" git tag v0.10.0.1; at "$d" git tag v1.0.0-rc1; at "$d" git tag latest
commit "$d" Dockerfile
run_case "semver ordering ignores other tag shapes" "$d" $'release=true\nversion=v0.10.1'

# The latest tag being on an older commit, with a newer change after it.
d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.2.2; commit "$d" Dockerfile; at "$d" git tag v0.3.0
commit "$d" README.md
run_case "changes before the latest tag do not count" "$d" $'release=false\nversion='

# With no vX.Y.Z tag there is no version to raise, so the script fails.
d="$(new_repo)"; commit "$d" Dockerfile
run_case "no version tag" "$d" "exit=1"

# Outputs are appended to GITHUB_OUTPUT when it is set.
d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0; commit "$d" Dockerfile
out="$(mktemp)"
(cd "$d" && GITHUB_OUTPUT="$out" "$SCRIPT" Dockerfile entrypoint.sh >/dev/null 2>&1)
if [[ "$(cat "$out")" == $'release=true\nversion=v0.3.1' ]]; then echo "ok   GITHUB_OUTPUT"; else echo "FAIL GITHUB_OUTPUT: $(cat "$out")"; failures=$((failures + 1)); fi
rm -rf "$d" "$out"

if (( failures > 0 )); then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
