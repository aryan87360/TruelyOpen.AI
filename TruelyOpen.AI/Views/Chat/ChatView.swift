//
//  ChatView.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import SwiftUI
import Combine

public struct ChatView: View {
    @ObservedObject var llmService = LocalLLMService.shared
    @ObservedObject var downloadService = ModelDownloadService.shared
    @ObservedObject var hardwareService = DeviceHardwareService.shared

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var selectedModel: LLMModelInfo = ModelCatalogue.textModels[0]
    @State private var showModelSelectorSheet: Bool = false
    @State private var showHistorySheet: Bool = false
    @State private var agenticSearchMode: AgenticSearchMode = .auto
    @ObservedObject var persistenceService = ChatPersistenceService.shared
    @FocusState private var isInputFocused: Bool
    public var isKeyboardVisible: Bool = false

    private var isKeyboardActive: Bool {
        isKeyboardVisible || isInputFocused
    }

    public init(isKeyboardVisible: Bool = false) {
        self.isKeyboardVisible = isKeyboardVisible
    }

    private var downloadedModels: [LLMModelInfo] {
        ModelCatalogue.textModels.filter { downloadService.isDownloaded(llmId: $0.id) }
    }

    public var body: some View {
        ZStack {
            AppTheme.backgroundDark.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                if messages.isEmpty {
                    emptyStateView
                } else {
                    messageScrollView
                }

                inputComposerBar
            }
        }
        .sheet(isPresented: $showModelSelectorSheet) {
            modelSelectorSheet
        }
        .sheet(isPresented: $showHistorySheet) {
            ChatHistorySheetView(
                onSelectThread: { thread in
                    selectThread(thread)
                },
                onStartNewChat: {
                    startNewChat()
                },
                onClearAll: {
                    clearAllChatAndHistory()
                },
                onDeleteActiveThread: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        messages.removeAll()
                    }
                }
            )
        }
        .onAppear {
            downloadService.refreshDownloadedStates()
            autoSelectDownloadedModelIfNeeded()
        }
    }

    // MARK: - Header Bar (Clean Single-Row)

    private var headerBar: some View {
        HStack(spacing: 12) {
            // History / Threads Button
            Button(action: {
                AppTheme.hapticImpact(.light)
                showHistorySheet = true
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(AppTheme.cardDark)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)

            // Simple, Crisp Brand Heading
            HStack(spacing: 5) {
                Text("TrulyOpen")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("AI")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.mintAccent)
            }

            Spacer()

            // Model Switcher Pill
            Button(action: {
                AppTheme.hapticImpact(.light)
                showModelSelectorSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppTheme.mintAccent)

                    Text(selectedModel.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(AppTheme.cardDark)
                        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
                )
            }
            .buttonStyle(.plain)

            // New Chat Button
            Button(action: {
                AppTheme.hapticImpact(.medium)
                startNewChat()
            }) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(AppTheme.cardDark)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.surfaceDark.opacity(0.95))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 32)

                // Tactile Squircle Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(AppTheme.cardDark)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 8)
                        .frame(width: 88, height: 88)

                    Image(systemName: "sparkles")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundColor(AppTheme.mintAccent)
                }

                VStack(spacing: 8) {
                    Text("100% On-Device Intelligence")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Zero cloud servers. Zero data tracking.\nInference runs entirely in local device RAM.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)
                }

                // Download Status Warning if no model downloaded
                if !downloadService.isDownloaded(llmId: selectedModel.id) {
                    Button(action: { showModelSelectorSheet = true }) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppTheme.amberAccent.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(AppTheme.amberAccent)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(selectedModel.name) not downloaded")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("Tap to download weights (\(selectedModel.sizeDisplay))")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(14)
                        .tactileCard(cornerRadius: 20, strokeColor: AppTheme.amberAccent.opacity(0.3))
                    }
                    .padding(.horizontal, 20)
                }

                // Starter Prompts (Tactile Cards)
                VStack(alignment: .leading, spacing: 10) {
                    Text("QUICK STARTERS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 20)

                    let starters = [
                        "Explain quantum computing in simple terms",
                        "Write a Swift extension to calculate relative time",
                        "Suggest 5 high-protein vegetarian meal ideas",
                        "Draft a friendly email asking for project feedback"
                    ]

                    ForEach(starters, id: \.self) { prompt in
                        Button(action: { submitStarterPrompt(prompt) }) {
                            HStack {
                                Text(prompt)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppTheme.mintAccent)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .tactileCard(cornerRadius: 18)
                        }
                        .padding(.horizontal, 20)
                    }
                }

                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Message List

    private var activeThreadHeader: some View {
        Group {
            if let activeId = persistenceService.activeConversationId,
               let activeConv = persistenceService.savedConversations.first(where: { $0.id == activeId }) {
                VStack(spacing: 4) {
                    Text(activeConv.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 20)

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(activeConv.relativeTimeDisplay)
                        Text("•")
                        Text("\(messages.count) messages")
                    }
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    activeThreadHeader

                    ForEach(messages) { msg in
                        ChatMessageRow(message: msg)
                            .id(msg.id)
                    }

                    if let error = llmService.loadError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppTheme.roseAccent)
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.roseAccent)
                        }
                        .padding(12)
                        .glassCard(cornerRadius: 12, strokeColor: AppTheme.roseAccent.opacity(0.4))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.content) { _, _ in
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }


    // MARK: - Input Composer Bar

    private var inputComposerBar: some View {
        VStack(spacing: 0) {
            // Generating status row
            if llmService.isGenerating {
                HStack {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.65)
                            .tint(AppTheme.mintAccent)
                        Text(String(format: "%.1f tok/s", llmService.currentTokensPerSecond))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppTheme.mintAccent)
                    }
                    Spacer()
                    Button(action: stopGeneration) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                            Text("Stop")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(AppTheme.roseAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppTheme.roseAccent.opacity(0.14)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            // Main composer row — single unified concentric pill
            HStack(alignment: .center, spacing: 8) {
                // Agentic Search Mode Pill
                Button(action: cycleAgenticSearchMode) {
                    HStack(spacing: 5) {
                        Image(systemName: agenticSearchMode.icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(agenticSearchMode == .off ? .white.opacity(0.35) : AppTheme.mintAccent)

                        if !isInputFocused {
                            Text(agenticSearchMode.label)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(agenticSearchMode == .off ? .white.opacity(0.4) : AppTheme.mintAccent)
                        }
                    }
                    .padding(.horizontal, isInputFocused ? 8 : 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(agenticSearchMode == .off ? Color.white.opacity(0.04) : AppTheme.mintAccent.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(agenticSearchMode == .off ? Color.white.opacity(0.08) : AppTheme.mintAccent.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                // Text field — vertically centered with icons
                TextField(
                    "Message \(selectedModel.name)...",
                    text: $inputText,
                    axis: .vertical
                )
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white)
                .lineLimit(1...5)
                .frame(minHeight: 38)
                .focused($isInputFocused)

                // Send button
                Button(action: handleSend) {
                    ZStack {
                        Circle()
                            .fill(canSend ? AppTheme.mintAccent : Color.white.opacity(0.07))
                            .frame(width: 38, height: 38)
                            .shadow(color: canSend ? AppTheme.mintAccent.opacity(0.4) : .clear, radius: 8, x: 0, y: 3)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(canSend
                                ? Color(red: 14/255, green: 16/255, blue: 19/255)
                                : .white.opacity(0.2))
                    }
                }
                .disabled(!canSend)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AppTheme.cardDark)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 16, x: 0, y: 6)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, isKeyboardActive ? 8 : 88)
        }
        .background(
            AppTheme.backgroundDark.opacity(0.97)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.white.opacity(0.05)),
                    alignment: .top
                )
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isKeyboardActive)
    }

    private func cycleAgenticSearchMode() {
        AppTheme.hapticImpact(.light)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            switch agenticSearchMode {
            case .auto: agenticSearchMode = .on
            case .on: agenticSearchMode = .off
            case .off: agenticSearchMode = .auto
            }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !llmService.isGenerating
    }

    // MARK: - Actions

    private func handleSend() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        AppTheme.hapticImpact(.medium)

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        _ = persistenceService.saveCurrentThread(messages: messages, modelId: selectedModel.id)

        // Ensure model is loaded
        startStreamingInference()
    }

    private func submitStarterPrompt(_ prompt: String) {
        inputText = prompt
        handleSend()
    }

    private func startStreamingInference() {
        let assistantMsgId = UUID()
        let lastUserText = messages.last(where: { $0.role == .user })?.content ?? ""

        let placeholder = ChatMessage(
            id: assistantMsgId,
            role: .assistant,
            content: "",
            modelName: selectedModel.name,
            isStreaming: true
        )
        messages.append(placeholder)

        Task {
            // Check if model file exists
            guard downloadService.isDownloaded(llmId: selectedModel.id) else {
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        messages[index].content = "⚠️ Model weights for '\(selectedModel.name)' are not downloaded yet. Please tap the model pill at the top to download it from the catalogue."
                        messages[index].isStreaming = false
                    }
                    _ = persistenceService.saveCurrentThread(messages: messages, modelId: selectedModel.id)
                }
                return
            }

            // Load model into RAM if not already loaded
            if !llmService.isModelLoaded || llmService.activeModel?.id != selectedModel.id {
                await llmService.loadModel(selectedModel)
            }

            guard llmService.isModelLoaded else {
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        messages[index].content = "⚠️ Could not load model into device memory: \(llmService.loadError ?? "Unknown error")."
                        messages[index].isStreaming = false
                    }
                    _ = persistenceService.saveCurrentThread(messages: messages, modelId: selectedModel.id)
                }
                return
            }

            // 1. Evaluate Agentic Requirement for Web Search
            let decision = WebSearchService.shared.evaluateRequirement(
                for: lastUserText,
                mode: agenticSearchMode
            )

            var searchResults: [WebSearchResult] = []

            if decision.requiresSearch, let query = decision.searchQuery {
                // Indicate Agentic Search step in UI
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        messages[index].isSearchingWeb = true
                        messages[index].searchQuery = query
                    }
                }

                // Execute Live Web Search
                searchResults = await WebSearchService.shared.search(query: query)

                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        messages[index].isSearchingWeb = false
                        messages[index].searchResults = searchResults
                    }
                }
            }

            // 2. Stream tokens (grounded with search observations if requirement was met, or direct otherwise)
            let stream = llmService.generateStream(
                messages: messages,
                model: selectedModel,
                webSearchResults: searchResults.isEmpty ? nil : searchResults
            )
            var accumulated = ""
            let startTime = Date()
            var lastUIUpdateTime = Date()

            do {
                for try await token in stream {
                    accumulated += token
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdateTime) >= 0.033 {
                        lastUIUpdateTime = now
                        let textSnapshot = accumulated
                        let speedSnapshot = llmService.currentTokensPerSecond
                        await MainActor.run {
                            if let index = messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                messages[index].content = textSnapshot
                                messages[index].tokensPerSecond = speedSnapshot
                            }
                        }
                    }
                }

                let duration = Date().timeIntervalSince(startTime)
                let finalText = accumulated
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        messages[index].content = finalText
                        messages[index].isStreaming = false
                        messages[index].generationDuration = duration
                        messages[index].searchResults = searchResults
                    }
                    _ = persistenceService.saveCurrentThread(messages: messages, modelId: selectedModel.id)
                }
            } catch {
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        if messages[index].content.isEmpty {
                            messages[index].content = "Error: \(error.localizedDescription)"
                        }
                        messages[index].isStreaming = false
                        messages[index].isSearchingWeb = false
                    }
                    _ = persistenceService.saveCurrentThread(messages: messages, modelId: selectedModel.id)
                }
            }
        }
    }

    private func stopGeneration() {
        llmService.stopGeneration()
        if let last = messages.last, last.isStreaming {
            if let index = messages.firstIndex(where: { $0.id == last.id }) {
                messages[index].isStreaming = false
                messages[index].isSearchingWeb = false
            }
            _ = persistenceService.saveCurrentThread(messages: messages, modelId: selectedModel.id)
        }
    }

    private func startNewChat() {
        AppTheme.hapticNotification(.success)
        if llmService.isGenerating {
            llmService.stopGeneration()
        }
        if !messages.isEmpty {
            _ = persistenceService.saveCurrentThread(messages: messages, modelId: selectedModel.id)
        }
        persistenceService.startNewConversation()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            messages.removeAll()
        }
    }

    private func clearAllChatAndHistory() {
        AppTheme.hapticNotification(.warning)
        if llmService.isGenerating {
            llmService.stopGeneration()
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            messages.removeAll()
        }
        persistenceService.clearAllConversations()
    }

    private func selectThread(_ conversation: ChatConversation) {
        if llmService.isGenerating {
            llmService.stopGeneration()
        }

        // Save current thread first if it has messages and is different
        if !messages.isEmpty && persistenceService.activeConversationId != conversation.id {
            _ = persistenceService.saveCurrentThread(messages: messages, modelId: selectedModel.id)
        }

        if let loaded = persistenceService.selectConversation(id: conversation.id) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                messages = loaded.messages
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                messages = conversation.messages
            }
        }

        // Match model if available in catalogue
        if let matched = ModelCatalogue.textModels.first(where: { $0.id == conversation.modelId || $0.name == conversation.modelId }) {
            selectedModel = matched
        }
    }

    private func clearChat() {
        AppTheme.hapticNotification(.warning)
        persistenceService.clearActiveChat()
        withAnimation {
            messages.removeAll()
        }
    }

    private func autoSelectDownloadedModelIfNeeded() {
        if !downloadService.isDownloaded(llmId: selectedModel.id),
           let firstDownloaded = downloadedModels.first {
            selectedModel = firstDownloaded
        }
    }

    // MARK: - Model Selector Sheet

    private var modelSelectorSheet: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        performanceTuningSection

                        VStack(alignment: .leading, spacing: 6) {
                            Text("AVAILABLE MODELS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 4)

                            ForEach(ModelCatalogue.textModels) { model in
                                let isDownloaded = downloadService.isDownloaded(llmId: model.id)
                                let isSelected = selectedModel.id == model.id

                                Button(action: {
                                    selectedModel = model
                                    showModelSelectorSheet = false
                                    if isDownloaded {
                                        Task { await llmService.loadModel(model) }
                                    }
                                }) {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(isSelected ? AppTheme.mintAccent.opacity(0.15) : AppTheme.surfaceDark)
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(isSelected ? AppTheme.mintAccent.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
                                                )

                                            Image(systemName: "brain.head.profile")
                                                .font(.system(size: 18))
                                                .foregroundColor(isSelected ? AppTheme.mintAccent : .white.opacity(0.8))
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                Text(model.name)
                                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                                    .foregroundColor(.white)

                                                if model.isRecommended {
                                                    Text("REC")
                                                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                                                        .foregroundColor(AppTheme.mintAccent)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Capsule().fill(AppTheme.mintAccent.opacity(0.12)))
                                                }
                                            }

                                            Text(model.description)
                                                .font(.system(size: 12))
                                                .foregroundColor(.white.opacity(0.6))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)

                                            HStack(spacing: 10) {
                                                Text("Size: \(model.sizeDisplay)")
                                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                    .foregroundColor(.white.opacity(0.4))

                                                Text(isDownloaded ? "✓ Ready on device" : "Download needed")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(isDownloaded ? AppTheme.mintAccent : AppTheme.amberAccent)
                                            }
                                        }

                                        Spacer()

                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(AppTheme.mintAccent)
                                        }
                                    }
                                    .padding(16)
                                    .tactileCard(
                                        cornerRadius: 18,
                                        strokeColor: isSelected ? AppTheme.mintAccent.opacity(0.4) : Color.white.opacity(0.06)
                                    )
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Select Local Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showModelSelectorSheet = false }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.mintAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Performance Tuning Card

    private var performanceTuningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.badge.clock.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.mintAccent)
                Text("HARDWARE TUNING")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1)
                Spacer()
                Text("A13 ARM NEON")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.mintAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.mintAccent.opacity(0.12)))
            }

            HStack(spacing: 8) {
                Text("CPU Threads:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                ForEach([2, 3, 4], id: \.self) { count in
                    Button(action: {
                        llmService.customThreadCount = Int32(count)
                        Task { await llmService.reloadActiveModel() }
                    }) {
                        Text("\(count) Cores")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(llmService.customThreadCount == Int32(count) ? Color(red: 14/255, green: 16/255, blue: 19/255) : .white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(llmService.customThreadCount == Int32(count) ? AppTheme.mintAccent : AppTheme.surfaceDark)
                            )
                    }
                }
            }

            Toggle(isOn: Binding(
                get: { llmService.enableFlashAttention },
                set: { val in
                    llmService.enableFlashAttention = val
                    Task { await llmService.reloadActiveModel() }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU Flash Attention")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                    Text("Fuses attention into zero-alloc SIMD loop")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .tint(AppTheme.mintAccent)
        }
        .padding(16)
        .tactileCard(cornerRadius: 20)
    }
}
