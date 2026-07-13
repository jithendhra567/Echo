import Foundation
import Network

/// Local WebSocket server that accepts one paired Android companion at a time.
/// Explicitly nonisolated — Network.framework callbacks run off the main actor.
nonisolated final class CompanionServer: @unchecked Sendable {
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "echo.companion.server")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var onMessage: (@Sendable (CompanionMessage) -> Void)?
    var onClientConnected: (@Sendable () -> Void)?
    var onClientDisconnected: (@Sendable () -> Void)?
    var onListening: (@Sendable (Bool) -> Void)?

    private(set) var isListening = false

    init(port: UInt16 = CompanionProtocol.defaultPort) {
        self.port = NWEndpoint.Port(rawValue: port) ?? 8742
    }

    func start() {
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    func send(_ message: CompanionMessage) {
        queue.async { [weak self] in
            self?.sendLocked(message)
        }
    }

    private func startLocked() {
        stopLocked()
        do {
            let parameters = NWParameters.tcp
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.queue.async {
                    self?.accept(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isListening = true
                    self.onListening?(true)
                case .failed, .cancelled:
                    self.isListening = false
                    self.onListening?(false)
                default:
                    break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            isListening = false
            onListening?(false)
        }
    }

    private func stopLocked() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        isListening = false
        onListening?(false)
    }

    private func accept(_ newConnection: NWConnection) {
        if let existing = connection {
            existing.cancel()
        }
        connection = newConnection
        newConnection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onClientConnected?()
                self.receive(on: newConnection)
            case .failed, .cancelled:
                if self.connection === newConnection {
                    self.connection = nil
                    self.onClientDisconnected?()
                }
            default:
                break
            }
        }
        newConnection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            if let content, !content.isEmpty,
               let message = try? self.decoder.decode(CompanionMessage.self, from: content) {
                self.onMessage?(message)
            }
            if connection === self.connection {
                self.receive(on: connection)
            }
        }
    }

    private func sendLocked(_ message: CompanionMessage) {
        guard let connection, let data = try? encoder.encode(message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "echo", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }
}
