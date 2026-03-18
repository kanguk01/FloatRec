<div align="center">

# FloatRec

**macOS 메뉴바 기반 스크린 레코더**

수동 카메라 제어 · 클릭 하이라이트 · 플로팅 셸프

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![ScreenCaptureKit](https://img.shields.io/badge/ScreenCaptureKit-Native-007AFF)](https://developer.apple.com/documentation/screencapturekit)

</div>

---

## Overview

FloatRec은 macOS 네이티브 화면 녹화 도구입니다. ScreenCaptureKit 기반으로 디스플레이, 윈도우, 영역을 녹화하고, 녹화 중 단축키로 줌·팔로우·스포트라이트를 실시간 제어합니다. 후처리를 통해 카메라 이동과 클릭 하이라이트를 적용하며, 녹화가 끝나면 플로팅 셸프에서 바로 저장하거나 공유할 수 있습니다.

## Features

### Recording

| 모드 | 설명 |
|------|------|
| **Display** | 전체 디스플레이 녹화 |
| **Window** | 개별 앱 윈도우 캡처 |
| **Area** | 전체화면 오버레이에서 드래그로 영역 선택 |

녹화 시작 시 통합 선택 오버레이가 뜨며, 하단 툴바에서 모드를 전환하고 대상을 클릭하면 바로 녹화가 시작됩니다.

### Post-Processing

- **Manual Camera** — 녹화 중 단축키로 줌 스텝, 커서 팔로우, 스포트라이트를 실시간 제어
- **Click Highlight** — 마우스 클릭 시 리플 이펙트

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
| `⌘⇧9` | 녹화 시작 (선택 오버레이 표시) |
| `⌘⇧0` | 녹화 종료 |
| `⌃1` | 줌 스텝 (1.22x → 1.86x) |
| `⌃2` | 커서 팔로우 모드 토글 |
| `⌃3` | 오버뷰로 리셋 |
| `⌃4` | 스포트라이트 토글 |

> `⌃1` ~ `⌃4`는 녹화 중 카메라 후처리가 켜져 있을 때 사용 가능합니다.

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
│   ├── AutoZoomProcessor          # 카메라 제어 후처리
│   ├── CursorTrackingService      # 프레임별 커서 추출
│   ├── CaptureSelectionOverlay    # 통합 캡처 대상 선택 UI
│   └── ...
└── Support/              # 유틸리티, 포매터
```

### Tech Stack

| 레이어 | 기술 |
|--------|------|
| UI | SwiftUI + AppKit |
| 캡처 | ScreenCaptureKit (macOS 15+ SCRecordingOutput) |
| 영상 처리 | AVFoundation · CoreImage · CoreMedia |
| 단축키 | Carbon (글로벌 핫키) + NSEvent 모니터 |
| 빌드 | Swift Package Manager |

### Recording Pipeline

```
⌘⇧9 → 통합 선택 오버레이 (디스플레이 / 윈도우 / 영역)
  → SCStream 시작 (적응형 FPS: 60fps / 30fps)
    → 원본 MP4 저장 + 커서 트랙 추출
      → ⌃1~⌃4 카메라 이벤트 기록
        → 후처리: 줌·팔로우·스포트라이트·클릭 하이라이트 합성
          → 최종 클립 → Shelf
```

## Requirements

- macOS 14.0 (Sonoma) 이상
- 화면 녹화 권한
- 라이브 녹화는 macOS 15+ 필요

## Settings

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| 카메라 후처리 | On | 녹화 결과에 줌·팔로우·스포트라이트 적용 |
| 클릭 강조 | On | 클릭 리플 이펙트 |
| 기본 스포트라이트 | On | 녹화 시작 시 스포트라이트 기본 활성화 |

설정은 앱을 재시작해도 유지됩니다.

## License

Private — All rights reserved.
