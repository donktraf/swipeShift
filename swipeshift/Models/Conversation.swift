//
//  Conversation.swift
//  swipeShift
//

import Foundation

// MARK: - Conversation Status
enum ConversationStatus: String {
    case today      // Job ist heute (nächste 24h) → blaue Pill
    case upcoming   // Zukünftiger Job → grüne Pill
    case completed  // Abgeschlossener Job → weiße Pill
    case cancelled  // Abgesagter Job → rote Pill

    var label: String {
        switch self {
        case .today:     return "Today"
        case .upcoming:  return "Upcoming"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    /// Sortiergewicht: kleinere Zahl = weiter oben
    var sortWeight: Int {
        switch self {
        case .today:     return 0
        case .upcoming:  return 1
        case .completed: return 2
        case .cancelled: return 3
        }
    }
}

// MARK: - Conversation
struct Conversation: Identifiable {
    let id: String
    let applyId: String
    let jobId: String
    let jobTitle: String
    let company: String
    let logoEmoji: String
    let status: ConversationStatus
    let jobDate: Date          // Für Sortierung innerhalb einer Gruppe
    var lastMessage: String
    var lastMessageTime: Date
    var isRead: Bool
    var messages: [ChatMessage]
    var presence: ChatPresence = .unknown
}

// MARK: - ChatPresence
/// Status der Gegenseite im Chat (Polling-basiert, kein WebSocket).
struct ChatPresence: Equatable {
    var otherIsTyping: Bool
    var otherIsOnline: Bool
    var otherLastSeenAt: Date?
    /// Zeitpunkt, an dem die Gegenseite die Konversation zuletzt gelesen hat → Lesebestaetigungen
    var otherLastReadAt: Date?

    static let unknown = ChatPresence(
        otherIsTyping: false, otherIsOnline: false, otherLastSeenAt: nil, otherLastReadAt: nil
    )
}

// MARK: - ChatMessage
struct ChatMessage: Identifiable {
    let id: String
    let text: String
    let isFromUser: Bool       // true = Worker, false = Employer
    let timestamp: Date
    let isSystemMessage: Bool  // Zentriert dargestellt (Job-Update, Stornierung etc.)
    /// Nur fuer eigene Nachrichten relevant: Gegenseite hat sie gelesen
    var isReadByOther: Bool = false
}
