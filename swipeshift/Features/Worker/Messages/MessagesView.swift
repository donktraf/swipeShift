//
//  MessagesView.swift
//  swipeShift
//

import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var messageStore: MessageStore

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
                        if messageStore.unreadCount > 0 {
                            Text("\(messageStore.unreadCount) unread message\(messageStore.unreadCount == 1 ? "" : "s")")
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
                if messageStore.conversations.isEmpty {
                    emptyView
                } else {
                    conversationList
                }
            }
        }
    }

    // MARK: - Konversationsliste
    private var conversationList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(messageStore.sortedConversations) { conversation in
                    NavigationLink {
                        ChatView(conversation: conversation)
                            .environmentObject(messageStore)
                    } label: {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        messageStore.markAsRead(conversationId: conversation.id)
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
                Text("Once an employer accepts your application, your chat will appear here.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

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

            Spacer()
        }
    }
}

// MARK: - ConversationRow
private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {

            // Logo
            ZStack(alignment: .topTrailing) {
                Text(conversation.logoEmoji)
                    .font(.system(size: 26))
                    .frame(width: 50, height: 50)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(Circle())

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
                    Text(conversation.jobTitle)
                        .font(.system(size: 15, weight: conversation.isRead ? .semibold : .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    StatusBadge(status: conversation.status)

                    Spacer()

                    Text(conversation.lastMessageTime.relativeLabel)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Text(conversation.company)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text(conversation.lastMessage)
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
