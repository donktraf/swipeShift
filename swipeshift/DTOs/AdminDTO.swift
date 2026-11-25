//
//  AdminDTO.swift
//  swipeShift
//
//  Admin-Moderation (Reports). Nur fuer Admin-Konten (User.isAdmin).
//

import Foundation

struct AdminUserBrief: Decodable, Equatable {
    let id: String
    let name: String
    let role: String?
    let photoUrl: String?
    var initial: String { name.first.map { String($0).uppercased() } ?? "?" }
    var roleLabel: String { role == "employer" ? "Employer" : (role == "worker" ? "Worker" : "User") }
}

struct AdminRestriction: Decodable, Equatable {
    let state: String          // "none" | "suspended" | "banned"
    let until: Date?
    let pendingReview: Bool
    var isRestricted: Bool { state != "none" }
    var label: String {
        switch state {
        case "banned": return "Banned"
        case "suspended":
            if pendingReview { return "Suspended (pending review)" }
            if let until { return "Suspended until \(until.formatted(date: .abbreviated, time: .omitted))" }
            return "Suspended"
        default: return "Active"
        }
    }
}

struct AdminReportedUser: Decodable, Equatable {
    let id: String
    let name: String
    let role: String?
    let photoUrl: String?
    let restriction: AdminRestriction
    let isAdmin: Bool?         // Admin-Konten koennen nicht gesperrt/gebannt werden (Backend: ADMIN_TARGET)
    // Geloeschtes Konto (Report bleibt bestehen): nur Dismiss und – mit Tombstone (canBan) – Ban moeglich
    let deleted: Bool?
    let deletedAt: Date?
    let deletedName: String?   // z.B. "Anna M." (nur Admin-Anzeige)
    let canBan: Bool?
    let banned: Bool?          // E-Mail des geloeschten Kontos ist gebannt (Unban moeglich)
    let emailVerified: Bool?   // nur bei geloeschten Konten mit Tombstone
    var isDeleted: Bool { deleted == true }
    var isEmailBanned: Bool { deleted == true && banned == true }
    var initial: String { name.first.map { String($0).uppercased() } ?? "?" }
    var roleLabel: String { role == "employer" ? "Employer" : (role == "worker" ? "Worker" : "User") }
}

struct AdminReport: Decodable, Identifiable, Equatable {
    let id: String
    let status: String
    let reason: String
    let details: String?
    let createdAt: Date
    let resolvedAt: Date?
    let resolution: String?
    let conversationId: String?
    let reporter: AdminUserBrief
    let reported: AdminReportedUser
    let openReportCount: Int
    let openReporterCount: Int

    var reasonLabel: String { AdminReport.label(for: reason) }
    var resolutionLabel: String? {
        switch resolution {
        case "action_taken": return "Action taken"
        case "dismissed": return "Dismissed"
        default: return nil
        }
    }

    static func label(for reason: String) -> String {
        switch reason {
        case "harassment": return "Harassment"
        case "spam": return "Spam"
        case "inappropriate": return "Inappropriate"
        case "safety": return "Safety concern"
        case "payment": return "Payment issue"
        default: return "Other"
        }
    }
}

struct AdminReportNote: Decodable, Identifiable, Equatable {
    let id: String
    let reason: String
    let details: String?
    let createdAt: Date
    let reporter: AdminUserBrief
}

struct AdminChatMessage: Decodable, Identifiable, Equatable {
    let id: String
    let senderId: String
    let text: String
    let isSystem: Bool
    let createdAt: Date
}

struct AdminConversation: Decodable, Equatable {
    let id: String
    let jobTitle: String?
    let participants: [AdminUserBrief]
    let messages: [AdminChatMessage]
}

struct AdminHistoryEntry: Decodable, Identifiable, Equatable {
    let id: String
    let action: String
    let durationDays: Int?
    let note: String?
    let createdAt: Date
    let admin: AdminUserBrief?   // nil = System

    var actionLabel: String {
        switch action {
        case "warn": return "Warning"
        case "suspend": return "Suspended\(durationDays.map { " \($0) days" } ?? "")"
        case "ban": return "Banned"
        case "dismiss": return "Report dismissed"
        case "auto_suspend": return "Auto-suspended (pending review)"
        case "lift": return "Restriction lifted"
        default: return action
        }
    }
}

struct AdminReportDetail: Decodable, Equatable {
    let report: AdminReport
    let reports: [AdminReportNote]
    let conversation: AdminConversation?
    let history: [AdminHistoryEntry]
}

enum AdminModerationAction {
    case warn, suspend7, suspend30, ban, dismiss

    var body: [String: Any] {
        switch self {
        case .warn: return ["action": "warn"]
        case .suspend7: return ["action": "suspend", "durationDays": 7]
        case .suspend30: return ["action": "suspend", "durationDays": 30]
        case .ban: return ["action": "ban"]
        case .dismiss: return ["action": "dismiss"]
        }
    }
}
