import Foundation

// T1.3 — approval/clarify respond (PRD section 50/53) + interrupt (PRD 55).
// Semua string method Hermes hidup DI SINI saja (D5).
// Param-builder murni -> bisa di-unit-test tanpa koneksi; E2E (T1.5/T1.6)
// membuktikan method string bekerja melawan gateway nyata.

/// Choice untuk `approval.respond` (diverifikasi §11.2).
public enum ApprovalChoice: String, Equatable, Sendable {
    case once
    case session
    case always
    case deny
}

extension HermesAdapter {
    /// Nama method Hermes — satu-satunya tempat literalnya.
    public enum Method {
        public static let approvalRespond = "approval.respond"
        public static let clarifyRespond = "clarify.respond"
        public static let sessionInterrupt = "session.interrupt"
    }

    /// Builder murni params `approval.respond` (server.py:9819).
    /// `resolveAll` true → `all:true` (resolve SEMUA pending approval sesi).
    public static func approvalParams(sessionID: String, choice: ApprovalChoice,
                                      resolveAll: Bool = false) -> [String: JSONValue] {
        var p: [String: JSONValue] = [
            "session_id": .string(sessionID),
            "choice": .string(choice.rawValue),
        ]
        if resolveAll { p["all"] = .bool(true) }
        return p
    }

    /// Builder murni params `clarify.respond` (server.py:9798).
    public static func clarifyParams(sessionID: String, requestID: String,
                                     answer: String) -> [String: JSONValue] {
        ["session_id": .string(sessionID),
         "request_id": .string(requestID),
         "answer": .string(answer)]
    }

    /// Builder murni params `session.interrupt`.
    public static func interruptParams(sessionID: String) -> [String: JSONValue] {
        ["session_id": .string(sessionID)]
    }

    /// Kirim `approval.respond`. Return jumlah approval ter-resolve
    /// (0 = tidak ada pending). Error 5004 dilempar sebagai HermesError.
    public func respondApproval(sessionID: String, choice: ApprovalChoice,
                                resolveAll: Bool = false) async throws -> Int {
        let resp = try await client.send(method: Method.approvalRespond,
                                         params: Self.approvalParams(sessionID: sessionID, choice: choice, resolveAll: resolveAll))
        if let err = resp.error { throw HermesError.rpc(err.code, err.message) }
        if case .object(let o)? = resp.result, case .number(let n)? = o["resolved"] {
            return Int(n)
        }
        return 0
    }

    /// Kirim `clarify.respond`. Return true kalau diterima; false kalau 4009
    /// (request_id stale/tak dikenal — aman, idempotens alami).
    public func respondClarify(sessionID: String, requestID: String, answer: String) async throws -> Bool {
        let resp = try await client.send(method: Method.clarifyRespond,
                                         params: Self.clarifyParams(sessionID: sessionID, requestID: requestID, answer: answer))
        if let err = resp.error {
            if err.code == 4009 { return false }
            throw HermesError.rpc(err.code, err.message)
        }
        return true
    }

    /// Kirim `session.interrupt` (stop turn berjalan, PRD 55).
    public func interrupt(sessionID: String) async throws {
        let resp = try await client.send(method: Method.sessionInterrupt,
                                         params: Self.interruptParams(sessionID: sessionID))
        if let err = resp.error { throw HermesError.rpc(err.code, err.message) }
    }
}