import Foundation
import CompanionCore

// companion-m0 — CLI driver untuk Milestone 0 (Gateway Proof).
// Usage:
//   companion-m0 doctor   → deteksi Hermes + versi + kompatibilitas

let args = CommandLine.arguments

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

if args.count >= 2 && args[1] == "doctor" {
    doctor()
} else {
    print("usage: companion-m0 doctor")
}
