#!/usr/bin/env bash
# Works out the release version for the current commit.
#
# The latest vX.Y.Z git tag is the source of truth. The APP_VERSION variable is
# also considered, so it can seed the first release or force a jump forward;
# the higher of the two is bumped.
#
# Inputs (environment variables):
#   BUMP            auto | patch | minor | major. auto picks the bump from
#                   LABELS and MESSAGE, defaulting to patch.
#   LABELS          PR label names, one per line: major, minor or patch
#                   (also semver:major, semver:minor, semver:patch).
#   MESSAGE         Commit message; #major, #minor or #patch choose the bump.
#   REUSE_HEAD_TAG  true: if HEAD already has a version tag (a re-run), reuse it.
#   BASE_VERSION    Current APP_VERSION variable (optional).
#
# Outputs (to $GITHUB_OUTPUT when set, otherwise stdout):
#   version   The release version, for example 1.2.4.
#   previous  The version it was bumped from.
#   bump      major | minor | patch | reuse.
set -euo pipefail

core='^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
out=${GITHUB_OUTPUT:-/dev/stdout}

highest() { grep -E "$core" | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1; }

emit() {
  echo "version=$1" >> "$out"
  echo "previous=$2" >> "$out"
  echo "bump=$3" >> "$out"
  echo "Release version: $1 (from ${2:-none}, $3)" >&2
}

if [[ "${REUSE_HEAD_TAG:-false}" == true ]]; then
  head_version=$(git tag --points-at HEAD --list 'v*' | highest || true)
  if [[ -n "$head_version" ]]; then
    emit "$head_version" "$head_version" reuse
    exit 0
  fi
fi

bump=${BUMP:-auto}
if [[ "$bump" == auto ]]; then
  bump=patch
  labels=$(printf '%s\n' "${LABELS:-}" | tr '[:upper:]' '[:lower:]' | sed 's/^semver://')
  message=$(printf '%s\n' "${MESSAGE:-}" | tr '[:upper:]' '[:lower:]')
  if grep -qx 'major' <<<"$labels" || grep -q '#major' <<<"$message"; then
    bump=major
  elif grep -qx 'minor' <<<"$labels" || grep -q '#minor' <<<"$message"; then
    bump=minor
  fi
fi
case "$bump" in
  major | minor | patch) ;;
  *) echo "::error::Unknown bump '$bump'; use auto, patch, minor or major." >&2; exit 1 ;;
esac

latest_tag=$(git tag --list 'v*' | highest || true)
# Ignore any pre-release or build suffix on the variable (1.2.3-rc.1 -> 1.2.3).
base_var=${BASE_VERSION:-}
base_var=${base_var%%[-+]*}
if [[ -n "$base_var" && ! "$base_var" =~ $core ]]; then
  echo "::warning::Ignoring APP_VERSION '$BASE_VERSION'; it is not a SemVer version." >&2
  base_var=
fi
previous=$(printf '%s\n' "$latest_tag" "$base_var" "0.0.0" | highest)

IFS=. read -r major minor patch <<<"$previous"
case "$bump" in
  major) version="$((major + 1)).0.0" ;;
  minor) version="$major.$((minor + 1)).0" ;;
  patch) version="$major.$minor.$((patch + 1))" ;;
esac
emit "$version" "$previous" "$bump"
