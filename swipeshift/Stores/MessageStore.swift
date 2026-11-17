//
//  MessageStore.swift
//  swipeShift
//

import Foundation
import Combine

@MainActor
final class MessageStore: ObservableObject {

    @Published var conversations:         [Conversation] = []
    @Published var employerConversations: [Conversation] = []
    @Published var isLoading = false
    /// Fehler beim Senden (z.B. blockiert) → ChatView zeigt einen Alert
    @Published var sendError: String?
    /// Text einer fehlgeschlagenen (nicht blockierten) Nachricht → ChatView schreibt ihn zurueck in die Eingabe
    @Published var failedDraft: FailedDraft?

    struct FailedDraft: Equatable {
        let id = UUID()
        let conversationId: String
        let text: String
    }

    // MARK: - Laden

    func loadConversations() async {
        isLoading = true
        do {
            let dtos = try await APIClient.shared.fetchConversations()
            let all  = dtos.map { $0.toDomain() }
            // Worker-Konversationen = alle die vom Backend kommen (Backend filtert nach role)
            conversations         = all
            employerConversations = all
        } catch {
            print("MessageStore: loadConversations error:", error)
        }
        isLoading = false
    }

    // MARK: - Sortierung

    var sortedConversations: [Conversation] {
        conversations.sorted(by: sortOrder)
    }

    var sortedEmployerConversations: [Conversation] {
        employerConversations.sorted(by: sortOrder)
    }

    private func sortOrder(_ a: Conversation, _ b: Conversation) -> Bool {
        if a.status.sortWeight != b.status.sortWeight {
            return a.status.sortWeight < b.status.sortWeight
        }
        if a.status == .today || a.status == .upcoming {
            if a.isRead != b.isRead { return !a.isRead }
        }
        return a.jobDate < b.jobDate
    }

    // MARK: - Unread-Counts

    var unreadCount: Int {
        conversations.filter { !$0.isRead }.count
    }

    var employerUnreadCount: Int {
        employerConversations.filter { !$0.isRead }.count
    }

    // MARK: - Als gelesen markieren

    func markAsRead(conversationId: String) {
        update(&conversations, id: conversationId) { $0.isRead = true }
        Task { try? await APIClient.shared.markConversationRead(conversationId: conversationId) }
    }

    func markEmployerConversationAsRead(conversationId: String) {
        update(&employerConversations, id: conversationId) { $0.isRead = true }
        Task { try? await APIClient.shared.markConversationRead(conversationId: conversationId) }
    }

    // MARK: - Nachricht senden

    func sendMessage(conversationId: String, text: String) {
        lastTypingPing[conversationId] = nil  // Server beendet Typing beim Senden
        let optimisticId = optimisticAppend(to: &conversations, conversationId: conversationId, text: text)
        Task {
            do {
                let dto = try await APIClient.shared.sendMessage(conversationId: conversationId, text: text)
                // Server-ID in die optimistisch hinzugefügte Nachricht zurückschreiben
                replaceOptimistic(in: &conversations, conversationId: conversationId, optimisticId: optimisticId, serverMsg: dto.toDomain())
            } catch {
                handleSendFailure(error, conversationId: conversationId, optimisticId: optimisticId, text: text)
            }
        }
    }

    func sendEmployerMessage(conversationId: String, text: String) {
        lastTypingPing[conversationId] = nil  // Server beendet Typing beim Senden
        let optimisticId = optimisticAppend(to: &employerConversations, conversationId: conversationId, text: text)
        Task {
            do {
                let dto = try await APIClient.shared.sendMessage(conversationId: conversationId, text: text)
                replaceOptimistic(in: &employerConversations, conversationId: conversationId, optimisticId: optimisticId, serverMsg: dto.toDomain())
            } catch {
                handleSendFailure(error, conversationId: conversationId, optimisticId: optimisticId, text: text)
            }
        }
    }

    // MARK: - Polling (neue Nachrichten seit letzter bekannter Nachricht)

    func refreshMessages(conversationId: String, isEmployerMode: Bool) async {
        let list = isEmployerMode ? employerConversations : conversations
        guard let conv = list.first(where: { $0.id == conversationId }) else { return }

        // Nur optimistische Nachrichten haben kein Server-Timestamp — wir nutzen das echte letzte
        let since = conv.messages
            .filter { !$0.id.hasPrefix("optimistic-") }
            .max(by: { $0.timestamp < $1.timestamp })?.timestamp

        do {
            let response = try await APIClient.shared.fetchMessages(conversationId: conversationId, since: since)
            let knownIds = Set(conv.messages.map(\.id))
            let incoming = response.messages.map { $0.toDomain() }.filter { !knownIds.contains($0.id) }
            let presence = response.presence?.toDomain() ?? conv.presence
            applyBlockFlags(conversationId: conversationId, byMe: response.blockedByMe, byOther: response.blockedByOther)

            if isEmployerMode {
                applyRefresh(&employerConversations, conversationId: conversationId, messages: incoming, presence: presence)
            } else {
                applyRefresh(&conversations, conversationId: conversationId, messages: incoming, presence: presence)
            }

            // Chat ist offen → neue Nachrichten der Gegenseite sofort als gelesen melden,
            // damit deren Lesebestaetigung stimmt.
            if incoming.contains(where: { !$0.isFromUser && !$0.isSystemMessage }) {
                try? await APIClient.shared.markConversationRead(conversationId: conversationId)
            }
        } catch {
            // Polling-Fehler still ignorieren — nächster Zyklus versucht es erneut
        }
    }

    private func applyRefresh(
        _ list: inout [Conversation],
        conversationId: String,
        messages: [ChatMessage],
        presence: ChatPresence
    ) {
        guard let idx = list.firstIndex(where: { $0.id == conversationId }) else { return }
        list[idx].messages.append(contentsOf: messages)
        if let last = messages.last {
            list[idx].lastMessage     = last.text
            list[idx].lastMessageTime = last.timestamp
        }
        list[idx].presence = presence

        // Lesebestaetigungen fuer bereits bekannte eigene Nachrichten nachziehen
        if let readAt = presence.otherLastReadAt {
            for mIdx in list[idx].messages.indices
            where list[idx].messages[mIdx].isFromUser
                && !list[idx].messages[mIdx].isReadByOther
                && !list[idx].messages[mIdx].id.hasPrefix("optimistic-")
                && list[idx].messages[mIdx].timestamp <= readAt {
                list[idx].messages[mIdx].isReadByOther = true
            }
        }
    }

    // MARK: - Blockieren / Speichern (lokaler Zustand, nachdem das Backend bestaetigt hat)

    func applyBlockFlags(conversationId: String, byMe: Bool?, byOther: Bool?) {
        guard let byMe, let byOther else { return }
        mutateEverywhere(conversationId) { $0.blockedByMe = byMe; $0.blockedByOther = byOther }
    }

    func setCounterpartSaved(conversationId: String, saved: Bool) {
        mutateEverywhere(conversationId) { $0.isCounterpartSaved = saved }
    }

    private func mutateEverywhere(_ id: String, _ mutation: (inout Conversation) -> Void) {
        update(&conversations, id: id, mutation: mutation)
        update(&employerConversations, id: id, mutation: mutation)
    }

    /// Fehlgeschlagene Nachricht zurueckrollen und Grund melden (BLOCKED → Eingabe sperren)
    private func handleSendFailure(_ error: Error, conversationId: String, optimisticId: String, text: String) {
        let isBlocked = (error as? APIError)?.code == "BLOCKED"
        mutateEverywhere(conversationId) { conv in
            if let mIdx = conv.messages.firstIndex(where: { $0.id == optimisticId }) {
                conv.messages.remove(at: mIdx)
                if let last = conv.messages.last {
                    conv.lastMessage = last.text
                    conv.lastMessageTime = last.timestamp
                }
            }
            if isBlocked { conv.blockedByOther = true }
        }
        if !isBlocked { failedDraft = FailedDraft(conversationId: conversationId, text: text) }
        sendError = error.localizedDescription
    }

    // MARK: - Typing-Indicator (eigene Seite)

    /// Letzter gesendeter Typing-Ping pro Konversation (Drosselung, Server-Fenster ist 6 s)
    private var lastTypingPing: [String: Date] = [:]
    private let typingPingInterval: TimeInterval = 3

    /// Bei jeder Eingabe aufrufen — sendet hoechstens alle 3 s einen Ping.
    func userIsTyping(conversationId: String) {
        let now = Date()
        if let last = lastTypingPing[conversationId], now.timeIntervalSince(last) < typingPingInterval { return }
        lastTypingPing[conversationId] = now
        Task { try? await APIClient.shared.sendTypingStatus(conversationId: conversationId, isTyping: true) }
    }

    /// Beim Leeren des Eingabefelds / Verlassen des Chats aufrufen.
    func userStoppedTyping(conversationId: String) {
        guard lastTypingPing.removeValue(forKey: conversationId) != nil else { return }
        Task { try? await APIClient.shared.sendTypingStatus(conversationId: conversationId, isTyping: false) }
    }

    // MARK: - Helpers

    private func update(_ list: inout [Conversation], id: String, mutation: (inout Conversation) -> Void) {
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        mutation(&list[idx])
    }

    @discardableResult
    private func optimisticAppend(to list: inout [Conversation], conversationId: String, text: String) -> String {
        let id = "optimistic-\(UUID().uuidString)"
        guard let idx = list.firstIndex(where: { $0.id == conversationId }) else { return id }
        let msg = ChatMessage(
            id:              id,
            text:            text,
            isFromUser:      true,
            timestamp:       Date(),
            isSystemMessage: false
        )
        list[idx].messages.append(msg)
        list[idx].lastMessage     = text
        list[idx].lastMessageTime = Date()
        return id
    }

    private func replaceOptimistic(in list: inout [Conversation], conversationId: String, optimisticId: String, serverMsg: ChatMessage) {
        guard let cIdx = list.firstIndex(where: { $0.id == conversationId }) else { return }
        if let mIdx = list[cIdx].messages.firstIndex(where: { $0.id == optimisticId }) {
            list[cIdx].messages[mIdx] = serverMsg
        }
    }
}
