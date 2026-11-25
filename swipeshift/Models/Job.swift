//
//  Job.swift
//  swipeShift
//
//  Created by DON on 15.12.25.
//

// Job.swift

import Foundation

/// Eine einzelne Schicht innerhalb eines Jobs (für Mehrfach-Schicht-Auswahl im Apply Flow)
struct JobShift: Identifiable, Equatable {
    let id: String
    let date: String        // z.B. "Mo, 12. Mai"
    let timeRange: String   // z.B. "18:00–23:00"
    let duration: String    // z.B. "5 Stunden"
    let totalPay: String    // z.B. "$75 total"
    var startDate: Date? = nil  // Schichtbeginn (nil bei Altdaten ohne startTimeISO)
}

struct Job: Identifiable, Equatable {
    let id: String
    let title: String
    let company: String
    let location: String
    let payText: String
    let distanceText: String
    let shiftText: String
    let shortInfo: String
    let tags: [String]
    let logoEmoji: String

    // Koordinaten für Radar/Map
    let lat: Double?
    let lng: Double?

    // Für Pin-Farben im Radar + Detail
    let payAmount: Double?      // Stundenlohn als Zahl (z.B. 15.0)
    let startTime: Date?        // Schichtbeginn als Date
    let category: String?

    // Detail-View Felder
    let jobDescription: String?
    let tasks: [String]?
    let openSpots: Int?
    let duration: String?           // z.B. "5 Stunden"
    let dressCode: String?
    let languages: [String]?
    let experienceLevel: String?    // z.B. "Keine Erfahrung nötig"
    let minAge: Int?
    let paymentMethod: String?      // z.B. "Same-day Pay"
    let contractType: String?       // z.B. "Freelance"
    let companyRating: Double?      // z.B. 4.7
    let replyTime: String?          // z.B. "Antwortet meist innerhalb von 2 Stunden"
    let isVerified: Bool?
    let shifts: [JobShift]?     // nil oder 1 Eintrag = single-shift, 2+ = multi-shift
    let reviewBreakdown: JobReviewSummary?
    let matchReasons: [String]

    // Firmenblock im Job-Detail (nur von GET /jobs/:id geliefert, sonst nil/leer)
    var companyIndustry: String? = nil
    var companyBusinessAreas: [String] = []
    var companyCompletedJobs: Int? = nil

    // Optionale Zusatzfelder (Add Job) — alle mit Default, damit aeltere Payloads weiter funktionieren
    var requiredSkills: [String] = []
    var physicalRequirements: [String] = []
    var certifications: [String] = []
    var educationLevel: String? = nil
    var workAuthorizationRequired: Bool = false
    var urgency: String = "normal"          // "normal" | "urgent"
    var locationType: String = "single"     // "single" | "multiple"
    var breakIncluded: Bool = false
    var breakMinutes: Int? = nil
    var sameDayPay: Bool = false
    var tipsIncluded: Bool = false
    var repeatWork: Bool = false
    var bonusAvailable: Bool = false
    var bonusDescription: String? = nil
    var cancellationPolicy: String? = nil   // "flexible" | "24h" | "48h" | "strict"
    var cancellationNotes: String? = nil
    var jobNotes: String? = nil
    var instantMatch: Bool = false

    var isUrgent: Bool { urgency == "urgent" }

    /// Anzeigetext der Stornierungsbedingung
    var cancellationPolicyLabel: String? {
        guard let cancellationPolicy else { return nil }
        return JobCancellationPolicy(rawValue: cancellationPolicy)?.label
    }
}

/// Stornierungsbedingungen (Raw Value = Backend-Wert)
enum JobCancellationPolicy: String, CaseIterable, Identifiable {
    case flexible, h24 = "24h", h48 = "48h", strict
    var id: String { rawValue }
    var label: String {
        switch self {
        case .flexible: return "Flexible"
        case .h24:      return "24 hours notice"
        case .h48:      return "48 hours notice"
        case .strict:   return "No cancellation after confirmation"
        }
    }
}

/// Auswahllisten der optionalen Job-Felder (identisch zu den erlaubten Werten im Backend)
enum JobOptions {
    static let skills = ["Communication", "Teamwork", "Reliability", "Working under Pressure"]
    static let physical = ["Standing for long periods", "Lifting up to 25 lbs", "Lifting up to 50 lbs", "Walking / on feet", "Bending / kneeling", "Working outdoors"]
    static let certifications = ["Food Handler Card", "Alcohol Server Certification", "Forklift License", "First Aid / CPR", "Security Guard License", "Driver's License"]
    static let education = ["None required", "High School Diploma / GED", "Vocational Training", "College Degree"]
    static let breakMinutes = [15, 30, 45, 60]
}

struct JobReviewSummary: Equatable {
    let avgRating: Double
    let totalReviews: Int
    let communication: Double
    let paymentFairness: Double
    let workEnvironment: Double
    let jobDescriptionAccuracy: Double
    let overallExperience: Double
    let tags: [String]
}
