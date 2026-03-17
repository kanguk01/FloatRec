# FloatRec

macOS 메뉴바 기반 화면 녹화 도구의 초기 프로토타입입니다.

현재 구현 범위:

- 메뉴바에서 녹화 시작/종료 상태 전환
- 글로벌 단축키 `⌘⇧9`
- 화면 녹화 권한 요청
- ScreenCaptureKit 기반 디스플레이/윈도우 소스 목록 로드
- 녹화 종료 후 우하단 `Floating Shelf`
- Shelf 카드에서 저장, 공유, Finder 열기, 드래그

주의:

- 아직 실제 ScreenCaptureKit 실녹화와 영역 선택 오버레이는 붙지 않았습니다.
- 현재는 종료 흐름과 Shelf UX를 검증하기 위한 데모 `.mov` 클립을 생성합니다.

실행:

```bash
swift run
```
