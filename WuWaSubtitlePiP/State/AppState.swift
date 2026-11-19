import Foundation
import Observation

public enum AppTab: Hashable, Sendable {
    case control
    case calibration
    case historyAndSettings
}

/// Central @MainActor coordinator tying together ReplayKit IPC, offline Apple Translation,
/// Picture-in-Picture rendering, ROI calibration, appearance preferences, and a 100-item backlog.
@MainActor
@Observable
public final class AppState {
    public static let maxHistoryEntries: Int = 100

    private enum DefaultsKey {
        static let roi = "wuwa.subtitle.roi.v1"
        static let appearance = "wuwa.subtitle.appearance.v1"
    }

    public let ipcBridge: BroadcastIPCBridge
    public let translationService: OfflineTranslationService
    public let pipManager: PiPSubtitleManager

    public var selectedTab: AppTab = .control

    public var roi: SubtitleROI {
        didSet {
            let clamped = roi.clamped()
            if clamped != roi {
                roi = clamped
                return
            }
            persistROI(clamped)
            ipcBridge.publishROI(clamped)
        }
    }

    public var appearance: PiPAppearanceSettings {
        didSet {
            persistAppearance(appearance)
            ipcBridge.publishAppearance(appearance)
            pipManager.updateAppearance(
                appearance,
                isLiveScanning: broadcastStatus.state == .active
            )
        }
    }

    public private(set) var broadcastStatus: BroadcastStatusPayload = .idle
    public private(set) var history: [TranslatedHistoryEntry] = []
    public private(set) var currentSpeaker: String?
    public private(set) var currentEnglish: String = ""
    public private(set) var currentVietnamese: String = "Sẵn sàng dịch phụ đề Wuthering Waves"
    public private(set) var lastTotalLatencyMs: Int = 0
    public private(set) var isTranslating: Bool = false
    public private(set) var statusBannerMessage: String?

    private var hasBootstrapped: Bool = false
    private var activeTranslationTask: Task<Void, Never>?
    private var demoSampleIndex: Int = 0

    private let demoDialogues: [(speaker: String, english: String, fallbackVietnamese: String)] = [
        (
            speaker: "Yangyang",
            english: "Rover, a Tacet Field just erupted near Jinzhou! Watch out for Overclocking.",
            fallbackVietnamese: "Lữ Khách ơi, một Vùng Tàn Tượng vừa bùng phát gần Cẩm Châu! Hãy cẩn thận kẻo bị Quá Tải."
        ),
        (
            speaker: "Jinhsi",
            english: "The Sentinel Jué foresaw the Waveworn Phenomenon returning to Huanglong.",
            fallbackVietnamese: "Tuế Chủ Giác đã tiên tri Hiện Tượng Sóng Mòn sẽ quay trở lại Hoàng Long."
        ),
        (
            speaker: "Shorekeeper",
            english: "The Tethys System detected Fractsidus activity inside the Sonoro Sphere.",
            fallbackVietnamese: "Hệ Thống Tethys đã phát hiện hoạt động của Tàn Tinh Hội bên trong Cầu Cộng Hưởng."
        )
    ]

    public init(
        ipcBridge: BroadcastIPCBridge = BroadcastIPCBridge(role: .hostApp),
        translationService: OfflineTranslationService = OfflineTranslationService(),
        pipManager: PiPSubtitleManager = PiPSubtitleManager()
    ) {
        self.ipcBridge = ipcBridge
        self.translationService = translationService
        self.pipManager = pipManager
        self.roi = Self.loadPersistedROI() ?? .wuWaDialogueDefault
        self.appearance = Self.loadPersistedAppearance() ?? .default
    }

    /// Initializes IPC listening, checks offline language pack status, and syncs initial settings.
    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        ipcBridge.publishROI(roi)
        ipcBridge.publishAppearance(appearance)
        broadcastStatus = ipcBridge.readBroadcastStatus()

        ipcBridge.startListening { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleIPCEvent(event)
            }
        }

        await translationService.refreshLanguagePackStatus()
        pipManager.updateSubtitle(
            speaker: currentSpeaker,
            vietnameseText: currentVietnamese,
            originalEnglish: currentEnglish.isEmpty ? nil : currentEnglish,
            appearance: appearance,
            isLiveScanning: broadcastStatus.state == .active
        )
    }

    public var resolvedBroadcastExtensionBundleID: String {
        AppGroupResolver.resolvedBroadcastExtensionBundleID()
    }

    public var activeTransportDescription: String {
        ipcBridge.activeTransportMode.vietnameseLabel
    }

    public var appGroupDiagnosticDescription: String {
        ipcBridge.resolvedAppGroup.status.vietnameseDescription
    }

    public func requestOfflinePackDownload() {
        Task {
            await translationService.prepareOfflineLanguagePack()
        }
    }

    public func refreshOfflinePackStatus() {
        Task {
            await translationService.refreshLanguagePackStatus()
        }
    }

    public func applyROIPreset(_ preset: SubtitleROI) {
        roi = preset.clamped()
    }

    public func clearHistory() {
        history.removeAll()
    }

    /// Runs a realistic Wuthering Waves sample line on the PiP subtitle renderer so the player
    /// can test Vietnamese diacritics, font size, opacity, and PiP floating before launching the game.
    public func runDemoSubtitleOnPiP() {
        let sample = demoDialogues[demoSampleIndex % demoDialogues.count]
        demoSampleIndex += 1

        let displaySpeaker = appearance.enableWuWaGlossary
            ? WuWaGlossary.localizeSpeakerName(sample.speaker)
            : sample.speaker

        Task {
            let vietnameseText: String
            let usedGlossary: Bool

            if translationService.packStatus.isReady {
                do {
                    let result = try await translationService.translate(
                        sample.english,
                        enableGlossary: appearance.enableWuWaGlossary
                    )
                    vietnameseText = result.translatedVietnamese
                    usedGlossary = result.usedGlossary
                } catch {
                    vietnameseText = sample.fallbackVietnamese
                    usedGlossary = appearance.enableWuWaGlossary
                }
            } else {
                vietnameseText = sample.fallbackVietnamese
                usedGlossary = appearance.enableWuWaGlossary
            }

            currentSpeaker = displaySpeaker
            currentEnglish = sample.english
            currentVietnamese = vietnameseText
            statusBannerMessage = "Đã đẩy câu thoại mẫu lên cửa sổ phụ đề PiP."

            pipManager.updateSubtitle(
                speaker: displaySpeaker,
                vietnameseText: vietnameseText,
                originalEnglish: sample.english,
                appearance: appearance,
                isLiveScanning: broadcastStatus.state == .active
            )

            appendHistory(
                TranslatedHistoryEntry(
                    speaker: displaySpeaker,
                    originalEnglish: sample.english,
                    translatedVietnamese: vietnameseText,
                    confidence: 0.99,
                    usedGlossary: usedGlossary
                )
            )
        }
    }

    // MARK: - IPC Handling

    private func handleIPCEvent(_ event: BroadcastIPCEvent) {
        switch event {
        case .dialogue(let payload):
            handleIncomingDialogue(payload)
        case .status(let status):
            broadcastStatus = status
            pipManager.updateAppearance(
                appearance,
                isLiveScanning: status.state == .active
            )
        case .roi, .appearance:
            break
        }
    }

    private func handleIncomingDialogue(_ payload: CapturedDialoguePayload) {
        activeTranslationTask?.cancel()

        let startedAt = ContinuousClock.now
        let localizedSpeaker = appearance.enableWuWaGlossary
            ? WuWaGlossary.localizeSpeakerName(payload.speaker)
            : payload.speaker

        activeTranslationTask = Task { [weak self] in
            guard let self else { return }
            self.isTranslating = true
            defer { self.isTranslating = false }

            do {
                let output = try await self.translationService.translate(
                    payload.rawText,
                    enableGlossary: self.appearance.enableWuWaGlossary
                )
                guard !Task.isCancelled else { return }

                let elapsed = startedAt.duration(to: .now)
                let translateMs = max(
                    0,
                    Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
                )

                self.currentSpeaker = localizedSpeaker
                self.currentEnglish = output.originalEnglish
                self.currentVietnamese = output.translatedVietnamese
                self.lastTotalLatencyMs = self.broadcastStatus.lastOCRDurationMs + translateMs
                self.statusBannerMessage = nil

                self.pipManager.updateSubtitle(
                    speaker: localizedSpeaker,
                    vietnameseText: output.translatedVietnamese,
                    originalEnglish: output.originalEnglish,
                    appearance: self.appearance,
                    isLiveScanning: self.broadcastStatus.state == .active
                )

                self.appendHistory(
                    TranslatedHistoryEntry(
                        speaker: localizedSpeaker,
                        originalEnglish: output.originalEnglish,
                        translatedVietnamese: output.translatedVietnamese,
                        confidence: payload.confidence,
                        usedGlossary: output.usedGlossary
                    )
                )
            } catch OfflineTranslationError.cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.statusBannerMessage = error.localizedDescription
                self.pipManager.updateSubtitle(
                    speaker: localizedSpeaker,
                    vietnameseText: "Cần tải gói dịch ngoại tuyến Anh → Việt ở Bước 1.",
                    originalEnglish: payload.rawText,
                    appearance: self.appearance,
                    isLiveScanning: self.broadcastStatus.state == .active
                )
            }
        }
    }

    private func appendHistory(_ entry: TranslatedHistoryEntry) {
        if let latest = history.first,
           DialogueTextCleaner.normalizeForComparison(latest.originalEnglish)
            == DialogueTextCleaner.normalizeForComparison(entry.originalEnglish) {
            return
        }
        history.insert(entry, at: 0)
        if history.count > Self.maxHistoryEntries {
            history.removeLast(history.count - Self.maxHistoryEntries)
        }
    }

    // MARK: - Local Persistence

    private func persistROI(_ roi: SubtitleROI) {
        if let data = try? JSONEncoder().encode(roi) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.roi)
        }
    }

    private func persistAppearance(_ settings: PiPAppearanceSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.appearance)
        }
    }

    private static func loadPersistedROI() -> SubtitleROI? {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.roi) else {
            return nil
        }
        return try? JSONDecoder().decode(SubtitleROI.self, from: data)
    }

    private static func loadPersistedAppearance() -> PiPAppearanceSettings? {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.appearance) else {
            return nil
        }
        return try? JSONDecoder().decode(PiPAppearanceSettings.self, from: data)
    }
}
