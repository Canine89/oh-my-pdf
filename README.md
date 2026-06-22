<h1 align="center">oh-my-pdf</h1>

macOS용 PDF 교정 도구입니다. PDF를 열어 읽고, 주석을 달고, CSV 용어집과 OpenAI GPT API를 함께 사용해 한국어 맞춤법 교정 후보를 PDF 위에 표시합니다.

## 요구 환경

- macOS 26 이상
- Xcode
- XcodeGen
- OpenAI API 키

## 개발 실행

```bash
xcodegen generate
xcodebuild -project oh-my-pdf.xcodeproj -scheme oh-my-pdf -configuration Debug -derivedDataPath build/dd build
open build/dd/Build/Products/Debug/oh-my-pdf.app
```

## 주요 기능

- PDF 열기, 보기, 페이지 이동, 저장, 다른 이름으로 저장
- PDF 주석
  - 하이라이트
  - 밑줄
  - 취소선
  - 텍스트 박스
  - 화살표가 있는 텍스트 박스
  - 선택한 텍스트에 대한 주석
  - 선택한 텍스트에 대한 삭제 제안
  - 선택한 텍스트에 대한 대체 텍스트 제안
- AI 교정
  - 사용자가 입력한 OpenAI API 키를 macOS Keychain에 저장
  - `gpt-4.1-mini`를 사용한 한국어 교정 후보 생성
  - `before`, `after` 열을 가진 CSV 용어집 우선 적용
  - PDF 페이지 텍스트의 줄바꿈을 자연스럽게 이어 붙인 뒤 교정
  - GPT 응답 JSON 검증, 원문 존재 여부 검사, 과교정 유사도 필터 적용
  - 교정 후보를 PDF 원문 위치에 하이라이트와 메모로 표시

## CSV 용어집 형식

```csv
before,after
깃 헙,깃허브
할수 있다,할 수 있다
되어 보,되어보
```

## 배포

참고 앱 `oh-my-opensnap`과 같은 흐름을 사용합니다.

```bash
./scripts/release.sh
./scripts/release.sh 0.1.1
./scripts/release.sh 0.1.1 --publish
```

배포 스크립트는 XcodeGen으로 프로젝트를 재생성하고, Release 앱을 빌드한 뒤 DMG와 ZIP을 만듭니다. Sparkle 자동 업데이트를 쓰려면 Sparkle EdDSA 키를 만든 뒤 `project.yml`의 `SUPublicEDKey`를 채워야 합니다.

## OpenAI API

앱은 OpenAI Responses API에 직접 요청합니다. 모델 기본값은 명세에 맞춰 `gpt-4.1-mini`입니다.
