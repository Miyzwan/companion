import Testing
import Foundation
@testable import CompanionCore

@Test func requestEncoding() throws {
    let req = JSONRPCRequest(id: 1, method: "session.create", params: ["cwd": "/tmp"])
    let data = try JSONEncoder().encode(req)
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(obj["jsonrpc"] as? String == "2.0")
    #expect(obj["id"] as? Int == 1)
    #expect(obj["method"] as? String == "session.create")
    #expect((obj["params"] as? [String: Any])?["cwd"] as? String == "/tmp")
}

@Test func idGeneratorIncrements() {
    var gen = JSONRPCIDGenerator()
    #expect(gen.nextID() == 1)
    #expect(gen.nextID() == 2)
    #expect(gen.nextID() == 3)
}

@Test func responseDecoding() throws {
    let json = #"{"jsonrpc":"2.0","id":5,"result":{"session_id":"abc12345"}}"#
    let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(json.utf8))
    #expect(resp.id == 5)
    #expect(resp.result == .object(["session_id": .string("abc12345")]))
    #expect(resp.error == nil)
}

@Test func errorDecoding() throws {
    let json = #"{"jsonrpc":"2.0","id":7,"error":{"code":4090,"message":"too many sessions"}}"#
    let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(json.utf8))
    #expect(resp.error?.code == 4090)
    #expect(resp.error?.message == "too many sessions")
    #expect(resp.result == nil)
}

@Test func eventEnvelopeDecoding() throws {
    let json = #"{"jsonrpc":"2.0","method":"event","params":{"type":"status.update","session_id":"ab12cd34","payload":{"kind":"status","text":"Reading files"}}}"#
    let env = try JSONDecoder().decode(JSONRPCEnvelope.self, from: Data(json.utf8))
    #expect(env.method == "event")
    #expect(env.params?.type == "status.update")
    #expect(env.params?.session_id == "ab12cd34")
    #expect(env.params?.payload == .object(["kind": .string("status"), "text": .string("Reading files")]))
}
