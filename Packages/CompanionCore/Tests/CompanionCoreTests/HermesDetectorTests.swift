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
