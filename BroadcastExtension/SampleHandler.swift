import CoreMedia
import Foundation
import QuartzCore
import ReplayKit
import os

final class SampleHandler: RPBroadcastSampleHandler {
    private struct RuntimeConfig: Sendable {
        var roi: SubtitleROI = .wuWaDialogueDefault
        var ocrAccurateMode: Bool = false
    }

    private struct GateState: Sendable {
        var isBusy: Bool = false
        var lastAcceptedTimestamp: CFTimeInterval = 0
        var lastConfigRefreshTimestamp: CFTimeInterval = 0
        var lastStatusPublishTimestamp: CFTimeInterval = 0
        var framesProcessed: Int = 0
        var framesDropped: Int = 0
        var lastOCRDurationMs: Int = 0
    }

    private let throttleIntervalSeconds: CFTimeInterval = 0.35
    private let configRefreshIntervalSeconds: CFTimeInterval = 2.0
    private let statusHeartbeatIntervalSeconds: CFTimeInterval = 2.0

    private let ipcBridge: BroadcastIPCBridge
    private let ocrProcessor = FrameOCRProcessor()
    private let configLock = OSAllocatedUnfairLock(initialState: RuntimeConfig())
    private let gateLock = OSAllocatedUnfairLock(initialState: GateState())

    override init() {
        self.ipcBridge = BroadcastIPCBridge(role: .broadcastExtension)
        super.init()
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        ocrProcessor.resetHistory()
        gateLock.withLock { state in
            state = GateState()
        }

        refreshConfigFromIPC()

        ipcBridge.startListening { [weak self] event in
            guard let self else { return }
            switch event {
            case .roi(let updatedROI):
                self.configLock.withLock { $0.roi = updatedROI.clamped() }
            case .appearance(let updatedAppearance):
                self.configLock.withLock { $0.ocrAccurateMode = updatedAppearance.ocrAccurateMode }
            case .dialogue, .status:
                break
            }
        }

        publishStatus(
            state: .active,
            message: "Đang quét phụ đề Wuthering Waves"
        )
    }

    override func broadcastPaused() {
        publishStatus(
            state: .paused,
            message: "Phiên quét màn hình đã tạm dừng"
        )
    }

    override func broadcastResumed() {
        refreshConfigFromIPC()
        publishStatus(
            state: .active,
            message: "Đã tiếp tục quét phụ đề"
        )
    }

    override func broadcastFinished() {
        publishStatus(
            state: .finished,
            message: "Đã dừng phiên phát màn hình"
        )
        ipcBridge.stopListening()
        ocrProcessor.resetHistory()
        gateLock.withLock { state in
            state.isBusy = false
        }
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        // Ignore app audio and microphone buffers immediately with zero heap allocation.
        switch sampleBufferType {
        case .video:
            break
        case .audioApp, .audioMic:
            return
        @unknown default:
            return
        }

        let now = CACurrentMediaTime()

        // Atomic drop-if-busy and 0.35s (~2.8 FPS) throttle gate.
        // Dropped frames return immediately without retaining CMSampleBuffer.
        let gateDecision = gateLock.withLock { state -> (accepted: Bool, shouldRefreshConfig: Bool) in
            if state.isBusy {
                state.framesDropped += 1
                return (false, false)
            }

            if state.lastAcceptedTimestamp > 0 &&
                (now - state.lastAcceptedTimestamp) < throttleIntervalSeconds {
                state.framesDropped += 1
                return (false, false)
            }

            state.isBusy = true
            state.lastAcceptedTimestamp = now

            let needsRefresh = state.lastConfigRefreshTimestamp == 0 ||
                (now - state.lastConfigRefreshTimestamp) >= configRefreshIntervalSeconds
            if needsRefresh {
                state.lastConfigRefreshTimestamp = now
            }

            return (true, needsRefresh)
        }

        guard gateDecision.accepted else {
            return
        }

        var measuredDurationMs = 0
        defer {
            let shouldPublishHeartbeat = gateLock.withLock { state -> Bool in
                state.isBusy = false
                state.framesProcessed += 1
                state.lastOCRDurationMs = measuredDurationMs

                if state.lastStatusPublishTimestamp == 0 ||
                    (now - state.lastStatusPublishTimestamp) >= statusHeartbeatIntervalSeconds {
                    state.lastStatusPublishTimestamp = now
                    return true
                }
                return false
            }

            if shouldPublishHeartbeat {
                publishStatus(state: .active, message: nil)
            }
        }

        if gateDecision.shouldRefreshConfig {
            refreshConfigFromIPC()
        }

        let currentConfig = configLock.withLock { $0 }

        // Execute Vision OCR synchronously within ReplayKit's callback inside an autoreleasepool
        // so CMSampleBuffer is released promptly and peak RAM stays strictly below 25 MB.
        let ocrResult = ocrProcessor.processVideoSampleBuffer(
            sampleBuffer,
            roi: currentConfig.roi,
            accurateMode: currentConfig.ocrAccurateMode
        )
        measuredDurationMs = ocrResult.durationMs

        if let payload = ocrResult.payload {
            ipcBridge.publishDialogue(payload)
        }
    }

    private func refreshConfigFromIPC() {
        let latestROI = ipcBridge.readROI().clamped()
        let latestAppearance = ipcBridge.readAppearance()

        configLock.withLock { config in
            config.roi = latestROI
            config.ocrAccurateMode = latestAppearance.ocrAccurateMode
        }
    }

    private func publishStatus(state: BroadcastSessionState, message: String?) {
        let snapshot = gateLock.withLock { gate in
            (gate.framesProcessed, gate.framesDropped, gate.lastOCRDurationMs)
        }

        let status = BroadcastStatusPayload(
            state: state,
            updatedAt: Date(),
            framesProcessed: snapshot.0,
            framesDropped: snapshot.1,
            lastOCRDurationMs: snapshot.2,
            estimatedMemoryMB: FrameOCRProcessor.currentResidentMemoryMB(),
            transportMode: ipcBridge.activeTransportMode,
            statusMessage: message
        )
        ipcBridge.publishBroadcastStatus(status)
    }
}
