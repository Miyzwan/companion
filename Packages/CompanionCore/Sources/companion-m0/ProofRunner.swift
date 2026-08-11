import Foundation
import CompanionCore

// T1.5/T1.6 — Proof runner: round trip Human-in-the-Loop (PRD section 78).
//   Working → approval.request → NeedsYou → approval.respond → Working → Success
//   clarify.request → clarify.respond → Working
// Menggabungkan TaskStateMachine + ApprovalGate + HermesAdapter, dan
// MENCETAK transisi state sebagai bukti. Choice/respon diprogram (CLI proof);
// bagian "human" UI menyusul di Milestone 2.
//
// Desain: onEvent hanya memasukkan TaskEvent ke AsyncStream (buffered);
// satu async task men-drain stream, menjalankan state machine, dan `await`
// respond langsung. Ini menghindari data-race strict-concurrency Swift 6.

enum ProofKind {
    case approval
    case clarify
}

/// Holder session_id (dibaca dari dalam onEvent filter + async task).
private final class SessionBox: @unchecked Sendable {
    var id: String?
}

/// Mutable state proof — dibungkus class supaya aman di-capture Task
/// (strict-concurrency Swift 6: var lokal yang di-capture + dibaca ulang
/// setelah task dimulai dianggap data race; box @unchecked Sendable menghindarinya).
private final class ProofState: @unchecked Sendable {
    var machine = TaskStateMachine(initial: .idle)
    var gate = ApprovalGate()
    var awaitingResume = false
    var approvalCount = 0
    var clarifyCount = 0
    var resolvedTotal = 0
    var finalSuccess = false
}

/// Attach kalau server milik kita UP, spawn kalau belum (D2).
/// Return (pid spawned?, token) — pid nil kalau attach ke server milik kita.
func attachOrSpawn() -> (Int32?, String)? {
    let up = GatewayLifecycle.probe(host: GatewayLifecycle.defaultHost,
                                    port: GatewayLifecycle.defaultPort, timeout: 1)
    if up {
        guard let t = readToken() else {
            print("server UP tapi token tidak diketahui (bukan spawn kita) — serve-stop dulu kalau milik kita (D2)")
            return nil
        }
        return (nil, t)
    }
    let token = UUID().uuidString
    do {
        let p = try GatewayLifecycle.spawnServer(
            arguments: GatewayLifecycle.spawnArguments(),
            logURL: URL(fileURLWithPath: logFile),
            sessionToken: token)
        let pid = p.processIdentifier
        try String(pid).write(toFile: pidFile, atomically: true, encoding: .utf8)
        try token.write(toFile: tokenFile, atomically: true, encoding: .utf8)
        let ready = GatewayLifecycle.waitUntilReady(
            timeout: 30, interval: 0.5,
            probe: { GatewayLifecycle.probe(host: GatewayLifecycle.defaultHost,
                                            port: GatewayLifecycle.defaultPort, timeout: 0.5) },
            isProcessAlive: { GatewayLifecycle.processAlive(pid) })
        guard ready else {
            print("server tidak ready 30s — cek \(logFile)")
            return nil
        }
        return (pid, token)
    } catch {
        print("spawn gagal: \(error)")
        return nil
    }
}

func runProof(kind: ProofKind, prompt: String) {
    guard let (spawned, token) = attachOrSpawn() else { return }
    defer { cleanupSpawned(spawned) }

    let timeout = 120
    let done = DispatchSemaphore(value: 0)
    let sessionBox = SessionBox()
    let frameFile = "/tmp/companion-m1-frames.jsonl"
    var frameHandle: FileHandle?
    if let f = FileHandle(forWritingAtPath: frameFile) {
        f.seekToEndOfFile()
        frameHandle = f
    } else {
        FileManager.default.createFile(atPath: frameFile, contents: nil)
        frameHandle = FileHandle(forWritingAtPath: frameFile)
    }

    // onEvent → AsyncStream buffered TaskEvent (pakai EventDecoder, non-blocking).
    let url = URL(string: GatewayLifecycle.wsURL(token: token))!
    let (stream, continuation) = AsyncStream<TaskEvent>.makeStream()
    let client = JSONRPCClient(url: url) { env in
        if let sid = env.params?.session_id, let known = sessionBox.id, sid != known { return }
        if let ev = EventDecoder.decode(env) {
            continuation.yield(ev)
        }
    }
    client.onRawFrame = { (raw: String) in
        if let h = frameHandle, let d = (raw + "\n").data(using: .utf8) {
            h.write(d)
        }
    }
    client.connect()

    let adapter = HermesAdapter(client: client)
    let sid: String
    do {
        sid = try awaitSync { try await adapter.createSession(cwd: FileManager.default.currentDirectoryPath) }
        sessionBox.id = sid
        try awaitSync { try await adapter.submitPrompt(sessionID: sid, text: prompt) }
    } catch {
        print("  ✗ \(error)")
        client.close()
        return
    }
    print("session \(sid) — prompt: \(prompt)")

    // Async loop: state machine + exactly-once + respond (await-able).
    let state = ProofState()
    _ = state.machine.transition(to: .starting)
    print("  ⬇ state: \(stateLabel(state.machine.state))")

    Task {
        for await ev in stream {
            let before = state.machine.state
            switch ev {
            case .ready, .activity, .messageDelta, .toolStarted, .toolCompleted:
                if state.machine.state == .starting { _ = state.machine.transition(to: .working) }
                if state.awaitingResume { _ = state.machine.transition(to: .working); state.awaitingResume = false }

            case .approvalRequest(let req):
                _ = state.machine.transition(to: .needsYou(.approval))
                state.gate.register(req)
                print("  ⚠ NEEDS YOU (approval) · pattern: \(req.patternKey)")
                print("    command: \(req.command)")
                if req.allowPermanent { print("    (allow_permanent: true → choice \"always\" tersedia)") }

                if case .approval = kind {
                    // Exactly-once (PRD 51): gate memungkinkan SATU kiriman.
                    let r1 = state.gate.respond(.once)
                    let r2 = state.gate.respond(.once)   // double click / retry → DITOLAK
                    if r1 {
                        state.approvalCount += 1
                        state.awaitingResume = true
                        print("  → approval.respond(choice: .once) — dikirim")
                        print(r2 ? "  ✗ [BUG] respond kedua lolos gate!" : "  → [exactly-once] respond kedua DITOLAK gate")
                        do {
                            let n = try await adapter.respondApproval(sessionID: sid, choice: .once)
                            state.resolvedTotal += n
                            print("  ← server: resolved=\(n)")
                        } catch {
                            print("  ✗ respondApproval gagal: \(error)")
                            done.signal()
                        }
                    }
                }

            case .clarifyRequest(let req):
                _ = state.machine.transition(to: .needsYou(.clarification))
                print("  ⚠ NEEDS YOU (clarify) · request_id: \(req.requestId)")
                print("    question: \(req.question)")
                if !req.choices.isEmpty { print("    choices: \(req.choices.joined(separator: " | "))") }

                if case .clarify = kind {
                    let answer = req.choices.first ?? "Lanjutkan"
                    state.clarifyCount += 1
                    state.awaitingResume = true
                    print("  → clarify.respond(answer: \"\(answer)\") — dikirim")
                    do {
                        let accepted = try await adapter.respondClarify(sessionID: sid, requestID: req.requestId, answer: answer)
                        print(accepted ? "  ← server: ok (diterima)" : "  ← server: 4009 no pending (stale?)")
                    } catch {
                        print("  ✗ respondClarify gagal: \(error)")
                        done.signal()
                    }
                }

            case .messageComplete:
                if case .needsYou = state.machine.state {
                    print("  ⚠ [anomali] message.complete saat masih NeedsYou — seharusnya tidak terjadi")
                }
                _ = state.machine.transition(to: .success)
                state.gate.invalidate()               // PRD 52: approval lama non-interaktif
                state.finalSuccess = true
                done.signal()

            case .failure(let msg):
                _ = state.machine.transition(to: .error)
                print("  ✗ error event: \(msg)")
                done.signal()

            default:
                break
            }
            if state.machine.state != before {
                print("  ⬇ state: \(stateLabel(before)) → \(stateLabel(state.machine.state))")
            }
            if state.finalSuccess { break }
        }
        continuation.finish()
        if !state.finalSuccess {
            // Stream habis tanpa terminal state (mis. WS tertutup).
            print("  ⬇ (connection ended tanpa terminal state)")
            done.signal()
        }
    }

    _ = done.wait(timeout: .now() + Double(timeout))
    client.close()
    frameHandle?.closeFile()

    print("---")
    print("hasil: \(state.finalSuccess ? "SUCCESS ✅" : "tidak selesai (timeout \(timeout)s)")")
    print("approval.request diterima : \(state.approvalCount)")
    print("approval ter-resolve      : \(state.resolvedTotal)")
    print("clarify.request diterima  : \(state.clarifyCount)")
    print("state akhir               : \(stateLabel(state.machine.state))")
}

func stateLabel(_ s: TaskState) -> String {
    switch s {
    case .idle: return "idle"
    case .starting: return "starting"
    case .working: return "working"
    case .needsYou(let c): return "needsYou(.\(c.rawValue))"
    case .success: return "success"
    case .error: return "error"
    case .stopping: return "stopping"
    case .disconnected: return "disconnected"
    }
}