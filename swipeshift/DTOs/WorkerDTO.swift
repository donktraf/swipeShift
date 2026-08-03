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
    let feedback:      String
    let wouldRehire:   Bool

    var avgRating: Double {
        Double(communication + teamwork + reliability + underPressure) / 4.0
    }
}

struct WorkerReviewsResponse: Decodable {
    let reviews:       [WorkerReviewItem]
    let overallRating: Double
    let totalJobs:     Int
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
}

struct WorkerFinancialsDTO: Decodable {
    let upcomingEarnings:  Double
    let completedEarnings: Double
    let paidOut:           Double
    let earningsList:      [WorkerEarningItem]
}
