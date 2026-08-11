import Foundation

// T1.2 — EventDecoder: JSONRPCEnvelope (protocol Hermes) → TaskEvent (domain).
// Satu-satunya tempat (selain HermesAdapter) yang tahu string event Hermes (D5).

public enum EventDecoder {
    /// Decode envelope → TaskEvent. Event tak dikenal → nil (jangan crash, PRD 36).
    public static func decode(_ envelope: JSONRPCEnvelope) -> TaskEvent? {
        guard let params = envelope.params else { return nil }
        let payload = params.payload
        switch params.type {
        case "status.update":
            guard let p = payload else { return nil }
            if p["kind"]?.string == "ready" { return .ready }
            guard let text = p["text"]?.string else { return nil }
            return .activity(text)
        case "message.delta":
            guard let text = payload?["text"]?.string else { return nil }
            return .messageDelta(text)
        case "message.complete":
            guard let text = payload?["text"]?.string else { return nil }
            return .messageComplete(MessageComplete(text: text))
        case "tool.start":
            guard let p = payload, let name = p["name"]?.string,
                  let toolId = p["tool_id"]?.string else { return nil }
            return .toolStarted(ToolInfo(toolId: toolId, name: name))
        case "tool.complete":
            guard let p = payload, let name = p["name"]?.string,
                  let toolId = p["tool_id"]?.string else { return nil }
            let duration = p["duration_s"]?.number
            return .toolCompleted(ToolInfo(toolId: toolId, name: name), duration: duration)
        case "approval.request":
            guard let p = payload,
                  let command = p["command"]?.string,
                  let patternKey = p["pattern_key"]?.string else { return nil }
            return .approvalRequest(ApprovalRequest(
                command: command,
                patternKey: patternKey,
                patternKeys: p["pattern_keys"]?.array?.compactMap { $0.string } ?? [],
                description: p["description"]?.string ?? "",
                allowPermanent: p["allow_permanent"]?.bool ?? false))
        case "clarify.request":
            guard let p = payload,
                  let requestId = p["request_id"]?.string,
                  let question = p["question"]?.string else { return nil }
            return .clarifyRequest(ClarifyRequest(
                requestId: requestId,
                question: question,
                choices: p["choices"]?.array?.compactMap { $0.string } ?? []))
        case "error":
            guard let message = payload?["message"]?.string else { return nil }
            return .failure(message)
        default:
            return nil
        }
    }
}
