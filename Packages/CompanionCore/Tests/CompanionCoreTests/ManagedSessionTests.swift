import Testing
@testable import CompanionCore

private final class FakeManagedSessionAdapter: ManagedSessionAdapter, @unchecked Sendable {
    private(set) var submittedPrompts: [String] = []
    private(set) var approvalChoices: [ApprovalChoice] = []
    private(set) var clarificationAnswers: [(String, String)] = []
    private(set) var interruptedSessionIDs: [String] = []

    func submitPrompt(sessionID: String, text: String) async throws {
        submittedPrompts.append(text)
    }

    func interrupt(sessionID: String) async throws {
        interruptedSessionIDs.append(sessionID)
    }

    func respondApproval(sessionID: String, choice: ApprovalChoice, resolveAll: Bool) async throws -> Int {
        approvalChoices.append(choice)
        return 1
    }

    func respondClarify(sessionID: String, requestID: String, answer: String) async throws -> Bool {
        clarificationAnswers.append((requestID, answer))
        return true
    }
}

private func managedApprovalRequest() -> ApprovalRequest {
    ApprovalRequest(
        command: "rm /tmp/example",
        patternKey: "delete in root path",
        patternKeys: ["delete in root path"],
        description: "delete in root path",
        allowPermanent: true
    )
}

@Test func startSubmitsPromptAndAutoApprovalIsDisabledByDefault() async {
    let adapter = FakeManagedSessionAdapter()
    let session = ManagedSession(adapterForTesting: adapter)
    let (states, stateContinuation) = AsyncStream<TaskState>.makeStream()
    session.onStateChange = { stateContinuation.yield($0) }

    let runTask = Task { await session.run(sessionID: "session", prompt: "inspect project") }
    var iterator = states.makeAsyncIterator()

    #expect(await iterator.next() == .starting)
    #expect(adapter.submittedPrompts == ["inspect project"])

    session.enqueueTestEvent(.approvalRequest(managedApprovalRequest()))
    #expect(await iterator.next() == .needsYou(.approval))
    #expect(adapter.approvalChoices.isEmpty)

    let stopped = await session.stop(sessionID: "session")
    #expect(stopped)
    #expect(adapter.interruptedSessionIDs == ["session"])
    #expect(session.state == .stopping)

    runTask.cancel()
    #expect(await runTask.value == .stopping)
}

@Test func approvalResponseWaitsForRuntimeActivityBeforeWorking() async {
    let adapter = FakeManagedSessionAdapter()
    let session = ManagedSession(adapterForTesting: adapter)
    let (states, stateContinuation) = AsyncStream<TaskState>.makeStream()
    session.onStateChange = { stateContinuation.yield($0) }

    let runTask = Task { await session.run(sessionID: "session", prompt: "do something") }
    var iterator = states.makeAsyncIterator()

    #expect(await iterator.next() == .starting)
    session.enqueueTestEvent(.approvalRequest(managedApprovalRequest()))
    #expect(await iterator.next() == .needsYou(.approval))

    let sent = await session.respondApproval(sessionID: "session", choice: .once)
    #expect(sent)
    #expect(session.state == .needsYou(.approval))
    #expect(adapter.approvalChoices == [.once])

    session.enqueueTestEvent(.activity("continuing"))
    #expect(await iterator.next() == .working)
    session.enqueueTestEvent(.messageComplete(MessageComplete(text: "done")))
    #expect(await iterator.next() == .success)
    #expect(await runTask.value == .success)
}

// T4.4b — jawaban agent harus sampai ke UI (PRD 22: "user-visible message
// content"). Sebelumnya teks `message.complete` cuma dipakai untuk transisi
// state lalu dibuang, jadi companion bisa bilang "Done" tanpa pernah bisa
// menunjukkan hasilnya.

@Test func messageCompleteMeneruskanTeksJawaban() async {
    let adapter = FakeManagedSessionAdapter()
    let session = ManagedSession(adapterForTesting: adapter)
    let (answers, answerContinuation) = AsyncStream<String>.makeStream()
    session.onMessage = { answerContinuation.yield($0) }

    let runTask = Task { await session.run(sessionID: "session", prompt: "folder apa?") }
    var iterator = answers.makeAsyncIterator()

    session.enqueueTestEvent(.messageComplete(MessageComplete(text: "Direktori kerja: /tmp/proyek")))
    #expect(await iterator.next() == "Direktori kerja: /tmp/proyek")
    #expect(await runTask.value == .success)
}

@Test func messageCompleteTanpaTeksTetapMenyelesaikanTurnTanpaJawabanKosong() async {
    // message.complete BOLEH datang tanpa `text` — turn tetap harus selesai,
    // tapi UI jangan dikirimi jawaban kosong.
    final class AnswerBox: @unchecked Sendable { var received: [String] = [] }
    let box = AnswerBox()
    let adapter = FakeManagedSessionAdapter()
    let session = ManagedSession(adapterForTesting: adapter)
    session.onMessage = { box.received.append($0) }

    let runTask = Task { await session.run(sessionID: "session", prompt: "kerjakan") }
    session.enqueueTestEvent(.messageComplete(MessageComplete(text: "")))

    #expect(await runTask.value == .success)
    #expect(box.received.isEmpty)
}

@Test func staleClarificationResponseIsRejectedBeforeGatewayCall() async {
    let adapter = FakeManagedSessionAdapter()
    let session = ManagedSession(adapterForTesting: adapter)
    let (states, stateContinuation) = AsyncStream<TaskState>.makeStream()
    session.onStateChange = { stateContinuation.yield($0) }

    let runTask = Task { await session.run(sessionID: "session", prompt: "ask me") }
    var iterator = states.makeAsyncIterator()
    #expect(await iterator.next() == .starting)

    session.enqueueTestEvent(.clarifyRequest(ClarifyRequest(
        requestId: "current-id",
        question: "Which folder should I use?",
        choices: ["Project A", "Project B"]
    )))
    #expect(await iterator.next() == .needsYou(.clarification))

    let stale = await session.respondClarify(
        sessionID: "session",
        requestID: "stale-id",
        answer: "Project A"
    )
    #expect(!stale)
    #expect(adapter.clarificationAnswers.isEmpty)

    let current = await session.respondClarify(
        sessionID: "session",
        requestID: "current-id",
        answer: "Project A"
    )
    #expect(current)
    session.enqueueTestEvent(.activity("continuing"))
    #expect(await iterator.next() == .working)
    session.enqueueTestEvent(.messageComplete(MessageComplete(text: "done")))
    #expect(await iterator.next() == .success)
    _ = await runTask.value
}

@Test func clarificationResponseWaitsForRuntimeActivityBeforeWorking() async {
    let adapter = FakeManagedSessionAdapter()
    let session = ManagedSession(adapterForTesting: adapter)
    let (states, stateContinuation) = AsyncStream<TaskState>.makeStream()
    session.onStateChange = { stateContinuation.yield($0) }

    let runTask = Task { await session.run(sessionID: "session", prompt: "ask me") }
    var iterator = states.makeAsyncIterator()

    #expect(await iterator.next() == .starting)
    session.enqueueTestEvent(.clarifyRequest(ClarifyRequest(
        requestId: "abc12345",
        question: "Which folder should I use?",
        choices: ["Project A", "Project B"]
    )))
    #expect(await iterator.next() == .needsYou(.clarification))

    let sent = await session.respondClarify(
        sessionID: "session",
        requestID: "abc12345",
        answer: "Project A"
    )
    #expect(sent)
    #expect(session.state == .needsYou(.clarification))
    #expect(adapter.clarificationAnswers.count == 1)

    session.enqueueTestEvent(.activity("continuing"))
    #expect(await iterator.next() == .working)
    session.enqueueTestEvent(.messageComplete(MessageComplete(text: "done")))
    #expect(await iterator.next() == .success)
    #expect(await runTask.value == .success)
}

@Test func approvalGateStillRejectsSecondResponseAfterRuntimeAcknowledgement() async {
    let adapter = FakeManagedSessionAdapter()
    let session = ManagedSession(adapterForTesting: adapter)
    let (states, stateContinuation) = AsyncStream<TaskState>.makeStream()
    session.onStateChange = { stateContinuation.yield($0) }

    let runTask = Task { await session.run(sessionID: "session", prompt: "do something") }
    var iterator = states.makeAsyncIterator()
    #expect(await iterator.next() == .starting)

    session.enqueueTestEvent(.approvalRequest(managedApprovalRequest()))
    #expect(await iterator.next() == .needsYou(.approval))
    #expect(await session.respondApproval(sessionID: "session", choice: .once))
    #expect(!(await session.respondApproval(sessionID: "session", choice: .deny)))

    session.enqueueTestEvent(.activity("continuing"))
    #expect(await iterator.next() == .working)
    session.enqueueTestEvent(.messageComplete(MessageComplete(text: "done")))
    #expect(await iterator.next() == .success)
    _ = await runTask.value
}
