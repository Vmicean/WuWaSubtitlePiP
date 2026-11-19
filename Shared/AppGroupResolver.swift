import Foundation
import os

public enum AppGroupResolutionSource: String, Codable, Equatable, Sendable {
    case embeddedMobileProvision
    case infoPlist
    case hardcodedDefault

    public var vietnameseLabel: String {
        switch self {
        case .embeddedMobileProvision:
            return "Hồ sơ ký embedded.mobileprovision"
        case .infoPlist:
            return "Cấu hình Info.plist"
        case .hardcodedDefault:
            return "Mã App Group mặc định"
        }
    }
}

public enum AppGroupDiagnosticStatus: Equatable, Sendable {
    case activeAppGroup(String)
    case unavailableFallback

    public var vietnameseDescription: String {
        switch self {
        case .activeAppGroup(let groupID):
            return "Đã kết nối App Group: \(groupID)"
        case .unavailableFallback:
            return "App Group không khả dụng — chuyển sang kết nối dự phòng nội bộ (Loopback)"
        }
    }

    public var isAppGroupAvailable: Bool {
        if case .activeAppGroup = self {
            return true
        }
        return false
    }
}

public struct ResolvedAppGroup: Equatable, Sendable {
    public let groupIdentifier: String
    public let containerURL: URL?
    public let status: AppGroupDiagnosticStatus
    public let source: AppGroupResolutionSource

    public init(
        groupIdentifier: String,
        containerURL: URL?,
        status: AppGroupDiagnosticStatus,
        source: AppGroupResolutionSource
    ) {
        self.groupIdentifier = groupIdentifier
        self.containerURL = containerURL
        self.status = status
        self.source = source
    }
}

/// Dynamically resolves the runtime App Group identifier after SideStore / AltStore / Sideloadly
/// re-signs the app and extension with a Free Apple ID team prefix.
public final class AppGroupResolver: @unchecked Sendable {
    public static let defaultFallbackGroupID = "group.com.wuwatranslator.shared"
    public static let infoPlistKey = "AppGroupIdentifier"
    public static let broadcastExtensionSuffix = ".BroadcastExtension"

    private static let cacheLock = OSAllocatedUnfairLock<ResolvedAppGroup?>(initialState: nil)

    public static func resolve(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        useCache: Bool = true
    ) -> ResolvedAppGroup {
        if useCache, let cached = cacheLock.withLock({ $0 }) {
            return cached
        }

        let candidates = buildCandidateIdentifiers(from: bundle)
        let firstCandidate = candidates.first ?? (defaultFallbackGroupID, AppGroupResolutionSource.hardcodedDefault)

        for candidate in candidates {
            if let containerURL = verifiedContainerURL(
                for: candidate.identifier,
                fileManager: fileManager
            ) {
                let resolved = ResolvedAppGroup(
                    groupIdentifier: candidate.identifier,
                    containerURL: containerURL,
                    status: .activeAppGroup(candidate.identifier),
                    source: candidate.source
                )
                if useCache {
                    cacheLock.withLock { $0 = resolved }
                }
                return resolved
            }
        }

        let fallback = ResolvedAppGroup(
            groupIdentifier: firstCandidate.identifier,
            containerURL: nil,
            status: .unavailableFallback,
            source: firstCandidate.source
        )
        if useCache {
            cacheLock.withLock { $0 = fallback }
        }
        return fallback
    }

    public static func resetCache() {
        cacheLock.withLock { $0 = nil }
    }

    /// Computes the active Broadcast Extension bundle ID dynamically so RPSystemBroadcastPickerView
    /// still binds cleanly even after SideStore / AltStore rewrites the main app's bundle ID.
    public static func resolvedBroadcastExtensionBundleID(bundle: Bundle = .main) -> String {
        guard let mainBundleID = bundle.bundleIdentifier, !mainBundleID.isEmpty else {
            return "com.wuwatranslator.app.BroadcastExtension"
        }
        if mainBundleID.hasSuffix(broadcastExtensionSuffix) {
            return mainBundleID
        }
        return mainBundleID + broadcastExtensionSuffix
    }

    /// Parses raw binary .mobileprovision bytes by locating the embedded XML <plist>...</plist> payload
    /// and reading Entitlements["com.apple.security.application-groups"].
    public static func extractAppGroups(fromMobileProvisionData data: Data) -> [String] {
        let startMarker = Data("<plist".utf8)
        let endMarker = Data("</plist>".utf8)

        guard let startRange = data.range(of: startMarker),
              let endRange = data.range(
                of: endMarker,
                options: [],
                in: startRange.lowerBound..<data.endIndex
              ) else {
            return []
        }

        let xmlSlice = data.subdata(in: startRange.lowerBound..<endRange.upperBound)
        guard let plistObject = try? PropertyListSerialization.propertyList(
            from: xmlSlice,
            options: [],
            format: nil
        ) as? [String: Any],
        let entitlements = plistObject["Entitlements"] as? [String: Any],
        let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
            return []
        }

        return groups
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func buildCandidateIdentifiers(
        from bundle: Bundle
    ) -> [(identifier: String, source: AppGroupResolutionSource)] {
        var results: [(identifier: String, source: AppGroupResolutionSource)] = []
        var seen = Set<String>()

        func appendIfUnique(_ id: String, source: AppGroupResolutionSource) {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            results.append((trimmed, source))
        }

        // 1. Primary source: embedded.mobileprovision rewritten by SideStore / AltStore / Sideloadly.
        if let provisionURL = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
           let provisionData = try? Data(contentsOf: provisionURL) {
            let signedGroups = extractAppGroups(fromMobileProvisionData: provisionData)
            let prioritized = signedGroups.sorted { lhs, rhs in
                let lhsMatches = lhs.localizedCaseInsensitiveContains("wuwatranslator")
                let rhsMatches = rhs.localizedCaseInsensitiveContains("wuwatranslator")
                return lhsMatches && !rhsMatches
            }
            for group in prioritized {
                appendIfUnique(group, source: .embeddedMobileProvision)
            }
        }

        // 2. Secondary source: Info.plist AppGroupIdentifier key.
        if let plistGroup = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String {
            appendIfUnique(plistGroup, source: .infoPlist)
        }

        // 3. Tertiary fallback: hardcoded default group identifier.
        appendIfUnique(defaultFallbackGroupID, source: .hardcodedDefault)

        return results
    }

    private static func verifiedContainerURL(
        for groupIdentifier: String,
        fileManager: FileManager
    ) -> URL? {
        guard let url = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }

        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            return nil
        }
    }
}
