import Foundation
import CompanionCore

// companion-m0 — CLI driver untuk Milestone 0 (Gateway Proof).
// Usage:
//   companion-m0 doctor            → deteksi Hermes + versi + kompatibilitas
//   companion-m0 serve-status      → probe port 9119 (UP = attach, DOWN = spawn dibutuhkan)
//   companion-m0 serve-spawn       → spawn `hermes serve --skip-build` (kalau belum UP)
//   companion-m0 serve-stop        → stop server MILIK companion saja (via PID file)

let args = CommandLine.arguments

let pidFile = "/tmp/companion-serve.pid"
let logFile = "/tmp/companion-serve.log"

func versionText(_ v: HermesVersion) -> String {
    "\(v.major).\(v.minor).\(v.patch)"
}

func doctor() {
    let detector = HermesDetector()
    guard let version = detector.detectVersion() else {
        print("Hermes — missing (tidak ditemukan di PATH)")
        return
    }
    switch detector.compatibility(for: version) {
    case .supported:
        print("Hermes v\(versionText(version)) — Supported")
    case .missing:
        print("Hermes v\(versionText(version)) — missing")
    case .unsupported(let found, let range):
        print("Hermes v\(versionText(found)) — Unsupported (supported: \(versionText(range.lowerBound))...\(versionText(range.upperBound)))")
    }
}

func serveStatus() {
    let up = GatewayLifecycle.probe(
        host: GatewayLifecycle.defaultHost, port: GatewayLifecycle.defaultPort, timeout: 1)
    print(up
        ? "server \(GatewayLifecycle.defaultHost):\(GatewayLifecycle.defaultPort) — UP (attach)"
        : "server \(GatewayLifecycle.defaultHost):\(GatewayLifecycle.defaultPort) — DOWN (spawn dibutuhkan)")
}

func serveSpawn() {
    if GatewayLifecycle.probe(host: GatewayLifecycle.defaultHost, port: GatewayLifecycle.defaultPort, timeout: 1) {
        print("sudah UP — tidak spawn (attach saja)")
        return
    }
    do {
        let process = try GatewayLifecycle.spawnServer(
            arguments: GatewayLifecycle.spawnArguments(),
            logURL: URL(fileURLWithPath: logFile))
        let pid = process.processIdentifier
        try String(pid).write(toFile: pidFile, atomically: true, encoding: .utf8)
        let ready = GatewayLifecycle.waitUntilReady(
            timeout: 30, interval: 0.5,
            probe: {
                GatewayLifecycle.probe(host: GatewayLifecycle.defaultHost, port: GatewayLifecycle.defaultPort, timeout: 0.5)
            },
            isProcessAlive: { GatewayLifecycle.processAlive(pid) })
        print(ready
            ? "spawned pid \(pid) — READY (ws://127.0.0.1:9119/api/ws)"
            : "spawned pid \(pid) — BELUM ready 30s; cek \(logFile)")
    } catch {
        print("spawn gagal: \(error)")
    }
}

func serveStop() {
    guard let raw = try? String(contentsOfFile: pidFile, encoding: .utf8),
          let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        print("tidak ada server milik companion (PID file tidak ada) — aman, tidak ada yang dihentikan")
        return
    }
    if GatewayLifecycle.stopPID(pid, grace: 3) {
        try? FileManager.default.removeItem(atPath: pidFile)
        print("server pid \(pid) dihentikan")
    } else {
        print("pid \(pid) tidak berhasil dihentikan — cek manual")
    }
}

switch args.count >= 2 ? args[1] : "" {
case "doctor":
    doctor()
case "serve-status":
    serveStatus()
case "serve-spawn":
    serveSpawn()
case "serve-stop":
    serveStop()
default:
    print("usage: companion-m0 [doctor | serve-status | serve-spawn | serve-stop]")
}
