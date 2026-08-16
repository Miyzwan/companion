import Foundation

/// Versi Hermes, dibandingkan secara numerik (0.9.0 < 0.10.0).
public struct HermesVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parse dari output "Hermes Agent v0.18.0 (2026.7.1)" / "v0.18.0" / "0.18.0".
    /// Regex cari pola "v?<maj>.<min>.<patch>" pertama yang muncul.
    public init?(string: String) {
        let pattern = #"v?(\d+)\.(\d+)\.(\d+)"#
        guard let range = string.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = String(string[range])
        let parts = matched.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0].dropFirst(parts[0].first == "v" ? 1 : 0)),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else { return nil }
        self.init(major, minor, patch)
    }

    public static func < (lhs: HermesVersion, rhs: HermesVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// Klasifikasi kompatibilitas Hermes terhadap range yang didukung Companion.
public enum Compatibility: Equatable {
    case supported(HermesVersion)
    case missing
    case unsupported(found: HermesVersion, supported: ClosedRange<HermesVersion>)
}

/// Deteksi binary Hermes + versi + klasifikasi kompatibilitas.
public struct HermesDetector {
    /// Range yang didukung Product 0.1 (pin: v0.18.0, diverifikasi 2026-08-11).
    public static let defaultSupportedRange: ClosedRange<HermesVersion> = HermesVersion(0, 18, 0)...HermesVersion(0, 18, 999)

    public var supportedRange: ClosedRange<HermesVersion>

    public init(supportedRange: ClosedRange<HermesVersion> = HermesDetector.defaultSupportedRange) {
        self.supportedRange = supportedRange
    }

    /// Lokasi instalasi hermes yang diketahui, dipakai kalau PATH tidak memuatnya.
    /// `~/.local/bin` adalah lokasi wrapper resmi (Tech Design §2.1).
    static func knownInstallDirectories(home: String) -> [String] {
        ["\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin"]
    }

    /// Kandidat path absolut binary hermes, urut prioritas: isi PATH dulu, lalu
    /// lokasi instalasi yang diketahui. Murni.
    ///
    /// PENTING: app yang dilaunch dari Finder/`open` TIDAK mewarisi PATH shell —
    /// `launchctl getenv PATH` kosong, jadi child hanya dapat
    /// /usr/bin:/bin:/usr/sbin:/sbin dan `/usr/bin/env hermes` gagal
    /// ("env: hermes: No such file or directory"). Karena itu spawn WAJIB pakai
    /// path absolut hasil resolusi ini, bukan mengandalkan PATH.
    public static func binaryCandidates(path: String?, home: String) -> [String] {
        let fromPath = (path ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (fromPath + knownInstallDirectories(home: home))
            .filter { !$0.isEmpty && $0.hasPrefix("/") }
            .map { $0.hasSuffix("/") ? "\($0)hermes" : "\($0)/hermes" }
            .filter { seen.insert($0).inserted }
    }

    /// Ambil kandidat binary pertama yang benar-benar ada. Murni — `exists` di-inject.
    public static func resolveBinary(in candidates: [String], exists: (String) -> Bool) -> String? {
        candidates.first(where: exists)
    }

    /// Path absolut binary hermes di mesin ini, atau nil kalau tidak terpasang.
    /// Integration (menyentuh filesystem + environment).
    public static func resolvedBinaryPath() -> String? {
        resolveBinary(
            in: binaryCandidates(
                path: ProcessInfo.processInfo.environment["PATH"],
                home: NSHomeDirectory()),
            exists: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    /// Klasifikasi dari versi (nil = Hermes tidak terpasang). Murni.
    public func compatibility(for version: HermesVersion?) -> Compatibility {
        guard let version else { return .missing }
        if supportedRange.contains(version) {
            return .supported(version)
        }
        return .unsupported(found: version, supported: supportedRange)
    }

    /// Jalankan `hermes --version` dan parse hasilnya. Integration (spawn proses).
    public func detectVersion() -> HermesVersion? {
        guard let binary = Self.resolvedBinaryPath() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return HermesVersion(string: output)
    }
}
