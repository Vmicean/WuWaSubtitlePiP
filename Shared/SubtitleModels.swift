import CoreGraphics
import Foundation

public struct CapturedDialoguePayload: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let speaker: String?
    public let rawText: String
    public let confidence: Float

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        speaker: String? = nil,
        rawText: String,
        confidence: Float
    ) {
        self.id = id
        self.timestamp = timestamp
        self.speaker = speaker
        self.rawText = rawText
        self.confidence = min(1.0, max(0.0, confidence))
    }
}

/// Normalized top-left rectangle (0.0 ... 1.0) in SwiftUI screen coordinate space.
public struct SubtitleROI: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Standard Wuthering Waves landscape dialogue box at the lower center of iPhone 14 Pro Max.
    public static let wuWaDialogueDefault = SubtitleROI(
        x: 0.08,
        y: 0.68,
        width: 0.84,
        height: 0.28
    )

    /// Expanded capture zone covering both branching dialogue choices and main subtitle lines.
    public static let wuWaDialogueWithChoices = SubtitleROI(
        x: 0.08,
        y: 0.44,
        width: 0.84,
        height: 0.52
    )

    /// Compact lower strip optimized for story cutscenes without choice buttons.
    public static let wuWaCutsceneSubtitles = SubtitleROI(
        x: 0.10,
        y: 0.76,
        width: 0.80,
        height: 0.20
    )

    /// Full screen capture for menus, tutorials, or lore documents.
    public static let fullScreen = SubtitleROI(
        x: 0.02,
        y: 0.04,
        width: 0.96,
        height: 0.92
    )

    public func clamped() -> SubtitleROI {
        let minExtent = 0.08
        let safeWidth = min(1.0, max(minExtent, width))
        let safeHeight = min(1.0, max(minExtent, height))
        let safeX = min(1.0 - safeWidth, max(0.0, x))
        let safeY = min(1.0 - safeHeight, max(0.0, y))
        return SubtitleROI(x: safeX, y: safeY, width: safeWidth, height: safeHeight)
    }

    /// Converts top-left UI coordinates into Apple Vision's normalized bottom-left coordinate space.
    public var visionRect: CGRect {
        let safe = clamped()
        let bottomLeftY = max(0.0, min(1.0 - safe.height, 1.0 - safe.y - safe.height))
        return CGRect(x: safe.x, y: bottomLeftY, width: safe.width, height: safe.height)
    }
}

public enum IPCTransportMode: String, Codable, Equatable, Sendable {
    case appGroupDarwin
    case loopbackTCP
    case initializing

    public var vietnameseLabel: String {
        switch self {
        case .appGroupDarwin:
            return "App Group + Darwin Notify (Tốc độ tối đa)"
        case .loopbackTCP:
            return "Loopback nội bộ 127.0.0.1:47891 (Dự phòng Free ID)"
        case .initializing:
            return "Đang khởi tạo kênh truyền..."
        }
    }
}

public enum BroadcastSessionState: String, Codable, Equatable, Sendable {
    case idle
    case active
    case paused
    case finished
    case error

    public var vietnameseLabel: String {
        switch self {
        case .idle:
            return "Chưa bắt đầu quét màn hình"
        case .active:
            return "Đang quét phụ đề Wuthering Waves"
        case .paused:
            return "Đã tạm dừng quét"
        case .finished:
            return "Đã dừng phát màn hình"
        case .error:
            return "Gặp lỗi kết nối Broadcast"
        }
    }
}

public struct BroadcastStatusPayload: Codable, Equatable, Sendable {
    public let state: BroadcastSessionState
    public let updatedAt: Date
    public let framesProcessed: Int
    public let framesDropped: Int
    public let lastOCRDurationMs: Int
    public let estimatedMemoryMB: Double
    public let transportMode: IPCTransportMode
    public let statusMessage: String?

    public init(
        state: BroadcastSessionState = .idle,
        updatedAt: Date = Date(),
        framesProcessed: Int = 0,
        framesDropped: Int = 0,
        lastOCRDurationMs: Int = 0,
        estimatedMemoryMB: Double = 0,
        transportMode: IPCTransportMode = .initializing,
        statusMessage: String? = nil
    ) {
        self.state = state
        self.updatedAt = updatedAt
        self.framesProcessed = max(0, framesProcessed)
        self.framesDropped = max(0, framesDropped)
        self.lastOCRDurationMs = max(0, lastOCRDurationMs)
        self.estimatedMemoryMB = max(0, estimatedMemoryMB)
        self.transportMode = transportMode
        self.statusMessage = statusMessage
    }

    public static let idle = BroadcastStatusPayload()
}

public struct PiPAppearanceSettings: Codable, Equatable, Sendable {
    public var fontSize: Double
    public var backgroundOpacity: Double
    public var showOriginalEnglish: Bool
    public var enableWuWaGlossary: Bool
    public var ocrAccurateMode: Bool

    public init(
        fontSize: Double = 23.0,
        backgroundOpacity: Double = 0.88,
        showOriginalEnglish: Bool = false,
        enableWuWaGlossary: Bool = true,
        ocrAccurateMode: Bool = false
    ) {
        self.fontSize = min(36.0, max(16.0, fontSize))
        self.backgroundOpacity = min(1.0, max(0.55, backgroundOpacity))
        self.showOriginalEnglish = showOriginalEnglish
        self.enableWuWaGlossary = enableWuWaGlossary
        self.ocrAccurateMode = ocrAccurateMode
    }

    public static let `default` = PiPAppearanceSettings()
}

public struct TranslatedHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let speaker: String?
    public let originalEnglish: String
    public let translatedVietnamese: String
    public let confidence: Float
    public let usedGlossary: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        speaker: String? = nil,
        originalEnglish: String,
        translatedVietnamese: String,
        confidence: Float,
        usedGlossary: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.speaker = speaker
        self.originalEnglish = originalEnglish
        self.translatedVietnamese = translatedVietnamese
        self.confidence = min(1.0, max(0.0, confidence))
        self.usedGlossary = usedGlossary
    }
}
