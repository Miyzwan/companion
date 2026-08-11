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
