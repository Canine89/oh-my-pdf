#!/usr/bin/env bash
#
# oh-my-pdf 배포 빌더 (DMG 설치 + Sparkle 자동 업데이트 포함).
#
#   ./scripts/release.sh                      # 현재 버전으로 DMG만 빌드(로컬 테스트)
#   ./scripts/release.sh 0.1.2                # 0.1.2 로 올려 DMG+ZIP+appcast 생성 (게시 X)
#   ./scripts/release.sh 0.1.2 --publish      # 위 + appcast 푸시 + GitHub Release 업로드
#
# 하는 일:
#   1) (버전 인자 있으면) project.yml 의 MARKETING_VERSION/CURRENT_PROJECT_VERSION 올림
#   2) project.yml → Xcode 프로젝트 재생성 → Release 빌드
#   3) 자체서명 인증서로 재서명(업데이트 간 앱 정체성 유지)
#   4) 사람이 받을 DMG + Sparkle 업데이트용 ZIP 패키징
#   5) ZIP 을 Sparkle EdDSA 개인키(키체인)로 서명 → appcast.xml 생성
#   6) --publish: appcast.xml/project.yml/updates ZIP 커밋/푸시 + GitHub Release 업로드

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
echo "▸ 자체서명 인증서로 재서명 ($SIGN_ID)"
if ! security find-identity 2>/dev/null | grep -q "\"$SIGN_ID\""; then
  echo "✗ '$SIGN_ID' 코드서명 인증서가 키체인에 없습니다."
  echo "  먼저 실행하세요: ./scripts/make-signing-cert.sh --backup"
  echo "  이 인증서를 고정해야 Sparkle 업데이트 후에도 앱 정체성이 유지됩니다."
  exit 1
fi
codesign --remove-signature "$APP" 2>/dev/null || true
codesign --force --deep --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict "$APP" && echo "  서명 확인 ✓"
codesign -d --requirements - "$APP" 2>&1 | grep -i designated || true

echo "▸ 패키징 (DMG + ZIP)"
mkdir -p "$DIST"
# 사람이 받는 DMG (앱 아이콘을 Applications 폴더로 드래그)
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
  gh release create "$TAG" "$DMG" "$ZIP" \
    --title "oh-my-pdf $VERSION" \
    --notes "$NOTES_MD

---
설치: [INSTALL.md](https://github.com/$REPO/blob/main/INSTALL.md) 참고. 이미 설치한 사용자는 앱이 자동으로 업데이트합니다." || \
    gh release upload "$TAG" "$DMG" "$ZIP" --clobber
  echo "✅ 게시 완료: $TAG"
else
  echo
  echo "다음 단계(게시): ./scripts/release.sh $VERSION --publish"
fi
