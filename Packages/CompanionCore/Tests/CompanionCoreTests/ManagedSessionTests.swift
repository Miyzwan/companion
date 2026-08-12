import Testing
@testable import CompanionCore

private final class FakeManagedSessionAdapter: ManagedSessionAdapter, @unchecked Sendable {
    private(set) var approvalChoices: [ApprovalChoice] = []
    private(set) var clarificationAnswers: [(String, String)] = []

    func submitPrompt(sessionID: String, text: String) async throws {}

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
