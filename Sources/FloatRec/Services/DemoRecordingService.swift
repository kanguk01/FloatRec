import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

struct RecordingArtifact {
    let fileURL: URL
    let duration: TimeInterval
    let sourceLabel: String
}

private final class AssetWriterBox: @unchecked Sendable {
    let writer: AVAssetWriter

    init(writer: AVAssetWriter) {
        self.writer = writer
    }
}

enum RecordingServiceError: LocalizedError {
    case alreadyRecording
    case notRecording
    case writerSetupFailed
    case bufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "이미 녹화 중입니다."
        case .notRecording:
            "진행 중인 녹화가 없습니다."
        case .writerSetupFailed:
            "임시 클립 생성 준비에 실패했습니다."
        case .bufferCreationFailed:
            "비디오 프레임 버퍼 생성에 실패했습니다."
        }
    }
}

actor DemoRecordingService {
    private var startedAt: Date?
    private var currentSourceLabel = "데모 캡처"

    func startRecording(sourceLabel: String) async throws {
        guard startedAt == nil else {
            throw RecordingServiceError.alreadyRecording
        }

        currentSourceLabel = sourceLabel
        startedAt = .now
    }

    func stopRecording() async throws -> RecordingArtifact {
        guard let startedAt else {
            throw RecordingServiceError.notRecording
        }

        self.startedAt = nil

        let elapsed = max(Date().timeIntervalSince(startedAt), 1.5)
        let clampedDuration = min(elapsed, 8)
        let outputURL = try await buildDemoClip(duration: clampedDuration)

        return RecordingArtifact(
            fileURL: outputURL,
            duration: clampedDuration,
            sourceLabel: currentSourceLabel
        )
    }

    private func buildDemoClip(duration: TimeInterval) async throws -> URL {
        let clipsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FloatRecClips",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)

        let outputURL = clipsDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let width = 1280
        let height = 720
        let frameRate = 30
        let frameCount = Int(duration * Double(frameRate))

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else {
            throw RecordingServiceError.writerSetupFailed
        }

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }

            guard let pixelBuffer = makePixelBuffer(width: width, height: height) else {
                throw RecordingServiceError.bufferCreationFailed
            }

            drawFrame(
                pixelBuffer: pixelBuffer,
                frameIndex: frameIndex,
                frameCount: frameCount,
                width: width,
                height: height
            )

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        input.markAsFinished()

        let writerBox = AssetWriterBox(writer: writer)

        return try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                if let error = writerBox.writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: outputURL)
                }
            }
        }
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess else {
            return nil
        }

        return pixelBuffer
    }

    private func drawFrame(
        pixelBuffer: CVPixelBuffer,
        frameIndex: Int,
        frameCount: Int,
        width: Int,
        height: Int
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let progress = CGFloat(frameIndex) / CGFloat(max(frameCount - 1, 1))

        let backgroundColors = [
            CGColor(red: 0.09, green: 0.12, blue: 0.18, alpha: 1),
            CGColor(red: 0.17, green: 0.39, blue: 0.62, alpha: 1),
        ] as CFArray
        let gradient = CGGradient(colorsSpace: colorSpace, colors: backgroundColors, locations: [0, 1])!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: CGFloat(width), y: CGFloat(height)),
            options: []
        )

        let panelRect = CGRect(x: 88, y: 82, width: 1104, height: 556)
        context.setFillColor(CGColor(red: 0.95, green: 0.97, blue: 0.99, alpha: 0.94))
        context.fill(panelRect)

        context.setFillColor(CGColor(red: 0.17, green: 0.21, blue: 0.28, alpha: 1))
        context.fill(CGRect(x: panelRect.minX, y: panelRect.maxY - 62, width: panelRect.width, height: 62))

        for index in 0..<4 {
            let barWidth = CGFloat(180 + (index * 90))
            let barY = panelRect.maxY - CGFloat(130 + index * 84)
            context.setFillColor(CGColor(red: 0.76, green: 0.83, blue: 0.89, alpha: 1))
            context.fill(CGRect(x: panelRect.minX + 52, y: barY, width: barWidth, height: 20))
        }

        let cursorX = panelRect.minX + 120 + progress * (panelRect.width - 240)
        let cursorY = panelRect.minY + 120 + 160 * sin(progress * .pi * 2)

        context.setStrokeColor(CGColor(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.18))
        context.setLineWidth(3)
        context.addEllipse(in: CGRect(x: cursorX - 48, y: cursorY - 48, width: 96, height: 96))
        context.strokePath()

        context.setFillColor(CGColor(red: 0.96, green: 0.29, blue: 0.19, alpha: 0.95))
        context.fillEllipse(in: CGRect(x: cursorX - 12, y: cursorY - 12, width: 24, height: 24))

        context.setStrokeColor(CGColor(red: 0.96, green: 0.29, blue: 0.19, alpha: 0.35))
        context.setLineWidth(10)
        context.addEllipse(in: CGRect(x: cursorX - 28, y: cursorY - 28, width: 56, height: 56))
        context.strokePath()
    }
}
