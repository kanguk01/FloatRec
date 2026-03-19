import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Exports a video clip as an animated GIF using AVAssetImageGenerator and CGImageDestination.
@MainActor
final class GIFExporter {
    private let logger = Logger(subsystem: "dev.floatrec.app", category: "gif-exporter")

    static let framesPerSecond: Double = 15
    static let maxWidth: CGFloat = 640
    static let maxDurationSeconds: Double = 30

    enum ExportError: LocalizedError {
        case noVideoTrack
        case destinationCreationFailed
        case frameGenerationFailed
        case exportCancelled

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                "영상 트랙을 찾을 수 없습니다."
            case .destinationCreationFailed:
                "GIF 파일을 생성할 수 없습니다."
            case .frameGenerationFailed:
                "프레임 추출에 실패했습니다."
            case .exportCancelled:
                "GIF 내보내기가 취소되었습니다."
            }
        }
    }

    /// Exports the video at `sourceURL` as an animated GIF, returning the output file URL.
    func export(from sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        let duration = try await asset.load(.duration)
        let durationSeconds = min(CMTimeGetSeconds(duration), Self.maxDurationSeconds)

        guard durationSeconds > 0 else {
            throw ExportError.noVideoTrack
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw ExportError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let scale = min(Self.maxWidth / naturalSize.width, 1.0)
        let outputSize = CGSize(
            width: round(naturalSize.width * scale),
            height: round(naturalSize.height * scale)
        )

        let frameCount = Int(durationSeconds * Self.framesPerSecond)
        guard frameCount > 0 else {
            throw ExportError.noVideoTrack
        }

        let frameTimes: [CMTime] = (0..<frameCount).map { index in
            CMTime(seconds: Double(index) / Self.framesPerSecond, preferredTimescale: 600)
        }

        logger.info(
            "starting GIF export: frames=\(frameCount, privacy: .public) duration=\(durationSeconds, privacy: .public)s size=\(Int(outputSize.width), privacy: .public)x\(Int(outputSize.height), privacy: .public)"
        )

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = outputSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)

        let images = try await generateFrames(generator: generator, times: frameTimes)

        let outputURL = try buildGIF(from: images, frameDelay: 1.0 / Self.framesPerSecond)

        logger.info("GIF export complete: \(outputURL.lastPathComponent, privacy: .public)")
        return outputURL
    }

    private func generateFrames(
        generator: AVAssetImageGenerator,
        times: [CMTime]
    ) async throws -> [CGImage] {
        let generatorBox = AssetImageGeneratorBox(generator: generator)
        let nsValues = times.map { NSValue(time: $0) }
        let collector = FrameCollector(expectedCount: nsValues.count, timeValues: nsValues)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CGImage], any Error>) in
            generatorBox.generator.generateCGImagesAsynchronously(forTimes: nsValues) { requestedTime, image, _, _, _ in
                let finished = collector.collect(requestedTime: requestedTime, image: image)

                if finished {
                    let validFrames = collector.orderedFrames()
                    if validFrames.isEmpty {
                        continuation.resume(throwing: ExportError.frameGenerationFailed)
                    } else {
                        continuation.resume(returning: validFrames)
                    }
                    _ = generatorBox
                }
            }
        }
    }

    private func buildGIF(from images: [CGImage], frameDelay: Double) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatRec-\(UUID().uuidString)")
            .appendingPathExtension("gif")

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            images.count,
            nil
        ) else {
            throw ExportError.destinationCreationFailed
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFUnclampedDelayTime as String: frameDelay
            ]
        ]

        for image in images {
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.destinationCreationFailed
        }

        return outputURL
    }
}

private final class AssetImageGeneratorBox: @unchecked Sendable {
    let generator: AVAssetImageGenerator

    init(generator: AVAssetImageGenerator) {
        self.generator = generator
    }
}

/// Thread-safe frame collector for async image generation callbacks.
private final class FrameCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let expectedCount: Int
    private let timeSeconds: [Double]
    private var frames: [CGImage?]
    private var receivedCount = 0

    init(expectedCount: Int, timeValues: [NSValue]) {
        self.expectedCount = expectedCount
        self.timeSeconds = timeValues.map { CMTimeGetSeconds($0.timeValue) }
        self.frames = Array(repeating: nil, count: expectedCount)
    }

    /// Returns `true` when all frames have been received.
    func collect(requestedTime: CMTime, image: CGImage?) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let requested = CMTimeGetSeconds(requestedTime)
        if let index = timeSeconds.firstIndex(where: { abs($0 - requested) < 0.001 }) {
            if let image {
                frames[index] = image
            }
        }

        receivedCount += 1
        return receivedCount == expectedCount
    }

    func orderedFrames() -> [CGImage] {
        lock.lock()
        defer { lock.unlock() }
        return frames.compactMap { $0 }
    }
}
