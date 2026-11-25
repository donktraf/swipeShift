//
//  ReliabilityDTO.swift
//  swipeShift
//
//  Zuverlaessigkeit eines Workers (Backend: utils/reliability.js): Anwesenheit, No-Shows, kurzfristige
//  Stornierungen. Regeln: Employer erfasst nach Schichtende (48-h-Fenster, sonst automatisch "showed up"),
//  Worker kann einmal widersprechen, Prozentwert erst ab 3 abgeschlossenen Schichten ("New").
//

import Foundation

// MARK: - Zusammenfassung

struct ReliabilitySummary: Decodable, Equatable, Hashable {
    let finishedShifts: Int
    let attended: Int
    let late: Int
    let noShows: Int
    let lateCancellations: Int
    /// nil, solange weniger als 3 Schichten abgeschlossen sind
    let showUpRate: Int?
    let isNew: Bool
    /// Fertiger Text vom Backend, z.B. "96% showed up · 1 late · 0 late cancellations" oder "New"
    let text: String
}

struct WorkerReliabilityResponse: Decodable {
    let reliability: ReliabilitySummary
    let windowDays: Int
    let minShiftsForRate: Int
}

// MARK: - Anwesenheit

enum AttendanceStatus: String, CaseIterable, Identifiable {
    case attended
    case late
    case noShow = "no_show"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .attended: return "Showed up"
        case .late:     return "Late"
        case .noShow:   return "No-show"
        }
    }

    var icon: String {
        switch self {
        case .attended: return "checkmark.circle.fill"
        case .late:     return "clock.badge.exclamationmark.fill"
        case .noShow:   return "xmark.circle.fill"
        }
    }
}

/// Hinweis fuer den Employer (identisch zum Backend-Text)
let attendanceGuidanceText = "Late = arrived more than 15 minutes after the start"

struct AttendanceWorker: Identifiable, Decodable, Equatable {
    let applyId: String
    let userId: String
    let name: String
    var attendance: String?
    var attendanceSource: String?   // "employer" | "auto" | "admin"
    var canRecord: Bool
    var pending: Bool
    var disputeStatus: String?      // nil | "pending" | "resolved"
    var disputeNote: String?

    var id: String { applyId }
    var status: AttendanceStatus? { attendance.flatMap(AttendanceStatus.init(rawValue:)) }
}

struct JobAttendanceResponse: Decodable {
    let ended: Bool
    let deadline: Date?
    let guidance: String
    var workers: [AttendanceWorker]
}

// MARK: - Admin

struct AdminFlaggedWorker: Identifiable, Decodable, Equatable {
    let worker: AdminReportedUser
    let finishedShifts: Int
    let noShows: Int
    let late: Int
    let lateCancellations: Int
    var id: String { worker.id }
}

struct AdminAttendanceDispute: Identifiable, Decodable, Equatable {
    let applyId: String
    let worker: AdminUserBrief
    let jobTitle: String
    let company: String
    let shiftEnd: Date?
    let attendance: String?
    let attendanceSource: String?
    let note: String?
    let disputedAt: Date
    /// Employer-Konto existiert nicht mehr (Zahlung evtl. nie moeglich)
    var employerDeleted: Bool? = nil
    var id: String { applyId }
    var status: AttendanceStatus? { attendance.flatMap(AttendanceStatus.init(rawValue:)) }
}

struct AdminReliabilityResponse: Decodable {
    let windowDays: Int
    let flagged: [AdminFlaggedWorker]
    let disputes: [AdminAttendanceDispute]
}
