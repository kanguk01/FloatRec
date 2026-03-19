import AVFoundation
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

private struct CapturePerformanceProfile {
    let outputSize: CGSize
    let minimumFrameInterval: CMTime
    let queueDepth: Int
    let pixelFormat: OSType
    let captureResolution: SCCaptureResolutionType
}

@available(macOS 15.0, *)
@MainActor
final class ScreenCaptureRecorder: NSObject {
    private let logger = Logger(subsystem: "dev.floatrec.app", category: "screen-capture-recorder")

    private var stream: SCStream?
    private var isCapturing = false
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var sourceLabel: String?

    var hasActiveRecordingOutput: Bool { recordingOutput != nil }

    private var recordingDidStartContinuation: CheckedContinuation<Void, Error>?
    private var recordingDidFinishContinuation: CheckedContinuation<Void, Error>?
    private var pendingRecordingDidFinishResult: Result<Void, Error>?

    func teardownImmediately() {
        if let stream, let recordingOutput {
            try? stream.removeRecordingOutput(recordingOutput)
        }
        if let stream, isCapturing {
            Task { try? await stream.stopCapture() }
        }
        stream = nil
        isCapturing = false
        recordingOutput = nil
        outputURL = nil

        // Resume pending continuations before dropping them to avoid hanging callers
        let startCont = recordingDidStartContinuation
        recordingDidStartContinuation = nil
        startCont?.resume(throwing: CancellationError())

        let finishCont = recordingDidFinishContinuation
        recordingDidFinishContinuation = nil
        finishCont?.resume(throwing: CancellationError())

        pendingRecordingDidFinishResult = nil
    }

    func start(
        source: ResolvedCaptureSource,
        showBuiltInClickHighlight: Bool,
        isSystemAudioEnabled: Bool = false,
        isMicrophoneEnabled: Bool = false
    ) async throws {
        let filter = source.makeFilter()
        let configuration = SCStreamConfiguration()
        let captureProfile = capturePerformanceProfile(
            for: source,
            filter: filter,
            showBuiltInClickHighlight: showBuiltInClickHighlight
        )

        configuration.width = Int(captureProfile.outputSize.width)
        configuration.height = Int(captureProfile.outputSize.height)
        configuration.minimumFrameInterval = captureProfile.minimumFrameInterval
        configuration.showsCursor = true
        configuration.queueDepth = captureProfile.queueDepth
        configuration.pixelFormat = captureProfile.pixelFormat
        configuration.captureResolution = captureProfile.captureResolution
        configuration.scalesToFit = true
        configuration.capturesAudio = isSystemAudioEnabled
        configuration.excludesCurrentProcessAudio = true
        if #available(macOS 15.4, *) {
            if isMicrophoneEnabled {
                configuration.captureMicrophone = true
                configuration.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
            }
        }
        configuration.showMouseClicks = showBuiltInClickHighlight
        if let sourceRect = source.sourceRect {
            configuration.sourceRect = sourceRect
        }

        let outputURL = try makeOutputURL()
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264

        logger.info(
            """
            starting capture: output=\(Int(captureProfile.outputSize.width), privacy: .public)x\(Int(captureProfile.outputSize.height), privacy: .public) fps=\(self.frameRateDescription(for: captureProfile.minimumFrameInterval), privacy: .public) builtInClicks=\(showBuiltInClickHighlight, privacy: .public)
            """
        )

        let newRecordingOutput = SCRecordingOutput(
            configuration: recordingConfiguration,
            delegate: self
        )
        self.pendingRecordingDidFinishResult = nil
        self.sourceLabel = source.sourceLabel

        if let existingStream = stream, isCapturing {
            // 기존 스트림 재사용: 필터와 설정만 교체
            logger.info("reusing active stream, updating filter and adding output")
            do {
                try await existingStream.updateContentFilter(filter)
                try await existingStream.updateConfiguration(configuration)
                self.outputURL = outputURL
                self.recordingOutput = newRecordingOutput
                try existingStream.addRecordingOutput(newRecordingOutput)
                try await waitForRecordingStart()
            } catch {
                // Roll back state on failure so the stream remains reusable
                self.recordingOutput = nil
                self.outputURL = nil
                throw error
            }
        } else {
            // 최초 스트림 생성
            self.outputURL = outputURL
            self.recordingOutput = newRecordingOutput
            let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
            self.stream = newStream
            do {
                try newStream.addRecordingOutput(newRecordingOutput)
                try await startCaptureWithTimeout(newStream)
                isCapturing = true
            } catch {
                // Roll back state -- this stream is dead
                self.stream = nil
                self.recordingOutput = nil
                self.outputURL = nil
                self.isCapturing = false
                throw error
            }
        }
    }

    func stopRecording() async throws -> RecordingArtifact {
        guard let recordingOutput, let outputURL else {
            throw RecordingServiceError.notRecording
        }
        guard let stream else {
            throw RecordingServiceError.notRecording
        }

        let durationFallback = recordingOutput.recordedDuration.seconds

        do {
            try stream.removeRecordingOutput(recordingOutput)
            try await waitForRecordingFinish()
        } catch {
            // removeRecordingOutput() threw -- the output was not properly detached.
            // Clean up any continuation that might have been set.
            let leakedCont = recordingDidFinishContinuation
            recordingDidFinishContinuation = nil
            leakedCont?.resume(throwing: error)
            pendingRecordingDidFinishResult = nil
            logger.warning("removeRecordingOutput or waitForRecordingFinish failed: \(error.localizedDescription, privacy: .public)")
        }

        // 스트림은 절대 멈추지 않음 — output만 해제
        self.recordingOutput = nil
        self.outputURL = nil
        self.pendingRecordingDidFinishResult = nil

        let actualDuration = await resolvedDuration(for: outputURL, fallback: durationFallback)

        return RecordingArtifact(
            fileURL: outputURL,
            duration: actualDuration,
            sourceLabel: sourceLabel ?? "실녹화",
            cursorTrack: nil
        )
    }

    func pauseRecording() async throws -> RecordingArtifact {
        guard let stream, let recordingOutput, let outputURL else {
            throw RecordingServiceError.notRecording
        }

        let durationFallback = recordingOutput.recordedDuration.seconds

        do {
            try stream.removeRecordingOutput(recordingOutput)
            try await waitForRecordingFinish()
        } catch {
            let leakedCont = recordingDidFinishContinuation
            recordingDidFinishContinuation = nil
            leakedCont?.resume(throwing: error)
            pendingRecordingDidFinishResult = nil
            logger.warning("pauseRecording removeOutput failed: \(error.localizedDescription, privacy: .public)")
        }

        self.recordingOutput = nil
        let segmentURL = outputURL
        self.outputURL = nil
        self.pendingRecordingDidFinishResult = nil

        let duration = await resolvedDuration(for: segmentURL, fallback: durationFallback)
        return RecordingArtifact(
            fileURL: segmentURL,
            duration: duration,
            sourceLabel: sourceLabel ?? "녹화",
            cursorTrack: nil
        )
    }

    func resumeRecording() async throws {
        guard let stream else {
            throw RecordingServiceError.notRecording
        }

        let newOutputURL = try makeOutputURL()
        let config = SCRecordingOutputConfiguration()
        config.outputURL = newOutputURL
        config.outputFileType = .mp4
        config.videoCodecType = .h264

        let newOutput = SCRecordingOutput(configuration: config, delegate: self)
        self.outputURL = newOutputURL
        self.recordingOutput = newOutput
        self.pendingRecordingDidFinishResult = nil

        try stream.addRecordingOutput(newOutput)
        try await waitForRecordingStart()
    }

    private func startCaptureWithTimeout(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recordingDidStartContinuation = continuation

            Task { @MainActor in
                do {
                    try await stream.startCapture()
                    // startCapture() returned without error, but recording hasn't truly started
                    // until the delegate callback fires. If the callback already fired and
                    // consumed the continuation, do nothing.
                } catch {
                    if let cont = self.recordingDidStartContinuation {
                        self.recordingDidStartContinuation = nil
                        cont.resume(throwing: error)
                    }
                }
            }

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                if let cont = self.recordingDidStartContinuation {
                    self.logger.error("startCapture timed out after 8 seconds")
                    self.recordingDidStartContinuation = nil
                    cont.resume(throwing: RecordingServiceError.writerSetupFailed)
                }
            }
        }
    }

    private func waitForRecordingStart() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recordingDidStartContinuation = continuation

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if let cont = self.recordingDidStartContinuation {
                    self.logger.error("recording start callback timed out")
                    self.recordingDidStartContinuation = nil
                    cont.resume(throwing: RecordingServiceError.writerSetupFailed)
                }
            }
        }
    }

    private func waitForRecordingFinish() async throws {
        // Check if the delegate already delivered the result before we even started waiting
        if let pending = pendingRecordingDidFinishResult {
            pendingRecordingDidFinishResult = nil
            return try pending.get()
        }

        // Race the delegate callback against a timeout
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                recordingDidFinishContinuation = continuation

                Task { @MainActor in
                    // Check again in case the callback arrived between our earlier check
                    // and setting the continuation
                    if let pending = self.pendingRecordingDidFinishResult {
                        guard self.recordingDidFinishContinuation != nil else { return }
                        self.pendingRecordingDidFinishResult = nil
                        self.recordingDidFinishContinuation = nil
                        switch pending {
                        case .success:
                            continuation.resume()
                        case .failure(let err):
                            continuation.resume(throwing: err)
                        }
                        return
                    }
                }

                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    if let cont = self.recordingDidFinishContinuation {
                        self.recordingDidFinishContinuation = nil
                        cont.resume()  // Treat timeout as success (file is already written)
                    }
                }
            }
        } catch {
            // Delegate signaled an error during finish; proceed with existing file
            logger.warning("recording finish signal received error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Performance Profile

    private func capturePerformanceProfile(
        for source: ResolvedCaptureSource,
        filter: SCContentFilter,
        showBuiltInClickHighlight: Bool
    ) -> CapturePerformanceProfile {
        let requestedSize = bestCaptureSize(for: source, filter: filter)
        let outputSize = scaledCaptureSize(from: requestedSize)
        let outputPixels = outputSize.width * outputSize.height
        let isLargeCapture = outputPixels > 2_073_600

        return CapturePerformanceProfile(
            outputSize: outputSize,
            minimumFrameInterval: CMTime(value: 1, timescale: isLargeCapture ? 30 : 60),
            queueDepth: 8,
            pixelFormat: showBuiltInClickHighlight
                ? kCVPixelFormatType_32BGRA
                : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            captureResolution: outputSize == requestedSize ? .automatic : .nominal
        )
    }

    private func bestCaptureSize(for source: ResolvedCaptureSource, filter: SCContentFilter) -> CGSize {
        let referenceRect = source.sourceRect ?? filter.contentRect
        let width = max(referenceRect.width * CGFloat(filter.pointPixelScale), 320)
        let height = max(referenceRect.height * CGFloat(filter.pointPixelScale), 240)
        return CGSize(width: width.rounded(.up), height: height.rounded(.up))
    }

    private func scaledCaptureSize(from requestedSize: CGSize) -> CGSize {
        let maxLongEdge: CGFloat = 2560
        let maxPixelCount: CGFloat = 3_686_400
        let requestedPixels = requestedSize.width * requestedSize.height

        let longEdgeScale = maxLongEdge / max(requestedSize.width, requestedSize.height)
        let pixelScale = sqrt(maxPixelCount / max(requestedPixels, 1))
        let scale = min(1, longEdgeScale, pixelScale)

        guard scale < 0.999 else {
            return evenCaptureSize(requestedSize)
        }

        return evenCaptureSize(
            CGSize(
                width: requestedSize.width * scale,
                height: requestedSize.height * scale
            )
        )
    }

    private func evenCaptureSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: CGFloat(max(Int(size.width.rounded(.down)) & ~1, 320)),
            height: CGFloat(max(Int(size.height.rounded(.down)) & ~1, 240))
        )
    }

    private func makeOutputURL() throws -> URL {
        let clipsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FloatRecClips",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        return clipsDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    }

    private func resolvedDuration(for outputURL: URL, fallback: TimeInterval) async -> TimeInterval {
        let asset = AVURLAsset(
            url: outputURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let safeFallback = max(fallback, 1)

        return await withTaskGroup(of: TimeInterval.self) { group in
            group.addTask {
                do {
                    let duration = try await asset.load(.duration).seconds
                    guard duration.isFinite, duration > 0 else {
                        return safeFallback
                    }
                    return max(duration, safeFallback)
                } catch {
                    return safeFallback
                }
            }

            group.addTask {
                try? await Task.sleep(for: .milliseconds(400))
                return safeFallback
            }

            let resolvedDuration = await group.next() ?? safeFallback
            group.cancelAll()
            return resolvedDuration
        }
    }

    // MARK: - Delegate Callbacks

    private func handleRecordingDidStart() {
        recordingDidStartContinuation?.resume()
        recordingDidStartContinuation = nil
    }

    private func handleRecordingDidFail(_ error: Error) {
        recordingDidStartContinuation?.resume(throwing: error)
        recordingDidStartContinuation = nil
        resolveRecordingDidFinish(with: .failure(error))
    }

    private func handleRecordingDidFinish() {
        resolveRecordingDidFinish(with: .success(()))
    }

    private func resolveRecordingDidFinish(with result: Result<Void, Error>) {
        if let recordingDidFinishContinuation {
            self.recordingDidFinishContinuation = nil
            switch result {
            case .success:
                recordingDidFinishContinuation.resume()
            case let .failure(error):
                recordingDidFinishContinuation.resume(throwing: error)
            }
            return
        }
        pendingRecordingDidFinishResult = result
    }

    private func frameRateDescription(for frameInterval: CMTime) -> Int {
        guard frameInterval.seconds > 0 else { return 0 }
        return Int((1 / frameInterval.seconds).rounded())
    }

    private func pixelFormatDescription(_ pixelFormat: OSType) -> String {
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA: "BGRA"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: "420v"
        default: "\(pixelFormat)"
        }
    }
}

@available(macOS 15.0, *)
extension ScreenCaptureRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let outputID = ObjectIdentifier(recordingOutput)
        Task { @MainActor in
            guard let currentOutput = self.recordingOutput,
                  ObjectIdentifier(currentOutput) == outputID else {
                self.logger.info("ignoring didStartRecording from stale output")
                return
            }
            self.handleRecordingDidStart()
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let outputID = ObjectIdentifier(recordingOutput)
        Task { @MainActor in
            guard let currentOutput = self.recordingOutput,
                  ObjectIdentifier(currentOutput) == outputID else {
                self.logger.info("ignoring didFail from stale output")
                return
            }
            self.handleRecordingDidFail(error)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            // Allow finish callbacks even for stale outputs --
            // the delegate fires after removeRecordingOutput() sets self.recordingOutput = nil.
            // We still need to resolve the pending finish continuation.
            self.handleRecordingDidFinish()
        }
    }
}

@available(macOS 15.0, *)
extension ScreenCaptureRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            self.logger.error("SCStream stopped unexpectedly: \(error.localizedDescription, privacy: .public)")
            self.isCapturing = false
            self.stream = nil
            self.recordingOutput = nil
            self.handleRecordingDidFail(error)
        }
    }
}
