import Foundation
import Observation
import os
import SwiftUI
import Translation

public enum OfflineLanguagePackStatus: Equatable, Sendable {
    case unknown
    case checking
    case installed
    case downloadRequired
    case unsupported
    case error(String)

    public var isReady: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    public var vietnameseLabel: String {
        switch self {
        case .unknown:
            return "Chưa kiểm tra gói ngôn ngữ"
        case .checking:
            return "Đang kiểm tra gói Anh – Việt..."
        case .installed:
            return "Đã cài đặt gói ngoại tuyến Anh → Việt"
        case .downloadRequired:
            return "Chưa tải gói dịch ngoại tuyến Anh → Việt"
        case .unsupported:
            return "Thiết bị chưa hỗ trợ dịch Anh → Việt ngoại tuyến"
        case .error(let message):
            return "Lỗi kiểm tra gói dịch: \(message)"
        }
    }
}

public struct TranslationOutput: Equatable, Sendable {
    public let originalEnglish: String
    public let translatedVietnamese: String
    public let usedGlossary: Bool
    public let fromCache: Bool
    public let durationMs: Int

    public init(
        originalEnglish: String,
        translatedVietnamese: String,
        usedGlossary: Bool,
        fromCache: Bool,
        durationMs: Int
    ) {
        self.originalEnglish = originalEnglish
        self.translatedVietnamese = translatedVietnamese
        self.usedGlossary = usedGlossary
        self.fromCache = fromCache
        self.durationMs = max(0, durationMs)
    }
}

public enum OfflineTranslationError: LocalizedError, Sendable {
    case emptyInput
    case packNotInstalled
    case sessionUnavailable
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Không có văn bản tiếng Anh để dịch."
        case .packNotInstalled:
            return "Gói dịch ngoại tuyến Anh → Việt chưa được tải xuống."
        case .sessionUnavailable:
            return "Phiên dịch Apple Translation chưa sẵn sàng."
        case .cancelled:
            return "Yêu cầu dịch đã được thay thế bởi câu thoại mới hơn."
        }
    }
}

/// Thread-safe bounded LRU cache (200 entries) preventing redundant Apple Translation calls
/// on recurring combat hints, NPC greetings, and choice prompts.
public final class TranslationLRUCache: @unchecked Sendable {
    private struct CacheKey: Hashable {
        let normalizedSource: String
        let useGlossary: Bool
    }

    private struct State {
        var storage: [CacheKey: String] = [:]
        var recencyOrder: [CacheKey] = []
    }

    public let capacity: Int
    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    public var count: Int {
        lock.withLock { $0.storage.count }
    }

    public func value(for normalizedSource: String, useGlossary: Bool) -> String? {
        let key = CacheKey(normalizedSource: normalizedSource, useGlossary: useGlossary)
        return lock.withLock { state in
            guard let existing = state.storage[key] else {
                return nil
            }
            if let index = state.recencyOrder.firstIndex(of: key) {
                state.recencyOrder.remove(at: index)
                state.recencyOrder.append(key)
            }
            return existing
        }
    }

    public func insert(_ translatedText: String, for normalizedSource: String, useGlossary: Bool) {
        let key = CacheKey(normalizedSource: normalizedSource, useGlossary: useGlossary)
        lock.withLock { state in
            if state.storage[key] != nil {
                if let index = state.recencyOrder.firstIndex(of: key) {
                    state.recencyOrder.remove(at: index)
                }
            } else if state.recencyOrder.count >= capacity {
                let evicted = state.recencyOrder.removeFirst()
                state.storage.removeValue(forKey: evicted)
            }
            state.storage[key] = translatedText
            state.recencyOrder.append(key)
        }
    }

    public func clear() {
        lock.withLock { state in
            state.storage.removeAll(keepingCapacity: false)
            state.recencyOrder.removeAll(keepingCapacity: false)
        }
    }
}

private enum TranslationWorkItem: Sendable {
    case prepare(CheckedContinuation<Void, Error>)
    case translate(
        sourceText: String,
        useGlossary: Bool,
        continuation: CheckedContinuation<TranslationOutput, Error>
    )
}

/// 100% offline English -> Vietnamese translation engine backed by Apple's iOS 18+ Translation
/// framework, consuming a persistent AsyncStream queue inside RootView's .translationTask modifier.
@MainActor
@Observable
public final class OfflineTranslationService {
    public let sourceLanguage = Locale.Language(identifier: "en")
    public let targetLanguage = Locale.Language(identifier: "vi")

    public private(set) var packStatus: OfflineLanguagePackStatus = .unknown
    public private(set) var isDownloadingPack: Bool = false
    public private(set) var isSessionConnected: Bool = false
    public private(set) var translationConfiguration: TranslationSession.Configuration?
    public private(set) var cacheEntryCount: Int = 0
    public private(set) var lastTranslationDurationMs: Int = 0
    public private(set) var lastErrorMessage: String?

    private let cache = TranslationLRUCache(capacity: 200)
    private let workStream: AsyncStream<TranslationWorkItem>
    private let workContinuation: AsyncStream<TranslationWorkItem>.Continuation
    private var shouldRunPrepareOnNextSessionAttach: Bool = false

    public init() {
        var capturedContinuation: AsyncStream<TranslationWorkItem>.Continuation?
        self.workStream = AsyncStream<TranslationWorkItem>(bufferingPolicy: .bufferingNewest(32)) { continuation in
            capturedContinuation = continuation
        }
        self.workContinuation = capturedContinuation!
    }

    /// Queries Apple's LanguageAvailability API to verify whether EN -> VI offline packs exist locally.
    public func refreshLanguagePackStatus() async {
        packStatus = .checking
        let availability = LanguageAvailability()
        let status = await availability.status(from: sourceLanguage, to: targetLanguage)

        switch status {
        case .installed:
            packStatus = .installed
            lastErrorMessage = nil
            ensurePersistentConfigurationMounted()
        case .supported:
            packStatus = .downloadRequired
            lastErrorMessage = nil
        case .unsupported:
            packStatus = .unsupported
            lastErrorMessage = "iOS trên thiết bị này chưa hỗ trợ cặp ngôn ngữ Anh → Việt."
        @unknown default:
            packStatus = .downloadRequired
        }
    }

    /// Mounts the persistent .translationTask configuration on RootView without triggering
    /// a download sheet unexpectedly.
    public func ensurePersistentConfigurationMounted() {
        if translationConfiguration == nil {
            translationConfiguration = TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage
            )
        }
    }

    /// One-tap trigger to prompt iOS to download the free offline English & Vietnamese packs.
    public func prepareOfflineLanguagePack() async {
        guard !isDownloadingPack else { return }
        isDownloadingPack = true
        lastErrorMessage = nil
        defer { isDownloadingPack = false }

        if isSessionConnected {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let result = workContinuation.yield(.prepare(continuation))
                    if case .terminated = result {
                        continuation.resume(throwing: OfflineTranslationError.sessionUnavailable)
                    }
                }
                await refreshLanguagePackStatus()
                return
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        // If the persistent .translationTask is not yet connected, mount or invalidate it
        // so consumeSession(_:) executes session.prepareTranslation() immediately on attach.
        shouldRunPrepareOnNextSessionAttach = true
        if translationConfiguration == nil {
            translationConfiguration = TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage
            )
        } else {
            translationConfiguration?.invalidate()
        }
    }

    /// Persistent consumer attached to RootView via .translationTask(configuration).
    public func consumeSession(_ session: TranslationSession) async {
        isSessionConnected = true
        defer { isSessionConnected = false }

        if shouldRunPrepareOnNextSessionAttach {
            shouldRunPrepareOnNextSessionAttach = false
            do {
                try await session.prepareTranslation()
                await refreshLanguagePackStatus()
            } catch {
                lastErrorMessage = "Chưa thể tải gói ngôn ngữ: \(error.localizedDescription)"
                await refreshLanguagePackStatus()
            }
        }

        for await item in workStream {
            if Task.isCancelled {
                failItemOnCancellation(item)
                break
            }

            switch item {
            case .prepare(let continuation):
                do {
                    try await session.prepareTranslation()
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }

            case .translate(let sourceText, let useGlossary, let continuation):
                do {
                    let output = try await executeTranslation(
                        sourceText: sourceText,
                        useGlossary: useGlossary,
                        using: session
                    )
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Translates English dialogue to natural Vietnamese 100% offline.
    public func translate(
        _ englishText: String,
        enableGlossary: Bool
    ) async throws -> TranslationOutput {
        let cleanedSource = DialogueTextCleaner.normalizeWhitespace(englishText)
        guard !cleanedSource.isEmpty else {
            throw OfflineTranslationError.emptyInput
        }

        let cacheKey = DialogueTextCleaner.normalizeForComparison(cleanedSource)
        if let cachedVietnamese = cache.value(for: cacheKey, useGlossary: enableGlossary) {
            return TranslationOutput(
                originalEnglish: cleanedSource,
                translatedVietnamese: cachedVietnamese,
                usedGlossary: enableGlossary,
                fromCache: true,
                durationMs: 0
            )
        }

        if packStatus == .unknown {
            await refreshLanguagePackStatus()
        }

        // On iOS 26+ (compiled with Xcode 26 / Swift 6.2+ SDK), use direct installed-pack initializer
        // for zero-overhead background translation without waiting on SwiftUI view lifecycle.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), packStatus == .installed {
            let directSession = TranslationSession(
                installedSource: sourceLanguage,
                target: targetLanguage
            )
            let output = try await executeTranslation(
                sourceText: cleanedSource,
                useGlossary: enableGlossary,
                using: directSession
            )
            return output
        }
        #endif

        ensurePersistentConfigurationMounted()

        guard packStatus == .installed || isSessionConnected else {
            throw OfflineTranslationError.packNotInstalled
        }

        return try await withCheckedThrowingContinuation { continuation in
            let yieldResult = workContinuation.yield(
                .translate(
                    sourceText: cleanedSource,
                    useGlossary: enableGlossary,
                    continuation: continuation
                )
            )
            if case .terminated = yieldResult {
                continuation.resume(throwing: OfflineTranslationError.sessionUnavailable)
            }
        }
    }

    public func clearCache() {
        cache.clear()
        cacheEntryCount = 0
    }

    private func executeTranslation(
        sourceText: String,
        useGlossary: Bool,
        using session: TranslationSession
    ) async throws -> TranslationOutput {
        let startedAt = ContinuousClock.now
        let prepared = useGlossary ? WuWaGlossary.prepareForTranslation(sourceText) : nil
        let textForAppleEngine = prepared?.maskedText ?? sourceText

        let response = try await session.translate(textForAppleEngine)
        let finalVietnamese: String
        if useGlossary {
            finalVietnamese = WuWaGlossary.applyPostProcessing(
                response.targetText,
                prepared: prepared
            )
        } else {
            finalVietnamese = DialogueTextCleaner.normalizeWhitespace(response.targetText)
        }

        let elapsed = startedAt.duration(to: .now)
        let elapsedMs = max(
            1,
            Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        )

        let cacheKey = DialogueTextCleaner.normalizeForComparison(sourceText)
        cache.insert(finalVietnamese, for: cacheKey, useGlossary: useGlossary)
        cacheEntryCount = cache.count
        lastTranslationDurationMs = elapsedMs
        lastErrorMessage = nil

        return TranslationOutput(
            originalEnglish: sourceText,
            translatedVietnamese: finalVietnamese,
            usedGlossary: useGlossary && (prepared?.hasMatches ?? false),
            fromCache: false,
            durationMs: elapsedMs
        )
    }

    private func failItemOnCancellation(_ item: TranslationWorkItem) {
        switch item {
        case .prepare(let continuation):
            continuation.resume(throwing: OfflineTranslationError.cancelled)
        case .translate(_, _, let continuation):
            continuation.resume(throwing: OfflineTranslationError.cancelled)
        }
    }
}
