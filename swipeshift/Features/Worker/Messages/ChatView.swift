//
//  ChatView.swift
//  swipeShift
//

import SwiftUI

struct ChatView: View {
    let conversation: Conversation
    var isEmployerMode: Bool = false

    @EnvironmentObject var messageStore: MessageStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    @State private var inputText = ""
    @State private var scrollToBottom = false
    @State var showRatingSheet = false
    @State var reviewSubmitted = false
    @State var jobDetailJob: Job? = nil
    @State var loadingJobDetail = false
    @State var showReportSheet = false
    @State var showBlockConfirm = false
    @State var showSupportFallback = false
    @State var showWorkerProfile = false
    @State var isBusy = false
    @State var actionError: String?

    var isReadOnly: Bool {
        conversation.status == .completed || conversation.status == .cancelled
    }

    /// Polling-Intervall waehrend der Chat offen ist. Kurz gehalten, damit Typing-Indicator
    /// und Lesebestaetigungen ohne WebSocket "live" wirken.
    private let pollInterval: Duration = .seconds(3)

    private var liveConversation: Conversation? {
        let pool = isEmployerMode ? messageStore.employerConversations : messageStore.conversations
        return pool.first(where: { $0.id == conversation.id })
    }

    /// Aktueller Stand (Polling aktualisiert Blockier-/Gespeichert-Flags im Store)
    var live: Conversation { liveConversation ?? conversation }

    private var currentMessages: [ChatMessage] {
        liveConversation?.messages ?? conversation.messages
    }

    var presence: ChatPresence {
        liveConversation?.presence ?? conversation.presence
    }

    /// Typing nur in aktiven Chats anzeigen
    private var showTypingIndicator: Bool {
        !isReadOnly && presence.otherIsTyping
    }

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            DSDivider()
            ChatJobInfoCard(conversation: live, onViewJob: openJobDetails, isLoadingJob: loadingJobDetail)
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.top, DS.Spacing.xs)
            messageList
            inputBar
        }
        .dsBackground()
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
        .onChange(of: messageStore.failedDraft) { _, draft in
            restoreFailedDraft(draft)
        }
        .onAppear {
            // Fehlgeschlagener Text, waehrend der Chat geschlossen war
            restoreFailedDraft(messageStore.failedDraft)
        }
        .onDisappear {
            messageStore.userStoppedTyping(conversationId: conversation.id)
        }
        .sheet(item: $jobDetailJob) { job in
            NavigationStack {
                JobDetailView(job: job)
            }
        }
        .sheet(isPresented: $showReportSheet) {
            if let userId = conversation.counterpartUserId {
                ReportUserSheet(conversation: live, userId: userId)
            }
        }
        .navigationDestination(isPresented: $showWorkerProfile) { workerProfileDestination }
        .alert(live.blockedByMe ? "Unblock \(conversation.company)?" : "Block \(conversation.company)?",
               isPresented: $showBlockConfirm) {
            Button(live.blockedByMe ? "Unblock" : "Block", role: live.blockedByMe ? nil : .destructive) {
                Task { await toggleBlock() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(live.blockedByMe
                 ? "You will be able to message each other again."
                 : "Neither of you will be able to send messages in this conversation. You can still read it, and you can unblock at any time.")
        }
        .alert("Contact support", isPresented: $showSupportFallback) {
            Button("Copy address") { UIPasteboard.general.string = ChatSafety.supportEmail }
            Button("OK", role: .cancel) {}
        } message: {
            Text("No mail app available. Write to \(ChatSafety.supportEmail) and mention \"\(conversation.jobTitle)\" (conversation \(conversation.id)).")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert("Message not sent", isPresented: Binding(
            get: { messageStore.sendError != nil },
            set: { if !$0 { messageStore.sendError = nil } }
        )) {
            Button("OK", role: .cancel) { messageStore.sendError = nil }
        } message: {
            Text(messageStore.sendError ?? "")
        }
        .sheet(isPresented: $showRatingSheet) {
            if isEmployerMode {
                // workerId/jobCategory kennt der Chat-Kontext nicht; das Formular nutzt sie nicht
                ChatReviewFormLoader(
                    review: PendingReviewItem(
                        applyId:     conversation.applyId,
                        workerId:    "",
                        workerName:  conversation.company,
                        workerPhoto: nil,
                        jobId:       conversation.jobId,
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
                LazyVStack(spacing: DS.Spacing.xs) {
                    safetyNotice
                    ForEach(Array(currentMessages.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || !Calendar.current.isDate(
                            message.timestamp, inSameDayAs: currentMessages[index - 1].timestamp
                        ) {
                            DateSeparator(date: message.timestamp)
                        }
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
                .dsAnimation(.snappy, value: showTypingIndicator)
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.vertical, DS.Spacing.sm)
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
        } else if live.isBlocked {
            blockedBar
        } else {
            activeInputBar
        }
    }

    private var readOnlyBar: some View {
        let completed = conversation.status == .completed
        let tone: DS.Tone = completed ? .success : .danger
        return VStack(spacing: DS.Spacing.xs) {
            if completed { completionSection }
            // Getoenter Block: Hinweis + Rating-Link
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(tone.foreground)
                    .accessibilityHidden(true)
                Text(completed ? "This conversation is closed." : "This shift was cancelled.")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text)

                Spacer(minLength: DS.Spacing.xs)

                // Rating-Link bei Completed
                if completed {
                    if reviewSubmitted {
                        Label("Review Submitted", systemImage: "star.fill")
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.text2)
                    } else {
                        Button("Leave Review") {
                            DS.Haptics.light()
                            showRatingSheet = true
                        }
                        .font(DS.Font.make(14, .bold))
                        .foregroundStyle(DS.Color.primaryText)
                        .frame(minHeight: 44)
                        .buttonStyle(.dsPressable)
                    }
                }
            }
            .padding(DS.Spacing.inset)
            .background(tone.soft, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.bg)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeInputBar: some View {
        VStack(spacing: 0) {
            DSDivider()
            HStack(alignment: .bottom, spacing: DS.Spacing.xs) {
                // Look wie DSTextField (ohne Label)
                TextField("Message...", text: $inputText,
                          prompt: Text("Message...").foregroundStyle(DS.Color.muted), axis: .vertical)
                    .font(DS.Font.make(15, .medium))
                    .foregroundStyle(DS.Color.text)
                    .tint(DS.Color.primary)
                    .lineLimit(1...5)
                    .padding(.horizontal, DS.Spacing.inset)
                    .padding(.vertical, DS.Spacing.sm)
                    .frame(minHeight: 48)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .strokeBorder(DS.Color.border, lineWidth: 1)
                    )

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(DS.Font.make(17, .bold))
                        .foregroundStyle(DS.Color.onPrimary)
                        .frame(width: 48, height: 48)
                        .background(canSend ? DS.Color.primary : DS.Color.muted.opacity(0.4), in: Circle())
                }
                .buttonStyle(.dsPressable)
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.bg)
        }
    }

    /// Schreibt den Text einer fehlgeschlagenen Nachricht zurueck in die Eingabe;
    /// steht dort schon etwas, wird er angehaengt statt verworfen.
    private func restoreFailedDraft(_ draft: MessageStore.FailedDraft?) {
        guard let draft, draft.conversationId == conversation.id else { return }
        inputText = inputText.isEmpty ? draft.text : inputText + "\n" + draft.text
        messageStore.failedDraft = nil
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        DS.Haptics.light()
        inputText = ""
        if isEmployerMode {
            messageStore.sendEmployerMessage(conversationId: conversation.id, text: text)
        } else {
            messageStore.sendMessage(conversationId: conversation.id, text: text)
        }
    }
}

// MARK: - ChatReviewFormLoader

/// Laedt einen vorhandenen Entwurf fuer diese Bewerbung, bevor das Formular editierbar wird
/// (sonst wuerde "Save as Draft" den Entwurf mit Leerwerten ueberschreiben).
private struct ChatReviewFormLoader: View {
    let review: PendingReviewItem
    let onSuccess: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var draft: ReviewDraftValues? = nil
    @State private var isLoaded = false
    @State private var loadError: String? = nil

    var body: some View {
        Group {
            if isLoaded {
                ReviewFormSheet(review: review, initialDraft: draft, onSuccess: onSuccess)
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                    Text("Loading review…").dsFont(.callout).foregroundStyle(DS.Color.text2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
        .alert("Could not load draft", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(loadError ?? "")
        }
    }

    private func load() async {
        do {
            let drafts = try await APIClient.shared.fetchReviewDrafts()
            draft = drafts.first { $0.review.applyId == review.applyId }?.draft
            isLoaded = true
        } catch {
            loadError = error.localizedDescription
        }
    }
}
