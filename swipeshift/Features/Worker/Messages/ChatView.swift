//
//  ChatView.swift
//  swipeShift
//

import SwiftUI

struct ChatView: View {
    let conversation: Conversation

    @EnvironmentObject var messageStore: MessageStore
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var scrollToBottom = false

    private var isReadOnly: Bool {
        conversation.status == .completed || conversation.status == .cancelled
    }

    // Aktuell immer aus dem Store holen damit sendMessage live aktualisiert
    private var currentMessages: [ChatMessage] {
        messageStore.conversations
            .first(where: { $0.id == conversation.id })?
            .messages ?? conversation.messages
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                chatHeader
                Divider()
                messageList
                inputBar
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            messageStore.markAsRead(conversationId: conversation.id)
        }
    }

    // MARK: - Header
    private var chatHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
            }

            // Logo (tippbar → TODO: Company Profile)
            Text(conversation.logoEmoji)
                .font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(conversation.company)
                        .font(.system(size: 16, weight: .semibold))
                    StatusBadge(status: conversation.status)
                }
                Text(conversation.jobTitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Info-Button → TODO: JobDetailView
            Button {
                // TODO: Navigation zu JobDetailView des Jobs
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .foregroundColor(SS.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Nachrichtenliste
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(currentMessages) { message in
                        if message.isSystemMessage {
                            SystemMessageBubble(text: message.text)
                        } else if message.isFromUser {
                            UserBubble(message: message)
                        } else {
                            EmployerBubble(message: message, logoEmoji: conversation.logoEmoji)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // Unsichtbarer Anker am Ende für automatisches Scrollen
                Color.clear.frame(height: 1).id("bottom")
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: currentMessages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input Bar
    @ViewBuilder
    private var inputBar: some View {
        if isReadOnly {
            readOnlyBar
        } else {
            activeInputBar
        }
    }

    private var readOnlyBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: conversation.status == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(conversation.status == .completed ? .green : .red)
                    .font(.system(size: 16))
                Text(conversation.status == .completed
                    ? "This conversation is closed."
                    : "This shift was cancelled.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Spacer()

                // Rating-Link bei Completed
                if conversation.status == .completed {
                    Button("Leave Review") {
                        // TODO: Navigation zu ReviewScreen
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SS.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground))
            .padding(.bottom, 20)
        }
    }

    private var activeInputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.gray.opacity(0.3)
                            : SS.primary)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
            .padding(.bottom, 16)
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        messageStore.sendMessage(conversationId: conversation.id, text: text)
    }
}

// MARK: - Nachrichten-Blasen

/// System-Nachricht: zentriert, kursiv (z.B. "Bewerbung angenommen", "Schicht abgeschlossen")
private struct SystemMessageBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 24)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .italic()
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Capsule())
            Spacer(minLength: 24)
        }
        .padding(.vertical, 4)
    }
}

/// Nachricht vom Worker (rechts, lila)
private struct UserBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 3) {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(SS.primary)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18)
                    )
                    .clipShape(
                        .rect(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: 18,
                            bottomTrailingRadius: 4,
                            topTrailingRadius: 18
                        )
                    )
                Text(message.timestamp.timeLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Nachricht vom Arbeitgeber (links, grau)
private struct EmployerBubble: View {
    let message: ChatMessage
    let logoEmoji: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(logoEmoji)
                .font(.system(size: 16))
                .frame(width: 28, height: 28)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(
                        .rect(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: 4,
                            bottomTrailingRadius: 18,
                            topTrailingRadius: 18
                        )
                    )
                    .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                Text(message.timestamp.timeLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 60)
        }
    }
}

// MARK: - Date Helper
private extension Date {
    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }
}
