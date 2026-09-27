//
//  ChatModels.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import Foundation
import Combine
import SwiftUI

public enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

public struct WebSearchResult: Identifiable, Codable, Equatable {
    public let id: UUID
    public let title: String
    public let url: String
    public let snippet: String
    public let sourceName: String

    public init(
        id: UUID = UUID(),
        title: String,
        url: String,
        snippet: String,
        sourceName: String = ""
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
        self.sourceName = sourceName.isEmpty ? (URL(string: url)?.host ?? "Web") : sourceName
    }
}

public enum AgenticSearchMode: String, CaseIterable, Identifiable, Codable {
    case auto = "Auto"
    case on = "Always"
    case off = "Offline"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .auto: return "sparkles"
        case .on: return "globe.americas.fill"
        case .off: return "bolt.slash.fill"
        }
    }

    public var label: String {
        switch self {
        case .auto: return "Agentic"
        case .on: return "Search On"
        case .off: return "Offline"
        }
    }
}

public struct AgenticDecision: Equatable {
    public let requiresSearch: Bool
    public let searchQuery: String?
    public let reason: String

    public init(requiresSearch: Bool, searchQuery: String?, reason: String) {
        self.requiresSearch = requiresSearch
        self.searchQuery = searchQuery
        self.reason = reason
    }
}

public struct ChatMessage: Identifiable, Codable, Equatable {
    public let id: UUID
    public let role: MessageRole
    public var content: String
    public let timestamp: Date
    public var modelName: String?
    public var tokensPerSecond: Double?
    public var generationDuration: TimeInterval?
    public var isStreaming: Bool
    public var searchResults: [WebSearchResult]?
    public var isSearchingWeb: Bool
    public var searchQuery: String?

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        modelName: String? = nil,
        tokensPerSecond: Double? = nil,
        generationDuration: TimeInterval? = nil,
        isStreaming: Bool = false,
        searchResults: [WebSearchResult]? = nil,
        isSearchingWeb: Bool = false,
        searchQuery: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.modelName = modelName
        self.tokensPerSecond = tokensPerSecond
        self.generationDuration = generationDuration
        self.isStreaming = isStreaming
        self.searchResults = searchResults
        self.isSearchingWeb = isSearchingWeb
        self.searchQuery = searchQuery
    }
}

public struct ChatConversation: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var modelId: String
    public var messages: [ChatMessage]

    public init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelId: String = "Llama-3.2",
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelId = modelId
        self.messages = messages
    }

    public var relativeTimeDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    public var previewSnippet: String {
        if let last = messages.last {
            let prefix = last.role == .user ? "You: " : ""
            let clean = last.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty {
                return "Empty message"
            }
            return prefix + (clean.count > 65 ? String(clean.prefix(65)) + "..." : clean)
        }
        return "New thread"
    }

    public var formattedDate: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: updatedAt)
    }

    public var userMessageCount: Int {
        messages.filter { $0.role == .user }.count
    }
}

