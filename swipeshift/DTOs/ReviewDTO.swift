//
//  ReviewDTO.swift
//  swipeShift
//

import Foundation

struct PendingReviewItem: Identifiable, Decodable {
    let applyId:     String
    let workerId:    String
    let workerName:  String
    let workerPhoto: String?
    let jobId:       String
    let jobTitle:    String
    let jobCategory: String
    let shiftDate:   Date
    let logoEmoji:   String

    var id: String { applyId }
}

struct PastReviewItem: Identifiable, Decodable {
    let id:            String
    let workerName:    String
    let workerPhoto:   String?
    let jobTitle:      String
    let jobCategory:   String
    let logoEmoji:     String
    let shiftDate:     Date
    let communication: Int
    let teamwork:      Int
    let reliability:   Int
    let underPressure: Int
    let comment:       String?
    let wouldRehire:   Bool
    let createdAt:     Date

    var avgRating: Double {
        Double(communication + teamwork + reliability + underPressure) / 4.0
    }
}

struct SubmitReviewRequest: Encodable {
    let applyId:       String
    let communication: Int
    let teamwork:      Int
    let reliability:   Int
    let underPressure: Int
    let comment:       String
    let wouldRehire:   Bool
}
