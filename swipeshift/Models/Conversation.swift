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

    // Gegenseite (Worker sieht Firma, Employer sieht Worker)
    var counterpartUserId: String? = nil
    var counterpartPhotoUrl: String? = nil

    // Job-Kontext fuer Header / Quick-Info-Karte
    var location: String = ""
    var payText: String = ""
    var payAmount: Double? = nil
    var shiftText: String = ""
    var startTime: Date? = nil
    var endTime: Date? = nil

    // Nach Jobende
    var isPaid: Bool = false
    var isCounterpartSaved: Bool = false

    // Blockieren (Inhalte bleiben lesbar, Senden gesperrt)
    var blockedByMe: Bool = false
    var blockedByOther: Bool = false

    var isBlocked: Bool { blockedByMe || blockedByOther }
}

// MARK: - Anzeige-Helper (feste Locale en_US, App nur auf Englisch)
extension Conversation {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = format
        return f
    }
    private static let dayFormatter  = formatter("EEE, MMM d")
    private static let timeFormatter = formatter("h:mm a")

    /// "Mon, Nov 17"
    var dateText: String { Self.dayFormatter.string(from: startTime ?? jobDate) }

    /// "9:00 AM – 1:00 PM"; ohne Zeiten faellt es auf den Backend-Schichttext zurueck
    var timeText: String {
        guard let start = startTime else { return shiftText }
        let startStr = Self.timeFormatter.string(from: start)
        guard let end = endTime else { return startStr }
        return "\(startStr) – \(Self.timeFormatter.string(from: end))"
    }

    /// "Mon, Nov 17 · 9:00 AM – 1:00 PM"
    var shiftSummary: String {
        let time = timeText
        return time.isEmpty ? dateText : "\(dateText) · \(time)"
    }

    /// Lohn: bevorzugt Stundenlohn ueber Money, sonst Backend-Text
    var payDisplay: String {
        if let payAmount { return Money.hourly(payAmount) }
        return payText
    }
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
