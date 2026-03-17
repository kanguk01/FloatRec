import AVFoundation
import CoreImage
import Foundation

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(session: AVAssetExportSession) {
        self.session = session
    }
}

enum AutoZoomProcessorError: LocalizedError {
    case missingVideoTrack
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            "자동 줌 처리에 사용할 비디오 트랙을 찾지 못했습니다."
        case .exportFailed:
            "자동 줌 비디오 내보내기에 실패했습니다."
        }
    }
}

actor AutoZoomProcessor {
    func process(
        _ artifact: RecordingArtifact,
        isAutoZoomEnabled: Bool,
        isClickHighlightEnabled: Bool
    ) async throws -> RecordingArtifact {
        guard let cursorTrack = artifact.cursorTrack,
              cursorTrack.isUsableForAutoZoom || cursorTrack.hasClicks else {
            return artifact
        }

        let asset = AVURLAsset(url: artifact.fileURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AutoZoomProcessorError.missingVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        let composition = AVMutableVideoComposition(asset: asset) { request in
            let outputImage = Self.makeFrame(
                request: request,
                renderSize: renderSize,
                cursorTrack: cursorTrack,
                isAutoZoomEnabled: isAutoZoomEnabled,
                isClickHighlightEnabled: isClickHighlightEnabled
            )
            request.finish(with: outputImage, context: nil)
        }
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: 60)

        let outputURL = try makeOutputURL()
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw AutoZoomProcessorError.exportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = composition

        try await export(session: exportSession)
        try? FileManager.default.removeItem(at: artifact.fileURL)

        return RecordingArtifact(
            fileURL: outputURL,
            duration: artifact.duration,
            sourceLabel: processedLabel(
                base: artifact.sourceLabel,
                isAutoZoomEnabled: isAutoZoomEnabled,
                isClickHighlightEnabled: isClickHighlightEnabled
            ),
            cursorTrack: cursorTrack
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

    private func export(session: AVAssetExportSession) async throws {
        let sessionBox = ExportSessionBox(session: session)

        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch sessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: sessionBox.session.error ?? AutoZoomProcessorError.exportFailed)
                default:
                    continuation.resume(throwing: AutoZoomProcessorError.exportFailed)
                }
            }
        }
    }

    private static func makeFrame(
        request: AVAsynchronousCIImageFilteringRequest,
        renderSize: CGSize,
        cursorTrack: CursorTrack,
        isAutoZoomEnabled: Bool,
        isClickHighlightEnabled: Bool
    ) -> CIImage {
        let sourceImage = request.sourceImage
        let sourceExtent = sourceImage.extent
        let currentTime = request.compositionTime.seconds
        let baseImage: CIImage
        let activeCropRect: CGRect?

        if isAutoZoomEnabled, cursorTrack.isUsableForAutoZoom {
            let focusPoint = cameraPoint(at: currentTime, samples: cursorTrack.samples)
            let zoomFactor = zoomFactor(at: currentTime, samples: cursorTrack.samples)
            let cropSize = CGSize(
                width: sourceExtent.width / zoomFactor,
                height: sourceExtent.height / zoomFactor
            )

            let focusX = sourceExtent.minX + sourceExtent.width * focusPoint.x
            let focusY = sourceExtent.minY + sourceExtent.height * focusPoint.y

            let cropOrigin = CGPoint(
                x: clamp(
                    focusX - cropSize.width / 2,
                    min: sourceExtent.minX,
                    max: sourceExtent.maxX - cropSize.width
                ),
                y: clamp(
                    focusY - cropSize.height / 2,
                    min: sourceExtent.minY,
                    max: sourceExtent.maxY - cropSize.height
                )
            )

            let cropRect = CGRect(origin: cropOrigin, size: cropSize).integral
            let cropped = sourceImage.cropped(to: cropRect)
            let translated = cropped.transformed(
                by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY)
            )
            baseImage = translated.transformed(
                by: CGAffineTransform(
                    scaleX: renderSize.width / cropRect.width,
                    y: renderSize.height / cropRect.height
                )
            )
            .cropped(to: CGRect(origin: .zero, size: renderSize))
            activeCropRect = cropRect
        } else {
            let translated = sourceImage.transformed(
                by: CGAffineTransform(translationX: -sourceExtent.minX, y: -sourceExtent.minY)
            )
            baseImage = translated.cropped(to: CGRect(origin: .zero, size: renderSize))
            activeCropRect = nil
        }

        guard isClickHighlightEnabled, let rippleImage = rippleOverlay(
            at: currentTime,
            renderSize: renderSize,
            sourceExtent: sourceExtent,
            activeCropRect: activeCropRect,
            cursorTrack: cursorTrack
        ) else {
            return baseImage
        }

        return rippleImage.composited(over: baseImage)
    }

    private static func cameraPoint(at time: TimeInterval, samples: [CursorTrackSample]) -> CGPoint {
        let current = interpolatedPoint(at: time, samples: samples)
        let trailing1 = interpolatedPoint(at: max(time - 0.10, 0), samples: samples)
        let trailing2 = interpolatedPoint(at: max(time - 0.22, 0), samples: samples)
        let trailing3 = interpolatedPoint(at: max(time - 0.34, 0), samples: samples)

        let smoothed = CGPoint(
            x: current.x * 0.46 + trailing1.x * 0.27 + trailing2.x * 0.17 + trailing3.x * 0.10,
            y: current.y * 0.46 + trailing1.y * 0.27 + trailing2.y * 0.17 + trailing3.y * 0.10
        )

        return CGPoint(
            x: 0.5 + (smoothed.x - 0.5) * 0.78,
            y: 0.5 + (smoothed.y - 0.5) * 0.78
        )
    }

    private static func interpolatedPoint(at time: TimeInterval, samples: [CursorTrackSample]) -> CGPoint {
        guard let firstSample = samples.first else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        if time <= firstSample.time {
            return firstSample.normalizedLocation
        }

        guard let lastSample = samples.last else {
            return firstSample.normalizedLocation
        }

        if time >= lastSample.time {
            return lastSample.normalizedLocation
        }

        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let next = samples[index]

            if time <= next.time {
                let progress = (time - previous.time) / max(next.time - previous.time, 0.0001)
                return CGPoint(
                    x: previous.normalizedLocation.x + (next.normalizedLocation.x - previous.normalizedLocation.x) * progress,
                    y: previous.normalizedLocation.y + (next.normalizedLocation.y - previous.normalizedLocation.y) * progress
                )
            }
        }

        return lastSample.normalizedLocation
    }

    private static func zoomFactor(at time: TimeInterval, samples: [CursorTrackSample]) -> CGFloat {
        guard samples.count >= 2 else {
            return 1.18
        }

        let current = interpolatedPoint(at: time, samples: samples)
        let previous = interpolatedPoint(at: max(time - 0.18, 0), samples: samples)
        let dx = current.x - previous.x
        let dy = current.y - previous.y
        let speed = min(sqrt(dx * dx + dy * dy) * 4.6, 1)

        return 1.18 + speed * 0.24
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private static func rippleOverlay(
        at time: TimeInterval,
        renderSize: CGSize,
        sourceExtent: CGRect,
        activeCropRect: CGRect?,
        cursorTrack: CursorTrack
    ) -> CIImage? {
        let clickDuration: TimeInterval = 0.52
        let activeClicks = cursorTrack.clickSamples.filter { click in
            let age = time - click.time
            return age >= 0 && age <= clickDuration
        }

        guard !activeClicks.isEmpty else {
            return nil
        }

        let extent = CGRect(origin: .zero, size: renderSize)
        var image = CIImage.empty().cropped(to: extent)

        for click in activeClicks {
            let age = time - click.time
            let progress = age / clickDuration
            let sourcePoint = CGPoint(
                x: sourceExtent.minX + sourceExtent.width * click.normalizedLocation.x,
                y: sourceExtent.minY + sourceExtent.height * click.normalizedLocation.y
            )

            let projectedPoint = projectPoint(
                sourcePoint,
                sourceExtent: sourceExtent,
                activeCropRect: activeCropRect,
                renderSize: renderSize
            )

            let center = CIVector(
                x: projectedPoint.x,
                y: projectedPoint.y
            )

            let radius = 18 + 120 * progress
            if let pulse = radialGradient(
                center: center,
                radius0: max(radius - 16, 0),
                radius1: radius,
                color0: CIColor(red: 1.0, green: 0.33, blue: 0.16, alpha: 0.34 * (1 - progress)),
                color1: CIColor.clear
            ) {
                image = pulse.cropped(to: extent).composited(over: image)
            }

            if let core = radialGradient(
                center: center,
                radius0: 0,
                radius1: 14 + 18 * progress,
                color0: CIColor(red: 1.0, green: 0.44, blue: 0.22, alpha: 0.18 * (1 - progress)),
                color1: CIColor.clear
            ) {
                image = core.cropped(to: extent).composited(over: image)
            }
        }

        return image
    }

    private func processedLabel(
        base: String,
        isAutoZoomEnabled: Bool,
        isClickHighlightEnabled: Bool
    ) -> String {
        if isAutoZoomEnabled && isClickHighlightEnabled {
            return "\(base) · 자동 줌 · 클릭 강조"
        }

        if isAutoZoomEnabled {
            return "\(base) · 자동 줌"
        }

        if isClickHighlightEnabled {
            return "\(base) · 클릭 강조"
        }

        return base
    }

    private static func radialGradient(
        center: CIVector,
        radius0: CGFloat,
        radius1: CGFloat,
        color0: CIColor,
        color1: CIColor
    ) -> CIImage? {
        guard let filter = CIFilter(name: "CIRadialGradient") else {
            return nil
        }

        filter.setValue(center, forKey: "inputCenter")
        filter.setValue(radius0, forKey: "inputRadius0")
        filter.setValue(radius1, forKey: "inputRadius1")
        filter.setValue(color0, forKey: "inputColor0")
        filter.setValue(color1, forKey: "inputColor1")
        return filter.outputImage
    }

    private static func projectPoint(
        _ point: CGPoint,
        sourceExtent: CGRect,
        activeCropRect: CGRect?,
        renderSize: CGSize
    ) -> CGPoint {
        let referenceRect = activeCropRect ?? sourceExtent
        let x = (point.x - referenceRect.minX) * renderSize.width / referenceRect.width
        let y = (point.y - referenceRect.minY) * renderSize.height / referenceRect.height

        return CGPoint(
            x: clamp(x, min: 0, max: renderSize.width),
            y: clamp(y, min: 0, max: renderSize.height)
        )
    }
}
