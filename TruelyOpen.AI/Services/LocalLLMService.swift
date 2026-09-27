//
//  LocalLLMService.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import Foundation
import Combine
import SwiftUI

#if canImport(SwiftLlama)
import SwiftLlama
#endif

public final class LocalLLMService: ObservableObject {
    public static let shared = LocalLLMService()

    @Published public private(set) var activeModel: LLMModelInfo? = nil
    @Published public private(set) var isModelLoaded: Bool = false
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isGenerating: Bool = false
    @Published public private(set) var currentTokensPerSecond: Double = 0.0
    @Published public private(set) var loadError: String? = nil

    #if canImport(SwiftLlama)
    @Published public var customThreadCount: Int32 = Configuration.optimalThreadCount
    @Published public var enableFlashAttention: Bool = true
    #endif

    #if canImport(SwiftLlama)
    private var swiftLlama: SwiftLlama? = nil
    #endif
    private var currentTask: Task<Void, Never>? = nil

    private init() {}

    // MARK: - Model Management

    public func reloadActiveModel() async {
        guard let model = activeModel else { return }
        await unloadModel()
        await loadModel(model)
    }

    public func loadModel(_ model: LLMModelInfo) async {
        guard !isLoading else { return }

        if activeModel?.id == model.id && isModelLoaded {
            return
        }

        await unloadModel()

        await MainActor.run {
            self.isLoading = true
            self.loadError = nil
            self.activeModel = model
        }

        let modelURL = ModelStorageService.shared.path(for: model)
        guard ModelStorageService.shared.isDownloaded(llm: model) else {
            await MainActor.run {
                self.loadError = "Model weights for '\(model.name)' are missing or incomplete. Please download from Model Hub."
                self.isLoading = false
            }
            return
        }

        #if canImport(SwiftLlama)
        let stopTokens = model.stopTokens
        let threads = self.customThreadCount
        let flashAttn = self.enableFlashAttention
        do {
            let llama = try await Task.detached(priority: .userInitiated) {
                let optimalBatchThreads = Configuration.optimalBatchThreadCount
                let optimalGpuLayers = Configuration.optimalGpuLayers
                print("[LocalLLMService] Configuring SwiftLlama: \(threads) gen threads, \(optimalBatchThreads) batch threads, \(optimalGpuLayers) GPU layers, flashAttn: \(flashAttn)")
                return try SwiftLlama(
                    modelPath: modelURL.path,
                    modelConfiguration: .init(
                        nCTX: 2048,
                        batchSize: 512,
                        maxTokenCount: 1024,
                        stopTokens: stopTokens,
                        nGpuLayers: optimalGpuLayers,
                        threads: threads,
                        batchThreads: optimalBatchThreads,
                        flashAttn: flashAttn
                    )
                )
            }.value

            await MainActor.run {
                self.swiftLlama = llama
                self.isModelLoaded = true
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = "Failed to load \(model.name): \(error.localizedDescription)"
                self.isModelLoaded = false
                self.isLoading = false
            }
        }
        #else
        await MainActor.run {
            self.loadError = "SwiftLlama package is not available in current build."
            self.isLoading = false
        }
        #endif
    }

    public func unloadModel() async {
        #if canImport(SwiftLlama)
        await MainActor.run {
            self.swiftLlama = nil
            self.isModelLoaded = false
            self.isGenerating = false
            self.activeModel = nil
            self.currentTokensPerSecond = 0.0
        }
        #endif
    }

    // MARK: - Tool Calling Support

    private struct ToolCall {
        let name: String
        let arguments: String
    }

    private func extractToolCalls(from text: String) -> (String, [ToolCall]) {
        var remainingText = text
        var toolCalls: [ToolCall] = []

        let patterns = [
            #"<\|tool_call_begin\|>.*?<\|tool_call_end\|>"#,
            #"<\|tool_call\|>.*?<\|tool_calls_end\|>"#,
            #"```json\s*(\{.*?\})\s*```"#
        ]

        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let nsString = remainingText as NSString
            let matches = regex?.matches(in: remainingText, range: NSRange(location: 0, length: nsString.length)) ?? []

            for match in matches.reversed() {
                let matchedString = nsString.substring(with: match.range)
                if let call = parseToolCall(from: matchedString) {
                    toolCalls.append(call)
                }
                remainingText = nsString.substring(with: NSRange(location: 0, length: match.range.location)) +
                               nsString.substring(with: NSRange(location: match.range.upperBound, length: nsString.length - match.range.upperBound))
            }
            if !toolCalls.isEmpty { break }
        }

        return (remainingText.trimmingCharacters(in: .whitespacesAndNewlines), toolCalls)
    }

    private func parseToolCall(from text: String) -> ToolCall? {
        let cleaned = text
            .replacingOccurrences(of: "<|tool_call_begin|>", with: "")
            .replacingOccurrences(of: "<|tool_call_end|>", with: "")
            .replacingOccurrences(of: "<|tool_call|>", with: "")
            .replacingOccurrences(of: "<|tool_calls_end|>", with: "")
            .replacingOccurrences(of: "[TOOL_CALLS]", with: "")
            .replacingOccurrences(of: "[/TOOL_CALLS]", with: "")
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              let args = json["arguments"] else {
            return nil
        }

        let argsData = try? JSONSerialization.data(withJSONObject: args)
        let argsString = argsData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ToolCall(name: name, arguments: argsString)
    }

    private func buildSystemPrompt(
        model: LLMModelInfo,
        currentDateTime: String,
        webSearchResults: [WebSearchResult]? = nil
    ) -> String {
        var prompt = """
        You are TrulyOpen AI, a helpful, brilliant, and concise local AI assistant running 100% on-device.
        Current Date and Time: \(currentDateTime).
        You are fully aware of today's date and current year. Always reference this current date when answering time-sensitive or date-related questions.
        """

        if let results = webSearchResults, !results.isEmpty {
            prompt += """


            [LIVE WEB SEARCH OBSERVATIONS - Retrieved by Agent]
            """
            for (idx, res) in results.prefix(4).enumerated() {
                prompt += """

                [\(idx + 1)] "\(res.title)" (\(res.sourceName))
                URL: \(res.url)
                Fact: \(res.snippet)
                """
            }
            prompt += """


            Instructions:
            The user's query required live web search. Synthesize an accurate, concise answer grounded in the live web search observations above. Reference the sources and current date when relevant.
            """
        }

        return prompt
    }

    // MARK: - Streaming Generation (Direct or Grounded)

    public func generateStream(
        messages: [ChatMessage],
        model: LLMModelInfo,
        webSearchResults: [WebSearchResult]? = nil
    ) -> AsyncThrowingStream<String, Error> {
        guard !isGenerating else {
            return AsyncThrowingStream { continuation in
                continuation.finish(
                    throwing: NSError(
                        domain: "LocalLLMService",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Inference is already in progress."]
                    )
                )
            }
        }

        #if canImport(SwiftLlama)
        guard let llama = swiftLlama else {
            return AsyncThrowingStream { continuation in
                continuation.finish(
                    throwing: NSError(
                        domain: "LocalLLMService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Model is not loaded in memory."]
                    )
                )
            }
        }

        let promptType: Prompt.`Type`
        switch model.promptType {
        case "gemma": promptType = .gemma
        case "llama", "llama3": promptType = .llama3
        case "phi": promptType = .phi
        case "chatML": fallthrough
        default: promptType = .chatML
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateStyle = .full
        df.timeStyle = .short
        let currentDateTimeString = df.string(from: Date())

        let (chatHistory, lastUserMessage) = buildChatHistory(from: messages)

        let systemPrompt = self.buildSystemPrompt(
            model: model,
            currentDateTime: currentDateTimeString,
            webSearchResults: webSearchResults
        )

        let promptObject = Prompt(
            type: promptType,
            systemPrompt: systemPrompt,
            userMessage: lastUserMessage,
            history: chatHistory
        )

        return AsyncThrowingStream { continuation in
            self.currentTask = Task(priority: .userInitiated) { [weak self] in
                guard let self else { continuation.finish(); return }
                await MainActor.run {
                    self.isGenerating = true
                    self.currentTokensPerSecond = 0.0
                }

                var tokenCount = 0
                let startTime = Date()
                var lastSpeedUpdateTime = Date()
                let stopTokens = model.stopTokens

                do {
                    for try await token in await llama.start(for: promptObject) {
                        if Task.isCancelled { break }

                        if stopTokens.contains(where: { token.contains($0) }) {
                            break
                        }

                        tokenCount += 1
                        let now = Date()
                        if tokenCount == 1 || now.timeIntervalSince(lastSpeedUpdateTime) >= 0.25 {
                            lastSpeedUpdateTime = now
                            let elapsed = now.timeIntervalSince(startTime)
                            if elapsed > 0 {
                                let tps = Double(tokenCount) / elapsed
                                Task { @MainActor [weak self] in
                                    self?.currentTokensPerSecond = tps
                                }
                            }
                        }

                        continuation.yield(token)
                    }
                } catch {
                    await MainActor.run {
                        self.isGenerating = false
                    }
                    continuation.finish(throwing: error)
                    return
                }

                await MainActor.run {
                    self.isGenerating = false
                }
                continuation.finish()
            }
        }
        #else
        return AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: NSError(
                    domain: "LocalLLMService",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "SwiftLlama package is not linked."]
                )
            )
        }
        #endif
    }

    public func generateStreamAgentic(
        messages: [ChatMessage],
        model: LLMModelInfo
    ) -> AsyncThrowingStream<String, Error> {
        return generateStream(messages: messages, model: model, webSearchResults: nil)
    }

    public func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
        Task { @MainActor in
            self.isGenerating = false
        }
    }

    // MARK: - History Builder

    #if canImport(SwiftLlama)
    private func buildChatHistory(from messages: [ChatMessage]) -> ([Chat], String) {
        var chats: [Chat] = []
        var currentUserPrompt: String? = nil

        let nonStreaming = messages.filter { !$0.isStreaming }

        for msg in nonStreaming {
            switch msg.role {
            case .user:
                if let pending = currentUserPrompt {
                    chats.append(Chat(user: pending, bot: ""))
                }
                currentUserPrompt = msg.content

            case .assistant:
                if let user = currentUserPrompt {
                    chats.append(Chat(user: user, bot: msg.content))
                    currentUserPrompt = nil
                }

            case .system:
                break
            }
        }

        let finalUserMessage = currentUserPrompt ?? ""

        let maxHistoryChars = 4500
        var totalChars = finalUserMessage.count
        var budgetedChats: [Chat] = []

        for chat in chats.reversed() {
            let chatChars = chat.user.count + chat.bot.count
            if totalChars + chatChars > maxHistoryChars && !budgetedChats.isEmpty {
                break
            }
            budgetedChats.insert(chat, at: 0)
            totalChars += chatChars
        }

        return (budgetedChats, finalUserMessage)
    }
    #endif
}