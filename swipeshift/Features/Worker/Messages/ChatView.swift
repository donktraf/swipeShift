//
//  ChatView.swift
//  swipeShift
//

import SwiftUI

struct ChatView: View {
    let conversation: Conversation
    var isEmployerMode: Bool = false

    @EnvironmentObject var messageStore: MessageStore
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var scrollToBottom = false
    @State private var showRatingSheet = false
    @State private var reviewSubmitted = false
    @State private var jobDetailJob: Job? = nil
    @State private var loadingJobDetail = false

    private var isReadOnly: Bool {
        conversation.status == .completed || conversation.status == .cancelled
    }

    /// Polling-Intervall waehrend der Chat offen ist. Kurz gehalten, damit Typing-Indicator
    /// und Lesebestaetigungen ohne WebSocket "live" wirken.
    private let pollInterval: Duration = .seconds(3)

    private var liveConversation: Conversation? {
        let pool = isEmployerMode ? messageStore.employerConversations : messageStore.conversations
        return pool.first(where: { $0.id == conversation.id })
    }

    private var currentMessages: [ChatMessage] {
        liveConversation?.messages ?? conversation.messages
    }

    private var presence: ChatPresence {
        liveConversation?.presence ?? conversation.presence
    }

    /// Typing nur in aktiven Chats anzeigen
    private var showTypingIndicator: Bool {
        !isReadOnly && presence.otherIsTyping
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
            if isEmployerMode {
                messageStore.markEmployerConversationAsRead(conversationId: conversation.id)
            } else {
                messageStore.markAsRead(conversationId: conversation.id)
            }
        }
        .task(id: conversation.id) {
            guard !isReadOnly else { return }
            // Sofort einmal laden (Presence/Lesestatus aktuell), dann im Intervall pollen
            while !Task.isCancelled {
                await messageStore.refreshMessages(
                    conversationId: conversation.id,
                    isEmployerMode: isEmployerMode
                )
                try? await Task.sleep(for: pollInterval)
            }
        }
        .onChange(of: inputText) { _, newValue in
            guard !isReadOnly else { return }
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messageStore.userStoppedTyping(conversationId: conversation.id)
            } else {
                messageStore.userIsTyping(conversationId: conversation.id)
            }
        }
        .onDisappear {
            messageStore.userStoppedTyping(conversationId: conversation.id)
        }
        .sheet(item: $jobDetailJob) { job in
            NavigationStack {
                JobDetailView(job: job)
            }
        }
        .sheet(isPresented: $showRatingSheet) {
            if isEmployerMode {
                ReviewFormSheet(
                    review: PendingReviewItem(
                        applyId:     conversation.applyId,
                        workerId:    "",
                        workerName:  conversation.company,
                        workerPhoto: nil,
                        jobId:       "",
                        jobTitle:    conversation.jobTitle,
                        jobCategory: "",
                        shiftDate:   conversation.jobDate,
                        logoEmoji:   conversation.logoEmoji
                    )
                ) { reviewSubmitted = true }
            } else {
                EmployerRatingSheet(
                    applyId:     conversation.applyId,
                    companyName: conversation.company,
                    jobTitle:    conversation.jobTitle
                ) { reviewSubmitted = true }
            }
        }
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
                    if showTypingIndicator {
                        TypingBubble(logoEmoji: conversation.logoEmoji)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: showTypingIndicator)
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
            .onChange(of: showTypingIndicator) { _, isTyping in
                guard isTyping else { return }
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
                    if reviewSubmitted {
                        Label("Review Submitted", systemImage: "star.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    } else {
                        Button("Leave Review") { showRatingSheet = true }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SS.primary)
                    }
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
        if isEmployerMode {
            messageStore.sendEmployerMessage(conversationId: conversation.id, text: text)
        } else {
            messageStore.sendMessage(conversationId: conversation.id, text: text)
        }
    }
}

// MARK: - Header (Extension, haelt den Struct-Body unter dem SwiftLint-Limit)
extension ChatView {
    // MARK: - Header
    private var chatHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
            }

            // Avatar: Employer → worker emoji; Worker → company logo (tippbar)
            if isEmployerMode {
                Text(conversation.logoEmoji)
                    .font(.system(size: 22))
                    .frame(width: 40, height: 40)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(Circle())
            } else {
                NavigationLink {
                    CompanyProfileView(
                        companyName: conversation.company,
                        logoEmoji:   conversation.logoEmoji
                    )
                } label: {
                    Text(conversation.logoEmoji)
                        .font(.system(size: 22))
                        .frame(width: 40, height: 40)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    // `company` wird serverseitig (routes.messages.js) je nach Rolle bereits
                    // mit dem richtigen Anzeigenamen befuellt (Worker: company name; Employer:
                    // worker name) — keine clientseitige Fallunterscheidung noetig.
                    Text(conversation.company)
                        .font(.system(size: 16, weight: .semibold))
                    StatusBadge(status: conversation.status)
                }
                Text(conversation.jobTitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if !isReadOnly {
                    PresenceLine(presence: presence)
                }
            }

            Spacer()

            // Info-Button → JobDetailView
            Button {
                guard !loadingJobDetail else { return }
                loadingJobDetail = true
                Task {
                    jobDetailJob = try? await APIClient.shared.fetchJob(jobId: conversation.jobId)
                    loadingJobDetail = false
                }
            } label: {
                if loadingJobDetail {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .foregroundColor(SS.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }
}
