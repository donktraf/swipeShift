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
        optimisticAppend(to: &conversations, conversationId: conversationId, text: text)
        Task {
            do {
                let dto = try await APIClient.shared.sendMessage(conversationId: conversationId, text: text)
                // Server-ID in die optimistisch hinzugefügte Nachricht zurückschreiben
                replaceOptimistic(in: &conversations, conversationId: conversationId, serverMsg: dto.toDomain())
            } catch {
                print("sendMessage error:", error)
            }
        }
    }

    func sendEmployerMessage(conversationId: String, text: String) {
        optimisticAppend(to: &employerConversations, conversationId: conversationId, text: text)
        Task {
            do {
                let dto = try await APIClient.shared.sendMessage(conversationId: conversationId, text: text)
                replaceOptimistic(in: &employerConversations, conversationId: conversationId, serverMsg: dto.toDomain())
            } catch {
                print("sendEmployerMessage error:", error)
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
            let dtos = try await APIClient.shared.fetchMessages(conversationId: conversationId, since: since)
            let newMessages = dtos.map { $0.toDomain() }
            guard !newMessages.isEmpty else { return }

            let knownIds = Set(conv.messages.map(\.id))
            let incoming = newMessages.filter { !knownIds.contains($0.id) }
            guard !incoming.isEmpty else { return }

            if isEmployerMode {
                appendMessages(&employerConversations, conversationId: conversationId, messages: incoming)
            } else {
                appendMessages(&conversations, conversationId: conversationId, messages: incoming)
            }
        } catch {
            // Polling-Fehler still ignorieren — nächster Zyklus versucht es erneut
        }
    }

    private func appendMessages(_ list: inout [Conversation], conversationId: String, messages: [ChatMessage]) {
        guard let idx = list.firstIndex(where: { $0.id == conversationId }) else { return }
        list[idx].messages.append(contentsOf: messages)
        if let last = messages.last {
            list[idx].lastMessage     = last.text
            list[idx].lastMessageTime = last.timestamp
        }
    }

    // MARK: - Helpers

    private func update(_ list: inout [Conversation], id: String, mutation: (inout Conversation) -> Void) {
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        mutation(&list[idx])
    }

    private func optimisticAppend(to list: inout [Conversation], conversationId: String, text: String) {
        guard let idx = list.firstIndex(where: { $0.id == conversationId }) else { return }
        let msg = ChatMessage(
            id:              "optimistic-\(UUID().uuidString)",
            text:            text,
            isFromUser:      true,
            timestamp:       Date(),
            isSystemMessage: false
        )
        list[idx].messages.append(msg)
        list[idx].lastMessage     = text
        list[idx].lastMessageTime = Date()
    }

    private func replaceOptimistic(in list: inout [Conversation], conversationId: String, serverMsg: ChatMessage) {
        guard let cIdx = list.firstIndex(where: { $0.id == conversationId }) else { return }
        if let mIdx = list[cIdx].messages.firstIndex(where: { $0.id.hasPrefix("optimistic-") }) {
            list[cIdx].messages[mIdx] = serverMsg
        }
    }
}
