import Foundation

/// Nilai JSON fleksibel buat payload/result yang bentuknya belum kita ketahui.
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "unexpected JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// Request JSON-RPC 2.0: {"jsonrpc":"2.0","id":N,"method":"...","params":{...}}
struct JSONRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: Params
}

/// Response JSON-RPC 2.0: {"jsonrpc":"2.0","id":N,"result":{...}} ATAU error.
struct JSONRPCResponse: Decodable {
    let id: Int
    let result: JSONValue?
    let error: JSONRPCError?
}

struct JSONRPCError: Decodable, Equatable {
    let code: Int
    let message: String
}

/// Event dari server: {"jsonrpc":"2.0","method":"event","params":{"type":"...","session_id":"...","payload":{...}}}
struct JSONRPCEnvelope: Decodable {
    let jsonrpc: String
    let id: Int?
    let method: String?
    let params: EventParams?
}

struct EventParams: Decodable {
    let type: String
    let session_id: String
    let payload: JSONValue?
}

/// Pemberi id otomatis (1, 2, 3, ...) — biar tiap request punya id unik.
struct JSONRPCIDGenerator {
    private var next = 0
    mutating func nextID() -> Int {
        next += 1
        return next
    }
}
