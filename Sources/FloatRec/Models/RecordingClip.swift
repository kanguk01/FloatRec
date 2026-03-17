import Foundation

struct RecordingClip: Identifiable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
    let duration: TimeInterval
    let sourceLabel: String
    let isTemporary: Bool

    init(
        id: UUID = UUID(),
        fileURL: URL,
        createdAt: Date = .now,
        duration: TimeInterval,
        sourceLabel: String,
        isTemporary: Bool = true
    ) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.duration = duration
        self.sourceLabel = sourceLabel
        self.isTemporary = isTemporary
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
