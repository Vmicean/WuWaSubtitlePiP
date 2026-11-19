import Foundation
import Network
import os

public enum BroadcastIPCEvent: Sendable {
    case dialogue(CapturedDialoguePayload)
    case roi(SubtitleROI)
    case status(BroadcastStatusPayload)
    case appearance(PiPAppearanceSettings)
}

private enum IPCWireEnvelope: Codable, Sendable {
    case dialogue(CapturedDialoguePayload)
    case roi(SubtitleROI)
    case status(BroadcastStatusPayload)
    case appearance(PiPAppearanceSettings)

    var asEvent: BroadcastIPCEvent {
        switch self {
        case .dialogue(let payload): return .dialogue(payload)
        case .roi(let roi): return .roi(roi)
        case .status(let status): return .status(status)
        case .appearance(let appearance): return .appearance(appearance)
        }
    }
}

/// Dual-transport IPC bridge between WuWaBroadcastExtension and WuWaSubtitlePiP:
/// 1) Primary: Atomic JSON files inside the dynamically resolved App Group container
///    paired with CFNotificationCenterGetDarwinNotifyCenter() instant wakeups.
/// 2) Fallback: Loopback TCP (127.0.0.1:47891) JSON-line transport when a Free Apple ID
///    sideload strips shared App Group containers.
public final class BroadcastIPCBridge: @unchecked Sendable {
    public enum Role: Sendable {
        case hostApp
        case broadcastExtension
    }

    public static let loopbackHost = "127.0.0.1"
    public static let loopbackPort: UInt16 = 47891

    public enum FileName {
        public static let latestOCR = "latest_ocr.json"
        public static let roiSettings = "roi_settings.json"
        public static let broadcastStatus = "broadcast_status.json"
        public static let appearanceSettings = "appearance_settings.json"
    }

    public enum DarwinNotificationName {
        public static let ocrUpdated = "com.wuwatranslator.darwin.ocrUpdated"
        public static let roiUpdated = "com.wuwatranslator.darwin.roiUpdated"
        public static let statusUpdated = "com.wuwatranslator.darwin.statusUpdated"
        public static let appearanceUpdated = "com.wuwatranslator.darwin.appearanceUpdated"
    }

    private struct MutableState {
        var activeTransportMode: IPCTransportMode
        var onEvent: (@Sendable (BroadcastIPCEvent) -> Void)?
        var listener: NWListener?
        var activeConnections: [ObjectIdentifier: NWConnection] = [:]
        var loopbackClient: NWConnection?
        var receiveBuffers: [ObjectIdentifier: Data] = [:]
        var darwinRegisteredNames: [String] = []
    }

    public let role: Role
    public let resolvedAppGroup: ResolvedAppGroup

    private let fileLock = OSAllocatedUnfairLock()
    private let stateLock: OSAllocatedUnfairLock<MutableState>
    private let networkQueue = DispatchQueue(label: "com.wuwatranslator.ipc.network", qos: .userInitiated)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public var activeTransportMode: IPCTransportMode {
        stateLock.withLock { $0.activeTransportMode }
    }

    public init(
        role: Role,
        resolvedAppGroup: ResolvedAppGroup = AppGroupResolver.resolve()
    ) {
        self.role = role
        self.resolvedAppGroup = resolvedAppGroup

        let initialMode: IPCTransportMode = resolvedAppGroup.containerURL != nil
            ? .appGroupDarwin
            : .loopbackTCP
        self.stateLock = OSAllocatedUnfairLock(
            initialState: MutableState(activeTransportMode: initialMode)
        )

        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        self.encoder = jsonEncoder

        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        self.decoder = jsonDecoder
    }

    deinit {
        stopListening()
    }

    // MARK: - Listening Lifecycle

    public func startListening(onEvent: @escaping @Sendable (BroadcastIPCEvent) -> Void) {
        stateLock.withLock { $0.onEvent = onEvent }

        if resolvedAppGroup.containerURL != nil {
            stateLock.withLock { $0.activeTransportMode = .appGroupDarwin }
            registerDarwinObservers()
        } else {
            stateLock.withLock { $0.activeTransportMode = .loopbackTCP }
            if role == .hostApp {
                startLoopbackServer()
            } else {
                connectLoopbackClientIfNeeded()
            }
        }
    }

    public func stopListening() {
        unregisterDarwinObservers()

        let resources = stateLock.withLock { state -> (NWListener?, [NWConnection], NWConnection?) in
            let listener = state.listener
            let connections = Array(state.activeConnections.values)
            let client = state.loopbackClient
            state.listener = nil
            state.activeConnections.removeAll()
            state.receiveBuffers.removeAll()
            state.loopbackClient = nil
            state.onEvent = nil
            return (listener, connections, client)
        }

        resources.0?.cancel()
        resources.1.forEach { $0.cancel() }
        resources.2?.cancel()
    }

    // MARK: - Typed Read / Write Operations

    public func publishDialogue(_ payload: CapturedDialoguePayload) {
        if writeAtomicJSON(payload, fileName: FileName.latestOCR) {
            postDarwinNotification(DarwinNotificationName.ocrUpdated)
        } else {
            sendLoopbackEnvelope(.dialogue(payload))
        }
    }

    public func readLatestDialogue() -> CapturedDialoguePayload? {
        readJSON(CapturedDialoguePayload.self, fileName: FileName.latestOCR)
    }

    public func publishROI(_ roi: SubtitleROI) {
        let clamped = roi.clamped()
        if writeAtomicJSON(clamped, fileName: FileName.roiSettings) {
            postDarwinNotification(DarwinNotificationName.roiUpdated)
        } else {
            sendLoopbackEnvelope(.roi(clamped))
        }
    }

    public func readROI() -> SubtitleROI {
        readJSON(SubtitleROI.self, fileName: FileName.roiSettings) ?? .wuWaDialogueDefault
    }

    public func publishBroadcastStatus(_ status: BroadcastStatusPayload) {
        if writeAtomicJSON(status, fileName: FileName.broadcastStatus) {
            postDarwinNotification(DarwinNotificationName.statusUpdated)
        } else {
            sendLoopbackEnvelope(.status(status))
        }
    }

    public func readBroadcastStatus() -> BroadcastStatusPayload {
        readJSON(BroadcastStatusPayload.self, fileName: FileName.broadcastStatus) ?? .idle
    }

    public func publishAppearance(_ settings: PiPAppearanceSettings) {
        if writeAtomicJSON(settings, fileName: FileName.appearanceSettings) {
            postDarwinNotification(DarwinNotificationName.appearanceUpdated)
        } else {
            sendLoopbackEnvelope(.appearance(settings))
        }
    }

    public func readAppearance() -> PiPAppearanceSettings {
        readJSON(PiPAppearanceSettings.self, fileName: FileName.appearanceSettings) ?? .default
    }

    // MARK: - Primary Transport: Atomic App Group Container + Darwin Notifications

    private func writeAtomicJSON<T: Encodable>(_ value: T, fileName: String) -> Bool {
        guard let containerURL = resolvedAppGroup.containerURL else {
            return false
        }

        return fileLock.withLock {
            guard let data = try? encoder.encode(value) else { return false }
            let targetURL = containerURL.appendingPathComponent(fileName, isDirectory: false)
            do {
                try data.write(to: targetURL, options: [.atomic])
                return true
            } catch {
                return false
            }
        }
    }

    private func readJSON<T: Decodable>(_ type: T.Type, fileName: String) -> T? {
        guard let containerURL = resolvedAppGroup.containerURL else {
            return nil
        }

        return fileLock.withLock {
            let targetURL = containerURL.appendingPathComponent(fileName, isDirectory: false)
            guard let data = try? Data(contentsOf: targetURL) else { return nil }
            return try? decoder.decode(type, from: data)
        }
    }

    private func postDarwinNotification(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    private func registerDarwinObservers() {
        unregisterDarwinObservers()

        let namesToObserve: [String]
        switch role {
        case .hostApp:
            namesToObserve = [
                DarwinNotificationName.ocrUpdated,
                DarwinNotificationName.statusUpdated
            ]
        case .broadcastExtension:
            namesToObserve = [
                DarwinNotificationName.roiUpdated,
                DarwinNotificationName.appearanceUpdated
            ]
        }

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observerPointer = Unmanaged.passUnretained(self).toOpaque()

        for name in namesToObserve {
            CFNotificationCenterAddObserver(
                center,
                observerPointer,
                Self.darwinNotificationCallback,
                name as CFString,
                nil,
                .deliverImmediately
            )
        }

        stateLock.withLock { $0.darwinRegisteredNames = namesToObserve }
    }

    private func unregisterDarwinObservers() {
        let registered = stateLock.withLock { state -> [String] in
            let names = state.darwinRegisteredNames
            state.darwinRegisteredNames = []
            return names
        }
        guard !registered.isEmpty else { return }

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observerPointer = Unmanaged.passUnretained(self).toOpaque()
        for name in registered {
            CFNotificationCenterRemoveObserver(
                center,
                observerPointer,
                CFNotificationName(name as CFString),
                nil
            )
        }
    }

    private func handleDarwinNotification(name: String) {
        let callback = stateLock.withLock { $0.onEvent }
        guard let callback else { return }

        switch name {
        case DarwinNotificationName.ocrUpdated:
            if let dialogue = readLatestDialogue() {
                callback(.dialogue(dialogue))
            }
        case DarwinNotificationName.roiUpdated:
            callback(.roi(readROI()))
        case DarwinNotificationName.statusUpdated:
            callback(.status(readBroadcastStatus()))
        case DarwinNotificationName.appearanceUpdated:
            callback(.appearance(readAppearance()))
        default:
            break
        }
    }

    private static let darwinNotificationCallback: CFNotificationCallback = { _, observer, cfName, _, _ in
        guard let observer, let cfName else { return }
        let bridge = Unmanaged<BroadcastIPCBridge>.fromOpaque(observer).takeUnretainedValue()
        bridge.handleDarwinNotification(name: cfName.rawValue as String)
    }

    // MARK: - Secondary Fallback Transport: Loopback TCP (127.0.0.1:47891) JSON-Line

    private func startLoopbackServer() {
        let alreadyRunning = stateLock.withLock { $0.listener != nil }
        guard !alreadyRunning else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: Self.loopbackPort),
              let listener = try? NWListener(using: parameters, on: port) else {
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.acceptLoopbackConnection(connection)
        }

        listener.stateUpdateHandler = { [weak self] newState in
            if case .failed = newState {
                self?.stateLock.withLock { $0.listener = nil }
            }
        }

        stateLock.withLock { $0.listener = listener }
        listener.start(queue: networkQueue)
    }

    private func acceptLoopbackConnection(_ connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        stateLock.withLock { state in
            state.activeConnections[identifier] = connection
            state.receiveBuffers[identifier] = Data()
        }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.cleanupConnection(identifier: identifier)
            default:
                break
            }
        }

        connection.start(queue: networkQueue)
        receiveNextChunk(on: connection, identifier: identifier)
    }

    private func connectLoopbackClientIfNeeded() {
        let existing = stateLock.withLock { $0.loopbackClient }
        if existing != nil { return }

        guard let port = NWEndpoint.Port(rawValue: Self.loopbackPort) else { return }
        let connection = NWConnection(
            host: NWEndpoint.Host(Self.loopbackHost),
            port: port,
            using: .tcp
        )
        let identifier = ObjectIdentifier(connection)

        stateLock.withLock { state in
            state.loopbackClient = connection
            state.receiveBuffers[identifier] = Data()
        }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.stateLock.withLock { mutable in
                    if mutable.loopbackClient === connection {
                        mutable.loopbackClient = nil
                    }
                    mutable.receiveBuffers.removeValue(forKey: identifier)
                }
            default:
                break
            }
        }

        connection.start(queue: networkQueue)
        receiveNextChunk(on: connection, identifier: identifier)
    }

    private func sendLoopbackEnvelope(_ envelope: IPCWireEnvelope) {
        guard var payloadData = try? encoder.encode(envelope) else { return }
        payloadData.append(0x0A) // Newline delimiter for JSON-line framing.

        if role == .hostApp {
            let connections = stateLock.withLock { Array($0.activeConnections.values) }
            for connection in connections {
                connection.send(content: payloadData, completion: .contentProcessed { _ in })
            }
        } else {
            connectLoopbackClientIfNeeded()
            let client = stateLock.withLock { $0.loopbackClient }
            client?.send(content: payloadData, completion: .contentProcessed { _ in })
        }
    }

    private func receiveNextChunk(on connection: NWConnection, identifier: ObjectIdentifier) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                let completeLines = self.appendAndExtractLines(data: data, identifier: identifier)
                for lineData in completeLines {
                    if let envelope = try? self.decoder.decode(IPCWireEnvelope.self, from: lineData) {
                        let callback = self.stateLock.withLock { $0.onEvent }
                        callback?(envelope.asEvent)
                    }
                }
            }

            if isComplete || error != nil {
                self.cleanupConnection(identifier: identifier)
                return
            }

            self.receiveNextChunk(on: connection, identifier: identifier)
        }
    }

    private func appendAndExtractLines(data: Data, identifier: ObjectIdentifier) -> [Data] {
        stateLock.withLock { state in
            var buffer = state.receiveBuffers[identifier] ?? Data()
            buffer.append(data)

            var lines: [Data] = []
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newlineIndex)
                if !line.isEmpty {
                    lines.append(line)
                }
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
            }

            // Cap buffer growth to protect extension memory budget under malformed streams.
            if buffer.count > 65_536 {
                buffer.removeAll(keepingCapacity: false)
            }
            state.receiveBuffers[identifier] = buffer
            return lines
        }
    }

    private func cleanupConnection(identifier: ObjectIdentifier) {
        let connection = stateLock.withLock { state -> NWConnection? in
            state.receiveBuffers.removeValue(forKey: identifier)
            return state.activeConnections.removeValue(forKey: identifier)
        }
        connection?.cancel()
    }
}
