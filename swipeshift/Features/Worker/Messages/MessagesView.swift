//
//  MessagesView.swift
//  swipeShift
//

import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var messageStore: MessageStore
    var isEmployerMode: Bool = false
    @ObservedObject private var push = PushNotificationManager.shared
    // Chat, der durch Tap auf eine Push-Benachrichtigung geoeffnet wird
    @State private var pushConversation: Conversation?
    @State private var showPushChat = false

    private var activeConversations: [Conversation] {
        isEmployerMode ? messageStore.sortedEmployerConversations : messageStore.sortedConversations
    }
    private var unread: Int {
        isEmployerMode ? messageStore.employerUnreadCount : messageStore.unreadCount
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Header
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Messages")
                    .dsFont(.display)
                    .foregroundStyle(DS.Color.text)
                    .accessibilityAddTraits(.isHeader)
                Text(unread > 0 ? "\(unread) unread message\(unread == 1 ? "" : "s")" : "All read")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.xs)
            .padding(.bottom, DS.Spacing.sm)

            // MARK: - Liste oder Leerzustand
            if activeConversations.isEmpty {
                emptyView
            } else {
                conversationList
            }
        }
        .dsBackground()
        .navigationDestination(isPresented: $showPushChat) {
            if let pushConversation {
                ChatView(conversation: pushConversation, isEmployerMode: isEmployerMode)
                    .environmentObject(messageStore)
            }
        }
        // Konversationen koennen beim Tap noch laden → bei Aenderung erneut versuchen
        .onChange(of: push.pendingConversationId, initial: true) { _, id in
            guard id != nil else { return }
            Task {
                if openPushConversation() { return }
                // Evtl. neue Konversation → einmal frisch laden; weiterhin unbekannt → Route verwerfen
                await messageStore.loadConversations()
                if !openPushConversation() { push.pendingConversationId = nil }
            }
        }
    }

    @discardableResult
    private func openPushConversation() -> Bool {
        guard let id = push.pendingConversationId,
              let conversation = messageStore.conversations.first(where: { $0.id == id }) else { return false }
        push.pendingConversationId = nil
        pushConversation = conversation
        showPushChat = true
        return true
    }

    // MARK: - Konversationsliste
    private var conversationList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(activeConversations) { conversation in
                    NavigationLink {
                        ChatView(conversation: conversation, isEmployerMode: isEmployerMode)
                            .environmentObject(messageStore)
                    } label: {
                        ConversationRow(conversation: conversation, isEmployerMode: isEmployerMode)
                    }
                    .buttonStyle(.dsPressable)
                    .simultaneousGesture(TapGesture().onEnded {
                        DS.Haptics.light()
                        if isEmployerMode {
                            messageStore.markEmployerConversationAsRead(conversationId: conversation.id)
                        } else {
                            messageStore.markAsRead(conversationId: conversation.id)
                        }
                    })

                    DSDivider()
                        .padding(.leading, DS.Spacing.screenEdge + 52 + DS.Spacing.sm)
                }
            }
            .padding(.bottom, DS.Spacing.xxl)
        }
        // Worker: Liste scrollt unter der schwebenden TabBar weiter
        .contentMargins(.bottom, isEmployerMode ? 0 : DS.tabBarInset, for: .scrollContent)
        .refreshable {
            await messageStore.loadConversations()
        }
    }

    // MARK: - Leerzustand
    private var emptyView: some View {
        ScrollView {
            Group {
                if isEmployerMode {
                    DSEmptyState(
                        systemIcon: "bubble.left.and.bubble.right",
                        title: "No conversations yet",
                        message: "Once you accept an applicant, your chat with them will appear here."
                    )
                } else {
                    VStack(spacing: DS.Spacing.xs) {
                        DSEmptyState(
                            systemIcon: "bubble.left.and.bubble.right",
                            title: "No conversations yet",
                            message: "Once an employer accepts your application, your chat will appear here."
                        )
                        NavigationLink {
                            JobListView()
                        } label: {
                            Text("Browse Jobs")
                        }
                        .buttonStyle(.ds(.primary, size: .medium, fullWidth: false))
                    }
                }
            }
            .padding(.top, DS.Spacing.xxl)
        }
        .refreshable { await messageStore.loadConversations() }
    }
}

// MARK: - ConversationRow (flache Zeile)
private struct ConversationRow: View {
    let conversation: Conversation
    var isEmployerMode: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            ChatAvatar(photoUrl: conversation.counterpartPhotoUrl, emoji: conversation.logoEmoji, size: 52)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    // Employer: worker name as title; Worker: job title as title
                    Text(isEmployerMode ? conversation.company : conversation.jobTitle)
                        .font(DS.Font.make(15, conversation.isRead ? .semibold : .bold))
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(1)
                    Spacer(minLength: DS.Spacing.xxs)
                    Text(conversation.lastMessageTime.relativeLabel)
                        .dsFont(.caption)
                        .foregroundStyle(conversation.isRead ? DS.Color.muted : DS.Color.primaryText)
                }

                HStack(spacing: DS.Spacing.xs) {
                    Text(isEmployerMode ? conversation.jobTitle : conversation.company)
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.text2)
                        .lineLimit(1)
                    StatusBadge(status: conversation.status)
                }

                HStack(spacing: DS.Spacing.xs) {
                    Text(conversation.blockedByMe ? "Blocked" : conversation.lastMessage)
                        .font(DS.Font.make(14, conversation.isRead ? .regular : .semibold))
                        .foregroundStyle(conversation.isRead ? DS.Color.text2 : DS.Color.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    // Ungelesen-Punkt nur bei ungelesener Nachricht
                    if !conversation.isRead {
                        Circle()
                            .fill(DS.Color.primary)
                            .frame(width: 10, height: 10)
                            .accessibilityLabel("Unread")
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - StatusBadge
struct StatusBadge: View {
    let status: ConversationStatus

    var body: some View {
        switch status {
        case .today:     DSBadge(status.label, .today)
        case .upcoming:  DSBadge(status.label, .upcoming)
        case .completed: DSBadge(status.label, .completed)
        case .cancelled: DSBadge(status.label, .cancelled)
        }
    }
}

// MARK: - Date Helper
private extension Date {
    var relativeLabel: String {
        let diff = Date().timeIntervalSince(self)
        if diff < 60 { return "Now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        let days = Int(diff / 86400)
        if days < 7 { return "\(days)d" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: self)
    }
}
