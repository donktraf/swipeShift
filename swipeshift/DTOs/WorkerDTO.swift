//
//  WorkerDTO.swift
//  swipeShift
//

import Foundation

// MARK: - Job Applications

struct WorkerApplicationItem: Identifiable, Decodable {
    let id:            String   // applyId
    let jobId:         String
    let jobTitle:      String
    let company:       String
    let logoEmoji:     String
    let location:      String
    let payText:       String
    let shiftText:     String
    let category:      String
    let startTime:     Date?
    let endTime:       Date?
    let appliedAt:     Date
    let displayStatus: String   // "confirmed" | "applied" | "completed" | "cancelled"
    // Optional, damit aeltere Backend-Antworten weiter dekodieren
    let cancellationKind:   String?   // "declined" | "jobCancelled" | "workerCancelled"
    let cancellationReason: String?
    let paymentStatus:      String?   // "paid" | "pending" (nur completed)
    let earnings:           Double?
    let conversationId:     String?
    let distanceMiles:      Double?   // Worker → Job, nil ohne Koordinaten
    let jobNotes:           String?   // Hinweise des Employers (nur bei offener/angenommener Bewerbung)
    // Reliability (alle optional, aeltere Backends liefern sie nicht)
    let canCancel:          Bool?     // bestaetigte, noch nicht begonnene Schicht → "Cancel shift"
    let lateIfCancelledNow: Bool?     // < 24 h bis Start → Warnung "late cancellation"
    let lateCancellation:   Bool?     // vom Worker kurzfristig storniert
    let attendance:         String?   // "attended" | "late" | "no_show" (vom Employer erfasst bzw. automatisch)
    let attendanceSource:   String?   // "employer" | "auto" | "admin"
    let canDispute:         Bool?
    let disputeStatus:      String?   // nil | "pending" | "resolved"
    let disputeResolution:  String?   // "upheld" | "changed"
    /// Vom Worker gebuchte Schichten (startTime/endTime oben gelten bereits nur fuer diese); fehlt bei aelteren Backends
    var bookedShifts:       [BookedShift]? = nil

    var attendanceStatus: AttendanceStatus? { attendance.flatMap(AttendanceStatus.init(rawValue:)) }
}

// MARK: - Saved Jobs

struct WorkerSavedJob: Identifiable, Decodable {
    let id:            String   // saveId
    let jobId:         String
    let title:         String
    let company:       String
    let logoEmoji:     String
    let location:      String
    let payText:       String
    let shiftText:     String
    let savedAt:       Date
    let appliedStatus: String?  // nil | "Applied" | "Confirmed"
    // Optional, damit aeltere Backend-Antworten weiter dekodieren
    let category:      String?
    let tags:          [String]?
    let distanceMiles: Double?
    let canApply:      Bool?    // noch nicht beworben und Job offen
}

// MARK: - Worker Reviews

struct WorkerReviewItem: Identifiable, Decodable {
    let id:            String
    let companyName:   String
    let jobType:       String
    let date:          Date
    let communication: Int
    let teamwork:      Int
    let reliability:   Int
    let underPressure: Int
    let workQuality:   Int?     // nil bei Bestandsbewertungen
    let topWorker:     Bool?
    let feedback:      String
    let wouldRehire:   Bool

    var isTopWorker: Bool { topWorker ?? false }

    var avgRating: Double {
        reviewAverage([communication, teamwork, reliability, underPressure, workQuality])
    }
}

struct WorkerReviewsResponse: Decodable {
    let reviews:       [WorkerReviewItem]
    let overallRating: Double
    let totalJobs:     Int
    let skillAverages: WorkerRatingBreakdown?
    let topWorkerCount: Int?
}

// MARK: - Worker Financials

struct WorkerEarningItem: Identifiable, Decodable {
    let id:        String
    let jobTitle:  String
    let company:   String
    let logoEmoji: String
    let shiftText: String
    let amount:    Double
    let status:    String   // "upcoming" | "completed"
    // amount = hourlyRate x hours (Backend utils/jobCost.js); optional fuer aeltere Antworten
    let hourlyRate: Double?
    let hours:      Double?
    let startTime:  Date?
    let isPaid:     Bool?
    /// Gebuchte Schichten (Betrag/Stunden gelten nur dafuer); fehlt bei aelteren Backends
    var bookedShifts: [BookedShift]? = nil
}

struct WorkerFinancialsDTO: Decodable {
    let upcomingEarnings:  Double
    let completedEarnings: Double
    let paidOut:           Double
    let thisWeekEarnings:  Double?   // laufende Woche Mo–So, unabhaengig vom Zeitraum
    let earningsTotal:     Int?      // Anzahl Schichten im Zeitraum (Liste ist auf die neuesten begrenzt)
    let earningsList:      [WorkerEarningItem]
}
