import Foundation

struct RecordingClip: Identifiable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
    let duration: TimeInterval
    let sourceLabel: String
    let isTemporary: Bool
    let isPostProcessing: Bool

    init(
        id: UUID = UUID(),
        fileURL: URL,
        createdAt: Date = .now,
        duration: TimeInterval,
        sourceLabel: String,
        isTemporary: Bool = true,
        isPostProcessing: Bool = false
    ) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.duration = duration
        self.sourceLabel = sourceLabel
        self.isTemporary = isTemporary
        self.isPostProcessing = isPostProcessing
    }

    var title: String {
        fileURL.deletingPathExtension().lastPathComponent
    }

    var formattedDuration: String {
        ClipDurationFormatter.string(from: duration)
    }

    var subtitle: String {
        "\(sourceLabel) · \(formattedDuration)"
    }
}
