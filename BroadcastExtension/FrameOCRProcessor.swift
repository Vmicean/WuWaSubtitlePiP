import CoreMedia
import CoreVideo
import Darwin
import Foundation
import ImageIO
import QuartzCore
import ReplayKit
import Vision
import os

struct FrameOCRResult: Sendable {
    let payload: CapturedDialoguePayload?
    let durationMs: Int
    let skippedAsDuplicate: Bool
}

/// Memory-disciplined English Vision OCR engine designed for ReplayKit's strict 50 MB Jetsam ceiling.
/// Processes CVPixelBuffer directly inside an autoreleasepool without copying full-resolution images.
final class FrameOCRProcessor: @unchecked Sendable {
    private struct DeduplicationState {
        var lastSpeaker: String?
        var lastDialogueText: String = ""
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: DeduplicationState())
    private let minimumConfidenceThreshold: Float = 0.25

    func resetHistory() {
        stateLock.withLock { state in
            state.lastSpeaker = nil
            state.lastDialogueText = ""
        }
    }

    /// Executes English-only Vision OCR on the calibrated ROI directly from the ReplayKit video buffer.
    func processVideoSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        roi: SubtitleROI,
        accurateMode: Bool
    ) -> FrameOCRResult {
        let startTimestamp = CACurrentMediaTime()

        return autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return FrameOCRResult(payload: nil, durationMs: 0, skippedAsDuplicate: false)
            }

            let orientation = Self.resolveOrientation(from: sampleBuffer)

            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.025
            request.recognitionLevel = accurateMode ? .accurate : .fast
            request.regionOfInterest = roi.visionRect

            // Feed CVPixelBuffer directly into Vision with zero UIImage / CGImage allocation.
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )

            do {
                try handler.perform([request])
            } catch {
                let elapsedMs = max(1, Int((CACurrentMediaTime() - startTimestamp) * 1000.0))
                return FrameOCRResult(payload: nil, durationMs: elapsedMs, skippedAsDuplicate: false)
            }

            let elapsedMs = max(1, Int((CACurrentMediaTime() - startTimestamp) * 1000.0))
            guard let observations = request.results, !observations.isEmpty else {
                return FrameOCRResult(payload: nil, durationMs: elapsedMs, skippedAsDuplicate: false)
            }

            // Sort observations top-to-bottom (higher midY first in Vision's bottom-left coordinate space)
            // with left-to-right tie breaking for segments on the same subtitle line.
            let orderedObservations = observations.sorted { lhs, rhs in
                let verticalDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                if verticalDelta < 0.015 {
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }

            var recognizedLines: [String] = []
            recognizedLines.reserveCapacity(orderedObservations.count)
            var confidenceAccumulator: Float = 0
            var confidenceCount: Int = 0

            for observation in orderedObservations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                guard candidate.confidence >= minimumConfidenceThreshold else { continue }

                let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                recognizedLines.append(trimmed)
                confidenceAccumulator += candidate.confidence
                confidenceCount += 1
            }

            guard !recognizedLines.isEmpty,
                  let cleaned = DialogueTextCleaner.clean(lines: recognizedLines) else {
                return FrameOCRResult(payload: nil, durationMs: elapsedMs, skippedAsDuplicate: false)
            }

            let shouldSkip = stateLock.withLock { state -> Bool in
                let speakerChanged = cleaned.speaker != nil && cleaned.speaker != state.lastSpeaker
                if !speakerChanged && DialogueTextCleaner.shouldSuppressDuplicate(
                    previous: state.lastDialogueText,
                    current: cleaned.dialogueText
                ) {
                    return true
                }

                state.lastSpeaker = cleaned.speaker
                state.lastDialogueText = cleaned.dialogueText
                return false
            }

            if shouldSkip {
                return FrameOCRResult(payload: nil, durationMs: elapsedMs, skippedAsDuplicate: true)
            }

            let meanConfidence = confidenceCount > 0
                ? confidenceAccumulator / Float(confidenceCount)
                : 0.0

            let payload = CapturedDialoguePayload(
                timestamp: Date(),
                speaker: cleaned.speaker,
                rawText: cleaned.dialogueText,
                confidence: meanConfidence
            )
            return FrameOCRResult(payload: payload, durationMs: elapsedMs, skippedAsDuplicate: false)
        }
    }

    /// Reads ReplayKit's RPVideoSampleOrientationKey attachment and maps it to CGImagePropertyOrientation
    /// so landscape Wuthering Waves frames are always oriented upright before Vision applies regionOfInterest.
    static func resolveOrientation(from sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let attachment = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        ) as? NSNumber else {
            return .up
        }

        let rawOrientation = attachment.uint32Value
        switch rawOrientation {
        case CGImagePropertyOrientation.up.rawValue:
            return .up
        case CGImagePropertyOrientation.upMirrored.rawValue:
            return .upMirrored
        case CGImagePropertyOrientation.down.rawValue:
            return .down
        case CGImagePropertyOrientation.downMirrored.rawValue:
            return .downMirrored
        case CGImagePropertyOrientation.leftMirrored.rawValue:
            return .leftMirrored
        case CGImagePropertyOrientation.right.rawValue:
            return .right
        case CGImagePropertyOrientation.rightMirrored.rawValue:
            return .rightMirrored
        case CGImagePropertyOrientation.left.rawValue:
            return .left
        default:
            return .up
        }
    }

    /// Reports the extension's actual resident physical memory in megabytes using public Mach task_info.
    static func currentResidentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    intPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return 0.0
        }
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }
}
