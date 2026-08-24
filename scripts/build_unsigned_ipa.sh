#!/usr/bin/env bash
# Builds an unsigned .ipa from an Xcode project/workspace.
#
# Required env vars:
#   SOURCE_DIR       - directory containing the checked-out Xcode project
#   OUTPUT_DIR        - directory to write the .ipa (and logs) into
#
# Optional env vars:
#   PROJECT_SUBPATH  - subdirectory inside SOURCE_DIR where the .xcodeproj/.xcworkspace lives
#   SCHEME           - scheme to build; auto-detected from the project if empty
#   CONFIGURATION    - build configuration, defaults to "Release"

set -euo pipefail

SOURCE_DIR="${SOURCE_DIR:?SOURCE_DIR is required}"
OUTPUT_DIR="${OUTPUT_DIR:?OUTPUT_DIR is required}"
PROJECT_SUBPATH="${PROJECT_SUBPATH:-}"
SCHEME="${SCHEME:-}"
CONFIGURATION="${CONFIGURATION:-Release}"

SEARCH_DIR="$SOURCE_DIR"
if [[ -n "$PROJECT_SUBPATH" ]]; then
  SEARCH_DIR="$SOURCE_DIR/$PROJECT_SUBPATH"
fi

if [[ ! -d "$SEARCH_DIR" ]]; then
  echo "::error::Project directory not found: $SEARCH_DIR"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "== Looking for Xcode project/workspace under: $SEARCH_DIR"

WORKSPACE_PATH="$(find "$SEARCH_DIR" -maxdepth 6 -iname "*.xcworkspace" -not -path "*.xcodeproj/*" -not -path "*/Pods/*" | head -n1 || true)"
PROJECT_PATH="$(find "$SEARCH_DIR" -maxdepth 6 -iname "*.xcodeproj" -not -path "*/Pods/*" | head -n1 || true)"

PODFILE_PATH="$(find "$SEARCH_DIR" -maxdepth 3 -iname "Podfile" | head -n1 || true)"
if [[ -n "$PODFILE_PATH" ]]; then
  echo "== Podfile found, running pod install"
  (cd "$(dirname "$PODFILE_PATH")" && pod install --repo-update)
  # pod install generates/refreshes the .xcworkspace, re-scan for it.
  WORKSPACE_PATH="$(find "$SEARCH_DIR" -maxdepth 6 -iname "*.xcworkspace" -not -path "*.xcodeproj/*" -not -path "*/Pods/*" | head -n1 || true)"
fi

XCODEBUILD_TARGET_ARGS=()
if [[ -n "$WORKSPACE_PATH" ]]; then
  echo "== Using workspace: $WORKSPACE_PATH"
  XCODEBUILD_TARGET_ARGS=(-workspace "$WORKSPACE_PATH")
elif [[ -n "$PROJECT_PATH" ]]; then
  echo "== Using project: $PROJECT_PATH"
  XCODEBUILD_TARGET_ARGS=(-project "$PROJECT_PATH")
else
  echo "::error::No .xcworkspace or .xcodeproj found under $SEARCH_DIR"
  exit 1
fi

if [[ -z "$SCHEME" ]]; then
  echo "== No scheme provided, auto-detecting shared schemes"
  SCHEME_LIST_JSON="$(xcodebuild -list -json "${XCODEBUILD_TARGET_ARGS[@]}")"
  SCHEME="$(python3 -c '
import json, sys
data = json.loads(sys.argv[1])
container = data.get("project") or data.get("workspace") or {}
schemes = container.get("schemes", [])
if not schemes:
    sys.exit(1)
print(schemes[0])
' "$SCHEME_LIST_JSON")"
  echo "== Auto-detected scheme: $SCHEME"
fi

if [[ -z "$SCHEME" ]]; then
  echo "::error::Could not determine a scheme to build. Pass one explicitly via the 'scheme' input."
  exit 1
fi

ARCHIVE_PATH="$OUTPUT_DIR/App.xcarchive"

echo "== Archiving (unsigned) scheme '$SCHEME', configuration '$CONFIGURATION'"
set -x
xcodebuild archive \
  "${XCODEBUILD_TARGET_ARGS[@]}" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  CODE_SIGNING_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  ONLY_ACTIVE_ARCH=NO
set +x

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -iname "*.app" | head -n1 || true)"
if [[ -z "$APP_PATH" ]]; then
  echo "::error::Archive succeeded but no .app was found in $ARCHIVE_PATH/Products/Applications"
  exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
echo "== Packaging unsigned IPA for $APP_NAME"

PAYLOAD_DIR="$OUTPUT_DIR/Payload"
rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"

IPA_NAME="${APP_NAME%.app}.ipa"
IPA_PATH="$OUTPUT_DIR/$IPA_NAME"

(cd "$OUTPUT_DIR" && zip -r -y -q "$IPA_NAME" "Payload")

rm -rf "$PAYLOAD_DIR"

echo "== Unsigned IPA written to: $IPA_PATH"
echo "ipa_path=$IPA_PATH" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "ipa_name=$IPA_NAME" >> "${GITHUB_OUTPUT:-/dev/null}"
