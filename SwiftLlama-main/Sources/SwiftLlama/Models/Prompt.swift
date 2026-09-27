import Foundation

public struct Prompt: Sendable {
    public enum `Type`: Sendable {
        case chatML
        case alpaca
        case llama
        case llama3
        case mistral
        case phi
        case gemma
    }

    public let type: `Type`
    public let systemPrompt: String
    public let userMessage: String
    public let history: [Chat]

    public init(type: `Type`,
                systemPrompt: String = "",
                userMessage: String,
                history: [Chat] = []) {
        self.type = type
        self.systemPrompt = systemPrompt
        self.userMessage = userMessage
        self.history = history
    }

    var prompt: String {
        switch type {
        case .llama: encodeLlamaPrompt()
        case .llama3: encodeLlama3Prompt()
        case .alpaca: encodeAlpacaPrompt()
        case .chatML: encodeChatMLPrompt()
        case .mistral: encodeMistralPrompt()
        case .phi: encodePhiPrompt()
        case .gemma: encodeGemmaPrompt()
        }
    }

    private func encodeLlamaPrompt() -> String {
        var result = ""
        if !systemPrompt.isEmpty {
            result += "[INST] <<SYS>>\n\(systemPrompt)\n<</SYS>>\n\n"
        } else {
            result += "[INST] "
        }
        for chat in history.suffix(Configuration.historySize) {
            result += "\(chat.user) [/INST] \(chat.bot) </s><s>[INST] "
        }
        result += "\(userMessage) [/INST]"
        return result
    }

    private func encodeLlama3Prompt() -> String {
        var segments: [String] = ["<|begin_of_text|>"]
        if !systemPrompt.isEmpty {
            segments.append("<|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|>")
        }
        for chat in history.suffix(Configuration.historySize) {
            let p = chat.llama3Prompt
            if !p.isEmpty {
                segments.append(p)
            }
        }
        segments.append("<|start_header_id|>user<|end_header_id|>\n\n\(userMessage)<|eot_id|>")
        segments.append("<|start_header_id|>assistant<|end_header_id|>\n\n")
        return segments.joined(separator: "\n")
    }

    private func encodeAlpacaPrompt() -> String {
        """
        Below is an instruction that describes a task.
        Write a response that appropriately completes the request.
        \(userMessage)
        """
    }

    private func encodeChatMLPrompt() -> String {
        var segments: [String] = []
        if !systemPrompt.isEmpty {
            segments.append("<|im_start|>system\n\(systemPrompt)<|im_end|>")
        }
        for chat in history.suffix(Configuration.historySize) {
            segments.append(chat.chatMLPrompt)
        }
        segments.append("<|im_start|>user\n\(userMessage)<|im_end|>")
        segments.append("<|im_start|>assistant\n")
        return segments.joined(separator: "\n")
    }

    private func encodeMistralPrompt() -> String {
        var result = "<s>"
        for chat in history.suffix(Configuration.historySize) {
            result += "[INST] \(chat.user) [/INST] \(chat.bot)</s>"
        }
        result += "[INST] \(userMessage) [/INST]"
        return result
    }

    private func encodePhiPrompt() -> String {
        var segments: [String] = []
        if !systemPrompt.isEmpty {
            segments.append("<|system|>\n\(systemPrompt)<|end|>")
        }
        for chat in history.suffix(Configuration.historySize) {
            segments.append(chat.phiPrompt)
        }
        segments.append("<|user|>\n\(userMessage)<|end|>")
        segments.append("<|assistant|>\n")
        return segments.joined(separator: "\n")
    }

    private func encodeGemmaPrompt() -> String {
        var segments: [String] = []
        if !systemPrompt.isEmpty {
            segments.append("<start_of_turn>user\nSystem: \(systemPrompt)<end_of_turn>\n<start_of_turn>model\nUnderstood.<end_of_turn>")
        }
        for chat in history.suffix(Configuration.historySize) {
            segments.append(chat.gemmaPrompt)
        }
        segments.append("<start_of_turn>user\n\(userMessage)<end_of_turn>")
        segments.append("<start_of_turn>model\n")
        return segments.joined(separator: "\n")
    }
}
