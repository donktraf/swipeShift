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

/// Gespeicherte Werte eines Bewertungs-Entwurfs. 0/nil = noch nicht bewertet.
struct ReviewDraftValues: Codable, Equatable {
    var communication: Int?
    var teamwork:      Int?
    var reliability:   Int?
    var underPressure: Int?
    var workQuality:   Int?
    var comment:       String?
    var wouldRehire:   Bool?
    var topWorker:     Bool?
}

/// Eintrag aus GET /employer/reviews/drafts (Worker-/Job-Infos wie bei Pending + Entwurfswerte)
struct ReviewDraftItem: Identifiable, Decodable {
    let review:    PendingReviewItem
    let draft:     ReviewDraftValues
    let updatedAt: Date

    var id: String { review.applyId }

    private enum CodingKeys: String, CodingKey { case draft, updatedAt }

    init(from decoder: Decoder) throws {
        review = try PendingReviewItem(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        draft = try c.decode(ReviewDraftValues.self, forKey: .draft)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

/// Gesamtwert = Mittel der vorhandenen Kategorien (workQuality kann bei Altbewertungen fehlen)
func reviewAverage(_ values: [Int?]) -> Double {
    let present = values.compactMap { $0 }.filter { $0 > 0 }
    guard !present.isEmpty else { return 0 }
    return Double(present.reduce(0, +)) / Double(present.count)
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
    let workQuality:   Int?
    let topWorker:     Bool?
    let comment:       String?
    let wouldRehire:   Bool
    let createdAt:     Date

    var isTopWorker: Bool { topWorker ?? false }

    var avgRating: Double {
        reviewAverage([communication, teamwork, reliability, underPressure, workQuality])
    }
}

struct SubmitReviewRequest: Encodable {
    let applyId:       String
    let communication: Int
    let teamwork:      Int
    let reliability:   Int
    let underPressure: Int
    let workQuality:   Int
    let comment:       String
    let wouldRehire:   Bool
    let topWorker:     Bool
}
