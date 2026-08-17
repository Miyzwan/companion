import Foundation
import Network

/// Lifecycle server Hermes: attach kalau sudah ada, spawn kalau belum (D2).
public struct GatewayLifecycle {
    public static let defaultHost = "127.0.0.1"
    public static let defaultPort = 9119

    /// URL WebSocket ke gateway (D1), dengan auth token (diverifikasi T0.5:
    /// loopback butuh `?token=<_SESSION_TOKEN>`, constant-time dibanding di `_ws_auth_reason`).
    public static func wsURL(host: String = defaultHost, port: Int = defaultPort, token: String) -> String {
        "ws://\(host):\(port)/api/ws?token=\(token)"
    }

    /// Argumen spawn `hermes serve` (D3): skip web build, bind lokal.
    public static func spawnArguments(host: String = defaultHost, port: Int = defaultPort) -> [String] {
        ["serve", "--skip-build", "--host", host, "--port", String(port)]
    }

    public enum SpawnError: Error, Equatable {
        case hermesNotFound
    }

    /// Spawn `hermes serve` sebagai child process; stdout/stderr ke log file,
    /// dan inject `HERMES_DASHBOARD_SESSION_TOKEN` (token inilah yang dipakai WS auth).
    /// Integration — hanya dipanggil setelah probe gagal (attach-first).
    ///
    /// Binary dipanggil lewat PATH ABSOLUT hasil `HermesDetector.resolvedBinaryPath()`,
    /// BUKAN `/usr/bin/env hermes`: app yang dilaunch dari Finder tidak mewarisi PATH
    /// shell, sehingga `env hermes` gagal walau hermes terpasang di ~/.local/bin.
    public static func spawnServer(arguments: [String], logURL: URL, sessionToken: String,
                                   binaryPath: String? = nil) throws -> Process {
        guard let binary = binaryPath ?? HermesDetector.resolvedBinaryPath() else {
            try? "companion: binary `hermes` tidak ditemukan di PATH maupun lokasi instalasi yang dikenal\n"
                .write(to: logURL, atomically: true, encoding: .utf8)
            throw SpawnError.hermesNotFound
        }
        // T4.9 — log SELALU dimulai dari nol. `FileHandle(forWritingTo:)` menulis
        // dari offset 0 TANPA truncate, jadi run baru yang lebih pendek akan
        // menyisakan ekor log run lama — dan ekor itu terbaca seolah milik run
        // sekarang saat kita menyuruh user "cek /tmp/companion-serve.log".
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        // MERGE env, jangan replace — child butuh PATH/HOME dsb; kita cuma nambah token.
        var env = ProcessInfo.processInfo.environment
        env["HERMES_DASHBOARD_SESSION_TOKEN"] = sessionToken
        // Folder binary ikut dimasukkan ke PATH child supaya proses turunan hermes
        // tetap menemukan tetangganya walau PATH warisan minim (kasus app GUI).
        let binDir = (binary as NSString).deletingLastPathComponent
        env["PATH"] = ([binDir] + (env["PATH"]?.split(separator: ":").map(String.init) ?? []))
            .joined(separator: ":")
        process.environment = env
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        return process
    }

    /// Probe TCP nyata: apakah ada yang listening di host:port? (timeout via Network framework)
    public static func probe(host: String, port: Int, timeout: TimeInterval) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        final class ProbeBox: @unchecked Sendable { var ok = false }
        let box = ProbeBox()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                box.ok = true
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: .global())
        _ = semaphore.wait(timeout: .now() + timeout)
        connection.cancel()
        return box.ok
    }

    /// Tunggu sampai probe sukses, proses mati, atau timeout. Murni — probe & alive di-inject.
    public static func waitUntilReady(
        timeout: TimeInterval,
        interval: TimeInterval,
        probe: () -> Bool,
        isProcessAlive: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if probe() { return true }
            if !isProcessAlive() { return false }
            Thread.sleep(forTimeInterval: interval)
        }
        return probe()
    }

    /// Apakah proses dengan PID ini masih hidup? (kill 0; EPERM = hidup tapi bukan punya kita)
    public static func processAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Hentikan proses via SIGTERM; kalau grace habis → SIGKILL. Return true kalau akhirnya mati.
    public static func stopPID(_ pid: Int32, grace: TimeInterval) -> Bool {
        guard processAlive(pid) else { return false }
        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            if !processAlive(pid) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        kill(pid, SIGKILL)
        Thread.sleep(forTimeInterval: 0.05)
        return !processAlive(pid)
    }

    /// Attach-first, spawn-second (D2) — satu sumber kebenaran untuk CLI & app.
    /// Return nil = gagal total (spawn/ready timeout). (nil, nil) = server UP
    /// tapi token tidak diketahui (bukan spawn kita). (nil, token) = attach.
    /// (pid, token) = spawned + ready (pid wajib di-stop pemanggil saat selesai).
    public static func attachOrSpawn(logURL: URL, pidURL: URL, tokenURL: URL) -> (pid: Int32?, token: String?)? {
        if probe(host: defaultHost, port: defaultPort, timeout: 1) {
            guard let t = readToken(from: tokenURL) else { return (nil, nil) }
            return (nil, t)
        }
        let token = UUID().uuidString
        do {
            let p = try spawnServer(arguments: spawnArguments(), logURL: logURL, sessionToken: token)
            let pid = p.processIdentifier
            try String(pid).write(to: pidURL, atomically: true, encoding: .utf8)
            try token.write(to: tokenURL, atomically: true, encoding: .utf8)
            let ready = waitUntilReady(
                timeout: 30, interval: 0.5,
                probe: { probe(host: defaultHost, port: defaultPort, timeout: 0.5) },
                isProcessAlive: { processAlive(pid) })
            guard ready else { return nil }
            return (pid, token)
        } catch {
            return nil
        }
    }

    private static func readToken(from url: URL) -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
