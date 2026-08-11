import Foundation

public enum HermesError: Error, Equatable {
    case rpc(Int, String)
    case missingSessionID
}

/// HermesAdapter (D5) — SATU-SATUNYA layer yang paham nama method/event Hermes.
/// Domain layer tidak pernah melihat string method mentah.
public struct HermesAdapter: Sendable {
    public let client: JSONRPCClient

    public init(client: JSONRPCClient) {
        self.client = client
    }

    /// `session.create` → session_id (hex 8).
    public func createSession(cwd: String) async throws -> String {
        let resp = try await client.send(method: "session.create", params: ["cwd": cwd])
        if let err = resp.error { throw HermesError.rpc(err.code, err.message) }
        if case .object(let obj)? = resp.result, case .string(let sid)? = obj["session_id"] {
            return sid
        }
        throw HermesError.missingSessionID
    }

    /// `prompt.submit` — async; hasil datang lewat event (message.delta/complete).
    public func submitPrompt(sessionID: String, text: String) async throws {
        let resp = try await client.send(method: "prompt.submit", params: ["session_id": sessionID, "text": text])
        if let err = resp.error { throw HermesError.rpc(err.code, err.message) }
    }
}
