import AVFoundation
import Foundation
import OSLog

@MainActor
final class RecordingCoordinator {
    private let logger = Logger(subsystem: "dev.floatrec.app", category: "recording-coordinator")
    private let sourceCatalog: ScreenCaptureSourceCatalog
    private let demoRecordingService: DemoRecordingService
    private let cursorTrackingService: CursorTrackingService
    private let autoZoomProcessor: AutoZoomProcessor
    private var liveRecorder: AnyObject?
    private var segments: [URL] = []
    private var isAutoZoomEnabled = true
    private var isClickHighlightEnabled = true
    private var defaultManualSpotlightEnabled = true
    private var cameraControlStyle: CameraControlStyle = .manualHotkeys
    private var isSystemAudioEnabled = false
    private var isMicrophoneEnabled = false

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

    func teardownOnTermination() {
        if #available(macOS 15.0, *),
           let recorder = liveRecorder as? ScreenCaptureRecorder {
            recorder.teardownImmediately()
            liveRecorder = nil
        }
        _ = cursorTrackingService.stopTracking()
    }

    func startRecording(
        mode: CaptureMode,
        selectedSourceID: String?,
        resolvedSourceOverride: ResolvedCaptureSource?,
        areaSelection: AreaSelection?,
        isAutoZoomEnabled: Bool,
        isClickHighlightEnabled: Bool,
        defaultManualSpotlightEnabled: Bool,
        cameraControlStyle: CameraControlStyle,
        isSystemAudioEnabled: Bool,
        isMicrophoneEnabled: Bool,
        fallbackSourceLabel: String
    ) async throws {
        self.isAutoZoomEnabled = isAutoZoomEnabled
        self.isClickHighlightEnabled = isClickHighlightEnabled
        self.defaultManualSpotlightEnabled = defaultManualSpotlightEnabled
        self.cameraControlStyle = cameraControlStyle
        self.isSystemAudioEnabled = isSystemAudioEnabled
        self.isMicrophoneEnabled = isMicrophoneEnabled
        segments.removeAll()
        if #available(macOS 15.0, *) {
            let resolvedSource: ResolvedCaptureSource?

            if let areaSelection {
                resolvedSource = try await sourceCatalog.resolveAreaSelection(areaSelection)
            } else if let resolvedSourceOverride {
                resolvedSource = resolvedSourceOverride
            } else {
                resolvedSource = try await sourceCatalog.resolveSource(
                    mode: mode,
                    selectedSourceID: selectedSourceID
                )
            }

            if let resolvedSource {
                let recorder: ScreenCaptureRecorder
                if let existing = liveRecorder as? ScreenCaptureRecorder {
                    recorder = existing
                } else {
                    recorder = ScreenCaptureRecorder()
                }

                do {
                    let needsPostProcessing = isAutoZoomEnabled || isClickHighlightEnabled
                    logger.info(
                        "start recording resolved source: mode=\(mode.title, privacy: .public) sourceLabel=\(resolvedSource.sourceLabel, privacy: .public) autoZoom=\(isAutoZoomEnabled, privacy: .public) clickHighlight=\(isClickHighlightEnabled, privacy: .public) cameraStyle=\(cameraControlStyle.rawValue, privacy: .public) trackingRectAvailable=\(resolvedSource.autoZoomTrackingRect != nil, privacy: .public)"
                    )
                    let useCustomClickHighlight = isClickHighlightEnabled && resolvedSource.autoZoomTrackingRect != nil
                    try await recorder.start(
                        source: resolvedSource,
                        showBuiltInClickHighlight: !useCustomClickHighlight,
                        isSystemAudioEnabled: isSystemAudioEnabled,
                        isMicrophoneEnabled: isMicrophoneEnabled
                    )
                    cursorTrackingService.startTracking(
                        for: resolvedSource,
                        enabled: needsPostProcessing,
                        cameraControlStyle: cameraControlStyle,
                        defaultManualSpotlightEnabled: defaultManualSpotlightEnabled
                    )
                    liveRecorder = recorder
                    return
                } catch {
                    _ = cursorTrackingService.stopTracking()
                    // Keep liveRecorder if the underlying stream is still capturing.
                    // The recorder.start() method rolls back its own state on failure,
                    // leaving the stream reusable for the next attempt.
                    // Only if liveRecorder was nil (brand new recorder), nothing to preserve.
                    logger.error("recorder.start failed: \(error.localizedDescription, privacy: .public) existingRecorder=\(self.liveRecorder != nil, privacy: .public)")
                    throw error
                }
            }
        }

        try await demoRecordingService.startRecording(sourceLabel: fallbackSourceLabel)
    }

    func stopRecording() async throws -> RecordingArtifact {
        if #available(macOS 15.0, *),
           let recorder = liveRecorder as? ScreenCaptureRecorder {
            let cursorTrack = cursorTrackingService.stopTracking()
            do {
                var finalURL: URL
                var finalDuration: TimeInterval
                var sourceLabel = "녹화"

                if recorder.hasActiveRecordingOutput {
                    let artifact = try await recorder.stopRecording()
                    finalURL = artifact.fileURL
                    finalDuration = artifact.duration
                    sourceLabel = artifact.sourceLabel

                    if !segments.isEmpty {
                        segments.append(artifact.fileURL)
                    }
                } else if !segments.isEmpty {
                    finalURL = segments.first!
                    finalDuration = 0
                } else {
                    throw RecordingServiceError.notRecording
                }

                if segments.count > 1 {
                    let mergedURL = try await mergeSegments(segments)
                    finalURL = mergedURL
                    let mergedAsset = AVURLAsset(url: mergedURL)
                    let mergedDuration = try await mergedAsset.load(.duration).seconds
                    finalDuration = (mergedDuration.isFinite && mergedDuration > 0) ? mergedDuration : finalDuration
                } else if segments.count == 1 {
                    finalURL = segments[0]
                    let asset = AVURLAsset(url: finalURL)
                    let dur = try await asset.load(.duration).seconds
                    if dur.isFinite, dur > 0 { finalDuration = dur }
                }
                segments.removeAll()

                logger.info(
                    "stop recording produced artifact: duration=\(finalDuration, privacy: .public)s cursorTrack=\(cursorTrack != nil, privacy: .public)"
                )
                return RecordingArtifact(
                    fileURL: finalURL,
                    duration: finalDuration,
                    sourceLabel: sourceLabel,
                    cursorTrack: cursorTrack
                )
            } catch {
                segments.removeAll()
                recorder.teardownImmediately()
                self.liveRecorder = nil
                throw error
            }
        }

        return try await demoRecordingService.stopRecording()
    }

    func pauseRecording() async throws {
        if #available(macOS 15.0, *),
           let recorder = liveRecorder as? ScreenCaptureRecorder {
            let artifact = try await recorder.pauseRecording()
            segments.append(artifact.fileURL)
            _ = cursorTrackingService.stopTracking()
            logger.info("recording paused, segment count=\(self.segments.count, privacy: .public)")
        }
    }

    func resumeRecording(resolvedSource: ResolvedCaptureSource) async throws {
        if #available(macOS 15.0, *),
           let recorder = liveRecorder as? ScreenCaptureRecorder {
            try await recorder.resumeRecording()
            let needsTracking = isAutoZoomEnabled || isClickHighlightEnabled
            cursorTrackingService.startTracking(
                for: resolvedSource,
                enabled: needsTracking,
                cameraControlStyle: cameraControlStyle,
                defaultManualSpotlightEnabled: defaultManualSpotlightEnabled
            )
            logger.info("recording resumed")
        }
    }

    private func mergeSegments(_ urls: [URL]) async throws -> URL {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecordingServiceError.writerSetupFailed
        }

        // Optional audio track
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var currentTime = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            if let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceVideoTrack,
                    at: currentTime
                )
            }
            if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
               let audioTrack {
                try? audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceAudioTrack,
                    at: currentTime
                )
            }
            currentTime = CMTimeAdd(currentTime, duration)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatRecClips", isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RecordingServiceError.writerSetupFailed
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        await exporter.export()

        if let error = exporter.error {
            throw error
        }

        logger.info("merged \(urls.count, privacy: .public) segments into \(outputURL.lastPathComponent, privacy: .public)")
        return outputURL
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

    func needsPostProcessing(_ artifact: RecordingArtifact) -> Bool {
        shouldProcessSynchronously(artifact) || shouldProcessInBackground(artifact)
    }

    func processRecordedArtifact(_ artifact: RecordingArtifact) async -> RecordingArtifact {
        guard shouldPostProcess(artifact) else {
            logger.info(
                "skip post-processing: duration=\(artifact.duration, privacy: .public)s cursorTrack=\(artifact.cursorTrack != nil, privacy: .public) sampleCount=\(artifact.cursorTrack?.samples.count ?? 0, privacy: .public) clickCount=\(artifact.cursorTrack?.clickSamples.count ?? 0, privacy: .public)"
            )
            return artifact
        }

        let timeoutSeconds: Double
        if shouldProcessSynchronously(artifact) {
            timeoutSeconds = 4
        } else {
            timeoutSeconds = min(max(artifact.duration * 2.2, 12), 60)
        }

        do {
            logger.info(
                "start post-processing: duration=\(artifact.duration, privacy: .public)s timeout=\(timeoutSeconds, privacy: .public)s sampleCount=\(artifact.cursorTrack?.samples.count ?? 0, privacy: .public) clickCount=\(artifact.cursorTrack?.clickSamples.count ?? 0, privacy: .public)"
            )
            let processedArtifact = try await processWithTimeout(
                artifact,
                isAutoZoomEnabled: isAutoZoomEnabled,
                isClickHighlightEnabled: isClickHighlightEnabled,
                defaultManualSpotlightEnabled: defaultManualSpotlightEnabled,
                cameraControlStyle: cameraControlStyle,
                timeout: .seconds(timeoutSeconds)
            )
            let changed = processedArtifact.fileURL != artifact.fileURL || processedArtifact.sourceLabel != artifact.sourceLabel
            logger.info("finish post-processing: changed=\(changed, privacy: .public)")
            return processedArtifact
        } catch {
            logger.error("post-processing failed: \(error.localizedDescription, privacy: .public)")
            return artifact
        }
    }

    private func processWithTimeout(
        _ artifact: RecordingArtifact,
        isAutoZoomEnabled: Bool,
        isClickHighlightEnabled: Bool,
        defaultManualSpotlightEnabled: Bool,
        cameraControlStyle: CameraControlStyle,
        timeout: Duration
    ) async throws -> RecordingArtifact {
        try await withThrowingTaskGroup(of: RecordingArtifact.self) { group in
            group.addTask {
                try await self.autoZoomProcessor.process(
                    artifact,
                    isAutoZoomEnabled: isAutoZoomEnabled,
                    isClickHighlightEnabled: isClickHighlightEnabled,
                    defaultManualSpotlightEnabled: defaultManualSpotlightEnabled,
                    cameraControlStyle: cameraControlStyle
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

        let shouldApplyCamera = isAutoZoomEnabled && cursorTrack.hasManualCameraEvents

        return shouldApplyCamera || cursorTrack.hasClicks
    }
}
