import Testing
@testable import CompanionCore

// T1.1 — TaskStateMachine (PRD section 25-34: state model; section 35: priority)
// TDD: test transisi legal/ilegal dulu.

// ── Jalur legal ──────────────────────────────────────────────────────

@Test func happyPathIdleToSuccess() {
    var m = TaskStateMachine(initial: .idle)
    let s1 = m.transition(to: .starting); #expect(s1)
    let s2 = m.transition(to: .working); #expect(s2)
    let s3 = m.transition(to: .success); #expect(s3)
    #expect(m.state == .success)
}

@Test func m1ApprovalLoopWorkingNeedsYouWorkingSuccess() {
    // Inti M1 (PRD section 78): Working → NeedsYou → Working → Success
    var m = TaskStateMachine(initial: .idle)
    let s1 = m.transition(to: .starting); #expect(s1)
    let s2 = m.transition(to: .working); #expect(s2)
    let s3 = m.transition(to: .needsYou(.approval)); #expect(s3)
    #expect(m.state == .needsYou(.approval))
    let s4 = m.transition(to: .working); #expect(s4)   // approval.respond → lanjut
    let s5 = m.transition(to: .success); #expect(s5)
}

@Test func m1ClarifyLoop() {
    var m = TaskStateMachine(initial: .idle)
    let s1 = m.transition(to: .starting); #expect(s1)
    let s2 = m.transition(to: .working); #expect(s2)
    let s3 = m.transition(to: .needsYou(.clarification)); #expect(s3)
    let s4 = m.transition(to: .working); #expect(s4)   // clarify.respond → lanjut
    let s5 = m.transition(to: .success); #expect(s5)
}

@Test func errorPaths() {
    var m = TaskStateMachine(initial: .idle)
    let s1 = m.transition(to: .starting); #expect(s1)
    let s2 = m.transition(to: .error); #expect(s2)
    let s3 = m.transition(to: .idle); #expect(s3)

    var m2 = TaskStateMachine(initial: .idle)
    let a1 = m2.transition(to: .starting); #expect(a1)
    let a2 = m2.transition(to: .working); #expect(a2)
    let a3 = m2.transition(to: .needsYou(.approval)); #expect(a3)
    let a4 = m2.transition(to: .error); #expect(a4)    // error saat nunggu jawaban
}

@Test func stopPaths() {
    var m = TaskStateMachine(initial: .idle)
    let s1 = m.transition(to: .starting); #expect(s1)
    let s2 = m.transition(to: .working); #expect(s2)
    let s3 = m.transition(to: .stopping); #expect(s3)  // user minta stop (PRD 33)
    let s4 = m.transition(to: .success); #expect(s4)
}

@Test func disconnectRecovery() {
    var m = TaskStateMachine(initial: .idle)
    let s1 = m.transition(to: .starting); #expect(s1)
    let s2 = m.transition(to: .working); #expect(s2)
    let s3 = m.transition(to: .disconnected); #expect(s3)
    let s4 = m.transition(to: .idle); #expect(s4)      // reconnect = fresh (M5 penuh)
}

// ── Transisi ilegal ─────────────────────────────────────────────────

@Test func needsYouCannotJumpToSuccess() {
    // PRD 50: tidak boleh Success sebelum approval/clarify dijawab.
    var m = TaskStateMachine(initial: .idle)
    let s1 = m.transition(to: .starting); #expect(s1)
    let s2 = m.transition(to: .working); #expect(s2)
    let s3 = m.transition(to: .needsYou(.approval)); #expect(s3)
    let bad = m.transition(to: .success); #expect(!bad)
    #expect(m.state == .needsYou(.approval))           // state tidak berubah
}

@Test func idleCannotJumpToSuccess() {
    var m = TaskStateMachine(initial: .idle)
    let b1 = m.transition(to: .success); #expect(!b1)
    let b2 = m.transition(to: .working); #expect(!b2)
    #expect(m.state == .idle)
}

@Test func successIsTerminal() {
    var m = TaskStateMachine(initial: .idle)
    let s1 = m.transition(to: .starting); #expect(s1)
    let s2 = m.transition(to: .working); #expect(s2)
    let s3 = m.transition(to: .success); #expect(s3)
    let b1 = m.transition(to: .working); #expect(!b1)
    let b2 = m.transition(to: .needsYou(.approval)); #expect(!b2)
}

@Test func needsYouCannotResetToIdle() {
    var m = TaskStateMachine(initial: .idle)
    let s1 = m.transition(to: .starting); #expect(s1)
    let s2 = m.transition(to: .working); #expect(s2)
    let s3 = m.transition(to: .needsYou(.clarification)); #expect(s3)
    let bad = m.transition(to: .idle); #expect(!bad)
    #expect(m.state == .needsYou(.clarification))
}

// ── Priority (PRD section 35) ───────────────────────────────────────

@Test func statePriorityOrdering() {
    // NeedsYou > Error > Working > Starting/Stopping > Success > Idle
    #expect(TaskStateMachine.priority(.needsYou(.approval)) > TaskStateMachine.priority(.error))
    #expect(TaskStateMachine.priority(.error) > TaskStateMachine.priority(.working))
    #expect(TaskStateMachine.priority(.working) > TaskStateMachine.priority(.stopping))
    #expect(TaskStateMachine.priority(.stopping) == TaskStateMachine.priority(.starting))
    #expect(TaskStateMachine.priority(.starting) > TaskStateMachine.priority(.success))
    #expect(TaskStateMachine.priority(.success) > TaskStateMachine.priority(.idle))
}

@Test func startingCanAskImmediately() {
    // Bugfix: agent bisa minta keputusan di DETIK-DETIK AWAL turn (belum ada
    // bukti working) → starting → needsYou harus legal, kalau tidak state
    // macet di starting padahal UI harusnya nunjukin Needs You.
    var m = TaskStateMachine(initial: .idle)
    let s1 = m.transition(to: .starting); #expect(s1)
    let s2 = m.transition(to: .needsYou(.approval)); #expect(s2)
    #expect(m.state == .needsYou(.approval))
    let s3 = m.transition(to: .working); #expect(s3)   // respond → lanjut
}

@Test func needsYouSubtypesDistinct() {
    #expect(TaskState.needsYou(.approval) != TaskState.needsYou(.clarification))
    #expect(NeedsYouCase.approval.rawValue == "approval")
    #expect(NeedsYouCase.clarification.rawValue == "clarification")
    #expect(NeedsYouCase.sudo.rawValue == "sudo")
    #expect(NeedsYouCase.secret.rawValue == "secret")
}