import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var clips: [RecordingClip] = []
    @Published private var clipThumbnails: [URL: NSImage] = [:]
    @Published var captureMode: CaptureMode = .display {
        didSet {
            syncSelectedSource()
        }
    }
    @Published var selectedSourceID: String?
    @Published private(set) var displaySources: [CaptureSourceOption] = []
    @Published private(set) var windowSources: [CaptureSourceOption] = []
    @Published private(set) var isRefreshingSources = false
    @Published var lastErrorMessage: String?
    @Published private(set) var lastAreaSelectionDescription: String?
    @Published var featureFlags = RecordingFeatureFlags()

    let hotKeyDisplayString = "⌘⇧9"

    private let permissionService: ScreenRecordingPermissionService
    private let sourceCatalog: ScreenCaptureSourceCatalog
    private let recordingCoordinator: RecordingCoordinator
    private let thumbnailService = ClipThumbnailService()
    private let areaSelectionOverlayController = AreaSelectionOverlayController()
    private lazy var shelfController = ShelfWindowController()
    private lazy var previewWindowController = ClipPreviewWindowController()
    private lazy var hotKeyManager: GlobalHotKeyManager = {
        let manager = GlobalHotKeyManager()
        manager.onActivate = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.toggleRecording()
            }
        }
        manager.register()
        return manager
    }()

    init(
        permissionService: ScreenRecordingPermissionService = ScreenRecordingPermissionService(),
        demoRecordingService: DemoRecordingService = DemoRecordingService(),
        sourceCatalog: ScreenCaptureSourceCatalog = ScreenCaptureSourceCatalog()
    ) {
        self.permissionService = permissionService
        self.sourceCatalog = sourceCatalog
        self.recordingCoordinator = RecordingCoordinator(
            sourceCatalog: sourceCatalog,
            demoRecordingService: demoRecordingService
        )
        _ = hotKeyManager
    }

    var statusItemSymbolName: String {
        recordingState.isRecording ? "record.circle.fill" : "circle.dashed"
    }

    var latestClip: RecordingClip? {
        clips.first
    }

    var currentSourceOptions: [CaptureSourceOption] {
        switch captureMode {
        case .display:
            displaySources
        case .window:
            windowSources
        case .area:
            []
        }
    }

    var selectedSourceOption: CaptureSourceOption? {
        guard let selectedSourceID else {
            return currentSourceOptions.first
        }

        return currentSourceOptions.first(where: { $0.id == selectedSourceID }) ?? currentSourceOptions.first
    }

    var captureSelectionSummary: String {
        switch captureMode {
        case .area:
            lastAreaSelectionDescription ?? "녹화 시작을 누르면 드래그로 영역을 선택합니다."
        case .display, .window:
            selectedSourceOption?.detail ?? "캡처 대상을 불러오지 않았습니다."
        }
    }

    func toggleRecording() async {
        switch recordingState {
        case .idle:
            await startRecording()
        case .recording:
            await stopRecording()
        case .requestingPermission, .processing:
            break
        }
    }

    func refreshCaptureSourcesIfNeeded() async {
        guard !permissionService.canAccess() else {
            await refreshCaptureSources(force: false)
            return
        }
    }

    func refreshCaptureSources(force: Bool) async {
        guard !isRefreshingSources else {
            return
        }

        if !permissionService.canAccess() {
            if force {
                lastErrorMessage = "화면 녹화 권한을 허용한 뒤 캡처 소스를 불러올 수 있습니다."
            }
            return
        }

        isRefreshingSources = true
        defer { isRefreshingSources = false }

        do {
            let snapshot = try await sourceCatalog.loadSnapshot()
            displaySources = snapshot.displays
            windowSources = snapshot.windows
            syncSelectedSource()
        } catch {
            lastErrorMessage = "캡처 소스 목록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func startRecording() async {
        guard !recordingState.isBusy else {
            return
        }

        lastErrorMessage = nil
        recordingState = .requestingPermission

        let granted = await permissionService.ensureAccess()
        guard granted else {
            recordingState = .idle
            lastErrorMessage = "화면 녹화 권한이 필요합니다. 시스템 설정에서 FloatRec 접근을 허용해 주세요."
            return
        }

        if displaySources.isEmpty && windowSources.isEmpty {
            await refreshCaptureSources(force: false)
        }

        guard captureMode == .area || selectedSourceOption != nil else {
            recordingState = .idle
            lastErrorMessage = "선택한 캡처 모드에 사용할 대상이 없습니다."
            return
        }

        let areaSelection: AreaSelection?
        if captureMode == .area {
            do {
                areaSelection = try await areaSelectionOverlayController.selectArea()
                lastAreaSelectionDescription = areaSelection?.sourceLabel
            } catch AreaSelectionError.cancelled {
                recordingState = .idle
                return
            } catch {
                recordingState = .idle
                lastErrorMessage = error.localizedDescription
                return
            }
        } else {
            areaSelection = nil
        }

        do {
            try await recordingCoordinator.startRecording(
                mode: captureMode,
                selectedSourceID: selectedSourceID,
                areaSelection: areaSelection,
                isAutoZoomEnabled: featureFlags.isAutoZoomEnabled,
                isClickHighlightEnabled: featureFlags.isClickHighlightEnabled,
                fallbackSourceLabel: currentSourceLabel
            )
            recordingState = .recording(startedAt: .now)
        } catch {
            recordingState = .idle
            lastErrorMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard recordingState.isRecording else {
            return
        }

        recordingState = .processing

        do {
            let artifact = try await recordingCoordinator.stopRecording()
            let clip = RecordingClip(
                fileURL: artifact.fileURL,
                duration: artifact.duration,
                sourceLabel: artifact.sourceLabel
            )

            clips.insert(clip, at: 0)
            recordingState = .idle
            showShelf()
        } catch {
            recordingState = .idle
            lastErrorMessage = error.localizedDescription
        }
    }

    func showShelf() {
        shelfController.show(using: self)
    }

    func hideShelf() {
        shelfController.hide()
    }

    func removeClip(_ clip: RecordingClip) {
        clips.removeAll { $0.id == clip.id }
        deleteTemporaryClipIfNeeded(clip)

        if clips.isEmpty {
            hideShelf()
        } else {
            showShelf()
        }
    }

    func clearClips() {
        let currentClips = clips
        clips.removeAll()
        currentClips.forEach(deleteTemporaryClipIfNeeded)
        hideShelf()
    }

    func revealClipInFinder(_ clip: RecordingClip) {
        NSWorkspace.shared.activateFileViewerSelecting([clip.fileURL])
    }

    func openPreview(for clip: RecordingClip) {
        previewWindowController.show(clip: clip)
    }

    func saveClip(_ clip: RecordingClip) {
        let savePanel = NSSavePanel()
        savePanel.title = "녹화 저장"
        savePanel.nameFieldStringValue = clip.fileURL.lastPathComponent
        savePanel.canCreateDirectories = true

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: clip.fileURL, to: destinationURL)
        } catch {
            lastErrorMessage = "파일 저장에 실패했습니다: \(error.localizedDescription)"
        }
    }

    func openScreenRecordingSettings() {
        permissionService.openSettings()
    }

    func clearError() {
        lastErrorMessage = nil
    }

    func thumbnail(for clip: RecordingClip) -> NSImage? {
        clipThumbnails[clip.fileURL] ?? thumbnailService.cachedThumbnail(for: clip.fileURL)
    }

    func loadThumbnailIfNeeded(for clip: RecordingClip) async {
        if clipThumbnails[clip.fileURL] != nil {
            return
        }

        if let cachedThumbnail = thumbnailService.cachedThumbnail(for: clip.fileURL) {
            clipThumbnails[clip.fileURL] = cachedThumbnail
            return
        }

        if let thumbnail = await thumbnailService.loadThumbnail(
            for: clip.fileURL,
            maxSize: CGSize(width: 640, height: 360)
        ) {
            clipThumbnails[clip.fileURL] = thumbnail
        }
    }

    private var currentSourceLabel: String {
        switch captureMode {
        case .area:
            lastAreaSelectionDescription ?? "영역 선택"
        case .display, .window:
            selectedSourceOption?.sourceLabel ?? captureMode.title
        }
    }

    private func syncSelectedSource() {
        switch captureMode {
        case .area:
            selectedSourceID = nil
        case .display, .window:
            if let selectedSourceID,
               currentSourceOptions.contains(where: { $0.id == selectedSourceID }) {
                return
            }

            selectedSourceID = currentSourceOptions.first?.id
        }
    }

    private func deleteTemporaryClipIfNeeded(_ clip: RecordingClip) {
        clipThumbnails.removeValue(forKey: clip.fileURL)
        thumbnailService.removeThumbnail(for: clip.fileURL)

        guard clip.isTemporary else {
            return
        }

        try? FileManager.default.removeItem(at: clip.fileURL)
    }
}
