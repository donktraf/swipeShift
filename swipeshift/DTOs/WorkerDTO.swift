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
    let cancellationKind:   String?   // "declined" | "jobCancelled"
    let cancellationReason: String?
    let paymentStatus:      String?   // "paid" | "pending" (nur completed)
    let earnings:           Double?
    let conversationId:     String?
    let distanceMiles:      Double?   // Worker → Job, nil ohne Koordinaten
    let jobNotes:           String?   // Hinweise des Employers (nur bei offener/angenommener Bewerbung)
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
}

struct WorkerFinancialsDTO: Decodable {
    let upcomingEarnings:  Double
    let completedEarnings: Double
    let paidOut:           Double
    let thisWeekEarnings:  Double?   // laufende Woche Mo–So, unabhaengig vom Zeitraum
    let earningsTotal:     Int?      // Anzahl Schichten im Zeitraum (Liste ist auf die neuesten begrenzt)
    let earningsList:      [WorkerEarningItem]
}
