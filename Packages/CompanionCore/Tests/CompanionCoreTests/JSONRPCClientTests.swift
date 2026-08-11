import Testing
import Foundation
@testable import CompanionCore

@Test func classifyGatewayReadyAsEvent() throws {
    let frame = #"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"skin":{}}}}"#
    let kind = JSONRPCClient.classify(frame)
    guard case .event(let env) = kind else { Issue.record("expected event"); return }
    #expect(env.params?.type == "gateway.ready")
    #expect(env.params?.session_id == nil)
}

@Test func classifyResponse() throws {
    let frame = #"{"jsonrpc":"2.0","id":3,"result":{"session_id":"abc12345"}}"#
    let kind = JSONRPCClient.classify(frame)
    guard case .response(let resp) = kind else { Issue.record("expected response"); return }
    #expect(resp.id == 3)
    #expect(resp.error == nil)
}

@Test func classifyErrorResponse() throws {
    let frame = #"{"jsonrpc":"2.0","id":7,"error":{"code":4090,"message":"too many sessions"}}"#
    let kind = JSONRPCClient.classify(frame)
    guard case .response(let resp) = kind else { Issue.record("expected response"); return }
    #expect(resp.error?.code == 4090)
}

@Test func classifyGarbageAsUnknown() {
    #expect(JSONRPCClient.classify("not json at all") == .unknown)
    #expect(JSONRPCClient.classify("") == .unknown)
}
