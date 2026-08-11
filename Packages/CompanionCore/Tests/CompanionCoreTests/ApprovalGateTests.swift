import Testing
@testable import CompanionCore

// T1.4 — ApprovalGate (PRD 51 exactly-once, PRD 52 stale).
// Approval TIDAK punya request_id (diverifikasi §11.1) → client yang
// memastikan satu approval.request dijawab TEPAT SATU KALI.

func sampleApproval(command: String = "rm /tmp/x") -> ApprovalRequest {
    ApprovalRequest(command: command, patternKey: "delete in root path",
                    patternKeys: ["delete in root path"], description: "delete in root path",
                    allowPermanent: true)
}

@Test func respondWithoutPendingRejected() {
    var gate = ApprovalGate()
    let ok = gate.respond(.once)
    #expect(!ok)
    #expect(!gate.canRespond)
}

@Test func exactlyOnceAfterRespond() {
    // PRD 51: double click / UI duplicate → approval TIDAK boleh dikirim dua kali.
    var gate = ApprovalGate()
    gate.register(sampleApproval())
    #expect(gate.canRespond)
    let first = gate.respond(.once)
    #expect(first)
    #expect(!gate.canRespond)               // terkunci setelah dijawab
    let second = gate.respond(.once)        // double click
    #expect(!second)
    let third = gate.respond(.deny)         // retry jaringan
    #expect(!third)
}

@Test func newRequestRearms() {
    // approval.request BARU = approval baru → boleh dijawab lagi.
    var gate = ApprovalGate()
    gate.register(sampleApproval(command: "rm /tmp/a"))
    let r = gate.respond(.once); #expect(r)
    gate.register(sampleApproval(command: "rm /tmp/b"))
    #expect(gate.canRespond)
    let r2 = gate.respond(.session); #expect(r2)
}

@Test func registerReplacesPending() {
    var gate = ApprovalGate()
    gate.register(sampleApproval(command: "rm /tmp/a"))
    gate.register(sampleApproval(command: "rm /tmp/b"))
    #expect(gate.pendingApproval?.command == "rm /tmp/b")
}

@Test func staleInvalidateBlocks() {
    // PRD 52: task berhenti/session berubah → UI tidak boleh menawarkan Allow/Deny.
    var gate = ApprovalGate()
    gate.register(sampleApproval())
    gate.invalidate()
    #expect(!gate.canRespond)
    let ok = gate.respond(.once)
    #expect(!ok)
}

@Test func invalidateThenNewRequestRearms() {
    // Setelah invalidate (mis. disconnect), approval baru masih bisa diproses.
    var gate = ApprovalGate()
    gate.register(sampleApproval())
    gate.invalidate()
    gate.register(sampleApproval())
    #expect(gate.canRespond)
    let r = gate.respond(.once); #expect(r)
}

@Test func respondRecordsRequest() {
    var gate = ApprovalGate()
    let req = sampleApproval(command: "rm /tmp/rahasia")
    gate.register(req)
    _ = gate.respond(.once)
    #expect(gate.pendingApproval == req)    // masih tersimpan utk audit/UI
}