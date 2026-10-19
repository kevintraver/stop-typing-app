#!/usr/bin/env bash
# Writes the Homebrew cask for a release into a local checkout of the tap, from the template in
# packaging/homebrew. It doesn't commit or push; it prints the commands to do that.
#
#   scripts/update-cask.sh <version> <dmg-sha256> [tap-dir]
#
# tap-dir defaults to ~/Code/homebrew-tap (a clone of kevintraver/homebrew-tap).
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <version> <dmg-sha256> [tap-dir]" >&2
  exit 2
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$1"
SHA256="$2"
TAP_DIR="${3:-${HOME}/Code/homebrew-tap}"
TEMPLATE="${REPO_DIR}/packaging/homebrew/stop-typing-app.rb"
CASK="${TAP_DIR}/Casks/stop-typing-app.rb"

if [[ ! "${SHA256}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: \"${SHA256}\" isn't a SHA-256 (64 lowercase hex digits)" >&2
  exit 2
fi
if [[ ! -d "${TAP_DIR}/.git" ]]; then
  echo "error: ${TAP_DIR} isn't a git checkout; clone it with: gh repo clone kevintraver/homebrew-tap \"${TAP_DIR}\"" >&2
  exit 1
fi

mkdir -p "${TAP_DIR}/Casks"
# Only the first version and sha256 stanzas are replaced, so the url's #{version} stays intact.
sed -E \
  -e "1,/^  version \"/s/^  version \".*\"$/  version \"${VERSION}\"/" \
  -e "1,/^  sha256 \"/s/^  sha256 \".*\"$/  sha256 \"${SHA256}\"/" \
  "${TEMPLATE}" >"${CASK}"

echo "Wrote ${CASK}:"
grep -E '^  (version|sha256) ' "${CASK}"
cat <<EOF

Check it, then commit and push the tap:
  brew style "${CASK}"
  git -C "${TAP_DIR}" add Casks/stop-typing-app.rb
  git -C "${TAP_DIR}" commit -m "stop-typing-app ${VERSION}"
  git -C "${TAP_DIR}" push
EOF
