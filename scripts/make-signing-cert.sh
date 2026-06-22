#!/usr/bin/env bash
#
# oh-my-pdf 배포 서명용 "자체서명 코드서명 인증서"를 만든다.
#
#   ./scripts/make-signing-cert.sh          # 키체인에 'oh-my-pdf' 인증서 생성
#   ./scripts/make-signing-cert.sh --backup # 위 + 백업용 .p12 내보내기(암호 입력)
#
# 왜 필요한가:
#   ad-hoc 또는 매번 달라지는 서명은 업데이트마다 macOS가 앱을 다른 앱처럼 볼 수 있다.
#   고정된 자체서명 인증서로 서명하면 같은 앱 정체성을 유지한 채 무료 배포할 수 있다.
#
# 중요:
#   이 인증서(개인키 포함)는 이 Mac 키체인에만 있다. 분실하면 새로 만들어야 하고,
#   새 인증서는 서명 식별자(Designated Requirement)가 달라진다. 반드시 --backup 으로
#   .p12 를 받아 안전한 곳에 보관하라. .p12 는 절대 git 에 커밋하지 말 것.

set -euo pipefail
cd "$(dirname "$0")/.."

NAME="oh-my-pdf"

if security find-identity 2>/dev/null | grep -q "\"$NAME\""; then
  echo "✓ '$NAME' 인증서가 이미 키체인에 있습니다."
else
  echo "▸ 자체서명 코드서명 인증서 생성 (유효기간 10년)"
  TMP="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -nodes \
    -subj "/CN=$NAME" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" 2>/dev/null
  openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" \
    -passout pass:omopdf -name "$NAME" \
    -legacy -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES 2>/dev/null
  security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P omopdf -T /usr/bin/codesign -A
  rm -rf "$TMP"
  echo "✓ 생성 완료"
fi

security find-identity | grep "\"$NAME\"" || true

if [ "${1:-}" = "--backup" ]; then
  OUT="$HOME/oh-my-pdf-signing-cert-BACKUP.p12"
  echo "▸ 백업 .p12 내보내기 → $OUT (내보내기 암호를 정해 입력하세요)"
  security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -o "$OUT"
  echo "✅ 백업 저장: $OUT"
  echo "   안전한 곳에 옮기고, 이 파일은 git 에 올리지 마세요."
fi
