//
//  ChatMessageRow.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import SwiftUI
import Combine

public struct ChatMessageRow: View {
    public let message: ChatMessage
    public let onCopy: () -> Void

    @State private var showCopiedBanner = false

    public init(message: ChatMessage, onCopy: @escaping () -> Void = {}) {
        self.message = message
        self.onCopy = onCopy
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                assistantAvatar
            } else {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Sender label & model info
                if message.role == .assistant {
                    HStack(spacing: 6) {
                        Text(message.modelName ?? "Local Assistant")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.mintAccent)

                        if let tps = message.tokensPerSecond, tps > 0 {
                            Text("•  \(String(format: "%.1f", tps)) tok/s")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }

                // Message Body Bubble
                messageBubble

                // Action Bar (for assistant messages)
                if message.role == .assistant && !message.isStreaming && !message.content.isEmpty {
                    HStack(spacing: 12) {
                        Button(action: copyToClipboard) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopiedBanner ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                Text(showCopiedBanner ? "Copied" : "Copy")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(showCopiedBanner ? AppTheme.mintAccent : .white.opacity(0.5))
                        }

                        if let duration = message.generationDuration {
                            Text(String(format: "%.1fs", duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }

                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }

            if message.role == .user {
                userAvatar
            } else {
                Spacer(minLength: 40)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bubble

    private var messageBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.isSearchingWeb {
                HStack(spacing: 7) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(AppTheme.mintAccent)
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.mintAccent)
                    if let query = message.searchQuery, !query.isEmpty {
                        Text("Agent searching: “\(query)”…")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.mintAccent)
                            .lineLimit(1)
                    } else {
                        Text("Agent searching live web…")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.mintAccent)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(AppTheme.mintAccent.opacity(0.12))
                        .overlay(Capsule().stroke(AppTheme.mintAccent.opacity(0.3), lineWidth: 0.8))
                )
                .padding(.vertical, 2)
            }

            if !message.content.isEmpty {
                Text(message.content)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
            }

            if message.isStreaming && !message.isSearchingWeb {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppTheme.mintAccent)
                        .frame(width: 6, height: 6)
                    Text("Thinking…")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.mintAccent.opacity(0.85))
                }
                .padding(.top, 2)
            }

            // Web Citations / Sources Chips
            if let results = message.searchResults, !results.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.mintAccent)
                        Text("SOURCES USED")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(results) { res in
                                if let url = URL(string: res.url) {
                                    Link(destination: url) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "safari")
                                                .font(.system(size: 10))
                                                .foregroundColor(AppTheme.mintAccent)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(res.title)
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                Text(res.sourceName)
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                            }
                                            Image(systemName: "arrow.up.right")
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(AppTheme.elevatedCardDark)
                                                .overlay(Capsule().stroke(AppTheme.mintAccent.opacity(0.3), lineWidth: 0.8))
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(message.role == .user ? AppTheme.elevatedCardDark : AppTheme.cardDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            message.role == .user ? Color.white.opacity(0.1) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
        )
    }

    // MARK: - Avatars

    private var assistantAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.cardDark)
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.mintAccent.opacity(0.3), lineWidth: 1)
                )

            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.mintAccent)
        }
    }

    private var userAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.elevatedCardDark)
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = message.content
        AppTheme.hapticNotification(.success)
        withAnimation {
            showCopiedBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showCopiedBanner = false
            }
        }
        onCopy()
    }
}
