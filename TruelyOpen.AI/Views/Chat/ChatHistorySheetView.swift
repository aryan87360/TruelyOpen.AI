//
//  ChatHistorySheetView.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import SwiftUI

public struct ChatHistorySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var persistenceService = ChatPersistenceService.shared

    public var onSelectThread: (ChatConversation) -> Void
    public var onStartNewChat: () -> Void
    public var onClearAll: () -> Void
    public var onDeleteActiveThread: (() -> Void)?

    @State private var searchText: String = ""
    @State private var conversationToRename: ChatConversation? = nil
    @State private var newTitleText: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var showClearAllConfirmation: Bool = false

    public init(
        onSelectThread: @escaping (ChatConversation) -> Void,
        onStartNewChat: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onDeleteActiveThread: (() -> Void)? = nil
    ) {
        self.onSelectThread = onSelectThread
        self.onStartNewChat = onStartNewChat
        self.onClearAll = onClearAll
        self.onDeleteActiveThread = onDeleteActiveThread
    }

    private var filteredConversations: [ChatConversation] {
        let all = persistenceService.savedConversations
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return all
        }
        let query = searchText.lowercased()
        return all.filter { conv in
            conv.title.lowercased().contains(query) ||
            conv.messages.contains(where: { $0.content.lowercased().contains(query) })
        }
    }

    // MARK: - Chronological Buckets

    private var todayConversations: [ChatConversation] {
        let calendar = Calendar.current
        return filteredConversations.filter { calendar.isDateInToday($0.updatedAt) }
    }

    private var yesterdayConversations: [ChatConversation] {
        let calendar = Calendar.current
        return filteredConversations.filter { calendar.isDateInYesterday($0.updatedAt) }
    }

    private var pastWeekConversations: [ChatConversation] {
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return filteredConversations.filter { conv in
            !calendar.isDateInToday(conv.updatedAt) &&
            !calendar.isDateInYesterday(conv.updatedAt) &&
            conv.updatedAt >= sevenDaysAgo
        }
    }

    private var olderConversations: [ChatConversation] {
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return filteredConversations.filter { $0.updatedAt < sevenDaysAgo }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundDark.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search Bar & Start New Chat CTA
                    topControlBar

                    if filteredConversations.isEmpty {
                        emptyStateView
                    } else {
                        conversationListView
                    }

                    if !persistenceService.savedConversations.isEmpty {
                        bottomClearBar
                    }
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        AppTheme.hapticImpact(.light)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.mintAccent)
                }
            }
            .alert("Rename Thread", isPresented: $showRenameAlert) {
                TextField("Conversation Title", text: $newTitleText)
                Button("Save") {
                    if let conv = conversationToRename {
                        persistenceService.renameConversation(id: conv.id, newTitle: newTitleText)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a new title for this conversation thread.")
            }
            .confirmationDialog(
                "Clear All History",
                isPresented: $showClearAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All Conversations", role: .destructive) {
                    AppTheme.hapticNotification(.warning)
                    dismiss()
                    onClearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all saved threads and reset assistant memory.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Controls

    private var topControlBar: some View {
        VStack(spacing: 12) {
            // New Chat CTA Pill
            Button(action: {
                AppTheme.hapticImpact(.medium)
                dismiss()
                onStartNewChat()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .bold))
                    Text("Start New Chat")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(Color(red: 14/255, green: 16/255, blue: 19/255))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(AppTheme.mintAccent)
                        .shadow(color: AppTheme.mintAccent.opacity(0.35), radius: 10, x: 0, y: 3)
                )
            }
            .buttonStyle(.plain)

            // Search Bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))

                TextField("Search past threads...", text: $searchText)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.white)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.cardDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Conversation List

    private var conversationListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !todayConversations.isEmpty {
                    sectionGroup(title: "TODAY", conversations: todayConversations)
                }

                if !yesterdayConversations.isEmpty {
                    sectionGroup(title: "YESTERDAY", conversations: yesterdayConversations)
                }

                if !pastWeekConversations.isEmpty {
                    sectionGroup(title: "PREVIOUS 7 DAYS", conversations: pastWeekConversations)
                }

                if !olderConversations.isEmpty {
                    sectionGroup(title: "EARLIER", conversations: olderConversations)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func sectionGroup(title: String, conversations: [ChatConversation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
                .padding(.leading, 4)

            ForEach(conversations) { conv in
                threadCard(for: conv)
            }
        }
    }

    // MARK: - Thread Card Row

    private func threadCard(for conv: ChatConversation) -> some View {
        let isActive = conv.id == persistenceService.activeConversationId

        return Button(action: {
            AppTheme.hapticImpact(.medium)
            dismiss()
            onSelectThread(conv)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Top row: Title + Relative Date
                HStack(alignment: .top, spacing: 8) {
                    Text(conv.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()

                    Text(conv.relativeTimeDisplay)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }

                // Middle: Preview Snippet
                Text(conv.previewSnippet)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)

                // Bottom row: Model badge + Message count + Active Tag
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10, weight: .bold))
                        Text(conv.modelId)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(AppTheme.mintAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.mintAccent.opacity(0.12)))

                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 10))
                        Text("\(conv.messages.count) msgs")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.06)))

                    Spacer()

                    if isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppTheme.mintAccent)
                                .frame(width: 6, height: 6)
                            Text("ACTIVE")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.mintAccent)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppTheme.mintAccent.opacity(0.15)))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.cardDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isActive ? AppTheme.mintAccent.opacity(0.5) : Color.white.opacity(0.07),
                                lineWidth: isActive ? 1.5 : 1
                            )
                    )
                    .shadow(
                        color: isActive ? AppTheme.mintAccent.opacity(0.15) : Color.black.opacity(0.3),
                        radius: isActive ? 10 : 6,
                        x: 0,
                        y: 3
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: {
                conversationToRename = conv
                newTitleText = conv.title
                showRenameAlert = true
            }) {
                Label("Rename Thread", systemImage: "pencil")
            }

            Button(role: .destructive, action: {
                AppTheme.hapticImpact(.medium)
                let wasActive = (conv.id == persistenceService.activeConversationId)
                withAnimation {
                    persistenceService.deleteConversation(id: conv.id)
                }
                if wasActive {
                    onDeleteActiveThread?()
                }
            }) {
                Label("Delete Thread", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppTheme.cardDark)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Image(systemName: searchText.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(AppTheme.mintAccent)
            }

            VStack(spacing: 6) {
                Text(searchText.isEmpty ? "No Saved Threads" : "No Results Found")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(searchText.isEmpty
                     ? "When you start conversations with local models, your threads will be saved here automatically."
                     : "No conversations matched '\(searchText)'. Try another keyword.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Spacer()
        }
        .padding(.vertical, 40)
    }

    // MARK: - Bottom Clear History Bar

    private var bottomClearBar: some View {
        HStack {
            Spacer()
            Button(action: {
                showClearAllConfirmation = true
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("Clear All History")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(AppTheme.roseAccent.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(AppTheme.roseAccent.opacity(0.12)))
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .background(AppTheme.surfaceDark.opacity(0.95))
    }
}
