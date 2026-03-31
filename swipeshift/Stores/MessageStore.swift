//
//  MessageStore.swift
//  swipeShift
//

import Foundation
import Combine

/// Zentraler Store für Konversationen und Chat-Nachrichten.
/// TODO: Backend-Anbindung via GET /messages + WebSocket/Polling
@MainActor
final class MessageStore: ObservableObject {

    @Published var conversations: [Conversation] = []

    init() {
        conversations = Self.makeMockConversations()
    }

    // MARK: - Sortierung (laut Wireframe)
    // 1) Today (nächste 24h)
    // 2) Upcoming nach Datum
    // 3) Completed
    // 4) Cancelled
    // Innerhalb Today/Upcoming: ungelesene zuerst
    var sortedConversations: [Conversation] {
        conversations.sorted { a, b in
            if a.status.sortWeight != b.status.sortWeight {
                return a.status.sortWeight < b.status.sortWeight
            }
            // Innerhalb aktiver Gruppen: ungelesen vor gelesen
            if a.status == .today || a.status == .upcoming {
                if a.isRead != b.isRead { return !a.isRead }
            }
            return a.jobDate < b.jobDate
        }
    }

    // MARK: - Aktionen

    func markAsRead(conversationId: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].isRead = true
    }

    func sendMessage(conversationId: String, text: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let msg = ChatMessage(
            id: UUID().uuidString,
            text: text,
            isFromUser: true,
            timestamp: Date(),
            isSystemMessage: false
        )
        conversations[idx].messages.append(msg)
        conversations[idx].lastMessage = text
        conversations[idx].lastMessageTime = Date()
        // TODO: POST /messages/:jobId an Backend senden
    }

    var unreadCount: Int {
        conversations.filter { !$0.isRead }.count
    }

    // MARK: - Mock-Daten
    private static func makeMockConversations() -> [Conversation] {
        let now = Date()
        let inTwoHours   = now.addingTimeInterval(2 * 3600)
        let inThreeDays  = now.addingTimeInterval(3 * 24 * 3600)
        let threeDaysAgo = now.addingTimeInterval(-3 * 24 * 3600)
        let oneWeekAgo   = now.addingTimeInterval(-7 * 24 * 3600)

        return [
            // 1) Today – ungelesen
            Conversation(
                id: "conv-1",
                jobTitle: "Event Staff",
                company: "Berlin Events GmbH",
                logoEmoji: "🎪",
                status: .today,
                jobDate: inTwoHours,
                lastMessage: "Could you please come 15 minutes earlier?",
                lastMessageTime: now.addingTimeInterval(-600),
                isRead: false,
                messages: [
                    ChatMessage(id: UUID().uuidString, text: "Your application has been accepted! We're excited to have you at our event.", isFromUser: false, timestamp: now.addingTimeInterval(-3600), isSystemMessage: true),
                    ChatMessage(id: UUID().uuidString, text: "Hi! I'm looking forward to the job tonight.", isFromUser: true, timestamp: now.addingTimeInterval(-3500), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "Great! Please wear Smart Casual. The entrance is to the left of the main entrance.", isFromUser: false, timestamp: now.addingTimeInterval(-3400), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "Got it, thanks!", isFromUser: true, timestamp: now.addingTimeInterval(-3300), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "Could you please come 15 minutes earlier?", isFromUser: false, timestamp: now.addingTimeInterval(-600), isSystemMessage: false),
                ]
            ),

            // 2) Upcoming – gelesen
            Conversation(
                id: "conv-2",
                jobTitle: "Retail Assistant",
                company: "Urban Fashion Store",
                logoEmoji: "🛍️",
                status: .upcoming,
                jobDate: inThreeDays,
                lastMessage: "See you on Saturday!",
                lastMessageTime: now.addingTimeInterval(-7200),
                isRead: true,
                messages: [
                    ChatMessage(id: UUID().uuidString, text: "Your application has been accepted! We look forward to having you.", isFromUser: false, timestamp: now.addingTimeInterval(-86400), isSystemMessage: true),
                    ChatMessage(id: UUID().uuidString, text: "Great, thanks! Is there anything I need to bring?", isFromUser: true, timestamp: now.addingTimeInterval(-85000), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "No, everything is provided. Just be on time.", isFromUser: false, timestamp: now.addingTimeInterval(-84000), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "See you on Saturday!", isFromUser: false, timestamp: now.addingTimeInterval(-7200), isSystemMessage: false),
                ]
            ),

            // 3) Completed – read-only
            Conversation(
                id: "conv-3",
                jobTitle: "Office Support",
                company: "Startup Hub",
                logoEmoji: "💻",
                status: .completed,
                jobDate: threeDaysAgo,
                lastMessage: "This shift has been successfully completed.",
                lastMessageTime: threeDaysAgo,
                isRead: true,
                messages: [
                    ChatMessage(id: UUID().uuidString, text: "Your application has been accepted!", isFromUser: false, timestamp: threeDaysAgo.addingTimeInterval(-172800), isSystemMessage: true),
                    ChatMessage(id: UUID().uuidString, text: "Please log in tomorrow morning at 9:00 am.", isFromUser: false, timestamp: threeDaysAgo.addingTimeInterval(-86400), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "Of course, see you tomorrow!", isFromUser: true, timestamp: threeDaysAgo.addingTimeInterval(-86000), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "This shift has been successfully completed.", isFromUser: false, timestamp: threeDaysAgo, isSystemMessage: true),
                ]
            ),

            // 4) Cancelled – read-only
            Conversation(
                id: "conv-4",
                jobTitle: "Barista",
                company: "Brew & Co.",
                logoEmoji: "☕",
                status: .cancelled,
                jobDate: oneWeekAgo,
                lastMessage: "This shift has been cancelled by the employer.",
                lastMessageTime: oneWeekAgo,
                isRead: true,
                messages: [
                    ChatMessage(id: UUID().uuidString, text: "Your application has been accepted!", isFromUser: false, timestamp: oneWeekAgo.addingTimeInterval(-86400), isSystemMessage: true),
                    ChatMessage(id: UUID().uuidString, text: "Unfortunately we have to cancel the shift. We're very sorry!", isFromUser: false, timestamp: oneWeekAgo.addingTimeInterval(-3600), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "This shift has been cancelled by the employer.", isFromUser: false, timestamp: oneWeekAgo, isSystemMessage: true),
                ]
            ),
        ]
    }
}
