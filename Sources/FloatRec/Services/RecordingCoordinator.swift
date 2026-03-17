import Foundation

@MainActor
final class RecordingCoordinator {
    private let sourceCatalog: ScreenCaptureSourceCatalog
    private let demoRecordingService: DemoRecordingService
    private var liveRecorder: AnyObject?

    init(
        sourceCatalog: ScreenCaptureSourceCatalog,
        demoRecordingService: DemoRecordingService
    ) {
        self.sourceCatalog = sourceCatalog
        self.demoRecordingService = demoRecordingService
    }

    func startRecording(
        mode: CaptureMode,
        selectedSourceID: String?,
        areaSelection: AreaSelection?,
        fallbackSourceLabel: String
    ) async throws {
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
                    try await recorder.start(source: resolvedSource)
                    liveRecorder = recorder
                    return
                } catch {
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
            return try await recorder.stopRecording()
        }

        return try await demoRecordingService.stopRecording()
    }
}
