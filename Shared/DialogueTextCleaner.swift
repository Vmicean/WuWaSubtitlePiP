import Foundation

public struct CleanedDialogue: Equatable, Sendable {
    public let speaker: String?
    public let dialogueText: String

    public init(speaker: String?, dialogueText: String) {
        self.speaker = speaker
        self.dialogueText = dialogueText
    }
}

public enum DialogueTextCleaner {
    public static let duplicateSimilarityThreshold: Double = 0.88

    private static let exactNoiseTokens: Set<String> = [
        "skip",
        "auto",
        "auto-play",
        "autoplay",
        "log",
        "story log",
        "review",
        "hide",
        "hide ui",
        "menu",
        "back",
        "next",
        "confirm",
        "cancel",
        "continue",
        "tap to continue",
        "click to continue",
        "touch to continue",
        "skip all",
        "play",
        "pause",
        "exit",
        "close",
        "uid",
        "fps",
        "ms",
        "ping"
    ]

    private static let hudNoisePatterns: [NSRegularExpression] = {
        let patterns = [
            #"(?i)^uid\s*[:#\-]?\s*\d{5,14}.*$"#,
            #"(?i)^\d{1,3}\s*fps$"#,
            #"(?i)^fps\s*[:\-]?\s*\d{1,3}$"#,
            #"(?i)^(ping\s*)?\d{1,4}\s*ms$"#,
            #"(?i)^(skip|auto|log|hide)(\s*[|/•·\-]\s*(skip|auto|log|hide))+$"#,
            #"^[\s\p{P}\p{S}\d]+$"#,
            #"^(?:[>»▶►▸•·●○◆◇★☆]+\s*)+$"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Cleans raw OCR lines from Wuthering Waves, filters HUD noise, and separates an optional speaker name.
    public static func clean(lines rawLines: [String]) -> CleanedDialogue? {
        let filteredLines = rawLines
            .map { normalizeWhitespace($0) }
            .filter { !isNoiseLine($0) }

        guard !filteredLines.isEmpty else {
            return nil
        }

        if filteredLines.count == 1 {
            return extractInlineSpeakerIfPresent(from: filteredLines[0])
        }

        let firstLine = filteredLines[0]
        if isLikelySpeakerHeader(firstLine) {
            let speakerName = firstLine
                .trimmingCharacters(in: CharacterSet(charactersIn: " :：-—–|•·"))
            let body = filteredLines.dropFirst().joined(separator: " ")
            let normalizedBody = normalizeWhitespace(body)
            guard !normalizedBody.isEmpty else {
                return nil
            }
            return CleanedDialogue(
                speaker: speakerName.isEmpty ? nil : speakerName,
                dialogueText: normalizedBody
            )
        }

        let joinedDialogue = normalizeWhitespace(filteredLines.joined(separator: " "))
        guard !joinedDialogue.isEmpty else { return nil }
        return extractInlineSpeakerIfPresent(from: joinedDialogue)
    }

    public static func isNoiseLine(_ line: String) -> Bool {
        let trimmed = normalizeWhitespace(line)
        guard trimmed.count >= 2 else {
            return true
        }

        let lowered = trimmed.lowercased()
        if exactNoiseTokens.contains(lowered) {
            return true
        }

        // Strip enclosing brackets/icons like "[Skip]" or "(Auto)" and recheck.
        let stripped = lowered.trimmingCharacters(
            in: CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces)
        )
        if stripped.isEmpty || exactNoiseTokens.contains(stripped) {
            return true
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        for regex in hudNoisePatterns {
            if regex.firstMatch(in: trimmed, options: [], range: range) != nil {
                return true
            }
        }

        // Require at least two alphabetic letters so stray HUD icons/numbers do not leak through.
        let letterCount = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letterCount < 2
    }

    /// Computes normalized Levenshtein similarity in range [0.0, 1.0].
    /// Uses O(min(m, n)) memory so it stays lightweight inside WuWaBroadcastExtension.
    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(normalizeForComparison(lhs))
        let b = Array(normalizeForComparison(rhs))

        if a.isEmpty && b.isEmpty { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }
        if a == b { return 1.0 }

        let shorter: [Character]
        let longer: [Character]
        if a.count <= b.count {
            shorter = a
            longer = b
        } else {
            shorter = b
            longer = a
        }

        var previousRow = Array(0...shorter.count)
        var currentRow = Array(repeating: 0, count: shorter.count + 1)

        for i in 1...longer.count {
            currentRow[0] = i
            let longChar = longer[i - 1]
            for j in 1...shorter.count {
                let substitutionCost = (longChar == shorter[j - 1]) ? 0 : 1
                let insertion = currentRow[j - 1] + 1
                let deletion = previousRow[j] + 1
                let substitution = previousRow[j - 1] + substitutionCost
                currentRow[j] = min(insertion, min(deletion, substitution))
            }
            swap(&previousRow, &currentRow)
        }

        let editDistance = previousRow[shorter.count]
        let maxLength = max(a.count, b.count)
        return max(0.0, 1.0 - (Double(editDistance) / Double(maxLength)))
    }

    /// Suppresses duplicate frames and smooths typewriter-effect text reveal.
    /// Returns true if the candidate frame should be skipped.
    public static func shouldSuppressDuplicate(
        previous: String,
        current: String,
        threshold: Double = duplicateSimilarityThreshold
    ) -> Bool {
        let prevNorm = normalizeForComparison(previous)
        let currNorm = normalizeForComparison(current)

        if currNorm.isEmpty {
            return true
        }
        if prevNorm.isEmpty {
            return false
        }
        if prevNorm == currNorm {
            return true
        }

        // Ignore brief OCR dropouts where the tail of the previous line disappeared.
        if currNorm.count < prevNorm.count && prevNorm.hasPrefix(currNorm) {
            return true
        }

        // Allow typewriter growth once at least 6 meaningful new characters have appeared.
        if currNorm.count >= prevNorm.count + 6 && currNorm.hasPrefix(prevNorm) {
            return false
        }

        return similarity(prevNorm, currNorm) >= threshold
    }

    public static func normalizeWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func normalizeForComparison(_ text: String) -> String {
        normalizeWhitespace(text)
            .lowercased()
    }

    private static func isLikelySpeakerHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 28 else {
            return false
        }

        let words = trimmed.split(separator: " ")
        guard words.count >= 1, words.count <= 4 else {
            return false
        }

        // Dialogue sentences normally end with sentence punctuation or contain commas.
        if let lastChar = trimmed.last, ".!?…\"'".contains(lastChar) {
            return false
        }
        if trimmed.contains(",") || trimmed.contains(";") {
            return false
        }

        // Speaker headers typically start with an uppercase letter or "?"" (e.g., "???").
        guard let firstScalar = trimmed.unicodeScalars.first else { return false }
        return CharacterSet.uppercaseLetters.contains(firstScalar) || trimmed == "???"
    }

    private static func extractInlineSpeakerIfPresent(from line: String) -> CleanedDialogue {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return CleanedDialogue(speaker: nil, dialogueText: line)
        }

        let prefix = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let remainder = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

        guard !prefix.isEmpty,
              !remainder.isEmpty,
              prefix.count <= 24,
              prefix.split(separator: " ").count <= 3,
              isLikelySpeakerHeader(prefix) else {
            return CleanedDialogue(speaker: nil, dialogueText: line)
        }

        return CleanedDialogue(speaker: prefix, dialogueText: remainder)
    }
}
