import Foundation

/// Client JSON-RPC 2.0 over WebSocket ke Hermes Gateway.
/// - Kirim request dengan id increment; response dicocokkan by id.
/// - Event server diteruskan ke callback.
/// - Baris tak dikenal dilewati (PRD: jangan crash, lewati dan lanjut).
public final class JSONRPCClient: @unchecked Sendable {
    /// Klasifikasi satu baris frame.
    public enum FrameKind: Equatable {
        case response(JSONRPCResponse)
        case event(JSONRPCEnvelope)
        case unknown
    }

    /// Murni — testable tanpa koneksi. Response punya `id` tanpa `method`;
    /// event punya `method == "event"`; sisanya unknown.
    public static func classify(_ line: String) -> FrameKind {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["jsonrpc"] != nil else { return .unknown }
        if obj["method"] as? String == "event" {
            guard let env = try? JSONDecoder().decode(JSONRPCEnvelope.self, from: data) else { return .unknown }
            return .event(env)
        }
        guard let resp = try? JSONDecoder().decode(JSONRPCResponse.self, from: data) else { return .unknown }
        return .response(resp)
    }

    private let task: URLSessionWebSocketTask
    private let queue = DispatchQueue(label: "jsonrpc-client")
    private var idGen = JSONRPCIDGenerator()
    private var pending: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var onEvent: ((JSONRPCEnvelope) -> Void)?
    /// Debug/capture: raw frame mentah sebelum diklasifikasi.
    public var onRawFrame: ((String) -> Void)?
    private var recvTask: Task<Void, Never>?

    public init(url: URL, onEvent: ((JSONRPCEnvelope) -> Void)? = nil) {
        self.task = URLSession.shared.webSocketTask(with: url)
        self.onEvent = onEvent
    }

    public func connect() {
        task.resume()
        recvTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    public func close() {
        recvTask?.cancel()
        task.cancel(with: .goingAway, reason: nil)
    }

    /// Kirim request, tunggu response dengan id yang sama.
    public func send<Params: Encodable>(method: String, params: Params) async throws -> JSONRPCResponse {
        let id = queue.sync { idGen.nextID() }
        let request = JSONRPCRequest(id: id, method: method, params: params)
        let json = String(data: try JSONEncoder().encode(request), encoding: .utf8)!
        return try await withCheckedThrowingContinuation { cont in
            queue.sync { pending[id] = cont }
            Task {
                do {
                    try await task.send(.string(json))
                } catch {
                    queue.sync { pending.removeValue(forKey: id) }
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let s):
                    onRawFrame?(s)
                    handleFrame(s)
                case .data(let d):
                    if let s = String(data: d, encoding: .utf8) { onRawFrame?(s); handleFrame(s) }
                @unknown default:
                    break
                }
            } catch {
                break
            }
        }
    }

    private func handleFrame(_ line: String) {
        switch JSONRPCClient.classify(line) {
        case .response(let resp):
            queue.sync {
                if let cont = pending.removeValue(forKey: resp.id) {
                    cont.resume(returning: resp)
                }
            }
        case .event(let env):
            onEvent?(env)
        case .unknown:
            break
        }
    }
}
