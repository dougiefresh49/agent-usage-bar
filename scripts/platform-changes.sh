#!/bin/bash
set -euo pipefail

# Report whether commits since the last platform tag touch platform-relevant paths.
# Usage: bash scripts/platform-changes.sh <macos|android>
# Outputs (GITHUB_OUTPUT): skip=true|false, last_tag=<tag or empty>

PLATFORM="${1:-}"
if [[ "$PLATFORM" != "macos" && "$PLATFORM" != "android" ]]; then
  echo "Usage: $0 <macos|android>" >&2
  exit 1
fi

if [ -z "${GITHUB_OUTPUT:-}" ]; then
  _PLATFORM_CHANGES_OUT="$(mktemp)"
  export GITHUB_OUTPUT="$_PLATFORM_CHANGES_OUT"
  trap 'echo "--- GITHUB_OUTPUT (local) ---"; cat "$_PLATFORM_CHANGES_OUT" 2>/dev/null || true; rm -f "$_PLATFORM_CHANGES_OUT"' EXIT
fi

latest_macos_tag() {
  git tag --list 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true
}

latest_android_tag() {
  git tag --list 'v*-android' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+-android$' | head -n 1 || true
}

path_regex_for_platform() {
  case "$1" in
    macos)
      printf '%s\n' '^(macos/|scripts/(resolve-bump|platform-changes)\.sh|Makefile|\.github/workflows/(build-macos|bump-macos|release)\.yml)'
      ;;
    android)
      printf '%s\n' '^(android/|Makefile|\.github/workflows/(build-android|bump-android|release-android)\.yml)'
      ;;
  esac
}

if [[ "$PLATFORM" == "macos" ]]; then
  LAST_TAG="$(latest_macos_tag)"
else
  LAST_TAG="$(latest_android_tag)"
fi

echo "last_tag=${LAST_TAG}" >> "$GITHUB_OUTPUT"

if [ -z "$LAST_TAG" ]; then
  echo "skip=false" >> "$GITHUB_OUTPUT"
  echo "No existing ${PLATFORM} version tags; continuing."
  exit 0
fi

COMMITS="$(git log "${LAST_TAG}..HEAD" --oneline | wc -l | tr -d ' ')"
if [ "$COMMITS" = "0" ]; then
  echo "skip=true" >> "$GITHUB_OUTPUT"
  echo "No commits since ${LAST_TAG}; skipping tag."
  exit 0
fi

PATH_REGEX="$(path_regex_for_platform "$PLATFORM")"
CHANGED="$(git diff --name-only "${LAST_TAG}..HEAD" || true)"
if echo "$CHANGED" | grep -qE "$PATH_REGEX"; then
  echo "skip=false" >> "$GITHUB_OUTPUT"
  echo "Found ${COMMITS} commit(s) since ${LAST_TAG} with ${PLATFORM}-relevant path changes."
else
  echo "skip=true" >> "$GITHUB_OUTPUT"
  echo "Commits since ${LAST_TAG} do not touch ${PLATFORM}-relevant paths; skipping tag."
fi
