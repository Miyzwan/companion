import Testing
import Foundation
@testable import CompanionCore

// T3.1 — TaskState → glif/bubble text (PRD 41/44/80).

@Test func glyphPerState() {
    #expect(TaskState.idle.glyph == "◉")
    #expect(TaskState.working.glyph == "●")
    #expect(TaskState.needsYou(.approval).glyph == "⚠")
    #expect(TaskState.success.glyph == "✓")
    #expect(TaskState.error.glyph == "!")
    #expect(TaskState.starting.glyph == "○")
    #expect(TaskState.stopping.glyph == "○")
    #expect(TaskState.disconnected.glyph == "○")
}

@Test func statusLinePerState() {
    #expect(TaskState.idle.statusLine == "Ready when you are.")
    #expect(TaskState.working.statusLine == "Working")
    #expect(TaskState.success.statusLine == "Done")
    #expect(TaskState.error.statusLine == "Problem")
    #expect(TaskState.stopping.statusLine == "Stopping…")
    #expect(TaskState.disconnected.statusLine == "Disconnected")
}

@Test func statusLineNeedsYouSubtypes() {
    #expect(TaskState.needsYou(.approval).statusLine == "Needs your approval")
    #expect(TaskState.needsYou(.clarification).statusLine == "Needs your input")
    #expect(TaskState.needsYou(.sudo).statusLine == "Needs sudo")
    #expect(TaskState.needsYou(.secret).statusLine == "Needs a secret")
    #expect(TaskState.needsYou(.other).statusLine == "Needs you")
}

@Test func decisionTextForRequests() {
    let approval = ApprovalRequest(command: "rm /tmp/x", patternKey: "delete",
                                   patternKeys: ["delete"], description: "delete", allowPermanent: true)
    #expect(TaskEvent.approvalRequest(approval).decisionText == "rm /tmp/x")
    let clarify = ClarifyRequest(requestId: "abcd1234", question: "Pilih A atau B?", choices: ["A", "B"])
    #expect(TaskEvent.clarifyRequest(clarify).decisionText == "Pilih A atau B?")
    #expect(TaskEvent.ready.decisionText == nil)
    #expect(TaskEvent.messageDelta("x").decisionText == nil)
    #expect(TaskEvent.failure("boom").decisionText == nil)
}