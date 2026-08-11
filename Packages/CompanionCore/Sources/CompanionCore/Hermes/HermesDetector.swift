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

    /// Ambil kandidat binary pertama yang benar-benar ada. Murni — `exists` di-inject.
    public static func resolveBinary(in candidates: [String], exists: (String) -> Bool) -> String? {
        candidates.first(where: exists)
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["hermes", "--version"]
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
