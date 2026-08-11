import Testing
import Foundation
@testable import CompanionCore

// Contract tests (PRD section 12): frame NYATA yang direkam dari gateway (T0.7).
// Kalau Hermes update dan bentuk payload berubah, test ini yang nangkap duluan.

func decodeFixture(_ name: String) throws -> JSONRPCEnvelope {
    // Path dihitung dari lokasi file test ini — robust tanpa Bundle.module.
    let thisFile = URL(fileURLWithPath: #filePath)
    let fixturesDir = thisFile.deletingLastPathComponent().appendingPathComponent("Fixtures")
    let url = fixturesDir.appendingPathComponent(name + ".jsonl")
    let line = try String(contentsOf: url, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return try JSONDecoder().decode(JSONRPCEnvelope.self, from: Data(line.utf8))
}

@Test func fixtureToolStartDecodes() throws {
    let env = try decodeFixture("tool-start-write_file")
    #expect(env.params?.type == "tool.start")
    guard case .object(let o)? = env.params?.payload else { Issue.record("payload bukan object"); return }
    #expect(o["name"] == .string("write_file"))
    guard case .string(let toolID)? = o["tool_id"] else { Issue.record("tool_id hilang"); return }
    #expect(toolID.hasPrefix("call_"))
}

@Test func fixtureToolCompleteDecodes() throws {
    let env = try decodeFixture("tool-complete-write_file")
    #expect(env.params?.type == "tool.complete")
    guard case .object(let o)? = env.params?.payload else { Issue.record("payload bukan object"); return }
    #expect(o["name"] == .string("write_file"))
    #expect(o["duration_s"] != nil)
    #expect(o["args"] != nil)
    #expect(o["result"] != nil)
}

@Test func fixtureToolGeneratingDecodes() throws {
    let env = try decodeFixture("tool-generating-write_file")
    #expect(env.params?.type == "tool.generating")
    guard case .object(let o)? = env.params?.payload else { Issue.record("payload bukan object"); return }
    #expect(o["name"] == .string("write_file"))
}

@Test func fixtureApprovalRequestDecodes() throws {
    // Frame emas buat M1: payload approval asli dari gateway.
    let env = try decodeFixture("approval-request-delete-root")
    #expect(env.params?.type == "approval.request")
    guard case .object(let o)? = env.params?.payload else { Issue.record("payload bukan object"); return }
    guard case .string(let cmd)? = o["command"] else { Issue.record("command hilang"); return }
    #expect(cmd.contains("rm "))
    #expect(o["pattern_key"] == .string("delete in root path"))
    #expect(o["allow_permanent"] == .bool(true))
}
