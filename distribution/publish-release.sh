#!/usr/bin/env bash
set -euo pipefail

# Publish GitHub release for current repo in one command.
# - creates/pushes tag v<version> (unless already present)
# - uploads zip asset (clobber)
# - ensures release is published (not draft)
#
# Usage:
#   ./distribution/publish-release.sh
#   ./distribution/publish-release.sh --version 1.2.1
#   ./distribution/publish-release.sh --version 1.2.1 --zip /path/to/Zman-claude-1.2.1.zip
#   ./distribution/publish-release.sh --allow-dirty
#   ./distribution/publish-release.sh --help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION=""
ZIP_PATH=""
ALLOW_DIRTY=0

show_help() {
  cat <<'EOF'
Publish a GitHub release for Zman in one command.

Usage:
  ./distribution/publish-release.sh [--version X.Y.Z] [--zip /path/to/zip] [--allow-dirty] [--help]

Options:
  --version X.Y.Z   Release version. Defaults to MARKETING_VERSION from project.pbxproj.
  --zip PATH        Zip asset path. Defaults to ./Zman-claude-<version>.zip
  --allow-dirty     Allow running with uncommitted changes.
  --help            Show this help and exit.

Behavior:
  - Ensures tag v<version> exists locally and on origin.
  - Creates release if missing, otherwise uploads asset with --clobber.
  - Publishes release if it is currently draft.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --zip)
      ZIP_PATH="${2:-}"
      shift 2
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

require_cmd git
require_cmd gh
require_cmd awk
require_cmd sed
require_cmd jq

cd "${REPO_ROOT}"

if [[ "${ALLOW_DIRTY}" -ne 1 ]] && [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is not clean. Commit/stash or use --allow-dirty." >&2
  git status --short
  exit 1
fi

if [[ -z "${VERSION}" ]]; then
  VERSION="$(grep 'MARKETING_VERSION' Zman-claude.xcodeproj/project.pbxproj | head -1 | sed 's/.*= *//;s/ *;.*//')"
fi

if [[ -z "${ZIP_PATH}" ]]; then
  ZIP_PATH="${REPO_ROOT}/Zman-claude-${VERSION}.zip"
fi

if [[ ! -f "${ZIP_PATH}" ]]; then
  echo "error: zip not found: ${ZIP_PATH}" >&2
  exit 1
fi

TAG="v${VERSION}"
ASSET_NAME="$(basename "${ZIP_PATH}")"

echo "==> Version: ${VERSION}"
echo "==> Tag: ${TAG}"
echo "==> Asset: ${ASSET_NAME}"

# Create and push tag if missing.
if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "==> Local tag ${TAG} already exists"
else
  echo "==> Creating local tag ${TAG}"
  git tag "${TAG}"
fi

if git ls-remote --tags origin | grep -q "refs/tags/${TAG}$"; then
  echo "==> Remote tag ${TAG} already exists"
else
  echo "==> Pushing tag ${TAG}"
  git push origin "${TAG}"
fi

# Try to get release by tag.
set +e
RELEASE_JSON="$(gh api "repos/{owner}/{repo}/releases/tags/${TAG}" 2>/dev/null)"
HAS_RELEASE=$?
set -e

if [[ "${HAS_RELEASE}" -ne 0 ]]; then
  echo "==> No release object yet; creating published release ${TAG}"
  NOTES_FILE="$(mktemp /tmp/zman-release-notes.XXXXXX.md)"
  trap 'rm -f "${NOTES_FILE}"' EXIT
  awk "/^## \\[${VERSION//./\\.}\\]/{found=1; next} /^## \\[/{if(found) exit} found{print}" CHANGELOG.md > "${NOTES_FILE}"
  gh release create "${TAG}" "${ZIP_PATH}" --title "${TAG}" --notes-file "${NOTES_FILE}"
else
  echo "==> Release ${TAG} exists; uploading asset with --clobber"
  gh release upload "${TAG}" "${ZIP_PATH}" --clobber

  # Fetch fresh release JSON for id and draft state.
  RELEASE_JSON="$(gh api "repos/{owner}/{repo}/releases/tags/${TAG}")"
  RELEASE_ID="$(echo "${RELEASE_JSON}" | jq -r '.id')"
  IS_DRAFT="$(echo "${RELEASE_JSON}" | jq -r '.draft')"

  if [[ "${IS_DRAFT}" == "true" ]]; then
    echo "==> Publishing existing draft release ${TAG}"
    gh api "repos/{owner}/{repo}/releases/${RELEASE_ID}" \
      --method PATCH \
      -f draft=false >/dev/null
  fi
fi

echo
echo "Release ready:"
echo "https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/${TAG}"
