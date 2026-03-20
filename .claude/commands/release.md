# FloatRec 릴리즈

인자: `$ARGUMENTS` (버전 번호, 예: 0.6.0)

버전 번호가 없으면 사용자에게 물어보세요.

## 릴리즈 절차

아래 단계를 **순서대로** 빠짐없이 수행하세요.

### 1. 버전 갱신
- `scripts/build_dmg.sh`의 `CFBundleShortVersionString`과 `CFBundleVersion`을 새 버전으로 변경 (둘 다 동일한 값)
- `README.md`의 다운로드 버튼 뱃지 버전 갱신 (`Download-v{버전}-28A745`)

### 2. CHANGELOG 작성
- `CHANGELOG.md` 최상단에 새 버전 섹션 추가
- `git log --oneline` 으로 이전 릴리즈 이후 커밋을 확인하고 Added/Fixed/Changed로 분류
- 형식: `## [{버전}] - {오늘 날짜 YYYY-MM-DD}`

### 3. 커밋 & 푸시
- 변경된 파일들 커밋: `chore: v{버전} 릴리즈 준비`
- `git push origin main`

### 4. 배포
- `./scripts/publish_update.sh {버전}` 실행
- 이 스크립트가 아래를 전부 수행:
  1. DMG 빌드
  2. EdDSA 서명
  3. appcast.xml 갱신 → gh-pages 배포
  4. GitHub Release 생성 (CHANGELOG.md에서 릴리즈 노트 자동 추출)
  5. Homebrew Cask 버전/SHA 갱신 → homebrew-floatrec repo 푸시

### 5. 완료 보고
- 릴리즈 URL 출력
- appcast.xml 반영 확인 (`curl -s https://kanguk01.github.io/FloatRec/appcast.xml | grep version`)
- Homebrew cask 반영 확인

## 주의사항
- 절대 `gh release create`를 수동으로 실행하지 마세요
- CFBundleVersion과 CFBundleShortVersionString은 반드시 동일한 값
- EdDSA 키: `~/.floatrec-sparkle/sparkle_private_key`
- Homebrew tap repo: `kanguk01/homebrew-floatrec`
