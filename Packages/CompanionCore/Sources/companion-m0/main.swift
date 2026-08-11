import Foundation
import CompanionCore

// companion-m0 — CLI driver untuk Milestone 0 (Gateway Proof).
// Usage:
//   companion-m0 doctor            → deteksi Hermes + versi + kompatibilitas
//   companion-m0 serve-status      → probe port 9119 (UP = attach, DOWN = spawn dibutuhkan)
//   companion-m0 serve-spawn       → spawn `hermes serve --skip-build` (kalau belum UP)
//   companion-m0 serve-stop        → stop server MILIK companion saja (via PID file)
//   companion-m0 ws-spike          → SPIKE: konek WS + dump frame mentah (observasi protocol)

let args = CommandLine.arguments

let pidFile = "/tmp/companion-serve.pid"
let tokenFile = "/tmp/companion-serve.token"
let logFile = "/tmp/companion-serve.log"

func versionText(_ v: HermesVersion) -> String {
    "\(v.major).\(v.minor).\(v.patch)"
}

func readPID() -> Int32? {
    guard let raw = try? String(contentsOfFile: pidFile, encoding: .utf8) else { return nil }
    return Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines))
}

func readToken() -> String? {
    guard let raw = try? String(contentsOfFile: tokenFile, encoding: .utf8) else { return nil }
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
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
        let token = UUID().uuidString
        let process = try GatewayLifecycle.spawnServer(
            arguments: GatewayLifecycle.spawnArguments(),
            logURL: URL(fileURLWithPath: logFile),
            sessionToken: token)
        let pid = process.processIdentifier
        try String(pid).write(toFile: pidFile, atomically: true, encoding: .utf8)
        try token.write(toFile: tokenFile, atomically: true, encoding: .utf8)
        let ready = GatewayLifecycle.waitUntilReady(
            timeout: 30, interval: 0.5,
            probe: {
                GatewayLifecycle.probe(host: GatewayLifecycle.defaultHost, port: GatewayLifecycle.defaultPort, timeout: 0.5)
            },
            isProcessAlive: { GatewayLifecycle.processAlive(pid) })
        print(ready
            ? "spawned pid \(pid) — READY"
            : "spawned pid \(pid) — BELUM ready 30s; cek \(logFile)")
    } catch {
        print("spawn gagal: \(error)")
    }
}

func serveStop() {
    guard let pid = readPID() else {
        print("tidak ada server milik companion (PID file tidak ada) — aman, tidak ada yang dihentikan")
        return
    }
    if GatewayLifecycle.stopPID(pid, grace: 3) {
        try? FileManager.default.removeItem(atPath: pidFile)
        try? FileManager.default.removeItem(atPath: tokenFile)
        print("server pid \(pid) dihentikan")
    } else {
        print("pid \(pid) tidak berhasil dihentikan — cek manual")
    }
}

/// SPIKE T0.5 — observasi protocol WS: auth?, event pertama, waktu boot.
func wsSpike(duration: TimeInterval = 5) {
    var spawned: Int32?
    var token: String

    let alreadyUp = GatewayLifecycle.probe(
        host: GatewayLifecycle.defaultHost, port: GatewayLifecycle.defaultPort, timeout: 1)
    if alreadyUp {
        guard let t = readToken() else {
            print("[spike] server UP tapi token tidak diketahui (bukan spawn kita) — tidak bisa attach (D2). serve-stop dulu kalau ada milik kita, lalu spawn ulang.")
            return
        }
        token = t
        print("[spike] server sudah UP — attach dengan token milik kita")
    } else {
        let t0 = Date()
        do {
            token = UUID().uuidString
            let p = try GatewayLifecycle.spawnServer(
                arguments: GatewayLifecycle.spawnArguments(),
                logURL: URL(fileURLWithPath: logFile),
                sessionToken: token)
            let pid = p.processIdentifier
            try String(pid).write(toFile: pidFile, atomically: true, encoding: .utf8)
            try token.write(toFile: tokenFile, atomically: true, encoding: .utf8)
            let ready = GatewayLifecycle.waitUntilReady(
                timeout: 30, interval: 0.5,
                probe: {
                    GatewayLifecycle.probe(host: GatewayLifecycle.defaultHost, port: GatewayLifecycle.defaultPort, timeout: 0.5)
                },
                isProcessAlive: { GatewayLifecycle.processAlive(pid) })
            let boot = Date().timeIntervalSince(t0)
            print("[spike] spawn pid \(pid) — ready=\(ready ? "YA" : "TIDAK") — boot \(String(format: "%.1f", boot))s")
            spawned = pid
        } catch {
            print("[spike] spawn gagal: \(error)")
            return
        }
    }

    // Konek WS + dump frame mentah.
    let url = URL(string: GatewayLifecycle.wsURL(token: token))!
    let task = URLSession.shared.webSocketTask(with: url)
    func recv() {
        task.receive { result in
            switch result {
            case .success(let m):
                switch m {
                case .string(let s): print("<< \(s)")
                case .data(let d): print("<< data \(String(data: d, encoding: .utf8) ?? "<bin>")")
                @unknown default: print("<< unknown")
                }
                recv()
            case .failure(let e):
                print("[spike] receive/connect error: \(e.localizedDescription)")
            }
        }
    }
    print("[spike] connect \(url.absoluteString)...")
    task.resume()
    recv()
    Thread.sleep(forTimeInterval: duration)
    task.cancel()
    print("[spike] selesai (\(duration)s dump)")

    if let pid = spawned {
        _ = GatewayLifecycle.stopPID(pid, grace: 3)
        try? FileManager.default.removeItem(atPath: pidFile)
        try? FileManager.default.removeItem(atPath: tokenFile)
        print("[spike] server spawned (pid \(pid)) dibersihkan")
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
case "ws-spike":
    wsSpike()
default:
    print("usage: companion-m0 [doctor | serve-status | serve-spawn | serve-stop | ws-spike]")
}