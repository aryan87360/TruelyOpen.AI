import Foundation

public struct Chat: Sendable {
    public let user: String
    public let bot: String

    public init(user: String, bot: String) {
        self.user = user
        self.bot = bot
    }
}

extension Chat {
    var chatMLPrompt: String {
        "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n\(bot)<|im_end|>"
    }

    var llamaPrompt: String {
        "[INST] \(user) [/INST] \(bot) </s>"
    }

    var llama3Prompt: String {
        var pieces: [String] = []
        if !user.isEmpty {
            pieces.append("<|start_header_id|>user<|end_header_id|>\n\n\(user)<|eot_id|>")
        }
        if !bot.isEmpty {
            pieces.append("<|start_header_id|>assistant<|end_header_id|>\n\n\(bot)<|eot_id|>")
        }
        return pieces.joined(separator: "\n")
    }

    var mistralPrompt: String {
        "[INST] \(user) [/INST] \(bot)</s>"
    }

    var phiPrompt: String {
        "<|user|>\n\(user)<|end|>\n<|assistant|>\n\(bot)<|end|>"
    }

    var gemmaPrompt: String {
        "<start_of_turn>user\n\(user)<end_of_turn>\n<start_of_turn>model\n\(bot)<end_of_turn>"
    }
}
