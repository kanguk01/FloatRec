import Foundation

@MainActor
final class RecordingCoordinator {
    private let sourceCatalog: ScreenCaptureSourceCatalog
    private let demoRecordingService: DemoRecordingService
    private let cursorTrackingService: CursorTrackingService
    private let autoZoomProcessor: AutoZoomProcessor
    private var liveRecorder: AnyObject?
    private var isAutoZoomEnabled = true
    private var isClickHighlightEnabled = true

    init(
        sourceCatalog: ScreenCaptureSourceCatalog,
        demoRecordingService: DemoRecordingService,
        cursorTrackingService: CursorTrackingService = CursorTrackingService(),
        autoZoomProcessor: AutoZoomProcessor = AutoZoomProcessor()
    ) {
        self.sourceCatalog = sourceCatalog
        self.demoRecordingService = demoRecordingService
        self.cursorTrackingService = cursorTrackingService
        self.autoZoomProcessor = autoZoomProcessor
    }

    func startRecording(
        mode: CaptureMode,
        selectedSourceID: String?,
        areaSelection: AreaSelection?,
        isAutoZoomEnabled: Bool,
        isClickHighlightEnabled: Bool,
        fallbackSourceLabel: String
    ) async throws {
        self.isAutoZoomEnabled = isAutoZoomEnabled
        self.isClickHighlightEnabled = isClickHighlightEnabled
        if #available(macOS 15.0, *) {
            let resolvedSource: ResolvedCaptureSource?

            if let areaSelection {
                resolvedSource = try await sourceCatalog.resolveAreaSelection(areaSelection)
            } else {
                resolvedSource = try await sourceCatalog.resolveSource(
                    mode: mode,
                    selectedSourceID: selectedSourceID
                )
            }

            if let resolvedSource {
                let recorder = ScreenCaptureRecorder()
                do {
                    let needsPostProcessing = isAutoZoomEnabled || isClickHighlightEnabled
                    cursorTrackingService.startTracking(for: resolvedSource, enabled: needsPostProcessing)
                    let useCustomClickHighlight = isClickHighlightEnabled && resolvedSource.autoZoomTrackingRect != nil
                    try await recorder.start(
                        source: resolvedSource,
                        showBuiltInClickHighlight: !useCustomClickHighlight
                    )
                    liveRecorder = recorder
                    return
                } catch {
                    _ = cursorTrackingService.stopTracking()
                    liveRecorder = nil
                    throw error
                }
            }
        }

        try await demoRecordingService.startRecording(sourceLabel: fallbackSourceLabel)
    }

    func stopRecording() async throws -> RecordingArtifact {
        if #available(macOS 15.0, *),
           let recorder = liveRecorder as? ScreenCaptureRecorder {
            defer { self.liveRecorder = nil }
            let cursorTrack = cursorTrackingService.stopTracking()
            let artifact = try await recorder.stopRecording()
            let liveArtifact = RecordingArtifact(
                fileURL: artifact.fileURL,
                duration: artifact.duration,
                sourceLabel: artifact.sourceLabel,
                cursorTrack: cursorTrack
            )

            guard isAutoZoomEnabled || isClickHighlightEnabled else {
                return liveArtifact
            }

            do {
                return try await processWithTimeout(
                    liveArtifact,
                    isAutoZoomEnabled: isAutoZoomEnabled,
                    isClickHighlightEnabled: isClickHighlightEnabled
                )
            } catch {
                return liveArtifact
            }
        }

        return try await demoRecordingService.stopRecording()
    }

    private func processWithTimeout(
        _ artifact: RecordingArtifact,
        isAutoZoomEnabled: Bool,
        isClickHighlightEnabled: Bool
    ) async throws -> RecordingArtifact {
        try await withThrowingTaskGroup(of: RecordingArtifact.self) { group in
            group.addTask {
                try await self.autoZoomProcessor.process(
                    artifact,
                    isAutoZoomEnabled: isAutoZoomEnabled,
                    isClickHighlightEnabled: isClickHighlightEnabled
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                return artifact
            }

            let result = try await group.next() ?? artifact
            group.cancelAll()
            return result
        }
    }
}
