#!/usr/bin/env bash
set -euo pipefail

# Build and install Zman from a local checkout using Homebrew cask.
# Usage:
#   ./distribution/install-local-homebrew.sh
#   ./distribution/install-local-homebrew.sh --open
#   ./distribution/install-local-homebrew.sh --help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPEN_AFTER_INSTALL=0

show_help() {
  cat <<'EOF'
Build and install Zman locally via a temporary Homebrew cask tap.

Usage:
  ./distribution/install-local-homebrew.sh [--open] [--help]

Options:
  --open   Launch /Applications/Zman-claude.app after install.
  --help   Show this help and exit.

Notes:
  - Creates/uses local tap: local/zman-local
  - Installs cask token: zman-local
  - Rebuilds release zip via make release
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open)
      OPEN_AFTER_INSTALL=1
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      echo "run with --help for usage" >&2
      exit 1
      ;;
  esac
done

if ! command -v brew >/dev/null 2>&1; then
  echo "error: Homebrew is not installed." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: Xcode command line tools are not available." >&2
  exit 1
fi

if [[ ! -f "${REPO_ROOT}/Makefile" ]]; then
  echo "error: Makefile not found. Run this script from inside the Zman repo." >&2
  exit 1
fi

echo "==> Building release zip via make release"
(
  cd "${REPO_ROOT}"
  make release
)

VERSION="$(grep 'MARKETING_VERSION' "${REPO_ROOT}/Zman-claude.xcodeproj/project.pbxproj" | head -1 | sed 's/.*= *//;s/ *;.*//')"
ZIP_PATH="${REPO_ROOT}/Zman-claude-${VERSION}.zip"

if [[ ! -f "${ZIP_PATH}" ]]; then
  echo "error: expected zip not found: ${ZIP_PATH}" >&2
  exit 1
fi

SHA256="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
TAP_NAME="local/zman-local"
CASK_TOKEN="zman-local"
TAP_REPO=""
ZIP_URL="file://${ZIP_PATH}"
ZIP_BASENAME="$(basename "${ZIP_PATH}")"

if ! brew tap | grep -qx "${TAP_NAME}"; then
  echo "==> Creating local tap: ${TAP_NAME}"
  brew tap-new "${TAP_NAME}" >/dev/null
fi

TAP_REPO="$(brew --repository "${TAP_NAME}")"
mkdir -p "${TAP_REPO}/Casks"
CASK_PATH="${TAP_REPO}/Casks/${CASK_TOKEN}.rb"

cat > "${CASK_PATH}" <<EOF
cask "${CASK_TOKEN}" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "${ZIP_URL}"
  name "Zman"
  desc "Highlights Calendar.app when viewing timezone differs from team timezone"
  homepage "https://github.com/plavrenko/zman"

  depends_on macos: ">= :tahoe"
  app "Zman-claude.app"

  caveats <<~EOS
    Zman is not notarized. If needed, remove quarantine:
      xattr -cr "#{appdir}/Zman-claude.app"
  EOS
end
EOF

echo "==> Installing local cask (${TAP_NAME}/${CASK_TOKEN})"
HOMEBREW_NO_AUTO_UPDATE=1 brew uninstall --cask "${CASK_TOKEN}" >/dev/null 2>&1 || true
if [[ -d "/Applications/Zman-claude.app" ]]; then
  echo "==> Removing existing /Applications/Zman-claude.app"
  rm -rf "/Applications/Zman-claude.app"
fi
echo "==> Clearing Homebrew cache for ${ZIP_BASENAME}"
rm -f "${HOME}/Library/Caches/Homebrew/downloads/"*"--${ZIP_BASENAME}" 2>/dev/null || true
HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask "${TAP_NAME}/${CASK_TOKEN}"
xattr -cr "/Applications/Zman-claude.app" 2>/dev/null || true

if [[ "${OPEN_AFTER_INSTALL}" -eq 1 ]]; then
  echo "==> Launching app"
  open -a "/Applications/Zman-claude.app"
fi

echo
echo "Installed: /Applications/Zman-claude.app"
echo "Version: ${VERSION}"
echo "Zip: ${ZIP_PATH}"
echo "SHA256: ${SHA256}"
