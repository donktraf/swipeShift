//
//  PostJobDTO.swift
//  swipeShift
//

import Foundation

struct PostJobShiftRequest: Encodable {
    let date: String        // z.B. "Mo, 12. Mai"
    let timeRange: String   // z.B. "18:00–23:00"
    let duration: String    // z.B. "5 Stunden"
    let totalPay: String    // z.B. "€75 gesamt"
}

struct PostJobRequest: Encodable {
    let title: String
    let company: String
    let location: String
    let lat: Double?
    let lng: Double?
    let category: String
    let tags: [String]
    let shifts: [PostJobShiftRequest]
    let openSpots: Int
    let payAmount: Double
    let payText: String
    let jobDescription: String
    let tasks: [String]
    let dressCode: String?
    let languages: [String]
    let experienceLevel: String?
    let minAge: Int?
    let paymentMethod: String?
    let contractType: String?
    let status: String          // "published" | "draft"
}
