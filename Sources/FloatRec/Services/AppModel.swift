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

    let hotKeyDisplayString = GlobalHotKeyAction.toggleRecording.displayString
    let stopHotKeyDisplayString = GlobalHotKeyAction.stopRecording.displayString

    private let permissionService: ScreenRecordingPermissionService
    private let sourceCatalog: ScreenCaptureSourceCatalog
    private let recordingCoordinator: RecordingCoordinator
    private let thumbnailService = ClipThumbnailService()
    private let areaSelectionOverlayController = AreaSelectionOverlayController()
    private let captureSelectionOverlayController = CaptureSelectionOverlayController()
    private let displayHighlightController = DisplayHighlightController()
    private var activeHotKeyTask: Task<Void, Never>?
    private var processingTimeoutTask: Task<Void, Never>?
    private var postProcessingTasks: [UUID: Task<Void, Never>] = [:]
    private var selectedSourceOverrides: [CaptureMode: CaptureSourceOption] = [:]
    private var selectedResolvedSources: [CaptureMode: ResolvedCaptureSource] = [:]
    private lazy var shelfController = ShelfWindowController()
    private lazy var settingsWindowController = SettingsWindowController()
    private lazy var hotKeyManager: GlobalHotKeyManager = {
        let manager = GlobalHotKeyManager()
        manager.onAction = { [weak self] action in
            Task { @MainActor [weak self] in
                self?.activeHotKeyTask?.cancel()
                self?.activeHotKeyTask = Task { [weak self] in
                    await self?.handleGlobalHotKey(action)
                }
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
        installLifecycleObservers()
        _ = hotKeyManager
    }

    func teardownOnTermination() {
        recordingCoordinator.teardownOnTermination()
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
            return selectedSourceOverrides[captureMode]
        }

        return currentSourceOptions.first(where: { $0.id == selectedSourceID })
            ?? selectedSourceOverrides[captureMode]
    }

    private var selectedResolvedSource: ResolvedCaptureSource? {
        selectedResolvedSources[captureMode]
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

    var cameraControlSummary: String {
        switch featureFlags.cameraControlStyle {
        case .automatic:
            "자동 추적으로 확대와 이동을 계산합니다."
        case .manualHotkeys:
            "녹화 중 ⌃1 반복 확대 · ⌃2 따라가기 · ⌃3 전체화면 · ⌃4 스포트라이트"
        }
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

    func handleGlobalHotKey(_ action: GlobalHotKeyAction) async {
        logger.info(
            "received global hotkey action=\(String(describing: action), privacy: .public) state=\(self.recordingState.statusText, privacy: .public)"
        )

        switch action {
        case .toggleRecording:
            switch recordingState {
            case .idle:
                await startRecording()
            case .recording:
                await stopRecording()
            case .requestingPermission:
                cancelPendingCapturePreparation()
            case .processing:
                break
            }
        case .stopRecording:
            switch recordingState {
            case .recording:
                await stopRecording()
            case .requestingPermission:
                cancelPendingCapturePreparation()
            case .processing:
                forceResetFromProcessing()
            case .idle:
                return
            }
        }
    }

    func refreshCaptureSourcesIfNeeded() async {
        guard displaySources.isEmpty, windowSources.isEmpty else {
            return
        }

        guard let cachedSnapshot = sourceCatalog.snapshotFromCache() else {
            return
        }

        applySnapshot(cachedSnapshot)
    }

    func refreshCaptureSources(force: Bool) async {
        guard !isRefreshingSources else {
            logger.info("source refresh skipped because refresh is already running")
            return
        }

        isRefreshingSources = true
        defer { isRefreshingSources = false }

        do {
            let snapshot = try await sourceCatalog.loadSnapshot(forceRefresh: force)
            applySnapshot(snapshot)
            logger.info(
                "source refresh succeeded: displays=\(snapshot.displays.count, privacy: .public) windows=\(snapshot.windows.count, privacy: .public)"
            )
        } catch {
            let preflightGranted = permissionService.canAccess()
            logger.error(
                "source refresh failed: preflightGranted=\(preflightGranted, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )

            if preflightGranted {
                if force || (displaySources.isEmpty && windowSources.isEmpty) {
                    lastErrorMessage = "캡처 소스 목록을 불러오지 못했습니다: \(error.localizedDescription)"
                }
            } else if force {
                lastErrorMessage = permissionService.noAccessSourceRefreshMessage()
            }
        }
    }

    func startRecording() async {
        guard !recordingState.isBusy else { return }

        lastErrorMessage = nil
        recordingState = .requestingPermission
        logger.info("recording start requested")

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

        let selectionResult: CaptureSelectionResult
        do {
            selectionResult = try await captureSelectionOverlayController.selectCaptureSource()
        } catch CaptureSelectionError.cancelled {
            recordingState = .idle
            return
        } catch {
            recordingState = .idle
            lastErrorMessage = error.localizedDescription
            return
        }

        let resolvedSource: ResolvedCaptureSource
        var areaSelection: AreaSelection? = nil

        switch selectionResult {
        case .display(let display):
            captureMode = .display
            resolvedSource = .display(display, sourceLabel: "디스플레이 녹화")
            let option = CaptureSourceOption(
                id: "display-\(display.displayID)",
                title: "디스플레이",
                detail: "\(Int(display.width))×\(Int(display.height))",
                sourceLabel: "디스플레이 녹화"
            )
            selectedSourceOverrides[.display] = option
            selectedResolvedSources[.display] = resolvedSource
            selectedSourceID = option.id

        case .window(let window):
            captureMode = .window
            let appName = window.owningApplication?.applicationName ?? "앱"
            let windowTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sourceLabel = windowTitle.isEmpty ? appName : "\(appName) · \(windowTitle)"
            resolvedSource = .window(window, sourceLabel: sourceLabel)
            let option = CaptureSourceOption(
                id: "window-\(window.windowID)",
                title: windowTitle.isEmpty ? "\(appName) 창" : windowTitle,
                detail: "\(appName) · \(Int(window.frame.width))×\(Int(window.frame.height))",
                sourceLabel: sourceLabel
            )
            selectedSourceOverrides[.window] = option
            selectedResolvedSources[.window] = resolvedSource
            selectedSourceID = option.id

        case .area(let area):
            captureMode = .area
            areaSelection = area
            lastAreaSelectionDescription = area.sourceLabel
            guard let resolved = try? await sourceCatalog.resolveAreaSelection(area) else {
                recordingState = .idle
                lastErrorMessage = "영역 선택을 처리하지 못했습니다."
                return
            }
            resolvedSource = resolved
        }

        do {
            try await recordingCoordinator.startRecording(
                mode: captureMode,
                selectedSourceID: selectedSourceID,
                resolvedSourceOverride: resolvedSource,
                areaSelection: areaSelection,
                isAutoZoomEnabled: featureFlags.isAutoZoomEnabled,
                isClickHighlightEnabled: featureFlags.isClickHighlightEnabled,
                defaultManualSpotlightEnabled: featureFlags.defaultManualSpotlightEnabled,
                cameraControlStyle: featureFlags.cameraControlStyle,
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
        guard recordingState.isRecording else { return }

        areaSelectionOverlayController.cancelSelection()
        recordingState = .processing
        scheduleProcessingTimeout()

        do {
            let artifact = try await recordingCoordinator.stopRecording()
            let shouldProcess = recordingCoordinator.needsPostProcessing(artifact)

            logger.info(
                "stop recording summary: duration=\(artifact.duration, privacy: .public)s needsProcessing=\(shouldProcess, privacy: .public)"
            )

            let clip = RecordingClip(
                fileURL: artifact.fileURL,
                duration: artifact.duration,
                sourceLabel: artifact.sourceLabel,
                isPostProcessing: shouldProcess
            )

            clips.insert(clip, at: 0)
            recordingState = .idle
            processingTimeoutTask?.cancel()
            showShelf()

            if shouldProcess {
                enqueuePostProcessing(for: clip, artifact: artifact)
            }
        } catch {
            recordingState = .idle
            processingTimeoutTask?.cancel()
            lastErrorMessage = error.localizedDescription
        }
    }

    func selectSource(_ option: CaptureSourceOption) {
        guard !recordingState.isBusy else { return }
        selectedSourceOverrides[captureMode] = option
        selectedSourceID = option.id
        lastErrorMessage = nil

        Task {
            if let resolved = try? await sourceCatalog.resolveSource(
                mode: captureMode,
                selectedSourceID: option.id
            ) {
                selectedResolvedSources[captureMode] = resolved
            }
        }
    }

    func highlightSource(_ option: CaptureSourceOption) {
        guard captureMode == .display else {
            displayHighlightController.hideAll()
            return
        }
        let idString = option.id.replacingOccurrences(of: "display-", with: "")
        guard let displayID = UInt32(idString) else { return }
        displayHighlightController.showHighlight(for: displayID, label: option.title)
    }

    func clearSourceHighlight() {
        displayHighlightController.hideAll()
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
            _ = try await sourceCatalog.loadSnapshot(forceRefresh: true, fallbackToCache: false)
            logger.info("operational screen access probe succeeded despite preflight access being false")
            return true
        } catch {
            logger.error("operational screen access probe failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func installLifecycleObservers() {
        let notificationCenter = NotificationCenter.default
        _ = notificationCenter.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.logger.info("application resigned active, cancelling area selection")
                self?.areaSelectionOverlayController.cancelSelection()
            }
        }
    }

    private func cancelPendingCapturePreparation() {
        logger.info("cancelling pending capture preparation")
        captureSelectionOverlayController.cancelSelection()
        areaSelectionOverlayController.cancelSelection()
        recordingState = .idle
        lastErrorMessage = nil
    }

    private func syncSelectedSource() {
        switch captureMode {
        case .area:
            selectedSourceID = nil
        case .display, .window:
            if selectedSourceID != selectedSourceOverrides[captureMode]?.id {
                selectedSourceID = selectedSourceOverrides[captureMode]?.id
            }

            guard let selectedSourceID else {
                return
            }

            guard !currentSourceOptions.isEmpty else {
                return
            }

            guard let matchedOption = currentSourceOptions.first(where: { $0.id == selectedSourceID }) else {
                selectedSourceOverrides[captureMode] = nil
                selectedResolvedSources[captureMode] = nil
                self.selectedSourceID = nil
                return
            }

            selectedSourceOverrides[captureMode] = matchedOption
        }
    }

    private func applySnapshot(_ snapshot: CaptureSourceSnapshot) {
        displaySources = snapshot.displays
        windowSources = snapshot.windows
        syncSelectedSource()
    }

    private func forceResetFromProcessing() {
        logger.warning("force-resetting from processing state via hotkey")
        recordingState = .idle
        lastErrorMessage = nil
    }

    private func scheduleProcessingTimeout() {
        processingTimeoutTask?.cancel()
        processingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if case .processing = self.recordingState {
                self.logger.warning("processing state timed out after 10 seconds, forcing idle")
                self.recordingState = .idle
                self.lastErrorMessage = "녹화 정리가 너무 오래 걸려 중단했습니다."
            }
        }
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
