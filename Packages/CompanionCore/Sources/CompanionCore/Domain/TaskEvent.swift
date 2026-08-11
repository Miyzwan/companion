import Foundation

// T1.2 — Domain events (PRD section 22-23, 30, 9).
// Tipe domain MURNI — tidak ada string protocol Hermes di sini (D5).
// String Hermes hidup di Hermes/EventDecoder.swift.

public struct ToolInfo: Equatable, Sendable {
    public let toolId: String
    public let name: String
}

public struct MessageComplete: Equatable, Sendable {
    public let text: String
}

/// Approval yang diminta gateway (PRD section 29/50): `approval.request`.
public struct ApprovalRequest: Equatable, Sendable {
    public let command: String
    public let patternKey: String
    public let patternKeys: [String]
    public let description: String
    public let allowPermanent: Bool
}

/// Clarification yang diminta gateway (PRD section 53): `clarify.request`.
public struct ClarifyRequest: Equatable, Sendable {
    public let requestId: String
    public let question: String
    public let choices: [String]
}

/// Event domain — hasil normalisasi event protocol (PRD section 36).
public enum TaskEvent: Equatable, Sendable {
    case ready
    case activity(String)
    case messageDelta(String)
    case messageComplete(MessageComplete)
    case toolStarted(ToolInfo)
    case toolCompleted(ToolInfo, duration: Double?)
    case approvalRequest(ApprovalRequest)
    case clarifyRequest(ClarifyRequest)
    case failure(String)
}
