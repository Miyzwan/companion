import Foundation
import Network

/// Lifecycle server Hermes: attach kalau sudah ada, spawn kalau belum (D2).
public struct GatewayLifecycle {
    public static let defaultHost = "127.0.0.1"
    public static let defaultPort = 9119

    /// URL WebSocket ke gateway (D1).
    public static func wsURL(host: String = defaultHost, port: Int = defaultPort) -> String {
        "ws://\(host):\(port)/api/ws"
    }

    /// Argumen spawn `hermes serve` (D3): skip web build, bind lokal.
    public static func spawnArguments(host: String = defaultHost, port: Int = defaultPort) -> [String] {
        ["serve", "--skip-build", "--host", host, "--port", String(port)]
    }

    /// Spawn `hermes serve` sebagai child process; stdout/stderr ke log file.
    /// Integration — hanya dipanggil setelah probe gagal (attach-first).
    public static func spawnServer(arguments: [String], logURL: URL) throws -> Process {
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["hermes"] + arguments
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
}
