//
//  NotificationDTO.swift
//  swipeShift
//

import Foundation

struct NotificationDTO: Identifiable, Decodable {
    let id: String
    let category: String   // "jobActivity" | "reviews" | "payments" | "system"
    let title: String
    let body: String
    let timestamp: Date
    let actionLabel: String?
}
