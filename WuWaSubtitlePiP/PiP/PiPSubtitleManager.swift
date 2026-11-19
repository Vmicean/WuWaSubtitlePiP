import AVFoundation
import AVKit
import CoreMedia
import Foundation
import Observation
import os
import SwiftUI
import UIKit

/// Public-API Picture-in-Picture controller driving an AVSampleBufferDisplayLayer.
/// Configures AVAudioSession with .mixWithOthers so Wuthering Waves audio is never interrupted,
/// enables automatic PiP transition when switching to the game, and uses a lightweight 1-second
/// zero-redraw keepalive heartbeat.
@MainActor
@Observable
public final class PiPSubtitleManager: NSObject {
    public let displayLayer = AVSampleBufferDisplayLayer()

    public private(set) var isPiPActive: Bool = false
    public private(set) var isPiPPossible: Bool = false
    public private(set) var isPiPSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()
    public private(set) var isStartingPiP: Bool = false
    public private(set) var lastErrorMessage: String?
    public private(set) var renderedFrameCount: Int = 0

    private let renderer = SubtitleFrameRenderer()
    private var pipController: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var heartbeatTask: Task<Void, Never>?

    private var lastRenderedPixelBuffer: CVPixelBuffer?
    private var currentSpeaker: String?
    private var currentVietnamese: String = "Sẵn sàng dịch phụ đề Wuthering Waves"
    private var currentEnglish: String?
    private var currentAppearance: PiPAppearanceSettings = .default
    private var currentLiveScanning: Bool = false

    private let playbackPausedLock = OSAllocatedUnfairLock<Bool>(initialState: false)

    public override init() {
        super.init()
        configureDisplayLayer()
        configureAudioSession()
        setupPictureInPictureController()
        renderCurrentFrameAndEnqueue()
        startKeepaliveHeartbeat()
    }

    public func stopKeepalive() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// Ensures AVAudioSession stays mixed with Wuthering Waves audio without ducking or pausing it.
    public func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            lastErrorMessage = "Không thể cấu hình âm thanh nền: \(error.localizedDescription)"
        }
    }

    /// Re-renders the 960x260 subtitle frame ONLY when dialogue, scan status, or appearance changes.
    public func updateSubtitle(
        speaker: String?,
        vietnameseText: String,
        originalEnglish: String?,
        appearance: PiPAppearanceSettings,
        isLiveScanning: Bool
    ) {
        currentSpeaker = speaker
        currentVietnamese = vietnameseText
        currentEnglish = originalEnglish
        currentAppearance = appearance
        currentLiveScanning = isLiveScanning

        renderCurrentFrameAndEnqueue()
    }

    public func updateAppearance(_ appearance: PiPAppearanceSettings, isLiveScanning: Bool) {
        currentAppearance = appearance
        currentLiveScanning = isLiveScanning
        renderCurrentFrameAndEnqueue()
    }

    public func startPictureInPicture() {
        guard isPiPSupported else {
            lastErrorMessage = "Thiết bị này không hỗ trợ Hình trong hình (PiP)."
            return
        }

        configureAudioSession()
        if pipController == nil {
            setupPictureInPictureController()
        }

        renderCurrentFrameAndEnqueue()
        startKeepaliveHeartbeat()

        guard let pipController else {
            lastErrorMessage = "Bộ điều khiển PiP chưa sẵn sàng."
            return
        }

        guard !pipController.isPictureInPictureActive else {
            isPiPActive = true
            return
        }

        isStartingPiP = true
        lastErrorMessage = nil
        pipController.startPictureInPicture()
    }

    public func stopPictureInPicture() {
        guard let pipController, pipController.isPictureInPictureActive else {
            isPiPActive = false
            isStartingPiP = false
            return
        }
        pipController.stopPictureInPicture()
    }

    public func togglePictureInPicture() {
        if isPiPActive {
            stopPictureInPicture()
        } else {
            startPictureInPicture()
        }
    }

    // MARK: - Private Setup & Rendering

    private func configureDisplayLayer() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor(red: 0.035, green: 0.043, blue: 0.067, alpha: 1.0).cgColor

        var timebase: CMTimebase?
        if CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        ) == noErr, let timebase {
            CMTimebaseSetTime(timebase, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(timebase, rate: 1.0)
            displayLayer.controlTimebase = timebase
        }
    }

    private func setupPictureInPictureController() {
        guard isPiPSupported else { return }

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )

        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = true

        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] ctrl, _ in
            let possible = ctrl.isPictureInPicturePossible
            Task { @MainActor [weak self] in
                self?.isPiPPossible = possible
            }
        }

        self.pipController = controller
    }

    private func renderCurrentFrameAndEnqueue() {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        guard let frame = renderer.renderFrame(
            speaker: currentSpeaker,
            vietnameseText: currentVietnamese,
            originalEnglish: currentEnglish,
            appearance: currentAppearance,
            isLiveScanning: currentLiveScanning,
            presentationTime: now
        ) else {
            return
        }

        lastRenderedPixelBuffer = frame.pixelBuffer
        enqueueSampleBuffer(frame.sampleBuffer)
        renderedFrameCount += 1
    }

    private func pushKeepaliveFrameIfAvailable() {
        guard let pixelBuffer = lastRenderedPixelBuffer else {
            renderCurrentFrameAndEnqueue()
            return
        }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        if let sampleBuffer = renderer.wrapPixelBuffer(pixelBuffer, presentationTime: now) {
            enqueueSampleBuffer(sampleBuffer)
        }
    }

    private func enqueueSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let bufferRenderer = displayLayer.sampleBufferRenderer
        if bufferRenderer.status == .failed {
            bufferRenderer.flush()
        }
        if bufferRenderer.isReadyForMoreMediaData {
            bufferRenderer.enqueue(sampleBuffer)
        }
    }

    private func startKeepaliveHeartbeat() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.pushKeepaliveFrameIfAvailable()
            }
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPSubtitleManager: AVPictureInPictureControllerDelegate {
    nonisolated public func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            self?.isStartingPiP = true
            self?.lastErrorMessage = nil
        }
    }

    nonisolated public func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            self?.isStartingPiP = false
            self?.isPiPActive = true
            self?.pushKeepaliveFrameIfAvailable()
        }
    }

    nonisolated public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.isStartingPiP = false
            self?.isPiPActive = false
            self?.lastErrorMessage = "Không thể mở cửa sổ PiP: \(message)"
        }
    }

    nonisolated public func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            self?.isStartingPiP = false
            self?.isPiPActive = false
        }
    }

    nonisolated public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension PiPSubtitleManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        playbackPausedLock.withLock { $0 = !playing }
    }

    nonisolated public func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated public func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        playbackPausedLock.withLock { $0 }
    }

    nonisolated public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        Task { @MainActor [weak self] in
            self?.pushKeepaliveFrameIfAvailable()
        }
    }

    nonisolated public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

// MARK: - SwiftUI Inline Host View

public final class PiPDisplayHostUIView: UIView {
    private let sampleBufferLayer: AVSampleBufferDisplayLayer

    public init(sampleBufferLayer: AVSampleBufferDisplayLayer) {
        self.sampleBufferLayer = sampleBufferLayer
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.035, green: 0.043, blue: 0.067, alpha: 1.0)
        layer.addSublayer(sampleBufferLayer)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sampleBufferLayer.frame = bounds
        CATransaction.commit()
    }
}

public struct PiPInlineHostRepresentable: UIViewRepresentable {
    public let displayLayer: AVSampleBufferDisplayLayer

    public init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
    }

    public func makeUIView(context: Context) -> PiPDisplayHostUIView {
        PiPDisplayHostUIView(sampleBufferLayer: displayLayer)
    }

    public func updateUIView(_ uiView: PiPDisplayHostUIView, context: Context) {
        uiView.setNeedsLayout()
    }
}
