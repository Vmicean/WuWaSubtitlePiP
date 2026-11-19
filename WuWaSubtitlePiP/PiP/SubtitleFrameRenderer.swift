import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import os
import UIKit

public struct RenderedSubtitleFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let sampleBuffer: CMSampleBuffer
}

/// Renders crisp, anti-aliased Vietnamese subtitles onto a 960x260 BGRA CVPixelBuffer
/// backed by IOSurface and wraps it into a CMSampleBuffer for AVSampleBufferDisplayLayer PiP.
public final class SubtitleFrameRenderer: @unchecked Sendable {
    public static let canvasWidth: Int = 960
    public static let canvasHeight: Int = 260

    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let poolLock = OSAllocatedUnfairLock<CVPixelBufferPool?>(initialState: nil)

    public init() {}

    /// Renders Vietnamese subtitle text, optional speaker badge, and optional English line
    /// into a ready-to-enqueue CMSampleBuffer.
    public func renderSampleBuffer(
        speaker: String?,
        vietnameseText: String,
        originalEnglish: String? = nil,
        appearance: PiPAppearanceSettings = .default,
        isLiveScanning: Bool = false,
        presentationTime: CMTime = CMClockGetTime(CMClockGetHostTimeClock())
    ) -> CMSampleBuffer? {
        renderFrame(
            speaker: speaker,
            vietnameseText: vietnameseText,
            originalEnglish: originalEnglish,
            appearance: appearance,
            isLiveScanning: isLiveScanning,
            presentationTime: presentationTime
        )?.sampleBuffer
    }

    /// Returns both CVPixelBuffer and CMSampleBuffer so PiPSubtitleManager can reuse the pixel
    /// buffer during lightweight 1-second keepalive heartbeats with near-zero GPU/CPU work.
    public func renderFrame(
        speaker: String?,
        vietnameseText: String,
        originalEnglish: String? = nil,
        appearance: PiPAppearanceSettings = .default,
        isLiveScanning: Bool = false,
        presentationTime: CMTime = CMClockGetTime(CMClockGetHostTimeClock())
    ) -> RenderedSubtitleFrame? {
        guard let pixelBuffer = makePixelBuffer() else {
            return nil
        }

        let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard lockResult == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: baseAddress,
            width: Self.canvasWidth,
            height: Self.canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsFontSmoothing(true)
        context.interpolationQuality = .high

        // Flip into standard top-left UIKit coordinate space for NSAttributedString drawing.
        context.translateBy(x: 0, y: CGFloat(Self.canvasHeight))
        context.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(context)
        drawSubtitleCard(
            in: context,
            speaker: speaker,
            vietnameseText: vietnameseText,
            originalEnglish: originalEnglish,
            appearance: appearance,
            isLiveScanning: isLiveScanning
        )
        UIGraphicsPopContext()

        guard let sampleBuffer = wrapPixelBuffer(
            pixelBuffer,
            presentationTime: presentationTime
        ) else {
            return nil
        }

        return RenderedSubtitleFrame(pixelBuffer: pixelBuffer, sampleBuffer: sampleBuffer)
    }

    /// Re-wraps an already rendered CVPixelBuffer with an updated presentation timestamp
    /// for zero-redraw 1-second keepalive heartbeats.
    public func wrapPixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            return nil
        }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sampleBuffer else {
            return nil
        }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        return sampleBuffer
    }

    // MARK: - CoreGraphics / UIKit Card Drawing

    private func drawSubtitleCard(
        in context: CGContext,
        speaker: String?,
        vietnameseText: String,
        originalEnglish: String?,
        appearance: PiPAppearanceSettings,
        isLiveScanning: Bool
    ) {
        let canvasRect = CGRect(x: 0, y: 0, width: Self.canvasWidth, height: Self.canvasHeight)

        // Solid dark outer clear so video edges stay clean inside PiP rounded corners.
        UIColor(red: 0.035, green: 0.043, blue: 0.067, alpha: 1.0).setFill()
        context.fill(canvasRect)

        // Deep obsidian card with subtle gold #E6C97A WuWa border.
        let cardRect = canvasRect.insetBy(dx: 10, dy: 10)
        let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 20)
        let opacity = CGFloat(min(1.0, max(0.55, appearance.backgroundOpacity)))

        UIColor(red: 0.055, green: 0.071, blue: 0.110, alpha: opacity).setFill()
        cardPath.fill()

        // Subtle warm golden inner top accent sheen.
        context.saveGState()
        cardPath.addClip()
        let sheenColors = [
            UIColor(red: 0.902, green: 0.788, blue: 0.478, alpha: 0.14).cgColor,
            UIColor(red: 0.902, green: 0.788, blue: 0.478, alpha: 0.0).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: sheenColors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: cardRect.midX, y: cardRect.minY),
                end: CGPoint(x: cardRect.midX, y: cardRect.minY + 62),
                options: []
            )
        }
        context.restoreGState()

        // Crisp WuWa gold #E6C97A border.
        let goldAccent = UIColor(red: 0.902, green: 0.788, blue: 0.478, alpha: 0.68)
        goldAccent.setStroke()
        cardPath.lineWidth = 2.0
        cardPath.stroke()

        // Content layout geometry.
        let horizontalInset: CGFloat = 34
        let contentWidth = cardRect.width - (horizontalInset * 2)
        var currentTopY = cardRect.minY + 18

        // Top bar: Speaker badge on left + subtle live scan dot on right.
        let trimmedSpeaker = speaker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSpeaker.isEmpty {
            let badgeHeight: CGFloat = 34
            drawSpeakerBadge(
                trimmedSpeaker,
                origin: CGPoint(x: cardRect.minX + horizontalInset, y: currentTopY),
                maxWidth: contentWidth - 130,
                height: badgeHeight
            )
            drawLiveStatusIndicator(
                isLive: isLiveScanning,
                rightEdge: cardRect.maxX - horizontalInset,
                centerY: currentTopY + badgeHeight / 2
            )
            currentTopY += badgeHeight + 12
        } else {
            drawLiveStatusIndicator(
                isLive: isLiveScanning,
                rightEdge: cardRect.maxX - horizontalInset,
                centerY: currentTopY + 11
            )
            currentTopY += 24
        }

        // Reserve bottom space when optional English original subtitle is visible.
        let trimmedEnglish = originalEnglish?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shouldShowEnglish = appearance.showOriginalEnglish && !trimmedEnglish.isEmpty
        let englishAreaHeight: CGFloat = shouldShowEnglish ? 34 : 0
        let bottomPadding: CGFloat = 18
        let availableVietnameseHeight = max(
            64,
            cardRect.maxY - bottomPadding - englishAreaHeight - (shouldShowEnglish ? 8 : 0) - currentTopY
        )

        let displayVietnamese = vietnameseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Sẵn sàng dịch phụ đề Wuthering Waves"
            : vietnameseText.trimmingCharacters(in: .whitespacesAndNewlines)

        let vietnameseRect = CGRect(
            x: cardRect.minX + horizontalInset,
            y: currentTopY,
            width: contentWidth,
            height: availableVietnameseHeight
        )
        drawAutoFittingVietnameseText(
            displayVietnamese,
            in: vietnameseRect,
            preferredFontSize: CGFloat(appearance.fontSize) * 1.45
        )

        if shouldShowEnglish {
            let englishRect = CGRect(
                x: cardRect.minX + horizontalInset,
                y: cardRect.maxY - bottomPadding - englishAreaHeight,
                width: contentWidth,
                height: englishAreaHeight
            )
            drawOriginalEnglishLine(trimmedEnglish, in: englishRect)
        }
    }

    private func drawSpeakerBadge(
        _ speaker: String,
        origin: CGPoint,
        maxWidth: CGFloat,
        height: CGFloat
    ) {
        let font = UIFont.systemFont(ofSize: 21, weight: .bold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 0.965, green: 0.890, blue: 0.651, alpha: 1.0)
        ]

        let measuredSize = (speaker as NSString).size(withAttributes: textAttributes)
        let horizontalPad: CGFloat = 16
        let badgeWidth = min(maxWidth, ceil(measuredSize.width) + horizontalPad * 2)
        let badgeRect = CGRect(x: origin.x, y: origin.y, width: badgeWidth, height: height)
        let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 9)

        UIColor(red: 0.902, green: 0.788, blue: 0.478, alpha: 0.16).setFill()
        badgePath.fill()

        UIColor(red: 0.902, green: 0.788, blue: 0.478, alpha: 0.55).setStroke()
        badgePath.lineWidth = 1.25
        badgePath.stroke()

        let textRect = CGRect(
            x: badgeRect.minX + horizontalPad,
            y: badgeRect.minY + (height - measuredSize.height) / 2,
            width: badgeWidth - horizontalPad * 2,
            height: measuredSize.height
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        var drawAttrs = textAttributes
        drawAttrs[.paragraphStyle] = paragraph
        (speaker as NSString).draw(in: textRect, withAttributes: drawAttrs)
    }

    private func drawLiveStatusIndicator(isLive: Bool, rightEdge: CGFloat, centerY: CGFloat) {
        let labelText = isLive ? "ĐANG QUÉT" : "CHỜ GAME"
        let dotColor = isLive
            ? UIColor(red: 0.251, green: 0.831, blue: 0.541, alpha: 1.0)
            : UIColor(red: 0.902, green: 0.788, blue: 0.478, alpha: 0.85)

        let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 0.72, green: 0.77, blue: 0.85, alpha: 0.9)
        ]
        let labelSize = (labelText as NSString).size(withAttributes: attrs)
        let textOrigin = CGPoint(x: rightEdge - labelSize.width, y: centerY - labelSize.height / 2)
        (labelText as NSString).draw(at: textOrigin, withAttributes: attrs)

        let dotDiameter: CGFloat = 9
        let dotRect = CGRect(
            x: textOrigin.x - dotDiameter - 8,
            y: centerY - dotDiameter / 2,
            width: dotDiameter,
            height: dotDiameter
        )
        dotColor.setFill()
        UIBezierPath(ovalIn: dotRect).fill()
    }

    private func drawAutoFittingVietnameseText(
        _ text: String,
        in rect: CGRect,
        preferredFontSize: CGFloat
    ) {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.75)
        shadow.shadowOffset = CGSize(width: 0, height: 1.5)
        shadow.shadowBlurRadius = 3.0

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 4

        let maxFontSize = min(46, max(24, preferredFontSize))
        let minFontSize: CGFloat = 20

        var chosenFontSize = maxFontSize
        var measuredHeight: CGFloat = rect.height

        while chosenFontSize >= minFontSize {
            let font = UIFont.systemFont(ofSize: chosenFontSize, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraph
            ]
            let bounding = (text as NSString).boundingRect(
                with: CGSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )
            measuredHeight = ceil(bounding.height)
            if measuredHeight <= rect.height {
                break
            }
            chosenFontSize -= 2
        }

        let finalFont = UIFont.systemFont(ofSize: max(minFontSize, chosenFontSize), weight: .semibold)
        let finalParagraph = NSMutableParagraphStyle()
        finalParagraph.alignment = .left
        finalParagraph.lineBreakMode = .byTruncatingTail
        finalParagraph.lineSpacing = 4

        let finalAttrs: [NSAttributedString.Key: Any] = [
            .font: finalFont,
            .foregroundColor: UIColor(red: 0.975, green: 0.980, blue: 0.992, alpha: 1.0),
            .paragraphStyle: finalParagraph,
            .shadow: shadow
        ]

        let verticalOffset = max(0, (rect.height - min(rect.height, measuredHeight)) / 2)
        let drawRect = CGRect(
            x: rect.minX,
            y: rect.minY + verticalOffset,
            width: rect.width,
            height: rect.height - verticalOffset
        )

        (text as NSString).draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: finalAttrs,
            context: nil
        )
    }

    private func drawOriginalEnglishLine(_ text: String, in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 19, weight: .regular),
            .foregroundColor: UIColor(red: 0.620, green: 0.675, blue: 0.765, alpha: 0.92),
            .paragraphStyle: paragraph
        ]

        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attrs,
            context: nil
        )
    }

    // MARK: - Reusable IOSurface Pixel Buffer Pool

    private func makePixelBuffer() -> CVPixelBuffer? {
        if let pool = ensurePixelBufferPool() {
            var pooledBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pooledBuffer)
            if status == kCVReturnSuccess, let pooledBuffer {
                return pooledBuffer
            }
        }

        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Self.canvasWidth,
            Self.canvasHeight,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }

    private func ensurePixelBufferPool() -> CVPixelBufferPool? {
        poolLock.withLock { existing in
            if let existing {
                return existing
            }

            let poolAttributes: [String: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey as String: 2
            ]
            let bufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Self.canvasWidth,
                kCVPixelBufferHeightKey as String: Self.canvasHeight,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]

            var pool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                poolAttributes as CFDictionary,
                bufferAttributes as CFDictionary,
                &pool
            )
            guard status == kCVReturnSuccess, let pool else {
                return nil
            }
            existing = pool
            return pool
        }
    }
}
