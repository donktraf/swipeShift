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
        ZStack {
            SS.background().ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: - Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Messages")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        if unread > 0 {
                            Text("\(unread) unread message\(unread == 1 ? "" : "s")")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        } else {
                            Text("All read")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)

                // MARK: - Liste oder Leerzustand
                if activeConversations.isEmpty {
                    emptyView
                } else {
                    conversationList
                }
            }
        }
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
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        if isEmployerMode {
                            messageStore.markEmployerConversationAsRead(conversationId: conversation.id)
                        } else {
                            messageStore.markAsRead(conversationId: conversation.id)
                        }
                    })

                    Divider()
                        .padding(.leading, 74)
                        .background(Color.white.opacity(0.08))
                }
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 0)
            .padding(.bottom, 32)
        }
        .refreshable {
            await messageStore.loadConversations()
        }
    }

    // MARK: - Leerzustand
    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 52))
                .foregroundColor(.white.opacity(0.3))

            VStack(spacing: 8) {
                Text("No conversations yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                if isEmployerMode {
                    Text("Once you accept an applicant, your chat with them will appear here.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                } else {
                    Text("Once an employer accepts your application, your chat will appear here.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    NavigationLink {
                        JobListView()
                    } label: {
                        Text("Browse Jobs")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(SS.primary)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 13)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                    }
                }
            }

            Spacer()
        }
    }
}

// MARK: - ConversationRow
private struct ConversationRow: View {
    let conversation: Conversation
    var isEmployerMode: Bool = false

    var body: some View {
        HStack(spacing: 12) {

            // Logo
            ZStack(alignment: .topTrailing) {
                ChatAvatar(photoUrl: conversation.counterpartPhotoUrl, emoji: conversation.logoEmoji, size: 50)

                // Ungelesen-Punkt
                if !conversation.isRead {
                    Circle()
                        .fill(SS.primary)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Employer: worker name as title; Worker: job title as title
                    Text(isEmployerMode ? conversation.company : conversation.jobTitle)
                        .font(.system(size: 15, weight: conversation.isRead ? .semibold : .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    StatusBadge(status: conversation.status)

                    Spacer()

                    Text(conversation.lastMessageTime.relativeLabel)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Text(isEmployerMode ? conversation.jobTitle : conversation.company)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text(conversation.blockedByMe ? "Blocked" : conversation.lastMessage)
                    .font(.system(size: 13))
                    .foregroundColor(conversation.isRead ? .secondary : .primary)
                    .fontWeight(conversation.isRead ? .regular : .medium)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - StatusBadge
struct StatusBadge: View {
    let status: ConversationStatus

    private var colors: (background: Color, foreground: Color) {
        switch status {
        case .today:     return (Color.blue.opacity(0.15),   .blue)
        case .upcoming:  return (Color.green.opacity(0.15),  .green)
        case .completed: return (Color.gray.opacity(0.12),   .gray)
        case .cancelled: return (Color.red.opacity(0.12),    .red)
        }
    }

    var body: some View {
        Text(status.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(colors.foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(colors.background)
            .clipShape(Capsule())
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
