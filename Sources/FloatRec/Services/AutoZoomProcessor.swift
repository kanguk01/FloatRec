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

private struct CameraFrameConfiguration {
    let focusPoint: CGPoint?
    let zoomFactor: CGFloat

    static let overview = CameraFrameConfiguration(focusPoint: nil, zoomFactor: 1)

    var hasZoom: Bool {
        zoomFactor > 1.001 && focusPoint != nil
    }
}

private struct SpotlightOverlayConfiguration {
    let focusPoint: CGPoint
    let zoomStep: Int
    let followsCursor: Bool
}

private enum ManualCameraState {
    case overview
    case spotlight(focusPoint: CGPoint, zoomStep: Int)
    case follow(zoomStep: Int)
}

private struct ManualCameraContext {
    let currentState: ManualCameraState
    let lastTransition: ManualCameraTransition?
    let isSpotlightEnabled: Bool
}

private struct ManualCameraTransition {
    let fromState: ManualCameraState
    let toState: ManualCameraState
    let startTime: TimeInterval
}

actor AutoZoomProcessor {
    private static let manualZoomFactors: [CGFloat] = [1.22, 1.4, 1.62, 1.86]

    func process(
        _ artifact: RecordingArtifact,
        isAutoZoomEnabled: Bool,
        isClickHighlightEnabled: Bool,
        defaultManualSpotlightEnabled: Bool,
        cameraControlStyle: CameraControlStyle
    ) async throws -> RecordingArtifact {
        guard let cursorTrack = artifact.cursorTrack else {
            return artifact
        }

        let shouldApplyCamera = isAutoZoomEnabled && cursorTrack.hasManualCameraEvents

        guard shouldApplyCamera || cursorTrack.hasClicks else {
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
                isClickHighlightEnabled: isClickHighlightEnabled,
                defaultManualSpotlightEnabled: defaultManualSpotlightEnabled,
                cameraControlStyle: cameraControlStyle
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
                isClickHighlightEnabled: isClickHighlightEnabled,
                defaultManualSpotlightEnabled: defaultManualSpotlightEnabled,
                cameraControlStyle: cameraControlStyle
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
        isClickHighlightEnabled: Bool,
        defaultManualSpotlightEnabled: Bool,
        cameraControlStyle: CameraControlStyle
    ) -> CIImage {
        let sourceImage = request.sourceImage
        let sourceExtent = sourceImage.extent
        let currentTime = request.compositionTime.seconds
        let baseImage: CIImage
        let activeCropRect: CGRect?

        let cameraConfiguration = cameraConfiguration(
            at: currentTime,
            cursorTrack: cursorTrack,
            isAutoZoomEnabled: isAutoZoomEnabled,
            defaultManualSpotlightEnabled: defaultManualSpotlightEnabled,
            cameraControlStyle: cameraControlStyle
        )

        if cameraConfiguration.hasZoom, let focusPoint = cameraConfiguration.focusPoint {
            let zoomFactor = cameraConfiguration.zoomFactor
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

            let cropRect = CGRect(origin: cropOrigin, size: cropSize)
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

        var overlayImage = CIImage.empty().cropped(to: CGRect(origin: .zero, size: renderSize))

        if let spotlightOverlay = spotlightOverlay(
            at: currentTime,
            renderSize: renderSize,
            sourceExtent: sourceExtent,
            activeCropRect: activeCropRect,
            cursorTrack: cursorTrack,
            cameraConfiguration: cameraConfiguration,
            defaultManualSpotlightEnabled: defaultManualSpotlightEnabled,
            cameraControlStyle: cameraControlStyle
        ) {
            overlayImage = spotlightOverlay.composited(over: overlayImage)
        }

        if isClickHighlightEnabled, let rippleImage = rippleOverlay(
            at: currentTime,
            renderSize: renderSize,
            sourceExtent: sourceExtent,
            activeCropRect: activeCropRect,
            cursorTrack: cursorTrack
        ) {
            overlayImage = rippleImage.composited(over: overlayImage)
        }

        return overlayImage.composited(over: baseImage)
    }

    private static func cameraConfiguration(
        at time: TimeInterval,
        cursorTrack: CursorTrack,
        isAutoZoomEnabled: Bool,
        defaultManualSpotlightEnabled: Bool,
        cameraControlStyle: CameraControlStyle
    ) -> CameraFrameConfiguration {
        guard isAutoZoomEnabled else {
            return .overview
        }

        return manualCameraConfiguration(
            at: time,
            cursorTrack: cursorTrack,
            defaultManualSpotlightEnabled: defaultManualSpotlightEnabled
        )
    }

    private static func manualCameraConfiguration(
        at time: TimeInterval,
        cursorTrack: CursorTrack,
        defaultManualSpotlightEnabled: Bool
    ) -> CameraFrameConfiguration {
        let context = manualCameraContext(
            at: time,
            cursorTrack: cursorTrack,
            defaultManualSpotlightEnabled: defaultManualSpotlightEnabled
        )
        let targetConfiguration = manualCameraConfiguration(
            for: context.currentState,
            at: time,
            cursorTrack: cursorTrack
        )

        guard let transition = context.lastTransition else {
            return targetConfiguration
        }

        let transitionDuration = manualTransitionDuration(to: transition.toState)
        let rawProgress = (time - transition.startTime) / transitionDuration
        guard rawProgress > 0, rawProgress < 1 else {
            return targetConfiguration
        }

        let fromConfiguration = manualCameraConfiguration(
            for: transition.fromState,
            at: transition.startTime,
            cursorTrack: cursorTrack
        )
        let easedProgress = easeInOutCubic(rawProgress)

        return interpolateCameraConfiguration(
            from: fromConfiguration,
            to: targetConfiguration,
            progress: easedProgress
        )
    }

    private static func manualCameraConfiguration(
        for state: ManualCameraState,
        at time: TimeInterval,
        cursorTrack: CursorTrack
    ) -> CameraFrameConfiguration {
        switch state {
        case .overview:
            return .overview
        case let .spotlight(point, zoomStep):
            return CameraFrameConfiguration(
                focusPoint: stabilizedManualPoint(point),
                zoomFactor: manualZoomFactor(for: zoomStep)
            )
        case let .follow(zoomStep):
            guard cursorTrack.isUsableForAutoZoom else {
                return .overview
            }

            return CameraFrameConfiguration(
                focusPoint: manualFollowPoint(at: time, samples: cursorTrack.samples),
                zoomFactor: manualZoomFactor(for: zoomStep)
            )
        }
    }

    private static func manualCameraContext(
        at time: TimeInterval,
        cursorTrack: CursorTrack,
        defaultManualSpotlightEnabled: Bool
    ) -> ManualCameraContext {
        var state: ManualCameraState = .overview
        var lastTransition: ManualCameraTransition?
        var isSpotlightEnabled = defaultManualSpotlightEnabled

        for event in cursorTrack.cameraControlEvents where event.time <= time {
            let previousState = state
            switch event.action {
            case .toggleSpotlightEffect:
                isSpotlightEnabled.toggle()
            default:
                state = nextManualCameraState(from: state, event: event, cursorTrack: cursorTrack)
                lastTransition = ManualCameraTransition(
                    fromState: previousState,
                    toState: state,
                    startTime: event.time
                )
            }
        }

        return ManualCameraContext(
            currentState: state,
            lastTransition: lastTransition,
            isSpotlightEnabled: isSpotlightEnabled
        )
    }

    private static func nextManualCameraState(
        from state: ManualCameraState,
        event: CameraControlEvent,
        cursorTrack: CursorTrack
    ) -> ManualCameraState {
        switch event.action {
        case .stepZoom:
            let nextZoomStep: Int
            switch state {
            case let .spotlight(_, zoomStep), let .follow(zoomStep):
                nextZoomStep = min(zoomStep + 1, manualZoomFactors.count)
            case .overview:
                nextZoomStep = 1
            }

            return .spotlight(
                focusPoint: event.normalizedLocation ?? interpolatedPoint(at: event.time, samples: cursorTrack.samples),
                zoomStep: nextZoomStep
            )
        case .toggleFollow:
            switch state {
            case .follow:
                return .overview
            case .overview:
                return .follow(zoomStep: 1)
            case let .spotlight(_, zoomStep):
                return .follow(zoomStep: zoomStep)
            }
        case .resetOverview:
            return .overview
        case .toggleSpotlightEffect:
            return state
        }
    }

    private static func cameraPoint(at time: TimeInterval, samples: [CursorTrackSample]) -> CGPoint {
        let current = interpolatedPoint(at: time, samples: samples)
        let trailing1 = interpolatedPoint(at: max(time - 0.14, 0), samples: samples)
        let trailing2 = interpolatedPoint(at: max(time - 0.30, 0), samples: samples)
        let trailing3 = interpolatedPoint(at: max(time - 0.50, 0), samples: samples)
        let trailing4 = interpolatedPoint(at: max(time - 0.74, 0), samples: samples)

        let smoothed = CGPoint(
            x: current.x * 0.22 + trailing1.x * 0.24 + trailing2.x * 0.24 + trailing3.x * 0.18 + trailing4.x * 0.12,
            y: current.y * 0.22 + trailing1.y * 0.24 + trailing2.y * 0.24 + trailing3.y * 0.18 + trailing4.y * 0.12
        )

        return CGPoint(
            x: 0.5 + stabilizedOffset(smoothed.x - 0.5, deadZone: 0.032, response: 0.78, maxOffset: 0.30),
            y: 0.5 + stabilizedOffset(smoothed.y - 0.5, deadZone: 0.028, response: 0.78, maxOffset: 0.28)
        )
    }

    private static func manualFollowPoint(at time: TimeInterval, samples: [CursorTrackSample]) -> CGPoint {
        let current = interpolatedPoint(at: time, samples: samples)
        let trailing1 = interpolatedPoint(at: max(time - 0.08, 0), samples: samples)
        let trailing2 = interpolatedPoint(at: max(time - 0.18, 0), samples: samples)

        let smoothed = CGPoint(
            x: current.x * 0.48 + trailing1.x * 0.32 + trailing2.x * 0.20,
            y: current.y * 0.48 + trailing1.y * 0.32 + trailing2.y * 0.20
        )

        return CGPoint(
            x: 0.5 + stabilizedOffset(smoothed.x - 0.5, deadZone: 0.014, response: 0.96, maxOffset: 0.34),
            y: 0.5 + stabilizedOffset(smoothed.y - 0.5, deadZone: 0.012, response: 0.96, maxOffset: 0.32)
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
            return 1.12
        }

        let current = interpolatedPoint(at: time, samples: samples)
        let previous = interpolatedPoint(at: max(time - 0.24, 0), samples: samples)
        let earlier = interpolatedPoint(at: max(time - 0.48, 0), samples: samples)
        let motion = distance(current, previous)
        let trend = distance(previous, earlier)
        let speed = max((motion * 0.65 + trend * 0.35) - 0.008, 0)

        return 1.12 + min(speed * 3.4, 1) * 0.10
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private static func stabilizedOffset(
        _ value: CGFloat,
        deadZone: CGFloat,
        response: CGFloat,
        maxOffset: CGFloat
    ) -> CGFloat {
        let magnitude = abs(value)
        guard magnitude > deadZone else {
            return 0
        }

        let sign: CGFloat = value >= 0 ? 1 : -1
        let adjusted = (magnitude - deadZone) * response
        return sign * min(adjusted, maxOffset)
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return sqrt(dx * dx + dy * dy)
    }

    private static func manualTransitionDuration(to state: ManualCameraState) -> TimeInterval {
        switch state {
        case .overview:
            0.22
        case let .spotlight(_, zoomStep), let .follow(zoomStep):
            0.26 + Double(zoomStep - 1) * 0.04
        }
    }

    private static func manualZoomFactor(for zoomStep: Int) -> CGFloat {
        let index = max(min(zoomStep, manualZoomFactors.count), 1) - 1
        return manualZoomFactors[index]
    }

    private static func interpolateCameraConfiguration(
        from: CameraFrameConfiguration,
        to: CameraFrameConfiguration,
        progress: Double
    ) -> CameraFrameConfiguration {
        let fromFocus = from.focusPoint ?? CGPoint(x: 0.5, y: 0.5)
        let toFocus = to.focusPoint ?? CGPoint(x: 0.5, y: 0.5)
        let x = interpolate(fromFocus.x, toFocus.x, progress)
        let y = interpolate(fromFocus.y, toFocus.y, progress)
        let zoom = interpolate(from.zoomFactor, to.zoomFactor, progress)

        if zoom <= 1.001 {
            return .overview
        }

        return CameraFrameConfiguration(
            focusPoint: CGPoint(x: x, y: y),
            zoomFactor: zoom
        )
    }

    private static func interpolate(_ from: CGFloat, _ to: CGFloat, _ progress: Double) -> CGFloat {
        from + (to - from) * CGFloat(progress)
    }

    private static func easeInOutCubic(_ progress: Double) -> Double {
        if progress < 0.5 {
            return 4 * progress * progress * progress
        }

        let adjusted = (-2 * progress) + 2
        return 1 - (adjusted * adjusted * adjusted) / 2
    }

    private static func stabilizedManualPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: clamp(point.x, min: 0.14, max: 0.86),
            y: clamp(point.y, min: 0.14, max: 0.86)
        )
    }

    private static func spotlightOverlay(
        at time: TimeInterval,
        renderSize: CGSize,
        sourceExtent: CGRect,
        activeCropRect: CGRect?,
        cursorTrack: CursorTrack,
        cameraConfiguration: CameraFrameConfiguration,
        defaultManualSpotlightEnabled: Bool,
        cameraControlStyle: CameraControlStyle
    ) -> CIImage? {
        guard let configuration = spotlightOverlayConfiguration(
            at: time,
            cursorTrack: cursorTrack,
            cameraConfiguration: cameraConfiguration,
            defaultManualSpotlightEnabled: defaultManualSpotlightEnabled,
            cameraControlStyle: cameraControlStyle
        ) else {
            return nil
        }

        let sourcePoint = CGPoint(
            x: sourceExtent.minX + sourceExtent.width * configuration.focusPoint.x,
            y: sourceExtent.minY + sourceExtent.height * configuration.focusPoint.y
        )
        let projectedPoint = projectPoint(
            sourcePoint,
            sourceExtent: sourceExtent,
            activeCropRect: activeCropRect,
            renderSize: renderSize
        )
        let extent = CGRect(origin: .zero, size: renderSize)
        let center = CIVector(x: projectedPoint.x, y: projectedPoint.y)
        let baseRadius = min(renderSize.width, renderSize.height)
        let focusRadius = max(
            baseRadius * (configuration.followsCursor ? 0.17 : 0.2) - CGFloat(configuration.zoomStep - 1) * 16,
            96
        )

        var overlay = CIImage.empty().cropped(to: extent)

        if let shadow = radialGradient(
            center: center,
            radius0: focusRadius * 0.82,
            radius1: focusRadius * 1.65,
            color0: CIColor.clear,
            color1: CIColor(red: 0.01, green: 0.02, blue: 0.03, alpha: configuration.followsCursor ? 0.36 : 0.30)
        ) {
            overlay = shadow.cropped(to: extent).composited(over: overlay)
        }

        return overlay
    }

    private static func spotlightOverlayConfiguration(
        at time: TimeInterval,
        cursorTrack: CursorTrack,
        cameraConfiguration: CameraFrameConfiguration,
        defaultManualSpotlightEnabled: Bool,
        cameraControlStyle: CameraControlStyle
    ) -> SpotlightOverlayConfiguration? {
        guard cameraControlStyle == .manualHotkeys,
              cameraConfiguration.focusPoint != nil,
              cameraConfiguration.hasZoom else {
            return nil
        }

        let context = manualCameraContext(
            at: time,
            cursorTrack: cursorTrack,
            defaultManualSpotlightEnabled: defaultManualSpotlightEnabled
        )
        guard context.isSpotlightEnabled else {
            return nil
        }
        switch context.currentState {
        case let .spotlight(point, zoomStep):
            return SpotlightOverlayConfiguration(
                focusPoint: stabilizedManualPoint(point),
                zoomStep: zoomStep,
                followsCursor: false
            )
        case let .follow(zoomStep):
            return SpotlightOverlayConfiguration(
                focusPoint: highlightFollowPoint(at: time, samples: cursorTrack.samples),
                zoomStep: zoomStep,
                followsCursor: true
            )
        case .overview:
            return nil
        }
    }

    private static func highlightFollowPoint(at time: TimeInterval, samples: [CursorTrackSample]) -> CGPoint {
        let current = interpolatedPoint(at: time, samples: samples)
        let trailing = interpolatedPoint(at: max(time - 0.03, 0), samples: samples)
        let blended = CGPoint(
            x: current.x * 0.82 + trailing.x * 0.18,
            y: current.y * 0.82 + trailing.y * 0.18
        )

        return CGPoint(
            x: clamp(blended.x, min: 0.06, max: 0.94),
            y: clamp(blended.y, min: 0.06, max: 0.94)
        )
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
        isClickHighlightEnabled: Bool,
        defaultManualSpotlightEnabled: Bool,
        cameraControlStyle: CameraControlStyle
    ) -> String {
        let cameraLabel = "수동 카메라"

        if isAutoZoomEnabled && isClickHighlightEnabled {
            return "\(base) · \(cameraLabel) · 클릭 강조"
        }

        if isAutoZoomEnabled {
            return "\(base) · \(cameraLabel)"
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
