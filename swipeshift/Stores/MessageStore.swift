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
    @Published var employerConversations: [Conversation] = []

    init() {
        conversations         = Self.makeMockConversations()
        employerConversations = Self.makeMockEmployerConversations()
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

    var sortedEmployerConversations: [Conversation] {
        employerConversations.sorted { a, b in
            if a.status.sortWeight != b.status.sortWeight {
                return a.status.sortWeight < b.status.sortWeight
            }
            if a.status == .today || a.status == .upcoming {
                if a.isRead != b.isRead { return !a.isRead }
            }
            return a.jobDate < b.jobDate
        }
    }

    var employerUnreadCount: Int {
        employerConversations.filter { !$0.isRead }.count
    }

    func markEmployerConversationAsRead(conversationId: String) {
        guard let idx = employerConversations.firstIndex(where: { $0.id == conversationId }) else { return }
        employerConversations[idx].isRead = true
    }

    func sendEmployerMessage(conversationId: String, text: String) {
        guard let idx = employerConversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let msg = ChatMessage(
            id: UUID().uuidString,
            text: text,
            isFromUser: true,
            timestamp: Date(),
            isSystemMessage: false
        )
        employerConversations[idx].messages.append(msg)
        employerConversations[idx].lastMessage = text
        employerConversations[idx].lastMessageTime = Date()
    }

    // MARK: - Mock-Daten (Employer-Perspektive: company = Worker-Name, isFromUser = Employer)
    private static func makeMockEmployerConversations() -> [Conversation] {
        let now          = Date()
        let inFourHours  = now.addingTimeInterval(4 * 3600)
        let inTwoDays    = now.addingTimeInterval(2 * 24 * 3600)
        let twoDaysAgo   = now.addingTimeInterval(-2 * 24 * 3600)

        return [
            // 1) Today – ungelesen
            Conversation(
                id: "emp-conv-1",
                jobTitle: "Event Staff",
                company: "Anna Schmidt",
                logoEmoji: "👩",
                status: .today,
                jobDate: inFourHours,
                lastMessage: "Perfect, see you tonight!",
                lastMessageTime: now.addingTimeInterval(-300),
                isRead: false,
                messages: [
                    ChatMessage(id: UUID().uuidString, text: "Anna has applied for your Event Staff shift tonight.", isFromUser: false, timestamp: now.addingTimeInterval(-7200), isSystemMessage: true),
                    ChatMessage(id: UUID().uuidString, text: "Hi Anna, your application looks great. You're in!", isFromUser: true, timestamp: now.addingTimeInterval(-7000), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "Thank you so much! What should I wear?", isFromUser: false, timestamp: now.addingTimeInterval(-6800), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "Smart casual please — dark trousers and a white shirt. Doors open at 18:00.", isFromUser: true, timestamp: now.addingTimeInterval(-6600), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "Perfect, see you tonight!", isFromUser: false, timestamp: now.addingTimeInterval(-300), isSystemMessage: false),
                ]
            ),

            // 2) Upcoming – gelesen
            Conversation(
                id: "emp-conv-2",
                jobTitle: "Warehouse Packer",
                company: "Max Meier",
                logoEmoji: "👨",
                status: .upcoming,
                jobDate: inTwoDays,
                lastMessage: "No problem, I'll be there on time.",
                lastMessageTime: now.addingTimeInterval(-3600),
                isRead: true,
                messages: [
                    ChatMessage(id: UUID().uuidString, text: "Max has applied for your Warehouse Packer shift.", isFromUser: false, timestamp: now.addingTimeInterval(-86400), isSystemMessage: true),
                    ChatMessage(id: UUID().uuidString, text: "Hi Max, welcome to the team! Shift starts at 20:00. Safety boots are mandatory.", isFromUser: true, timestamp: now.addingTimeInterval(-85000), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "Understood. Do I need to bring anything else?", isFromUser: false, timestamp: now.addingTimeInterval(-84000), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "Just your ID and boots. Everything else is provided.", isFromUser: true, timestamp: now.addingTimeInterval(-83000), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "No problem, I'll be there on time.", isFromUser: false, timestamp: now.addingTimeInterval(-3600), isSystemMessage: false),
                ]
            ),

            // 3) Completed – read-only
            Conversation(
                id: "emp-conv-3",
                jobTitle: "Retail Assistant",
                company: "Lisa Weber",
                logoEmoji: "👩",
                status: .completed,
                jobDate: twoDaysAgo,
                lastMessage: "Shift completed successfully.",
                lastMessageTime: twoDaysAgo,
                isRead: true,
                messages: [
                    ChatMessage(id: UUID().uuidString, text: "Lisa has applied for your Retail Assistant shift.", isFromUser: false, timestamp: twoDaysAgo.addingTimeInterval(-172800), isSystemMessage: true),
                    ChatMessage(id: UUID().uuidString, text: "Hi Lisa, you're confirmed for Saturday 10:00–18:00.", isFromUser: true, timestamp: twoDaysAgo.addingTimeInterval(-86400), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "Great, looking forward to it!", isFromUser: false, timestamp: twoDaysAgo.addingTimeInterval(-85000), isSystemMessage: false),
                    ChatMessage(id: UUID().uuidString, text: "Shift completed successfully.", isFromUser: false, timestamp: twoDaysAgo, isSystemMessage: true),
                ]
            ),
        ]
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
