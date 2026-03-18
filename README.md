<div align="center">

# FloatRec

**macOS 메뉴바 기반 스크린 레코더**

커서 추적 자동 줌 · 클릭 하이라이트 · 플로팅 셸프

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![ScreenCaptureKit](https://img.shields.io/badge/ScreenCaptureKit-Native-007AFF)](https://developer.apple.com/documentation/screencapturekit)

</div>

---

## Overview

FloatRec은 macOS 네이티브 화면 녹화 도구입니다. ScreenCaptureKit 기반으로 디스플레이, 윈도우, 영역을 녹화하고, 후처리를 통해 커서 움직임에 따른 자동 줌과 클릭 하이라이트를 적용합니다. 녹화가 끝나면 우하단 플로팅 셸프에서 바로 저장, 공유, 드래그할 수 있습니다.

## Features

### Recording

| 모드 | 설명 |
|------|------|
| **Display** | 전체 디스플레이 녹화 |
| **Window** | 개별 앱 윈도우 캡처 |
| **Area** | 전체화면 오버레이에서 드래그로 영역 선택 |

### Post-Processing

- **Auto Zoom** — 커서 이동 속도를 분석해 자동으로 줌·팬 적용
- **Click Highlight** — 마우스 클릭 시 리플 이펙트
- **Manual Camera** — 단축키로 실시간 줌 스텝, 팔로우 모드, 스포트라이트 전환

<div align="center">
<img src="assets/camera-control.gif" width="720" alt="Manual Camera Control">
<br><sub>줌 스텝 · 커서 팔로우 · 오버뷰 리셋 · 스포트라이트</sub>
</div>

### Floating Shelf

녹화 종료 후 우하단에 플로팅 셸프가 나타납니다.

- 썸네일 미리보기 · 재생 시간 표시
- 저장 / 공유 / Finder 열기 / 드래그 앤 드롭
- 후처리 진행 상태 실시간 표시

<div align="center">
<img src="assets/shelf.gif" width="720" alt="Floating Shelf">
<br><sub>녹화 완료 → 셸프 → 저장 · 공유 · 드래그</sub>
</div>

## Keyboard Shortcuts

| 단축키 | 동작 |
|--------|------|
| `⌘⇧9` | 녹화 시작 / 종료 토글 |
| `⌃1` | 줌 스텝 (1.22x → 1.86x) |
| `⌃2` | 커서 팔로우 모드 토글 |
| `⌃3` | 오버뷰로 리셋 |
| `⌃4` | 스포트라이트 토글 |

> `⌃1` ~ `⌃4`는 카메라 컨트롤이 **수동 모드**일 때 사용 가능합니다.

## Architecture

```
Sources/FloatRec/
├── App/                  # 앱 진입점
├── Features/
│   ├── MenuBar/          # 메뉴바 드롭다운 UI
│   ├── Shelf/            # 플로팅 셸프
│   └── Settings/         # 설정 창
├── Models/               # 데이터 모델, 상태 열거형
├── Services/             # 핵심 비즈니스 로직
│   ├── ScreenCaptureRecorder      # SCStream 녹화 관리
│   ├── RecordingCoordinator       # 녹화 라이프사이클 조율
│   ├── AutoZoomProcessor          # 커서 추적 후처리
│   ├── CursorTrackingService      # 프레임별 커서 추출
│   └── ...
└── Support/              # 유틸리티, 포매터
```

### Tech Stack

| 레이어 | 기술 |
|--------|------|
| UI | SwiftUI + AppKit |
| 캡처 | ScreenCaptureKit (macOS 15+ SCRecordingOutput) |
| 영상 처리 | AVFoundation · CoreImage · CoreMedia |
| 단축키 | Carbon (글로벌 핫키) |
| 빌드 | Swift Package Manager |

### Recording Pipeline

```
캡처 소스 선택
  → SCStream 시작 (적응형 FPS: 60fps / 30fps)
    → 원본 MP4 저장
      → 커서 트랙 추출
        → Auto Zoom / Click Highlight / Spotlight 합성
          → 최종 클립 → Shelf
```

## Requirements

- macOS 14.0 (Sonoma) 이상
- 화면 녹화 권한
- 라이브 녹화는 macOS 15+ 필요

## Settings

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| Auto Zoom | On | 커서 추적 기반 자동 줌 후처리 |
| Click Highlight | On | 클릭 리플 이펙트 |
| Camera Control | Automatic | 자동 / 수동 카메라 모드 |
| Spotlight | On | 수동 모드 기본 스포트라이트 |

## Notes

- 영역 모드는 선택한 화면의 `sourceRect`를 사용해 녹화합니다.
- 자동 줌은 디스플레이/영역 모드에 적용되고, 윈도우 모드는 원본을 유지합니다.
- 라이브 녹화 실패 시 검증용 데모 클립으로 fallback합니다.

## License

Private — All rights reserved.
