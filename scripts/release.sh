#!/usr/bin/env bash
# Builds a release of Stop Typing App into dist/: a signed (and, when possible, notarized) DMG for
# people and Homebrew, a zip and appcast.xml for Sparkle, and the DMG's SHA-256 for the cask.
#
#   scripts/release.sh            prepare dist/ (the default; never publishes anything)
#   scripts/release.sh publish    prepare, then create the GitHub release and update the cask
#
# Environment:
#   GITHUB_REPO      owner/name the release goes to (default kevintraver/stop-typing-app)
#   NOTARY_PROFILE   notarytool keychain profile (default stop-typing)
#   NOTARY_KEY_ID, NOTARY_ISSUER, NOTARY_KEY
#                    an App Store Connect API key to notarize with instead of the profile
#                    (NOTARY_KEY defaults to ~/.appstoreconnect/private_keys/AuthKey_<id>.p8)
#   TAP_DIR          local checkout of the Homebrew tap, for publish (default ~/Code/homebrew-tap)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-prepare}"
case "${MODE}" in
  prepare | publish) ;;
  *)
    echo "usage: $0 [prepare|publish]" >&2
    exit 2
    ;;
esac

APP_NAME="Stop Typing App"
TEAM_ID="8EDDZ23NT2"
GITHUB_REPO="${GITHUB_REPO:-kevintraver/stop-typing-app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-stop-typing}"
# project.yml is the single source of the version.
VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' "${REPO_DIR}/project.yml" | head -1)"

DIST_DIR="${REPO_DIR}/dist"
# Kept apart from the Debug build in build/ so a release never disturbs `make build`.
DERIVED_DATA="${REPO_DIR}/build/release"
ARCHIVE="${DERIVED_DATA}/StopTyping.xcarchive"
EXPORT_DIR="${DERIVED_DATA}/export"
STAGING_DIR="${DERIVED_DATA}/dmg"
UPDATES_DIR="${DIST_DIR}/updates"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG="${DIST_DIR}/StopTypingApp-${VERSION}.dmg"
LATEST_DMG="${DIST_DIR}/StopTypingApp-latest.dmg"
ZIP="${UPDATES_DIR}/StopTypingApp-${VERSION}.zip"
APPCAST="${UPDATES_DIR}/appcast.xml"
SPARKLE_BIN="${DERIVED_DATA}/SourcePackages/artifacts/sparkle/Sparkle/bin"

warn() {
  printf "\nwarning: %s\n" "$*" >&2
}

cd "${REPO_DIR}"
echo "==> Stop Typing App ${VERSION} for ${GITHUB_REPO}"

if [[ "${MODE}" == "publish" && -n "$(git status --porcelain)" ]]; then
  echo "error: the working tree has uncommitted changes; publish only what's committed" >&2
  exit 1
fi

# Sparkle decides whether an update is newer by build number, not version, so a release that doesn't
# raise CURRENT_PROJECT_VERSION is silently never offered to anyone. Compare with the published appcast.
BUILD="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' "${REPO_DIR}/project.yml" | head -1)"
if [[ "${MODE}" == "publish" ]]; then
  PUBLISHED_BUILD="$(curl -fsSL "https://github.com/${GITHUB_REPO}/releases/latest/download/appcast.xml" 2>/dev/null \
    | sed -nE 's|.*<sparkle:version>([0-9]+)</sparkle:version>.*|\1|p' | sort -n | tail -1)"
  if [[ -n "${PUBLISHED_BUILD}" && "${BUILD}" -le "${PUBLISHED_BUILD}" ]]; then
    echo "error: CURRENT_PROJECT_VERSION ${BUILD} isn't above the published build ${PUBLISHED_BUILD} in project.yml;" \
      "Sparkle would never offer this release as an update" >&2
    exit 1
  fi
fi

# --- Signing identity ---------------------------------------------------------------------------
# Only a Developer ID Application certificate produces something Gatekeeper accepts on other Macs.
# Without one the pipeline still runs end to end, signed with Apple Development (or ad hoc), so
# it can be tested before the certificate exists.
IDENTITIES="$(security find-identity -v -p codesigning)"
if grep -q "Developer ID Application: .*(${TEAM_ID})" <<<"${IDENTITIES}"; then
  SIGNING="developer-id"
  XCODE_IDENTITY="Developer ID Application"
  SIGN_ID="$(awk -v team="(${TEAM_ID})" '/Developer ID Application/ && index($0, team) { print $2; exit }' <<<"${IDENTITIES}")"
elif grep -q "Apple Development: " <<<"${IDENTITIES}"; then
  SIGNING="development"
  XCODE_IDENTITY="Apple Development"
  SIGN_ID="$(awk '/Apple Development: / { print $2; exit }' <<<"${IDENTITIES}")"
else
  SIGNING="adhoc"
  XCODE_IDENTITY="-"
  SIGN_ID="-"
fi

if [[ "${SIGNING}" != "developer-id" ]]; then
  cat >&2 <<WARNING

  ******************************************************************************************
  *  No "Developer ID Application" certificate for team ${TEAM_ID} is installed.
  *  Signing with: ${SIGNING} (${SIGN_ID})
  *
  *  This release is for testing the pipeline only. It won't be notarized, and Gatekeeper
  *  will refuse to open it on any other Mac. Don't publish it.
  ******************************************************************************************

WARNING
fi

# --- Project and Sparkle key --------------------------------------------------------------------
xcodegen generate --quiet
# Resolving packages first puts Sparkle's command-line tools (generate_keys, generate_appcast)
# where the rest of this script expects them.
xcodebuild -resolvePackageDependencies -quiet -project StopTyping.xcodeproj -scheme StopTyping \
  -derivedDataPath "${DERIVED_DATA}"

# Sparkle keeps its EdDSA private key in the login keychain under this service and account.
# Checking without -w doesn't read the secret, so this never shows a keychain prompt.
SPARKLE_PUBLIC_KEY=""
if security find-generic-password -s "https://sparkle-project.org" -a ed25519 >/dev/null 2>&1; then
  # -p only looks up the existing key; generate_keys without it would create a new one.
  SPARKLE_PUBLIC_KEY="$("${SPARKLE_BIN}/generate_keys" -p)"
else
  warn "no Sparkle EdDSA key in the keychain: the app's updater stays off and no appcast is made"
fi

# --- Archive and export -------------------------------------------------------------------------
rm -rf "${ARCHIVE}" "${EXPORT_DIR}" "${STAGING_DIR}" "${UPDATES_DIR}" "${APP_BUNDLE}" \
  "${DMG}" "${LATEST_DMG}"
mkdir -p "${DIST_DIR}" "${UPDATES_DIR}"

ARCHIVE_SETTINGS=(
  "GITHUB_REPO=${GITHUB_REPO}"
  "SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY}"
)
if [[ "${SIGNING}" != "developer-id" ]]; then
  # A secure timestamp only matters for notarization, and skipping it lets this run offline.
  ARCHIVE_SETTINGS+=("CODE_SIGN_IDENTITY=${XCODE_IDENTITY}" "OTHER_CODE_SIGN_FLAGS=")
fi

echo "==> Archiving"
xcodebuild archive -quiet -project StopTyping.xcodeproj -scheme StopTyping -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "${DERIVED_DATA}" -archivePath "${ARCHIVE}" \
  "${ARCHIVE_SETTINGS[@]}"

if [[ "${SIGNING}" == "developer-id" ]]; then
  echo "==> Exporting for Developer ID"
  # Exporting re-signs Sparkle's XPC services and helpers with Developer ID, keeps the hardened
  # runtime, and strips get-task-allow, all of which notarization requires.
  EXPORT_OPTIONS="${DERIVED_DATA}/ExportOptions.plist"
  cat >"${EXPORT_OPTIONS}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -quiet -archivePath "${ARCHIVE}" -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}"
  /usr/bin/ditto "${EXPORT_DIR}/${APP_NAME}.app" "${APP_BUNDLE}"
else
  echo "==> Copying the app out of the archive (no Developer ID to export with)"
  /usr/bin/ditto "${ARCHIVE}/Products/Applications/${APP_NAME}.app" "${APP_BUNDLE}"
  # Without an export, Xcode has re-signed Sparkle.framework but left its XPC services and helpers
  # with Sparkle's ad hoc signature. Re-sign them inside out, as Sparkle's sandboxing guide does by
  # hand, then the app itself. Never --deep, which would replace each helper's own signing settings.
  # Note: as Sparkle ships them, the Downloader and Installer have no entitlements, so they run outside
  # the sandbox; only the app itself (which sees the keyboard) is sandboxed, with no network access.
  SIGN=(codesign --force --options runtime --sign "${SIGN_ID}")
  SPARKLE_VERSION_DIR="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B"
  "${SIGN[@]}" "${SPARKLE_VERSION_DIR}/XPCServices/Installer.xpc"
  "${SIGN[@]}" --preserve-metadata=entitlements "${SPARKLE_VERSION_DIR}/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "${SPARKLE_VERSION_DIR}/Autoupdate"
  "${SIGN[@]}" "${SPARKLE_VERSION_DIR}/Updater.app"
  "${SIGN[@]}" "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
  "${SIGN[@]}" --preserve-metadata=identifier,entitlements "${APP_BUNDLE}"
fi

echo "==> Verifying the app's signature"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
if [[ "${SIGNING}" == "developer-id" ]] \
  && codesign -d --entitlements - --xml "${APP_BUNDLE}" 2>/dev/null | grep -q "get-task-allow"; then
  echo "error: the exported app still has get-task-allow, which notarization rejects" >&2
  exit 1
fi

# --- DMG ----------------------------------------------------------------------------------------
echo "==> Building the DMG"
mkdir -p "${STAGING_DIR}"
/usr/bin/ditto "${APP_BUNDLE}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"
# APFS with ULFO (lzfse) compression: the smallest image that mounts on macOS 10.15+. macOS 27
# marks hdiutil create as deprecated in favour of `diskutil image create`, which older macOS lacks.
hdiutil create -quiet -fs APFS -format ULFO -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" "${DMG}"
if [[ "${SIGNING}" == "developer-id" ]]; then
  codesign --force --timestamp --sign "${SIGN_ID}" "${DMG}"
else
  codesign --force --sign "${SIGN_ID}" "${DMG}"
fi

# --- Notarization -------------------------------------------------------------------------------
# The DMG is submitted because it carries the app, so one ticket covers both; stapling them lets
# Gatekeeper accept either without a network connection.
NOTARIZED=0
if [[ "${SIGNING}" == "developer-id" ]]; then
  NOTARY_AUTH=()
  if [[ -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    NOTARY_KEY="${NOTARY_KEY:-${HOME}/.appstoreconnect/private_keys/AuthKey_${NOTARY_KEY_ID}.p8}"
    NOTARY_AUTH=(--key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER}")
  # notarytool has no offline way to ask whether a profile exists; history is its cheapest call.
  elif xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    NOTARY_AUTH=(--keychain-profile "${NOTARY_PROFILE}")
  fi

  if ((${#NOTARY_AUTH[@]})); then
    echo "==> Notarizing (this usually takes a few minutes)"
    xcrun notarytool submit "${DMG}" "${NOTARY_AUTH[@]}" --wait --timeout 30m
    xcrun stapler staple "${DMG}"
    xcrun stapler staple "${APP_BUNDLE}"
    spctl -a -vv -t install "${DMG}"
    NOTARIZED=1
  else
    warn "no notarytool profile \"${NOTARY_PROFILE}\" or API key: the DMG isn't notarized, so Gatekeeper will block it"
  fi
fi
cp -f "${DMG}" "${LATEST_DMG}"

# --- Sparkle update -----------------------------------------------------------------------------
# Zipped after stapling so updates carry the notarization ticket too.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP}"
if [[ -n "${SPARKLE_PUBLIC_KEY}" ]]; then
  echo "==> Generating appcast.xml"
  # Reads the private key from the keychain (macOS may ask to allow it) and signs the zip with it.
  "${SPARKLE_BIN}/generate_appcast" \
    --download-url-prefix "https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/" \
    -o "${APPCAST}" \
    "${UPDATES_DIR}"
fi

SHA256="$(shasum -a 256 "${DMG}" | awk '{ print $1 }')"
echo
echo "Prepared release ${VERSION} (signing: ${SIGNING}, notarized: $( ((NOTARIZED)) && echo yes || echo no ))"
echo "  ${DMG}"
echo "  ${LATEST_DMG}"
echo "  ${ZIP}"
[[ -f "${APPCAST}" ]] && echo "  ${APPCAST}"
echo "DMG SHA-256: ${SHA256}"

[[ "${MODE}" == "publish" ]] || exit 0

# --- Publish ------------------------------------------------------------------------------------
if [[ "${NOTARIZED}" != 1 || ! -f "${APPCAST}" ]]; then
  echo "error: refusing to publish a release that isn't notarized or has no appcast" >&2
  exit 1
fi

echo "==> Publishing v${VERSION} to ${GITHUB_REPO}"
# The appcast rides along on every release, so .../releases/latest/download/appcast.xml (the app's
# SUFeedURL) always serves the newest one. The tag points at the commit that was built, so push it first.
gh release create "v${VERSION}" --repo "${GITHUB_REPO}" --target "$(git rev-parse HEAD)" \
  --title "${APP_NAME} ${VERSION}" --generate-notes \
  "${DMG}" "${LATEST_DMG}" "${ZIP}" "${APPCAST}"

"${REPO_DIR}/scripts/update-cask.sh" "${VERSION}" "${SHA256}" ${TAP_DIR:+"${TAP_DIR}"}
