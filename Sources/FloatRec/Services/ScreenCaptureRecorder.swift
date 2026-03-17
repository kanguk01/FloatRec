import CoreMedia
import Foundation
import ScreenCaptureKit

@available(macOS 15.0, *)
@MainActor
final class ScreenCaptureRecorder: NSObject {
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var sourceLabel: String?
    private var recordingDidStartContinuation: CheckedContinuation<Void, Error>?
    private var recordingDidFinishContinuation: CheckedContinuation<Void, Error>?

    func start(source: ResolvedCaptureSource) async throws {
        let filter = source.makeFilter()
        let configuration = SCStreamConfiguration()
        let captureSize = bestCaptureSize(for: filter)

        configuration.width = Int(captureSize.width)
        configuration.height = Int(captureSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = true
        configuration.queueDepth = 6
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showMouseClicks = true

        let outputURL = try makeOutputURL()
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL

        let recordingOutput = SCRecordingOutput(
            configuration: recordingConfiguration,
            delegate: self
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        self.outputURL = outputURL
        self.stream = stream
        self.recordingOutput = recordingOutput
        self.sourceLabel = source.sourceLabel

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

        let finishTask = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                recordingDidFinishContinuation = continuation
            }
        }

        do {
            try await stream.stopCapture()
            try await finishTask.value
        } catch {
            recordingDidFinishContinuation = nil
            throw error
        }

        self.stream = nil
        self.recordingOutput = nil
        self.outputURL = nil

        return RecordingArtifact(
            fileURL: outputURL,
            duration: max(durationFallback, 1),
            sourceLabel: sourceLabel ?? "실녹화"
        )
    }

    private func bestCaptureSize(for filter: SCContentFilter) -> CGSize {
        let width = max(filter.contentRect.width * CGFloat(filter.pointPixelScale), 1280)
        let height = max(filter.contentRect.height * CGFloat(filter.pointPixelScale), 720)
        return CGSize(width: width.rounded(.up), height: height.rounded(.up))
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
        recordingDidFinishContinuation?.resume(throwing: error)
        recordingDidFinishContinuation = nil
    }

    private func handleRecordingDidFinish() {
        recordingDidFinishContinuation?.resume()
        recordingDidFinishContinuation = nil
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
