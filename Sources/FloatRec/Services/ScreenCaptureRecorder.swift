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

    func start(source: ResolvedCaptureSource, showBuiltInClickHighlight: Bool) async throws {
        let filter = source.makeFilter()
        let configuration = SCStreamConfiguration()
        let captureSize = bestCaptureSize(for: source, filter: filter)

        configuration.width = Int(captureSize.width)
        configuration.height = Int(captureSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = true
        configuration.queueDepth = 6
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showMouseClicks = showBuiltInClickHighlight
        if let sourceRect = source.sourceRect {
            configuration.sourceRect = sourceRect
        }

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
            do {
                try stream.removeRecordingOutput(recordingOutput)
            } catch {
                // Fallback to stopCapture path if the recording output is already detached.
            }

            try await stopCaptureWithTimeout(stream)
            try await waitForRecordingFinish(finishTask)
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

    private func waitForRecordingFinish(_ finishTask: Task<Void, Error>) async throws {
        let timeoutTask = Task<Void, Error> {
            try await Task.sleep(for: .seconds(2))
            throw RecordingServiceError.writerSetupFailed
        }

        defer {
            finishTask.cancel()
            timeoutTask.cancel()
        }

        do {
            _ = try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await finishTask.value }
                group.addTask { try await timeoutTask.value }
                let value: Void? = try await group.next()
                group.cancelAll()
                return value
            }
        } catch {
            // If the finish callback is missing, proceed with the file that was already written
            // instead of leaving the app stuck in the processing state forever.
        }
    }

    private func bestCaptureSize(for source: ResolvedCaptureSource, filter: SCContentFilter) -> CGSize {
        let referenceRect = source.sourceRect ?? filter.contentRect
        let width = max(referenceRect.width * CGFloat(filter.pointPixelScale), 320)
        let height = max(referenceRect.height * CGFloat(filter.pointPixelScale), 240)
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
