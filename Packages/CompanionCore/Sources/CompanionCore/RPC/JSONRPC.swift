import Foundation

/// Nilai JSON fleksibel buat payload/result yang bentuknya belum kita ketahui.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "unexpected JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
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
public struct JSONRPCRequest<Params: Encodable>: Encodable {
    public let jsonrpc: String = "2.0"
    public let id: Int
    public let method: String
    public let params: Params

    public init(id: Int, method: String, params: Params) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// Response JSON-RPC 2.0: {"jsonrpc":"2.0","id":N,"result":{...}} ATAU error.
public struct JSONRPCResponse: Decodable, Equatable, Sendable {
    public let id: Int
    public let result: JSONValue?
    public let error: JSONRPCError?
}

public struct JSONRPCError: Decodable, Equatable, Sendable {
    public let code: Int
    public let message: String
}

/// Event dari server: {"jsonrpc":"2.0","method":"event","params":{"type":"...","session_id":"...","payload":{...}}}
public struct JSONRPCEnvelope: Decodable, Equatable, Sendable {
    public let jsonrpc: String
    public let id: Int?
    public let method: String?
    public let params: EventParams?
}

public struct EventParams: Decodable, Equatable, Sendable {
    public let type: String
    /// OPTIONAL — frame `gateway.ready` TIDAK membawa session_id (diverifikasi spike T0.5).
    public let session_id: String?
    public let payload: JSONValue?
}

/// Pemberi id otomatis (1, 2, 3, ...) — biar tiap request punya id unik.
public struct JSONRPCIDGenerator {
    private var next = 0
    public init() {}
    public mutating func nextID() -> Int {
        next += 1
        return next
    }
}

// Convenience accessor JSONValue — dipakai decoder/domain (T1.2).
public extension JSONValue {
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var number: Double? { if case .number(let n) = self { return n }; return nil }
    var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    subscript(key: String) -> JSONValue? { object?[key] }
}
