//
//  WorkerProfileDTO.swift
//  swipeShift
//
//  Worker-Profil aus Arbeitgeber-Sicht (GET /employer/workers/:userId).
//

import Foundation

struct WorkerProfileDTO: Decodable {
    let worker: WorkerProfileInfo
    let stats: WorkerProfileStats
    let recentReviews: [WorkerProfileReview]
    /// Die folgenden Felder fehlen in aelteren Backend-Antworten
    let pastJobs: [WorkerPastJob]?
    let account: WorkerAccountStatus?
    /// Nur mit Job-Kontext: "Category matches · 2 of 3 required skills · ..."
    let matchHint: String?
    /// Anwesenheit / No-Shows / kurzfristige Stornos (fehlt in aelteren Backend-Antworten)
    let reliability: ReliabilitySummary?
    /// Nur mit Job-Kontext: die Schichten, die dieser Worker fuer den Job gebucht hat
    let bookedShifts: [BookedShift]?
}

struct WorkerPastJob: Decodable, Identifiable {
    let companyName: String
    let jobTitle: String
    let date: Date?
    /// Bewertung, die der Employer dieses Jobs vergeben hat (nil = noch keine)
    let rating: Double?
    var id: String { "\(companyName)-\(jobTitle)-\(date?.timeIntervalSince1970 ?? 0)" }
}

struct WorkerAccountStatus: Decodable {
    let emailVerified: Bool
    let memberSince: Date?
}

struct WorkerProfileInfo: Decodable {
    let id: String
    let firstName: String?
    let lastName: String?
    let location: String?
    let isEmailVerified: Bool
    let profilePhotoUrl: String?
    let bio: String?
    let age: Int?
    let isAdult: Bool?
    let availableDays: [String]
    let maxTravelDistance: Int?
    let willingToRelocate: Bool
    let availableForSameDay: Bool
    let availableTimes: [String]
    let shiftTypes: [String]
    let experience: [WorkerExperienceEntry]
    let transport: String?
    let preferredCategories: [String]
    let jobInterests: [String]
    let payRangeMin: Double?
    let payRangeMax: Double?
    let selfRatedSkills: WorkerSkillsDTO?
    let workAuthorization: Bool
}

struct WorkerRatingBreakdown: Decodable {
    let communication: Double?
    let teamwork: Double?
    let reliability: Double?
    let underPressure: Double?
    let workQuality: Double?
}

struct WorkerCategoryCount: Decodable, Identifiable {
    let category: String
    let count: Int
    var id: String { category }
}

struct WorkerProfileStats: Decodable {
    let reviewCount: Int
    let overallRating: Double?
    let ratings: WorkerRatingBreakdown?
    let wouldRehirePercent: Int?
    let topWorkerCount: Int?
    let completedJobs: Int
    let completedByCategory: [WorkerCategoryCount]
}

struct WorkerProfileReview: Decodable, Identifiable {
    let comment: String
    let jobTitle: String?
    let createdAt: Date
    let rating: Double?
    let wouldRehire: Bool
    let topWorker: Bool?
    var id: String { "\(createdAt.timeIntervalSince1970)-\(comment.prefix(20))" }
}
