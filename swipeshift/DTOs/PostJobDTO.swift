//
//  PostJobDTO.swift
//  swipeShift
//

import Foundation

struct PostJobShiftRequest: Encodable {
    let date: String        // e.g. "Mon, Apr 28"
    let timeRange: String   // e.g. "18:00–23:00"
    let duration: String    // e.g. "5h"
    let totalPay: String    // e.g. "€75 total"
    let startTimeISO: String?   // ISO 8601 — used by backend to set startTime
    let endTimeISO: String?     // ISO 8601 — used by backend to set endTime
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
