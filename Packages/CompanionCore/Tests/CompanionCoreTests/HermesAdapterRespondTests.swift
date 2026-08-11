import Testing
import Foundation
@testable import CompanionCore

// T1.3 — HermesAdapter respond: param-builder murni + method string (D5).

@Test func approvalParamsDefault() {
    let p = HermesAdapter.approvalParams(sessionID: "s1", choice: .once)
    #expect(p["session_id"] == .string("s1"))
    #expect(p["choice"] == .string("once"))
    #expect(p["all"] == nil)
}

@Test func approvalParamsDenyDefaultChoice() {
    let p = HermesAdapter.approvalParams(sessionID: "s1", choice: .deny)
    #expect(p["choice"] == .string("deny"))
}

@Test func approvalParamsResolveAll() {
    let p = HermesAdapter.approvalParams(sessionID: "s1", choice: .session, resolveAll: true)
    #expect(p["choice"] == .string("session"))
    #expect(p["all"] == .bool(true))
}

@Test func approvalChoiceRawValues() {
    // Contract §11.2 — choice valid di gateway.
    #expect(ApprovalChoice.once.rawValue == "once")
    #expect(ApprovalChoice.session.rawValue == "session")
    #expect(ApprovalChoice.always.rawValue == "always")
    #expect(ApprovalChoice.deny.rawValue == "deny")
}

@Test func clarifyParamsShape() {
    let p = HermesAdapter.clarifyParams(sessionID: "s1", requestID: "a1b2c3d4", answer: "Keep existing")
    #expect(p["session_id"] == .string("s1"))
    #expect(p["request_id"] == .string("a1b2c3d4"))
    #expect(p["answer"] == .string("Keep existing"))
}

@Test func interruptParamsShape() {
    let p = HermesAdapter.interruptParams(sessionID: "s1")
    #expect(p == ["session_id": .string("s1")])
}

@Test func methodStringsMatchGateway() {
    // Literal yang dipakai gateway (server.py) — kalau berubah, test ini nangkap.
    #expect(HermesAdapter.Method.approvalRespond == "approval.respond")
    #expect(HermesAdapter.Method.clarifyRespond == "clarify.respond")
    #expect(HermesAdapter.Method.sessionInterrupt == "session.interrupt")
}