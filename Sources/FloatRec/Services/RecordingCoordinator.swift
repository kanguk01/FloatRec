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
            return RecordingArtifact(
                fileURL: artifact.fileURL,
                duration: artifact.duration,
                sourceLabel: artifact.sourceLabel,
                cursorTrack: cursorTrack
            )
        }

        return try await demoRecordingService.stopRecording()
    }

    func shouldProcessSynchronously(_ artifact: RecordingArtifact) -> Bool {
        shouldPostProcess(artifact)
            && artifact.duration <= RecordingFeatureFlags.synchronousPostProcessingDuration
    }

    func shouldProcessInBackground(_ artifact: RecordingArtifact) -> Bool {
        shouldPostProcess(artifact)
            && artifact.duration > RecordingFeatureFlags.synchronousPostProcessingDuration
            && artifact.duration <= RecordingFeatureFlags.maxBackgroundPostProcessingDuration
    }

    func processRecordedArtifact(_ artifact: RecordingArtifact) async -> RecordingArtifact {
        guard shouldPostProcess(artifact) else {
            return artifact
        }

        let timeoutSeconds: Double
        if shouldProcessSynchronously(artifact) {
            timeoutSeconds = 4
        } else {
            timeoutSeconds = min(max(artifact.duration * 2.2, 12), 60)
        }

        do {
            return try await processWithTimeout(
                artifact,
                isAutoZoomEnabled: isAutoZoomEnabled,
                isClickHighlightEnabled: isClickHighlightEnabled,
                timeout: .seconds(timeoutSeconds)
            )
        } catch {
            return artifact
        }
    }

    private func processWithTimeout(
        _ artifact: RecordingArtifact,
        isAutoZoomEnabled: Bool,
        isClickHighlightEnabled: Bool,
        timeout: Duration
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
                try await Task.sleep(for: timeout)
                return artifact
            }

            let result = try await group.next() ?? artifact
            group.cancelAll()
            return result
        }
    }

    private func shouldPostProcess(_ artifact: RecordingArtifact) -> Bool {
        guard isAutoZoomEnabled || isClickHighlightEnabled else {
            return false
        }

        guard let cursorTrack = artifact.cursorTrack else {
            return false
        }

        return cursorTrack.isUsableForAutoZoom || cursorTrack.hasClicks
    }
}
