#!/bin/bash
# FloatRec 업데이트 배포 스크립트
# Usage: ./scripts/publish_update.sh <version> [release-notes-file]
# Example: ./scripts/publish_update.sh 0.2.0

set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
NOTES_FILE="${2:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG_PATH="$REPO_ROOT/dist/FloatRec.dmg"
SIGN_TOOL="$HOME/.floatrec-sparkle/sign_update"
PAGES_DIR="$REPO_ROOT/.build/gh-pages"

echo "=== FloatRec v${VERSION} 배포 ==="

# 1. DMG 빌드
echo "[1/4] DMG 빌드 중..."
"$REPO_ROOT/scripts/build_dmg.sh"

# 2. EdDSA 서명
echo "[2/4] EdDSA 서명 중..."
if [ ! -f "$SIGN_TOOL" ]; then
    echo "Error: sign_update 도구가 없습니다. ~/.floatrec-sparkle/sign_update 확인"
    exit 1
fi
SIGNATURE=$("$SIGN_TOOL" "$DMG_PATH" 2>&1)
ED_SIGNATURE=$(echo "$SIGNATURE" | grep 'edSignature=' | sed 's/.*edSignature="\([^"]*\)".*/\1/')
LENGTH=$(echo "$SIGNATURE" | grep 'length=' | sed 's/.*length="\([^"]*\)".*/\1/')

if [ -z "$ED_SIGNATURE" ] || [ -z "$LENGTH" ]; then
    echo "Error: 서명 실패"
    echo "$SIGNATURE"
    exit 1
fi

echo "  Signature: ${ED_SIGNATURE:0:20}..."
echo "  Length: $LENGTH"

# 3. appcast.xml 생성 및 gh-pages 배포
echo "[3/4] appcast.xml 생성 및 GitHub Pages 배포 중..."

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
PUBDATE=$(date -u '+%a, %d %b %Y %H:%M:%S %z')
DMG_URL="https://github.com/kanguk01/FloatRec/releases/download/v${VERSION}/FloatRec.dmg"

rm -rf "$PAGES_DIR"
mkdir -p "$PAGES_DIR"

# gh-pages 브랜치가 있으면 기존 내용을 가져옴
if git rev-parse --verify origin/gh-pages >/dev/null 2>&1; then
    git worktree add "$PAGES_DIR" gh-pages 2>/dev/null || {
        rm -rf "$PAGES_DIR"
        mkdir -p "$PAGES_DIR"
        git archive origin/gh-pages | tar -x -C "$PAGES_DIR"
    }
fi

cat > "$PAGES_DIR/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>FloatRec Updates</title>
    <link>https://kanguk01.github.io/FloatRec/appcast.xml</link>
    <language>ko</language>
    <item>
      <title>FloatRec v${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${DMG_URL}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIGNATURE}"
        length="${LENGTH}"
      />
    </item>
  </channel>
</rss>
APPCAST

# gh-pages 배포
cd "$PAGES_DIR"
if [ -d .git ] || git rev-parse --git-dir >/dev/null 2>&1; then
    git add appcast.xml
    git commit -m "update appcast for v${VERSION}" --allow-empty
    git push origin gh-pages
    cd "$REPO_ROOT"
    git worktree remove "$PAGES_DIR" 2>/dev/null || true
else
    cd "$REPO_ROOT"
    TEMP_BRANCH="gh-pages-deploy-$$"
    git checkout --orphan "$TEMP_BRANCH" 2>/dev/null
    git rm -rf . 2>/dev/null || true
    cp "$PAGES_DIR/appcast.xml" .
    git add appcast.xml
    git commit -m "update appcast for v${VERSION}"
    git push origin "$TEMP_BRANCH":gh-pages --force
    git checkout "$CURRENT_BRANCH"
    git branch -D "$TEMP_BRANCH"
fi

rm -rf "$PAGES_DIR"

# 4. GitHub Release
echo "[4/4] GitHub Release 생성 중..."
git tag -f "v${VERSION}" HEAD
git push --force origin "refs/tags/v${VERSION}"

# 릴리즈 노트 결정
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
    RELEASE_NOTES=$(cat "$NOTES_FILE")
elif [ -f "$REPO_ROOT/CHANGELOG.md" ]; then
    # CHANGELOG.md에서 현재 버전 섹션 추출
    RELEASE_NOTES=$(sed -n "/^## \[${VERSION}\]/,/^## \[/p" "$REPO_ROOT/CHANGELOG.md" | sed '$d')
fi

if [ -z "${RELEASE_NOTES:-}" ]; then
    RELEASE_NOTES="## FloatRec v${VERSION}

### 설치
1. \`FloatRec.dmg\` 다운로드
2. FloatRec.app을 응용 프로그램 폴더로 드래그
3. 첫 실행 시 화면 녹화 권한 허용

> macOS 14.0 이상, 라이브 녹화는 macOS 15+ 필요"
fi

gh release delete "v${VERSION}" --yes 2>/dev/null || true
gh release create "v${VERSION}" "$DMG_PATH" \
    --title "FloatRec v${VERSION}" \
    --notes "$RELEASE_NOTES"

echo ""
echo "=== 배포 완료 ==="
echo "  Release: https://github.com/kanguk01/FloatRec/releases/tag/v${VERSION}"
echo "  Appcast: https://kanguk01.github.io/FloatRec/appcast.xml"
