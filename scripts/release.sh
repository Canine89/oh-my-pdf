#!/usr/bin/env bash
#
# oh-my-pdf 배포 빌더.
#
#   ./scripts/release.sh
#   ./scripts/release.sh 0.1.1
#   ./scripts/release.sh 0.1.1 --publish

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

SCHEME="oh-my-pdf"
PROJECT="oh-my-pdf.xcodeproj"
APP_NAME="oh-my-pdf.app"
VOL_NAME="oh-my-pdf"
REPO="Canine89/oh-my-pdf"
DD="$ROOT/build/dd"
DIST="$ROOT/dist"
UPDATES="$ROOT/updates"
APPCAST="$ROOT/appcast.xml"

VERSION_ARG=""
PUBLISH=0
for a in "$@"; do
  case "$a" in
    --publish) PUBLISH=1 ;;
    *) VERSION_ARG="$a" ;;
  esac
done

if [ -n "$VERSION_ARG" ]; then
  CUR_MARKETING=$(grep 'MARKETING_VERSION:' project.yml | grep -oE '"[^"]*"' | tr -d '"' | head -1)
  if [ "$VERSION_ARG" != "$CUR_MARKETING" ]; then
    CUR_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | grep -oE '[0-9]+' | head -1)
    NEW_BUILD=$((CUR_BUILD + 1))
    echo "▸ 버전 올림: $CUR_MARKETING → $VERSION_ARG (빌드 $CUR_BUILD → $NEW_BUILD)"
    sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION_ARG\"/" project.yml
    sed -i '' "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" project.yml
  else
    echo "▸ 버전 동일($VERSION_ARG) → 올림 생략"
  fi
fi

echo "▸ 프로젝트 재생성"
command -v xcodegen >/dev/null || { echo "✗ 'brew install xcodegen' 필요"; exit 1; }
xcodegen generate >/dev/null

echo "▸ Release 빌드"
rm -rf "$DD" "$DIST"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DD" clean build >/dev/null

APP="$DD/Build/Products/Release/$APP_NAME"
[ -d "$APP" ] || { echo "✗ 빌드 결과 앱 없음: $APP"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")"
MINOS="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")"

SIGN_ID="oh-my-pdf"
if security find-identity 2>/dev/null | grep -q "\"$SIGN_ID\""; then
  echo "▸ 자체서명 인증서로 재서명 ($SIGN_ID)"
  codesign --remove-signature "$APP" 2>/dev/null || true
  codesign --force --deep --sign "$SIGN_ID" "$APP"
  codesign --verify --deep --strict "$APP"
else
  echo "▸ '$SIGN_ID' 인증서 없음 → Xcode 서명 결과 유지"
fi

echo "▸ 패키징"
mkdir -p "$DIST"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="$DIST/oh-my-pdf-$VERSION.dmg"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

ZIP="$DIST/oh-my-pdf-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "✅ 빌드 산출물:"
echo "   $DMG"
echo "   $ZIP"

if [ -z "$VERSION_ARG" ]; then
  echo
  echo "(버전 인자 없이 실행 → appcast/게시는 건너뜀)"
  exit 0
fi

SIGN_UPDATE="$(find "$HOME/Library/Developer/Xcode/DerivedData" -name sign_update -path '*sparkle*' -type f 2>/dev/null | head -1)"
[ -x "$SIGN_UPDATE" ] || { echo "✗ sign_update 도구를 못 찾음. Sparkle 패키지 해석 후 다시 실행하세요."; exit 1; }
SIG_ATTRS="$("$SIGN_UPDATE" --account oh-my-pdf "$ZIP")"
mkdir -p "$UPDATES"
UPDATE_ZIP="$UPDATES/oh-my-pdf-$VERSION.zip"
cp "$ZIP" "$UPDATE_ZIP"
ZIP_URL="https://raw.githubusercontent.com/$REPO/main/updates/oh-my-pdf-$VERSION.zip"
PUBDATE="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"

NOTES_MD="- 개선 및 버그 수정"
if [ -f CHANGELOG.md ]; then
  NOTES_MD="$(awk -v v="$VERSION" '$0 ~ ("^## " v "( |$)"){f=1;next} /^## /{f=0} f' CHANGELOG.md)"
  [ -n "$NOTES_MD" ] || NOTES_MD="- 개선 및 버그 수정"
fi
NOTES_HTML="$(printf '%s\n' "$NOTES_MD" \
  | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
  | awk 'BEGIN{print "<ul>"} {line=$0; sub(/^[[:space:]]*[-*][[:space:]]+/,"",line); if(line!="") print "<li>"line"</li>"} END{print "</ul>"}')"

cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>oh-my-pdf</title>
    <link>https://raw.githubusercontent.com/$REPO/main/appcast.xml</link>
    <description>oh-my-pdf 업데이트</description>
    <language>ko</language>
    <item>
      <title>$VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINOS</sparkle:minimumSystemVersion>
      <description><![CDATA[<h2>oh-my-pdf $VERSION</h2>
$NOTES_HTML]]></description>
      <enclosure url="$ZIP_URL" type="application/octet-stream" $SIG_ATTRS />
    </item>
  </channel>
</rss>
XML

if [ "$PUBLISH" = "1" ]; then
  command -v gh >/dev/null || { echo "✗ 'brew install gh' 필요"; exit 1; }
  TAG="v$VERSION"
  git add appcast.xml project.yml "$UPDATE_ZIP"
  git commit -q -m "release: v$VERSION" || true
  git push
  gh release create "$TAG" "$DMG" "$ZIP" --title "oh-my-pdf $VERSION" --notes "$NOTES_MD" || \
    gh release upload "$TAG" "$DMG" "$ZIP" --clobber
fi
