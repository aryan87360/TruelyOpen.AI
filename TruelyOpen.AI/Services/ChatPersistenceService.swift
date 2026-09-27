//
//  ChatPersistenceService.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import Foundation
import Combine

public final class ChatPersistenceService: ObservableObject {
    public static let shared = ChatPersistenceService()

    @Published public private(set) var savedConversations: [ChatConversation] = []
    @Published public var activeConversationId: UUID? = nil

    private let fileManager = FileManager.default

    private var activeChatURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("active_chat.json")
    }

    private var archiveURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("conversations_archive.json")
    }

    private init() {
        loadArchivedConversations()
        migrateActiveChatIfNeeded()
    }

    // MARK: - Thread Lifecycle Management

    @discardableResult
    public func saveCurrentThread(messages: [ChatMessage], modelId: String) -> UUID? {
        let validMessages = messages.filter { !$0.isStreaming && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !validMessages.isEmpty else { return nil }

        let threadId: UUID

        if let existingId = activeConversationId,
           let index = savedConversations.firstIndex(where: { $0.id == existingId }) {
            // Update existing conversation
            var conversation = savedConversations[index]
            conversation.messages = validMessages
            conversation.modelId = modelId
            conversation.updatedAt = Date()

            // Update title if it was placeholder
            if conversation.title == "New Conversation" || conversation.title.isEmpty {
                conversation.title = generateTitle(from: validMessages)
            }

            savedConversations.remove(at: index)
            savedConversations.insert(conversation, at: 0)
            threadId = existingId
        } else {
            // Create a brand new thread
            let newId = activeConversationId ?? UUID()
            let title = generateTitle(from: validMessages)
            let conversation = ChatConversation(
                id: newId,
                title: title,
                createdAt: validMessages.first?.timestamp ?? Date(),
                updatedAt: Date(),
                modelId: modelId,
                messages: validMessages
            )
            savedConversations.insert(conversation, at: 0)
            activeConversationId = newId
            threadId = newId
        }

        saveArchivedConversations()
        saveActiveMessages(validMessages)
        return threadId
    }

    public func selectConversation(id: UUID) -> ChatConversation? {
        guard let conversation = savedConversations.first(where: { $0.id == id }) else { return nil }
        activeConversationId = id
        saveActiveMessages(conversation.messages)
        return conversation
    }

    public func startNewConversation() {
        activeConversationId = nil
        clearActiveChat()
    }

    public func deleteConversation(id: UUID) {
        savedConversations.removeAll(where: { $0.id == id })
        if activeConversationId == id {
            activeConversationId = nil
            clearActiveChat()
        }
        saveArchivedConversations()
    }

    public func renameConversation(id: UUID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let index = savedConversations.firstIndex(where: { $0.id == id }) {
            savedConversations[index].title = trimmed
            savedConversations[index].updatedAt = Date()
            saveArchivedConversations()
        }
    }

    public func clearAllConversations() {
        savedConversations.removeAll()
        activeConversationId = nil
        clearActiveChat()
        try? fileManager.removeItem(at: archiveURL)
    }

    // MARK: - Title Generator

    private func generateTitle(from messages: [ChatMessage]) -> String {
        if let firstUser = messages.first(where: { $0.role == .user }) {
            let text = firstUser.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let firstLine = text.components(separatedBy: .newlines).first ?? text
                let clean = firstLine.trimmingCharacters(in: .whitespaces)
                if clean.count > 34 {
                    return String(clean.prefix(34)) + "..."
                }
                return clean
            }
        }
        return "Conversation"
    }

    // MARK: - Active Conversation (Compatibility)

    public func saveActiveMessages(_ messages: [ChatMessage]) {
        let filtered = messages.filter { !$0.isStreaming && !$0.content.isEmpty }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let data = try JSONEncoder().encode(filtered)
                try data.write(to: self.activeChatURL, options: .atomic)
            } catch {
                print("[ChatPersistenceService] Failed to save active chat: \(error)")
            }
        }
    }

    public func loadActiveMessages() -> [ChatMessage] {
        // If we have an active conversation selected, load its messages directly
        if let currentId = activeConversationId,
           let conversation = savedConversations.first(where: { $0.id == currentId }) {
            return conversation.messages
        }

        // Fallback to active_chat.json
        guard fileManager.fileExists(atPath: activeChatURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: activeChatURL)
            let messages = try JSONDecoder().decode([ChatMessage].self, from: data)
            return messages
        } catch {
            print("[ChatPersistenceService] Failed to load active chat: \(error)")
            return []
        }
    }

    public func clearActiveChat() {
        try? fileManager.removeItem(at: activeChatURL)
    }

    // MARK: - Archive Conversations (Legacy)

    public func archiveConversation(messages: [ChatMessage], modelId: String) {
        _ = saveCurrentThread(messages: messages, modelId: modelId)
        startNewConversation()
    }

    // MARK: - Internal Storage & Migration

    private func saveArchivedConversations() {
        let list = savedConversations
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let data = try JSONEncoder().encode(list)
                try data.write(to: self.archiveURL, options: .atomic)
            } catch {
                print("[ChatPersistenceService] Failed to save archives: \(error)")
            }
        }
    }

    private func loadArchivedConversations() {
        guard fileManager.fileExists(atPath: archiveURL.path) else { return }
        do {
            let data = try Data(contentsOf: archiveURL)
            let list = try JSONDecoder().decode([ChatConversation].self, from: data)
            self.savedConversations = list
        } catch {
            print("[ChatPersistenceService] Failed to load archives: \(error)")
        }
    }

    private func migrateActiveChatIfNeeded() {
        if savedConversations.isEmpty && fileManager.fileExists(atPath: activeChatURL.path) {
            let oldMessages = loadActiveMessages()
            if !oldMessages.isEmpty {
                let newId = UUID()
                let title = generateTitle(from: oldMessages)
                let conversation = ChatConversation(
                    id: newId,
                    title: title,
                    createdAt: oldMessages.first?.timestamp ?? Date(),
                    updatedAt: Date(),
                    modelId: oldMessages.last?.modelName ?? "Llama-3.2",
                    messages: oldMessages
                )
                self.savedConversations = [conversation]
                saveArchivedConversations()
            }
        }
        // Always leave activeConversationId as nil on app launch so new chat creates a fresh thread
        activeConversationId = nil
    }
}

