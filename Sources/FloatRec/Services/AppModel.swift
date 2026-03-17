import AppKit
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    private let logger = Logger(subsystem: "dev.floatrec.app", category: "app-model")
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
    private lazy var captureTargetPickerController: CaptureTargetPickerController = {
        let controller = CaptureTargetPickerController()
        controller.onSelection = { [weak self] selection in
            Task { @MainActor [weak self] in
                await self?.applyCaptureTargetSelection(selection)
            }
        }
        controller.onCancel = { [weak self] in
            self?.logger.info("content picker selection cancelled")
        }
        controller.onError = { [weak self] error in
            self?.lastErrorMessage = "캡처 대상을 선택하지 못했습니다: \(error.localizedDescription)"
        }
        return controller
    }()
    private var postProcessingTasks: [UUID: Task<Void, Never>] = [:]
    private lazy var shelfController = ShelfWindowController()
    private lazy var settingsWindowController = SettingsWindowController()
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
            return nil
        }

        return currentSourceOptions.first(where: { $0.id == selectedSourceID })
    }

    var captureSelectionSummary: String {
        switch captureMode {
        case .area:
            lastAreaSelectionDescription ?? "녹화 시작을 누르면 드래그로 영역을 선택합니다."
        case .display, .window:
            selectedSourceOption?.detail ?? "\(captureMode.title) 대상을 화면에서 직접 선택해 주세요."
        }
    }

    var installRecommendationMessage: String? {
        permissionService.runtimeInstallIssue()?.guidanceText
    }

    var shouldRecommendApplicationsInstall: Bool {
        installRecommendationMessage != nil
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
        await refreshCaptureSources(force: false)
    }

    func refreshCaptureSources(force: Bool) async {
        guard !isRefreshingSources else {
            logger.info("source refresh skipped because refresh is already running")
            return
        }

        isRefreshingSources = true
        defer { isRefreshingSources = false }

        do {
            let snapshot = try await sourceCatalog.loadSnapshot()
            displaySources = snapshot.displays
            windowSources = snapshot.windows
            logger.info(
                "source refresh succeeded: displays=\(snapshot.displays.count, privacy: .public) windows=\(snapshot.windows.count, privacy: .public)"
            )
            syncSelectedSource()
        } catch {
            let preflightGranted = permissionService.canAccess()
            logger.error(
                "source refresh failed: preflightGranted=\(preflightGranted, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )

            if preflightGranted {
                lastErrorMessage = "캡처 소스 목록을 불러오지 못했습니다: \(error.localizedDescription)"
            } else if force {
                lastErrorMessage = permissionService.noAccessSourceRefreshMessage()
            }
        }
    }

    func startRecording() async {
        guard !recordingState.isBusy else {
            return
        }

        lastErrorMessage = nil
        recordingState = .requestingPermission
        logger.info("recording start requested for mode=\(self.captureMode.title, privacy: .public)")

        let granted = await permissionService.ensureAccess()
        if !granted {
            let operationalAccess = await hasOperationalScreenAccess()
            guard operationalAccess else {
                recordingState = .idle
                logger.error("recording start blocked because permission request was denied")
                lastErrorMessage = permissionService.deniedAccessMessage()
                return
            }

            logger.info("recording start continuing because source access probe succeeded after denied permission request")
        }

        if displaySources.isEmpty && windowSources.isEmpty {
            await refreshCaptureSources(force: false)
        }

        guard captureMode == .area || selectedSourceOption != nil else {
            recordingState = .idle
            logger.error("recording start blocked because no source option is available")
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
            logger.info("recording started successfully")
        } catch {
            recordingState = .idle
            logger.error("recording start failed: \(error.localizedDescription, privacy: .public)")
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
            let finalArtifact: RecordingArtifact
            let shouldProcessInBackground = recordingCoordinator.shouldProcessInBackground(artifact)
            logger.info(
                "stop recording summary: duration=\(artifact.duration, privacy: .public)s background=\(shouldProcessInBackground, privacy: .public) sync=\(self.recordingCoordinator.shouldProcessSynchronously(artifact), privacy: .public) cursorTrack=\(artifact.cursorTrack != nil, privacy: .public)"
            )

            if recordingCoordinator.shouldProcessSynchronously(artifact) {
                finalArtifact = await recordingCoordinator.processRecordedArtifact(artifact)
            } else {
                finalArtifact = artifact
            }

            let clip = RecordingClip(
                fileURL: finalArtifact.fileURL,
                duration: finalArtifact.duration,
                sourceLabel: finalArtifact.sourceLabel,
                isPostProcessing: shouldProcessInBackground
            )

            clips.insert(clip, at: 0)
            recordingState = .idle
            showShelf()

            if shouldProcessInBackground {
                enqueuePostProcessing(for: clip, artifact: artifact)
            }
        } catch {
            recordingState = .idle
            lastErrorMessage = error.localizedDescription
        }
    }

    func presentCaptureTargetPicker() {
        guard captureMode != .area else {
            return
        }

        lastErrorMessage = nil
        captureTargetPickerController.present(for: captureMode)
    }

    func showShelf() {
        shelfController.show(using: self)
    }

    func hideShelf() {
        shelfController.hide()
    }

    func removeClip(_ clip: RecordingClip) {
        postProcessingTasks[clip.id]?.cancel()
        postProcessingTasks.removeValue(forKey: clip.id)
        clips.removeAll { $0.id == clip.id }
        deleteTemporaryClipIfNeeded(clip)

        if clips.isEmpty {
            hideShelf()
        } else {
            showShelf()
        }
    }

    func clearClips() {
        postProcessingTasks.values.forEach { $0.cancel() }
        postProcessingTasks.removeAll()
        let currentClips = clips
        clips.removeAll()
        currentClips.forEach(deleteTemporaryClipIfNeeded)
        hideShelf()
    }

    func revealClipInFinder(_ clip: RecordingClip) {
        guard !clip.isPostProcessing else {
            lastErrorMessage = "후처리 중에는 결과 클립이 아직 준비되지 않았습니다."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([clip.fileURL])
    }

    func copyClipToPasteboard(_ clip: RecordingClip) {
        guard !clip.isPostProcessing else {
            lastErrorMessage = "후처리 완료 후 복사할 수 있습니다."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([clip.fileURL as NSURL])
    }

    func openPreview(for clip: RecordingClip) {
        guard !clip.isPostProcessing else {
            lastErrorMessage = "후처리 완료 후 미리보기를 열 수 있습니다."
            return
        }

        let opened = NSWorkspace.shared.open(clip.fileURL)
        if !opened {
            lastErrorMessage = "미리보기를 열지 못했습니다."
        }
    }

    func saveClip(_ clip: RecordingClip) {
        guard !clip.isPostProcessing else {
            lastErrorMessage = "후처리 완료 후 저장할 수 있습니다."
            return
        }

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

    func openApplicationsFolder() {
        permissionService.openApplicationsFolder()
    }

    func revealRunningApp() {
        permissionService.revealRunningApp()
    }

    func openSettingsWindow() {
        settingsWindowController.show(using: self)
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

    private func hasOperationalScreenAccess() async -> Bool {
        if permissionService.canAccess() {
            return true
        }

        do {
            _ = try await sourceCatalog.loadSnapshot()
            logger.info("operational screen access probe succeeded despite preflight access being false")
            return true
        } catch {
            logger.error("operational screen access probe failed: \(error.localizedDescription, privacy: .public)")
            return false
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

            selectedSourceID = nil
        }
    }

    private func applyCaptureTargetSelection(_ selection: CaptureTargetPickerController.Selection) async {
        captureMode = selection.mode
        await refreshCaptureSources(force: false)
        selectedSourceID = selection.sourceID
        lastErrorMessage = nil
    }

    private func enqueuePostProcessing(for clip: RecordingClip, artifact: RecordingArtifact) {
        postProcessingTasks[clip.id]?.cancel()
        logger.info("queued background post-processing for clip \(clip.id.uuidString, privacy: .public)")
        postProcessingTasks[clip.id] = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let processedArtifact = await self.recordingCoordinator.processRecordedArtifact(artifact)
            guard !Task.isCancelled else {
                return
            }

            self.finishPostProcessing(for: clip, processedArtifact: processedArtifact)
        }
    }

    private func finishPostProcessing(for clip: RecordingClip, processedArtifact: RecordingArtifact) {
        defer {
            postProcessingTasks[clip.id] = nil
        }

        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else {
            return
        }

        let updatedClip = RecordingClip(
            id: clip.id,
            fileURL: processedArtifact.fileURL,
            createdAt: clip.createdAt,
            duration: processedArtifact.duration,
            sourceLabel: processedArtifact.sourceLabel,
            isTemporary: clip.isTemporary,
            isPostProcessing: false
        )

        let postProcessingSucceeded =
            processedArtifact.fileURL != clip.fileURL ||
            processedArtifact.sourceLabel != clip.sourceLabel

        if postProcessingSucceeded {
            logger.info("background post-processing finished for clip \(clip.id.uuidString, privacy: .public)")
        } else {
            logger.error("background post-processing fell back to original clip \(clip.id.uuidString, privacy: .public)")
            lastErrorMessage = "후처리가 완료되지 않아 원본 클립을 유지했습니다."
        }

        if clip.fileURL != updatedClip.fileURL {
            clipThumbnails.removeValue(forKey: clip.fileURL)
            thumbnailService.removeThumbnail(for: clip.fileURL)

            if clip.isTemporary {
                try? FileManager.default.removeItem(at: clip.fileURL)
            }
        }

        clips[index] = updatedClip
        Task {
            await loadThumbnailIfNeeded(for: updatedClip)
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
