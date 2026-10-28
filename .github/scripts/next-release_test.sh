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

RENOVATE='renovate[bot] <29139614+renovate[bot]@users.noreply.github.com>'
RESPONDER='fraction-vuln-responder[bot] <348762456+fraction-vuln-responder[bot]@users.noreply.github.com>'
HUMAN='Someone <someone@example.com>'

# commit_as DIR FILE AUTHOR: a commit to FILE written by AUTHOR ("Name <email>").
commit_as() {
  local dir="$1" file="$2" author="$3"
  mkdir -p "$dir/$(dirname "$file")"
  echo "$RANDOM" >> "$dir/$file"
  at "$dir" git add "$file"
  at "$dir" git commit -q --author="$author" -m "change $file by ${author%% <*}"
}

# merge_branch DIR BRANCH: merges BRANCH into master with a merge commit by the test user.
merge_branch() {
  at "$1" git merge -q --no-ff -m "Merge $2" "$2"
}

# run_case NAME DIR EXPECTED [OPTION...]: EXPECTED is the script's output
# (release=..., version=...); OPTIONs go before the paths.
run_case() {
  local name="$1" dir="$2" expected="$3" actual
  shift 3
  actual="$(cd "$dir" && GITHUB_OUTPUT='' GITHUB_STEP_SUMMARY='' "$SCRIPT" "$@" Dockerfile entrypoint.sh 2>/dev/null)" || actual="exit=$?"
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

# With --bots-only, as after a vulnerability fix is merged, a release is cut
# only when every commit since the latest tag was written by Renovate or the
# vulnerability responder.
d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0; commit_as "$d" Dockerfile "$RESPONDER"
run_case "bots-only: a fix by the vulnerability responder" "$d" $'release=true\nversion=v0.3.1' --bots-only

d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0; commit_as "$d" Dockerfile "$RENOVATE"
run_case "bots-only: an update by Renovate" "$d" $'release=true\nversion=v0.3.1' --bots-only

d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0
commit_as "$d" Dockerfile "$RENOVATE"; commit_as "$d" entrypoint.sh "$RESPONDER"
run_case "bots-only: Renovate and the responder mixed" "$d" $'release=true\nversion=v0.3.1' --bots-only

d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0
commit_as "$d" Dockerfile "$RESPONDER"; commit_as "$d" Dockerfile "$HUMAN"
run_case "bots-only: a person's commit holds the release back" "$d" $'release=false\nversion=' --bots-only

# Every commit counts, not only those to the image's files.
d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0
commit_as "$d" README.md "$HUMAN"; commit_as "$d" Dockerfile "$RESPONDER"
run_case "bots-only: a person's commit outside the image holds it back too" "$d" $'release=false\nversion=' --bots-only

# The merge commit of the fix's pull request is made by whoever merged it, and is not counted.
d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0
at "$d" git checkout -q -b vuln-responder/fix; commit_as "$d" Dockerfile "$RESPONDER"
at "$d" git checkout -q master; merge_branch "$d" vuln-responder/fix
run_case "bots-only: merge commits are not counted" "$d" $'release=true\nversion=v0.3.1' --bots-only

# Commits before the latest tag do not count.
d="$(new_repo)"; commit_as "$d" Dockerfile "$HUMAN"; at "$d" git tag v0.3.0; commit_as "$d" Dockerfile "$RESPONDER"
run_case "bots-only: commits before the latest tag are not counted" "$d" $'release=true\nversion=v0.3.1' --bots-only

# Bots alone with nothing to release in the image's files still release nothing.
d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0; commit_as "$d" renovate.json "$RENOVATE"
run_case "bots-only: no change to the image" "$d" $'release=false\nversion=' --bots-only

# The weekly release, without --bots-only, releases a person's change as before.
d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0
commit_as "$d" Dockerfile "$RESPONDER"; commit_as "$d" Dockerfile "$HUMAN"
run_case "weekly: a person's commit is released" "$d" $'release=true\nversion=v0.3.1'

# A release held back is explained in the job summary: the commits that held
# it back, and how to release by hand.
d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0
commit_as "$d" Dockerfile "$RESPONDER"; commit_as "$d" Dockerfile "$HUMAN"
human="$(at "$d" git rev-parse --short HEAD)"; bot="$(at "$d" git rev-parse --short HEAD~1)"
summary="$(mktemp)"
(cd "$d" && GITHUB_OUTPUT='' GITHUB_STEP_SUMMARY="$summary" GITHUB_REPOSITORY=yuanying/docker-sshd \
  "$SCRIPT" --bots-only Dockerfile entrypoint.sh >/dev/null 2>&1)
if grep -q "$human" "$summary" && grep -q "Someone" "$summary" && ! grep -q "$bot" "$summary" \
  && grep -qF 'gh workflow run release.yml --repo yuanying/docker-sshd --ref master' "$summary"; then
  echo "ok   bots-only: job summary"
else
  echo "FAIL bots-only: job summary"; sed 's/^/  /' "$summary"; failures=$((failures + 1))
fi
rm -rf "$d" "$summary"

# The summary is left alone when the release goes ahead.
d="$(new_repo)"; commit "$d" Dockerfile; at "$d" git tag v0.3.0; commit_as "$d" Dockerfile "$RESPONDER"
summary="$(mktemp)"
(cd "$d" && GITHUB_OUTPUT='' GITHUB_STEP_SUMMARY="$summary" "$SCRIPT" --bots-only Dockerfile entrypoint.sh >/dev/null 2>&1)
if [[ ! -s "$summary" ]]; then echo "ok   bots-only: no summary when released"; else echo "FAIL bots-only: summary when released"; failures=$((failures + 1)); fi
rm -rf "$d" "$summary"

if (( failures > 0 )); then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
