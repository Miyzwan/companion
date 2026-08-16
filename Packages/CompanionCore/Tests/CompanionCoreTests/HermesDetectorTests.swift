import Testing
import Foundation
@testable import CompanionCore

@Test func versionParsing() {
    #expect(HermesVersion(string: "Hermes Agent v0.18.0 (2026.7.1)") == HermesVersion(0, 18, 0))
    #expect(HermesVersion(string: "v0.18.0") == HermesVersion(0, 18, 0))
    #expect(HermesVersion(string: "0.18.0") == HermesVersion(0, 18, 0))
    #expect(HermesVersion(string: "garbage") == nil)
    #expect(HermesVersion(string: "") == nil)
}

@Test func versionComparisonIsNumeric() {
    #expect(HermesVersion(0, 9, 0) < HermesVersion(0, 10, 0))
    #expect(HermesVersion(0, 2, 0) < HermesVersion(0, 18, 0))
    #expect(HermesVersion(0, 18, 0) == HermesVersion(0, 18, 0))
    #expect(HermesVersion(0, 18, 1) > HermesVersion(0, 18, 0))
}

@Test func binaryResolution() {
    let exists: (String) -> Bool = { $0 == "/usr/local/bin/hermes" }
    #expect(HermesDetector.resolveBinary(in: ["/nonexistent", "/usr/local/bin/hermes"], exists: exists) == "/usr/local/bin/hermes")
    #expect(HermesDetector.resolveBinary(in: ["/nonexistent", "/also/missing"], exists: exists) == nil)
}

// T4.4-fix — app yang dilaunch dari Finder TIDAK mewarisi PATH shell
// (`launchctl getenv PATH` kosong → hanya /usr/bin:/bin:/usr/sbin:/sbin),
// sedangkan hermes terpasang di ~/.local/bin. Kandidat wajib memuat lokasi
// instalasi yang diketahui (Tech Design §2.1), bukan cuma isi PATH.

@Test func binaryCandidatesMendahulukanIsiPATH() {
    let candidates = HermesDetector.binaryCandidates(path: "/usr/bin:/opt/bin", home: "/Users/x")
    #expect(candidates.first == "/usr/bin/hermes")
    #expect(candidates[1] == "/opt/bin/hermes")
    #expect(candidates.contains("/Users/x/.local/bin/hermes"))
}

@Test func binaryCandidatesTetapAdaSaatPATHKosong() {
    // Kasus app GUI: PATH tidak diwariskan sama sekali.
    let candidates = HermesDetector.binaryCandidates(path: nil, home: "/Users/x")
    #expect(candidates.contains("/Users/x/.local/bin/hermes"))
    #expect(candidates.contains("/usr/local/bin/hermes"))
    #expect(candidates.contains("/opt/homebrew/bin/hermes"))
}

@Test func binaryCandidatesTidakDuplikatDanAbaikanEntriKosong() {
    let candidates = HermesDetector.binaryCandidates(path: "/Users/x/.local/bin::/usr/bin", home: "/Users/x")
    #expect(candidates.filter { $0 == "/Users/x/.local/bin/hermes" }.count == 1)
    #expect(candidates.allSatisfy { !$0.isEmpty && $0.hasPrefix("/") })
}

@Test func compatibilityClassification() {
    let detector = HermesDetector()
    #expect(detector.compatibility(for: HermesVersion(0, 18, 0)) == .supported(HermesVersion(0, 18, 0)))
    #expect(detector.compatibility(for: nil) == .missing)
    if case .unsupported(let found, let range) = detector.compatibility(for: HermesVersion(0, 17, 0)) {
        #expect(found == HermesVersion(0, 17, 0))
        #expect(range.contains(HermesVersion(0, 18, 0)))
    } else {
        Issue.record("expected unsupported")
    }
}
