import Testing
import Foundation
@testable import CompanionCore

// T1.2 — EventDecoder mengubah envelope protocol jadi TaskEvent domain.

func loadFixture(_ name: String) throws -> JSONRPCEnvelope {
    let thisFile = URL(fileURLWithPath: #filePath)
    let fixturesDir = thisFile.deletingLastPathComponent().appendingPathComponent("Fixtures")
    let url = fixturesDir.appendingPathComponent(name + ".jsonl")
    let line = try String(contentsOf: url, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return try JSONDecoder().decode(JSONRPCEnvelope.self, from: Data(line.utf8))
}

@Test func decodeApprovalFixtureToApprovalRequest() throws {
    let ev = try EventDecoder.decode(loadFixture("approval-request-delete-root"))
    guard case .approvalRequest(let a)? = ev else {
        Issue.record("expected approvalRequest, got \(String(describing: ev))"); return
    }
    #expect(a.command.contains("rm "))
    #expect(a.patternKey == "delete in root path")
    #expect(a.patternKeys == ["delete in root path"])
    #expect(a.allowPermanent)
}

@Test func decodeClarifyFixtureToClarifyRequest() throws {
    // Fixture = frame clarify.request NYATA direkam dari gateway (T1.6) —
    // bukti request_id dibawa oleh payload (server.py:1925 _block).
    let ev = try EventDecoder.decode(loadFixture("clarify-request-choices"))
    guard case .clarifyRequest(let c)? = ev else {
        Issue.record("expected clarifyRequest, got \(String(describing: ev))"); return
    }
    #expect(c.requestId.count == 8)          // uuid4().hex[:8]
    #expect(!c.question.isEmpty)
    #expect(c.choices.count >= 2)
    // Karena request_id di-generate per-session, jangan assert value literal.
    // Cukup pastikan id valid hex-8 (seperti session_id).
    #expect(c.requestId.allSatisfy { $0.isHexDigit })
}

@Test func decodeMessageDelta() {
    let env = JSONRPCEnvelope(jsonrpc: "2.0", id: nil, method: "event",
        params: EventParams(type: "message.delta", session_id: "s1",
            payload: .object(["text": .string("halo")])))
    #expect(EventDecoder.decode(env) == .messageDelta("halo"))
}

@Test func decodeMessageCompleteWithoutText() {
    // Bugfix: message.complete TANPA text harus tetap decode (bukan nil),
    // kalau nil E2E tidak pernah tahu turn selesai → timeout 120s.
    let env = JSONRPCEnvelope(jsonrpc: "2.0", id: nil, method: "event",
        params: EventParams(type: "message.complete", session_id: "s1", payload: .object([:])))
    #expect(EventDecoder.decode(env) == .messageComplete(MessageComplete(text: "")))
}

@Test func decodeStatusReady() {
    let env = JSONRPCEnvelope(jsonrpc: "2.0", id: nil, method: "event",
        params: EventParams(type: "status.update", session_id: "s1",
            payload: .object(["kind": .string("ready")])))
    #expect(EventDecoder.decode(env) == .ready)
}

@Test func decodeToolStart() {
    let env = JSONRPCEnvelope(jsonrpc: "2.0", id: nil, method: "event",
        params: EventParams(type: "tool.start", session_id: "s1",
            payload: .object(["name": .string("write_file"), "tool_id": .string("call_123")])))
    #expect(EventDecoder.decode(env) == .toolStarted(ToolInfo(toolId: "call_123", name: "write_file")))
}

@Test func decodeErrorToFailure() {
    let env = JSONRPCEnvelope(jsonrpc: "2.0", id: nil, method: "event",
        params: EventParams(type: "error", session_id: "s1",
            payload: .object(["message": .string("boom")])))
    #expect(EventDecoder.decode(env) == .failure("boom"))
}

@Test func decodeUnknownEventReturnsNil() {
    let env = JSONRPCEnvelope(jsonrpc: "2.0", id: nil, method: "event",
        params: EventParams(type: "reasoning.delta", session_id: "s1", payload: nil))
    #expect(EventDecoder.decode(env) == nil)   // bukan crash (PRD 36)
}

@Test func decodeNonEventReturnsNil() {
    // Frame response / gateway.ready (bukan task event) → nil.
    #expect(EventDecoder.decode(JSONRPCEnvelope(jsonrpc: "2.0", id: nil, method: nil, params: nil)) == nil)
}