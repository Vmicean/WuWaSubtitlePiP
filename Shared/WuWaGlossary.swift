import Foundation

public struct GlossaryPreparationResult: Equatable, Sendable {
    public let maskedText: String
    public let tokenMap: [String: String]
    public let matchedTerms: [String]

    public var hasMatches: Bool {
        !tokenMap.isEmpty
    }

    public init(maskedText: String, tokenMap: [String: String], matchedTerms: [String]) {
        self.maskedText = maskedText
        self.tokenMap = tokenMap
        self.matchedTerms = matchedTerms
    }
}

/// Offline English-to-Vietnamese terminology engine for Wuthering Waves.
/// Uses word-boundary-safe numbered placeholders prior to Apple Translation and restores
/// canonical Vietnamese lore/combat terms afterward.
public enum WuWaGlossary {
    public struct TermEntry: Equatable, Sendable {
        public let english: String
        public let vietnamese: String

        public init(_ english: String, _ vietnamese: String) {
            self.english = english
            self.vietnamese = vietnamese
        }
    }

    /// 130+ canonical Wuthering Waves lore, faction, region, combat, item, and character terms.
    public static let entries: [TermEntry] = [
        // Core World & Phenomena
        TermEntry("Waveworn Phenomenon", "Hiện Tượng Sóng Mòn"),
        TermEntry("Waveworn Residue", "Tàn Dư Sóng Mòn"),
        TermEntry("Tacet Discords", "các Tàn Tượng"),
        TermEntry("Tacet Discord", "Tàn Tượng"),
        TermEntry("Tacet Fields", "các Vùng Tàn Tượng"),
        TermEntry("Tacet Field", "Vùng Tàn Tượng"),
        TermEntry("Tacet Mark", "Dấu Ấn Tàn Tượng"),
        TermEntry("Tacetite", "Đá Tàn Tượng"),
        TermEntry("Resonators", "các Cộng Hưởng Giả"),
        TermEntry("Resonator", "Cộng Hưởng Giả"),
        TermEntry("Rover", "Lữ Khách"),
        TermEntry("Forte Circuit", "Mạch Cộng Hưởng"),
        TermEntry("Forte Examination", "Kiểm Tra Cộng Hưởng Lực"),
        TermEntry("Forte", "Cộng Hưởng Lực"),
        TermEntry("Overclocking", "Quá Tải"),
        TermEntry("Overclock", "Quá Tải"),
        TermEntry("The Lament", "Bi Minh"),
        TermEntry("Lament", "Bi Minh"),
        TermEntry("Sentinels", "các Tuế Chủ"),
        TermEntry("Sentinel", "Tuế Chủ"),
        TermEntry("Threnodians", "các Minh Thức"),
        TermEntry("Threnodian", "Minh Thức"),
        TermEntry("Sonoro Spheres", "các Cầu Cộng Hưởng"),
        TermEntry("Sonoro Sphere", "Cầu Cộng Hưởng"),
        TermEntry("Retroact Rain", "Mưa Nghịch Hành"),
        TermEntry("Etheric Sea", "Biển Hư Vô"),
        TermEntry("Dark Tide", "Thủy Triều Đen"),
        TermEntry("Remnant Energy", "Năng Lượng Tàn Dư"),
        TermEntry("Remnant", "Tàn Dư"),
        TermEntry("Frequency", "Tần Số"),
        TermEntry("Frequencies", "các Tần Số"),
        TermEntry("Echoes", "Echo"),
        TermEntry("Echo", "Echo"),
        TermEntry("Data Bank", "Kho Dữ Liệu"),
        TermEntry("Pangu Terminal", "Thiết Bị Đầu Cuối Bàn Cổ"),
        TermEntry("Tethys System", "Hệ Thống Tethys"),
        TermEntry("Tethys Deep", "Vực Sâu Tethys"),
        TermEntry("Stellar Matrix", "Ma Trận Tinh Tú"),
        TermEntry("Somnoire", "Mộng Cảnh"),
        TermEntry("Solaris-3", "Solaris-3"),
        TermEntry("Waveplates", "Tấm Sóng"),
        TermEntry("Waveplate", "Tấm Sóng"),

        // Regions & Locations
        TermEntry("Huanglong", "Hoàng Long"),
        TermEntry("Jinzhou", "Cẩm Châu"),
        TermEntry("Rinascita", "Rinascita"),
        TermEntry("Ragunna City", "Thành Phố Ragunna"),
        TermEntry("Ragunna", "Ragunna"),
        TermEntry("Septimont", "Septimont"),
        TermEntry("The Black Shores", "Bờ Biển Đen"),
        TermEntry("Black Shores", "Bờ Biển Đen"),
        TermEntry("Mt. Firmament", "Thừa Tiêu Sơn"),
        TermEntry("Mount Firmament", "Thừa Tiêu Sơn"),
        TermEntry("Port City of Guixu", "Cảng Thành Quy Khư"),
        TermEntry("Guixu", "Quy Khư"),
        TermEntry("Norfall Barrens", "Bắc Lạc Dã"),
        TermEntry("Desorock Highland", "Cao Nguyên Hoang Thạch"),
        TermEntry("Central Plains", "Trung Đài"),
        TermEntry("Dim Forest", "Rừng U Ám"),
        TermEntry("Whining Aix's Mire", "Đầm Lầy Oán Điểu"),
        TermEntry("Tiger's Maw", "Hổ Khẩu"),
        TermEntry("Qichi Village", "Làng Kỳ Trì"),
        TermEntry("Gorges of Spirits", "Hẻm Núi Quỷ Hồn"),
        TermEntry("Hongzhen", "Hồng Trấn"),
        TermEntry("Loong's Gaze", "Long Vọng"),
        TermEntry("Penitent's End", "Bến Sám Hối"),
        TermEntry("Averardo Vault", "Kho Báu Averardo"),
        TermEntry("Whisperwind Haven", "Vịnh Gió Thầm"),
        TermEntry("Fagaceae Peninsula", "Bán Đảo Sồi"),
        TermEntry("Beohr Waters", "Vùng Biển Beohr"),
        TermEntry("Thessaleo Fells", "Đồi Thessaleo"),

        // Factions & Titles
        TermEntry("Fractsidus Overseer", "Giám Sát Tàn Tinh Hội"),
        TermEntry("Fractsidus", "Tàn Tinh Hội"),
        TermEntry("Midnight Rangers", "Dạ Quy Quân"),
        TermEntry("Huaxu Academy", "Học Viện Hoa Tư"),
        TermEntry("Jinzhou Magistrate", "Lệnh Doãn Cẩm Châu"),
        TermEntry("Ministry of Development", "Bộ Công Nghiệp"),
        TermEntry("Order of the Deep", "Giáo Hội Biển Sâu"),
        TermEntry("Montelli Family", "Gia Tộc Montelli"),
        TermEntry("Fisalia Family", "Gia Tộc Fisalia"),
        TermEntry("Fool's Troupe", "Đoàn Kịch Kẻ Ngốc"),
        TermEntry("Bloom Bearer", "Người Giữ Hoa"),
        TermEntry("Black Shores Consultant", "Cố Vấn Bờ Biển Đen"),
        TermEntry("Patroller", "Tuần Tra Viên"),

        // Combat Skills & Elements
        TermEntry("Resonance Liberation", "Giải Phóng Cộng Hưởng"),
        TermEntry("Resonance Skill", "Kỹ Năng Cộng Hưởng"),
        TermEntry("Intro Skill", "Kỹ Năng Biến Tấu"),
        TermEntry("Outro Skill", "Kỹ Năng Diên Tấu"),
        TermEntry("Concerto Energy", "Năng Lượng Hiệp Tấu"),
        TermEntry("Resonance Energy", "Năng Lượng Cộng Hưởng"),
        TermEntry("Vibration Strength", "Độ Bền Rung Động"),
        TermEntry("Inherent Skill", "Kỹ Năng Cố Hữu"),
        TermEntry("Heavy Attack", "Trọng Kích"),
        TermEntry("Plunging Attack", "Tấn Công Đáp Đất"),
        TermEntry("Dodge Counter", "Phản Kích Né Tránh"),
        TermEntry("Coordinated Attack", "Đòn Đánh Phối Hợp"),
        TermEntry("Spectro Frazzle", "Hiệu Ứng Quang Nhiễu"),
        TermEntry("Aero Erosion", "Hiệu Ứng Phong Thực"),
        TermEntry("Spectro", "Quang Ảnh"),
        TermEntry("Havoc", "Ám Diệt"),
        TermEntry("Aero", "Khí Động"),
        TermEntry("Electro", "Dẫn Lôi"),
        TermEntry("Fusion", "Nhiệt Dung"),
        TermEntry("Glacio", "Ngưng Dạ"),

        // Collectibles, Currency & Exploration
        TermEntry("Sonance Caskets", "các Hộp Thanh Hưởng"),
        TermEntry("Sonance Casket", "Hộp Thanh Hưởng"),
        TermEntry("Astrites", "Tinh Thanh"),
        TermEntry("Astrite", "Tinh Thanh"),
        TermEntry("Lustrous Tide", "Sóng Xanh Gọi Hồn"),
        TermEntry("Radiant Tide", "Sóng Vàng Gọi Hồn"),
        TermEntry("Forging Tide", "Sóng Rèn Vũ Khí"),
        TermEntry("Shell Credits", "Bối Tệ"),
        TermEntry("Shell Credit", "Bối Tệ"),
        TermEntry("Convene", "Triệu Hồi"),
        TermEntry("Resonance Beacon", "Cột Tín Hiệu Cộng Hưởng"),
        TermEntry("Resonance Nexus", "Trạm Trung Tâm Cộng Hưởng"),
        TermEntry("Tower of Adversity", "Tháp Nghịch Cảnh"),
        TermEntry("Depths of Illusive Realm", "Thâm Uyên Mộng Cảnh"),
        TermEntry("Tactical Hologram", "Ảo Ảnh Chiến Thuật"),

        // Sentinels, Bosses & Major Characters
        TermEntry("Jué", "Giác"),
        TermEntry("Imperator", "Imperator"),
        TermEntry("Ovathrax", "Vô Tướng Minh Thức"),
        TermEntry("Leviathan", "Leviathan"),
        TermEntry("Crownless", "Vô Quan Giả"),
        TermEntry("Dreamless", "Vô Vọng Giả"),
        TermEntry("Shorekeeper", "Người Gác Bờ"),
        TermEntry("Jinhsi", "Jinhsi"),
        TermEntry("Changli", "Trường Ly"),
        TermEntry("Jiyan", "Kỵ Viêm"),
        TermEntry("Yinlin", "Ngâm Lâm"),
        TermEntry("Yangyang", "Dương Dương"),
        TermEntry("Chixia", "Xích Hà"),
        TermEntry("Baizhi", "Bạch Chỉ"),
        TermEntry("Sanhua", "Tán Hoa"),
        TermEntry("Jianxin", "Giám Tâm"),
        TermEntry("Lingyang", "Lăng Dương"),
        TermEntry("Taoqi", "Đào Kỳ"),
        TermEntry("Danjin", "Đan Cẩn"),
        TermEntry("Yuanwu", "Uyên Vũ"),
        TermEntry("Xiangli Yao", "Tương Lý Yếu"),
        TermEntry("Zhezhi", "Chiết Chi"),
        TermEntry("Youhu", "Dứu Hô"),
        TermEntry("Camellya", "Camellya"),
        TermEntry("Carlotta", "Carlotta"),
        TermEntry("Roccia", "Roccia"),
        TermEntry("Phoebe", "Phoebe"),
        TermEntry("Brant", "Brant"),
        TermEntry("Cantarella", "Cantarella"),
        TermEntry("Zani", "Zani"),
        TermEntry("Cartethyia", "Cartethyia"),
        TermEntry("Ciaccona", "Ciaccona"),
        TermEntry("Scar", "Scar"),
        TermEntry("Phrolova", "Phrolova"),
        TermEntry("Encore", "Encore"),
        TermEntry("Verina", "Verina"),
        TermEntry("Calcharo", "Calcharo"),
        TermEntry("Mortefi", "Mortefi"),
        TermEntry("Aalto", "Aalto"),
        TermEntry("Lumi", "Lumi"),
        TermEntry("Abby", "Abby")
    ]

    private struct CompiledRule: @unchecked Sendable {
        let english: String
        let vietnamese: String
        let regex: NSRegularExpression
    }

    /// Pre-compiled word-boundary regexes sorted longest-first to avoid partial sub-term collisions.
    private static let compiledRules: [CompiledRule] = {
        let sorted = entries.sorted { $0.english.count > $1.english.count }
        return sorted.compactMap { entry in
            let escaped = NSRegularExpression.escapedPattern(for: entry.english)
            let pattern = "(?<![\\p{L}\\p{N}_])" + escaped + "(?![\\p{L}\\p{N}_])"
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                return nil
            }
            return CompiledRule(english: entry.english, vietnamese: entry.vietnamese, regex: regex)
        }
    }()

    /// Post-translation literal correction pairs when Apple Translation translates a residual term directly.
    private static let literalVietnameseFixes: [(pattern: String, replacement: String)] = [
        ("(?i)bất hòa tacet", "Tàn Tượng"),
        ("(?i)lĩnh vực tacet", "Vùng Tàn Tượng"),
        ("(?i)người cộng hưởng", "Cộng Hưởng Giả"),
        ("(?i)bộ cộng hưởng", "Cộng Hưởng Giả"),
        ("(?i)lời than thở", "Bi Minh"),
        ("(?i)bờ biển đen", "Bờ Biển Đen"),
        ("(?i)hiện tượng sóng mòn", "Hiện Tượng Sóng Mòn"),
        ("(?i)giải phóng cộng hưởng", "Giải Phóng Cộng Hưởng"),
        ("(?i)kỹ năng cộng hưởng", "Kỹ Năng Cộng Hưởng"),
        ("(?i)năng lượng hiệp tấu", "Năng Lượng Hiệp Tấu")
    ]

    /// Masks recognized WuWa English terms using numbered placeholder tokens (e.g., WWT001)
    /// so offline Apple Translation preserves them intact without literal mistranslation.
    public static func prepareForTranslation(_ sourceText: String) -> GlossaryPreparationResult {
        var workingText = sourceText
        var tokenMap: [String: String] = [:]
        var matchedTerms: [String] = []
        var tokenIndex = 1

        for rule in compiledRules {
            let nsRange = NSRange(workingText.startIndex..<workingText.endIndex, in: workingText)
            let matches = rule.regex.matches(in: workingText, options: [], range: nsRange)
            guard !matches.isEmpty else { continue }

            let token = String(format: "WWT%03d", tokenIndex)
            tokenIndex += 1
            tokenMap[token] = rule.vietnamese
            matchedTerms.append(rule.english)

            // Replace matches from right to left to preserve string indices.
            for match in matches.reversed() {
                guard let swiftRange = Range(match.range, in: workingText) else { continue }
                workingText.replaceSubrange(swiftRange, with: token)
            }
        }

        return GlossaryPreparationResult(
            maskedText: workingText,
            tokenMap: tokenMap,
            matchedTerms: matchedTerms
        )
    }

    /// Restores masked placeholder tokens into canonical Vietnamese WuWa terminology and polishes punctuation.
    public static func applyPostProcessing(
        _ translatedText: String,
        prepared: GlossaryPreparationResult? = nil
    ) -> String {
        var output = translatedText

        if let prepared, !prepared.tokenMap.isEmpty {
            let sortedTokens = prepared.tokenMap.keys.sorted { $0.count > $1.count }
            for token in sortedTokens {
                guard let vietnamese = prepared.tokenMap[token] else { continue }
                // Tolerate case changes or accidental whitespace inserted between "WWT" and digits.
                let suffix = token.dropFirst(3)
                let flexiblePattern = "(?i)WWT\\s*" + NSRegularExpression.escapedPattern(for: String(suffix))
                if let regex = try? NSRegularExpression(pattern: flexiblePattern) {
                    let fullRange = NSRange(output.startIndex..<output.endIndex, in: output)
                    output = regex.stringByReplacingMatches(
                        in: output,
                        options: [],
                        range: fullRange,
                        withTemplate: NSRegularExpression.escapedTemplate(for: vietnamese)
                    )
                }
            }
        }

        for fix in literalVietnameseFixes {
            if let regex = try? NSRegularExpression(pattern: fix.pattern) {
                let fullRange = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(
                    in: output,
                    options: [],
                    range: fullRange,
                    withTemplate: NSRegularExpression.escapedTemplate(for: fix.replacement)
                )
            }
        }

        return polishVietnamesePunctuation(output)
    }

    /// Translates a standalone speaker name directly when it exists in the WuWa glossary.
    public static func localizeSpeakerName(_ speaker: String?) -> String? {
        guard let speaker else { return nil }
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for entry in entries where entry.english.caseInsensitiveCompare(trimmed) == .orderedSame {
            return entry.vietnamese
        }
        return trimmed
    }

    private static func polishVietnamesePunctuation(_ text: String) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsed
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " !", with: "!")
            .replacingOccurrences(of: " ?", with: "?")
            .replacingOccurrences(of: " :", with: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
