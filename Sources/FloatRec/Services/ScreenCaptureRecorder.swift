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
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var sourceLabel: String?
    private var recordingDidStartContinuation: CheckedContinuation<Void, Error>?
    private var recordingDidFinishContinuation: CheckedContinuation<Void, Error>?
    private var pendingRecordingDidFinishResult: Result<Void, Error>?

    func start(source: ResolvedCaptureSource, showBuiltInClickHighlight: Bool) async throws {
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
            starting stream with capture profile: output=\(Int(captureProfile.outputSize.width), privacy: .public)x\(Int(captureProfile.outputSize.height), privacy: .public) fps=\(self.frameRateDescription(for: captureProfile.minimumFrameInterval), privacy: .public) queueDepth=\(captureProfile.queueDepth, privacy: .public) pixelFormat=\(self.pixelFormatDescription(captureProfile.pixelFormat), privacy: .public) builtInClicks=\(showBuiltInClickHighlight, privacy: .public)
            """
        )

        let recordingOutput = SCRecordingOutput(
            configuration: recordingConfiguration,
            delegate: self
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        self.outputURL = outputURL
        self.stream = stream
        self.recordingOutput = recordingOutput
        self.sourceLabel = source.sourceLabel
        self.pendingRecordingDidFinishResult = nil

        try stream.addRecordingOutput(recordingOutput)

        try await withCheckedThrowingContinuation { continuation in
            recordingDidStartContinuation = continuation

            Task {
                do {
                    try await stream.startCapture()
                } catch {
                    recordingDidStartContinuation = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopRecording() async throws -> RecordingArtifact {
        guard let stream, let recordingOutput, let outputURL else {
            throw RecordingServiceError.notRecording
        }

        let durationFallback = recordingOutput.recordedDuration.seconds

        do {
            do {
                try stream.removeRecordingOutput(recordingOutput)
            } catch {
                // Fallback to stopCapture path if the recording output is already detached.
            }

            try await stopCaptureWithTimeout(stream)
            try await waitForRecordingFinish()
        } catch {
            recordingDidFinishContinuation = nil
            pendingRecordingDidFinishResult = nil
            throw error
        }

        self.stream = nil
        self.recordingOutput = nil
        self.outputURL = nil
        self.pendingRecordingDidFinishResult = nil

        return RecordingArtifact(
            fileURL: outputURL,
            duration: max(durationFallback, 1),
            sourceLabel: sourceLabel ?? "실녹화",
            cursorTrack: nil
        )
    }

    private func stopCaptureWithTimeout(_ stream: SCStream) async throws {
        let stopTask = Task<Void, Error> {
            try await stream.stopCapture()
        }

        let timeoutTask = Task<Void, Error> {
            try await Task.sleep(for: .seconds(3))
            throw RecordingServiceError.notRecording
        }

        defer {
            stopTask.cancel()
            timeoutTask.cancel()
        }

        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await stopTask.value }
                group.addTask { try await timeoutTask.value }
                let value: Void? = try await group.next()
                group.cancelAll()
                return value
            }
        } catch {
            // Proceed with the partially finalized file instead of hanging forever.
        }
    }

    private func waitForRecordingFinish() async throws {
        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.awaitRecordingDidFinishSignal() }
                group.addTask {
                    try await Task.sleep(for: .seconds(2))
                    throw RecordingServiceError.writerSetupFailed
                }
                let value: Void? = try await group.next()
                group.cancelAll()
                return value
            }
        } catch {
            // If the finish callback is missing, proceed with the file that was already written
            // instead of leaving the app stuck in the processing state forever.
        }
    }

    private func awaitRecordingDidFinishSignal() async throws {
        if let pendingRecordingDidFinishResult {
            self.pendingRecordingDidFinishResult = nil
            return try pendingRecordingDidFinishResult.get()
        }

        try await withCheckedThrowingContinuation { continuation in
            recordingDidFinishContinuation = continuation
        }
    }

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
        guard frameInterval.seconds > 0 else {
            return 0
        }

        return Int((1 / frameInterval.seconds).rounded())
    }

    private func pixelFormatDescription(_ pixelFormat: OSType) -> String {
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            "BGRA"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            "420v"
        default:
            "\(pixelFormat)"
        }
    }
}

@available(macOS 15.0, *)
extension ScreenCaptureRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.handleRecordingDidStart()
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in
            self.handleRecordingDidFail(error)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.handleRecordingDidFinish()
        }
    }
}

@available(macOS 15.0, *)
extension ScreenCaptureRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            self.handleRecordingDidFail(error)
        }
    }
}
