import AVFoundation
import AppKit
import Foundation

private final class AssetImageGeneratorBox: @unchecked Sendable {
    let generator: AVAssetImageGenerator

    init(generator: AVAssetImageGenerator) {
        self.generator = generator
    }
}

@MainActor
final class ClipThumbnailService {
    private let cache = NSCache<NSURL, NSImage>()

    func cachedThumbnail(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func loadThumbnail(for url: URL, maxSize: CGSize) async -> NSImage? {
        if let cachedThumbnail = cachedThumbnail(for: url) {
            return cachedThumbnail
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize

        let generatorBox = AssetImageGeneratorBox(generator: generator)

        let thumbnail: NSImage? = await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 0.15, preferredTimescale: 600))]) { _, image, _, _, _ in
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }

                let thumbnail = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
                continuation.resume(returning: thumbnail)
                _ = generatorBox
            }
        }

        if let thumbnail {
            cache.setObject(thumbnail, forKey: url as NSURL)
        }

        return thumbnail
    }

    func removeThumbnail(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}
