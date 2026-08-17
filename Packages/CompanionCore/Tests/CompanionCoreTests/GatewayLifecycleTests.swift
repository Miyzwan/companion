import Testing
import Foundation
@testable import CompanionCore

@Test func spawnArgumentsMatchD3() {
    #expect(GatewayLifecycle.spawnArguments() == ["serve", "--skip-build", "--host", "127.0.0.1", "--port", "9119"])
}

@Test func wsURLFormat() {
    #expect(GatewayLifecycle.wsURL(token: "abc") == "ws://127.0.0.1:9119/api/ws?token=abc")
    #expect(GatewayLifecycle.wsURL(host: "localhost", port: 9999, token: "xyz") == "ws://localhost:9999/api/ws?token=xyz")
}

@Test func waitUntilReadyReturnsWhenProbeSucceeds() {
    var calls = 0
    let ready = GatewayLifecycle.waitUntilReady(
        timeout: 2, interval: 0.05,
        probe: { calls += 1; return calls >= 3 },
        isProcessAlive: { true })
    #expect(ready)
    #expect(calls == 3)
}

@Test func waitUntilReadyFailsWhenProcessDies() {
    let ready = GatewayLifecycle.waitUntilReady(
        timeout: 2, interval: 0.05,
        probe: { false },
        isProcessAlive: { false })
    #expect(!ready)
}

@Test func waitUntilReadyTimesOut() {
    let ready = GatewayLifecycle.waitUntilReady(
        timeout: 0.2, interval: 0.05,
        probe: { false },
        isProcessAlive: { true })
    #expect(!ready)
}

@Test func stopNonexistentPIDIsFalse() {
    #expect(!GatewayLifecycle.stopPID(999_999, grace: 0.1))
}

// ── T4.9 — log spawn tidak boleh tercampur sisa run lama ──

@Test func spawnMenulisLogDariNolBukanMenimpaSebagian() throws {
    // `FileHandle(forWritingTo:)` menulis dari offset 0 TANPA truncate: run baru
    // yang lebih pendek meninggalkan ekor log lama, dan ekor itu terbaca seolah
    // milik run sekarang (mis. pesan error yang sudah tidak relevan).
    let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("companion-spawn-log-\(UUID().uuidString).log")
    defer { try? FileManager.default.removeItem(at: logURL) }
    try String(repeating: "SISA LOG RUN LAMA\n", count: 20)
        .write(to: logURL, atomically: true, encoding: .utf8)

    // `/bin/echo` menggantikan hermes: yang diuji perilaku log, bukan servernya.
    let process = try GatewayLifecycle.spawnServer(
        arguments: ["halo"], logURL: logURL, sessionToken: "t", binaryPath: "/bin/echo")
    process.waitUntilExit()

    let written = try String(contentsOf: logURL, encoding: .utf8)
    #expect(written == "halo\n")
    #expect(!written.contains("SISA LOG RUN LAMA"))
}
