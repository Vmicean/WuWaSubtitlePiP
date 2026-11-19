import CoreMedia
import CoreVideo
import XCTest
@testable import WuWaSubtitlePiP

final class WuWaSubtitlePiPTests: XCTestCase {

    // MARK: - DialogueTextCleaner Tests

    func testDialogueTextCleanerFiltersWuWaHUDNoiseAndSeparatesSpeaker() {
        let rawLines = [
            "Skip",
            "Auto",
            "UID: 901234567",
            "60 FPS",
            "28 ms",
            ">>>",
            "Yangyang",
            "Rover, a Tacet Field just erupted near Jinzhou!"
        ]

        let cleaned = DialogueTextCleaner.clean(lines: rawLines)
        XCTAssertNotNil(cleaned)
        XCTAssertEqual(cleaned?.speaker, "Yangyang")
        XCTAssertEqual(
            cleaned?.dialogueText,
            "Rover, a Tacet Field just erupted near Jinzhou!"
        )
    }

    func testDialogueTextCleanerExtractsInlineSpeaker() {
        let cleaned = DialogueTextCleaner.clean(lines: [
            "Jinhsi: The Sentinel Jué watches over Huanglong."
        ])
        XCTAssertEqual(cleaned?.speaker, "Jinhsi")
        XCTAssertEqual(
            cleaned?.dialogueText,
            "The Sentinel Jué watches over Huanglong."
        )
    }

    func testDialogueTextCleanerReturnsNilForPureNoise() {
        let cleaned = DialogueTextCleaner.clean(lines: [
            "Skip",
            "Auto",
            "UID 900112233",
            "120 FPS",
            "..."
        ])
        XCTAssertNil(cleaned)
    }

    func testDialogueTextCleanerLevenshteinSimilarityAndDedupe() {
        let exact = DialogueTextCleaner.similarity(
            "The Lament reshaped Solaris-3.",
            "the lament reshaped solaris-3."
        )
        XCTAssertEqual(exact, 1.0, accuracy: 0.0001)

        let minorOCRJitter = DialogueTextCleaner.similarity(
            "Rover, a Tacet Field just erupted near Jinzhou!",
            "Rover, a Tacet Field just erupted near Jinzhou."
        )
        XCTAssertGreaterThanOrEqual(minorOCRJitter, DialogueTextCleaner.duplicateSimilarityThreshold)
        XCTAssertTrue(
            DialogueTextCleaner.shouldSuppressDuplicate(
                previous: "Rover, a Tacet Field just erupted near Jinzhou!",
                current: "Rover, a Tacet Field just erupted near Jinzhou."
            )
        )

        // Typewriter reveal growing by >= 6 characters must pass through so subtitles finish smoothly.
        XCTAssertFalse(
            DialogueTextCleaner.shouldSuppressDuplicate(
                previous: "Rover, a Tacet Field",
                current: "Rover, a Tacet Field just erupted near Jinzhou!"
            )
        )

        // Brand-new dialogue must never be suppressed.
        XCTAssertFalse(
            DialogueTextCleaner.shouldSuppressDuplicate(
                previous: "Rover, a Tacet Field just erupted near Jinzhou!",
                current: "The Sentinel Jué foresaw the Waveworn Phenomenon."
            )
        )
    }

    // MARK: - WuWaGlossary Tests

    func testWuWaGlossaryWordBoundarySafety() {
        // Words that merely contain glossary substrings ("clover" contains "rover",
        // "comfortable" contains "forte", "technology" contains "echo") must remain untouched.
        let safeSentence = "A comfortable clover patch displays new technology."
        let prepared = WuWaGlossary.prepareForTranslation(safeSentence)

        XCTAssertFalse(prepared.hasMatches)
        XCTAssertEqual(prepared.maskedText, safeSentence)
    }

    func testWuWaGlossaryMasksAndRestoresCanonicalVietnameseTerms() {
        let source = "Rover and the Resonator defeated a Tacet Discord in Jinzhou using Resonance Liberation."
        let prepared = WuWaGlossary.prepareForTranslation(source)

        XCTAssertTrue(prepared.hasMatches)
        XCTAssertGreaterThanOrEqual(prepared.tokenMap.count, 5)
        XCTAssertFalse(prepared.maskedText.contains("Tacet Discord"))
        XCTAssertFalse(prepared.maskedText.contains("Resonance Liberation"))

        let restored = WuWaGlossary.applyPostProcessing(prepared.maskedText, prepared: prepared)
        XCTAssertTrue(restored.contains("Lữ Khách"))
        XCTAssertTrue(restored.contains("Cộng Hưởng Giả"))
        XCTAssertTrue(restored.contains("Tàn Tượng"))
        XCTAssertTrue(restored.contains("Cẩm Châu"))
        XCTAssertTrue(restored.contains("Giải Phóng Cộng Hưởng"))
    }

    // MARK: - SubtitleROI Tests

    func testSubtitleROIVisionCoordinateConversion() {
        let defaultROI = SubtitleROI.wuWaDialogueDefault
        let visionRect = defaultROI.visionRect

        // Top-left y = 0.68, height = 0.28 => Vision bottom-left y = 1.0 - 0.68 - 0.28 = 0.04
        XCTAssertEqual(visionRect.origin.x, 0.08, accuracy: 0.0001)
        XCTAssertEqual(visionRect.origin.y, 0.04, accuracy: 0.0001)
        XCTAssertEqual(visionRect.size.width, 0.84, accuracy: 0.0001)
        XCTAssertEqual(visionRect.size.height, 0.28, accuracy: 0.0001)

        let choicesVision = SubtitleROI.wuWaDialogueWithChoices.visionRect
        // y = 0.44, height = 0.52 => Vision y = 1.0 - 0.44 - 0.52 = 0.04
        XCTAssertEqual(choicesVision.origin.y, 0.04, accuracy: 0.0001)
        XCTAssertEqual(choicesVision.size.height, 0.52, accuracy: 0.0001)
    }

    func testSubtitleROIClampingBoundsInvalidValues() {
        let invalid = SubtitleROI(x: -0.5, y: 0.98, width: 0.01, height: 0.50).clamped()
        XCTAssertGreaterThanOrEqual(invalid.x, 0.0)
        XCTAssertGreaterThanOrEqual(invalid.y, 0.0)
        XCTAssertGreaterThanOrEqual(invalid.width, 0.08)
        XCTAssertGreaterThanOrEqual(invalid.height, 0.08)
        XCTAssertLessThanOrEqual(invalid.x + invalid.width, 1.0001)
        XCTAssertLessThanOrEqual(invalid.y + invalid.height, 1.0001)
    }

    // MARK: - AppGroupResolver Tests

    func testAppGroupResolverParsesMobileProvisionPlistChunk() {
        let mockProvision = """
        BINARY_HEADER_BYTES<?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Entitlements</key>
            <dict>
                <key>com.apple.security.application-groups</key>
                <array>
                    <string>group.com.wuwatranslator.shared.ABC123XYZ</string>
                </array>
            </dict>
        </dict>
        </plist>BINARY_TRAILER_BYTES
        """
        let groups = AppGroupResolver.extractAppGroups(fromMobileProvisionData: Data(mockProvision.utf8))
        XCTAssertEqual(groups, ["group.com.wuwatranslator.shared.ABC123XYZ"])
    }

    // MARK: - SubtitleFrameRenderer Tests

    func testSubtitleFrameRendererProducesValid960x260BGRAMediaSampleBuffer() {
        let renderer = SubtitleFrameRenderer()
        let appearance = PiPAppearanceSettings(
            fontSize: 24,
            backgroundOpacity: 0.90,
            showOriginalEnglish: true,
            enableWuWaGlossary: true,
            ocrAccurateMode: false
        )

        let sampleBuffer = renderer.renderSampleBuffer(
            speaker: "Dương Dương",
            vietnameseText: "Lữ Khách ơi, một Vùng Tàn Tượng vừa bùng phát gần Cẩm Châu! Hãy cẩn thận kẻo bị Quá Tải.",
            originalEnglish: "Rover, a Tacet Field just erupted near Jinzhou! Watch out for Overclocking.",
            appearance: appearance,
            isLiveScanning: true
        )

        XCTAssertNotNil(sampleBuffer)
        guard let sampleBuffer else { return }

        XCTAssertTrue(CMSampleBufferIsValid(sampleBuffer))
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            XCTFail("Expected CVPixelBuffer attached to rendered CMSampleBuffer")
            return
        }

        XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), SubtitleFrameRenderer.canvasWidth)
        XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), SubtitleFrameRenderer.canvasHeight)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixelBuffer), kCVPixelFormatType_32BGRA)
    }
}
