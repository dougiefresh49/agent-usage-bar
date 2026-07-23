#!/bin/bash
set -euo pipefail

# GitHub Actions sets GITHUB_OUTPUT. For local runs, use a temp file and print it on exit.
if [ -z "${GITHUB_OUTPUT:-}" ]; then
  _RESOLVE_BUMP_OUT="$(mktemp)"
  export GITHUB_OUTPUT="$_RESOLVE_BUMP_OUT"
  trap 'echo "--- GITHUB_OUTPUT (local) ---"; cat "$_RESOLVE_BUMP_OUT" 2>/dev/null || true; rm -f "$_RESOLVE_BUMP_OUT"' EXIT
fi

# Resolve semver bump type from commit messages.
# Priority: explicit [major]/[minor]/[patch] keyword in HEAD commit → Gemini analysis → patch fallback.
# Outputs: bump_type (major|minor|patch), current_version, new_version (vX.Y.Z)

latest_version_tag() {
  git tag --list 'v*' --sort=-v:refname | head -n 1
}

bump_semver() {
  local version="$1"
  local bump="$2"
  version="${version#v}"

  local major minor patch
  IFS=. read -r major minor patch <<< "$version"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"

  case "$bump" in
    major) printf 'v%s.0.0\n' "$((major + 1))" ;;
    minor) printf 'v%s.%s.0\n' "$major" "$((minor + 1))" ;;
    patch) printf 'v%s.%s.%s\n' "$major" "$minor" "$((patch + 1))" ;;
    *)
      echo "Unknown bump type: $bump" >&2
      return 1
      ;;
  esac
}

write_outputs() {
  local bump_type="$1"
  local current_version="$2"
  local new_version
  new_version="$(bump_semver "$current_version" "$bump_type")"

  {
    echo "bump_type=$bump_type"
    echo "current_version=$current_version"
    echo "new_version=$new_version"
  } >> "$GITHUB_OUTPUT"

  echo "Resolved bump: ${bump_type} (${current_version} → ${new_version})"
}

CURRENT_TAG="$(latest_version_tag || true)"
CURRENT_VERSION="${CURRENT_TAG:-v0.0.0}"

# Commits since last version tag (or all commits if no tags exist)
if [ -n "$CURRENT_TAG" ]; then
  LAST_REF="$CURRENT_TAG"
else
  LAST_REF="$(git rev-list --max-parents=0 HEAD)"
fi

COMMITS="$(git log "${LAST_REF}..HEAD" --pretty=format:"%s" -30 || true)"

if [ -z "$COMMITS" ]; then
  COMMITS="$(git log -1 --pretty=format:"%s")"
fi

HEAD_MSG="$(git log -1 --pretty=format:"%s")"

# 1. Check for explicit keyword overrides in the HEAD commit
if echo "$HEAD_MSG" | grep -qi '\[major\]'; then
  write_outputs major "$CURRENT_VERSION"
  exit 0
fi

if echo "$HEAD_MSG" | grep -qi '\[minor\]'; then
  write_outputs minor "$CURRENT_VERSION"
  exit 0
fi

if echo "$HEAD_MSG" | grep -qi '\[patch\]'; then
  write_outputs patch "$CURRENT_VERSION"
  exit 0
fi

# 2. Ask Gemini to classify the bump
if [ -n "${GEMINI_API_KEY:-}" ]; then
  PROMPT="You are a semver versioning assistant. Given the current version and recent git commits for a macOS menu bar app (Agent Usage Bar), determine if the next version bump should be major, minor, or patch.

Rules:
- major: breaking changes, large rewrites, incompatible behavior changes
- minor: new features, significant enhancements, new providers/UI surfaces
- patch: bug fixes, small tweaks, dependency updates, refactoring, docs, CI/config changes

Current version: ${CURRENT_VERSION#v}

Recent commits:
${COMMITS}

Reply with exactly one word: major, minor, or patch."

  # Omit maxOutputTokens — use API default so thinking + short answer are not truncated.
  PAYLOAD=$(jq -n --arg prompt "$PROMPT" '{
    contents: [{parts: [{text: $prompt}]}],
    generationConfig: {temperature: 0}
  }')

  RESPONSE=$(curl -sf --max-time 120 \
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=${GEMINI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null || echo "")

  if [ -z "$RESPONSE" ]; then
    echo "Gemini returned empty response (curl failed, timeout, or non-2xx)."
  else
    BUMP=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text // ""' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    if [[ "$BUMP" == "major" || "$BUMP" == "minor" || "$BUMP" == "patch" ]]; then
      write_outputs "$BUMP" "$CURRENT_VERSION"
      exit 0
    fi

    echo "Gemini response was not usable, falling back to patch"
    echo "Parsed bump candidate (normalized): '${BUMP}'"
    FINISH=$(echo "$RESPONSE" | jq -r '.candidates[0].finishReason // empty')
    if [ -n "$FINISH" ]; then
      echo "Gemini finishReason: ${FINISH}"
    fi
    API_ERR=$(echo "$RESPONSE" | jq -r '.error.message // empty')
    if [ -n "$API_ERR" ]; then
      echo "Gemini API error field: ${API_ERR}"
    fi
    echo "Raw response body (first 2000 chars): ${RESPONSE:0:2000}"
  fi
fi

# 3. Fallback
write_outputs patch "$CURRENT_VERSION"
