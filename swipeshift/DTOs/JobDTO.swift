//
//  JobDTO.swift
//  swipeShift
//
//  Created by DON on 24.12.25.
//

import Foundation

// DTO = so wie es aus dem Backend kommt (Decodable)
struct ShiftDTO: Decodable {
    let id: String?
    let date: String
    let timeRange: String
    let duration: String
    let totalPay: String
    let startTimeISO: String?

    /// `fallbackIndex`: Backend-Fallback-ID "s<Position ab 1>" fuer Altdaten ohne id (muss zu utils/shiftBooking.js passen)
    func toDomain(fallbackIndex: Int = 0) -> JobShift {
        JobShift(id: id ?? "s\(fallbackIndex + 1)", date: date, timeRange: timeRange, duration: duration, totalPay: totalPay,
                 startDate: startTimeISO.flatMap { ShiftDTO.parseISO($0) })
    }
}

extension ShiftDTO {
    /// ISO-8601 mit und ohne Millisekunden (Backend liefert je nach Quelle beides)
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func parseISO(_ iso: String) -> Date? {
        isoWithFraction.date(from: iso) ?? isoPlain.date(from: iso)
    }
}

struct JobDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let company: String
    let location: String
    let payText: String
    let distanceText: String?
    let shiftText: String
    let shortInfo: String
    let tags: [String]
    let logoEmoji: String
    let lat: Double?
    let lng: Double?
    let payAmount: Double?
    let startTime: String?
    let category: String?
    // Detail-Felder
    let jobDescription: String?
    let tasks: [String]?
    let openSpots: Int?
    let duration: String?
    let dressCode: String?
    let languages: [String]?
    let experienceLevel: String?
    let minAge: Int?
    let paymentMethod: String?
    let contractType: String?
    let companyRating: Double?
    let replyTime: String?
    let isVerified: Bool?
    let shifts: [ShiftDTO]?
    let reviewBreakdown: JobReviewBreakdownDTO?
    let matchReasons: [String]?
    // Nur bei GET /jobs/:id
    let companyIndustry: String?
    let companyBusinessAreas: [String]?
    let companyCompletedJobs: Int?
    // Optionale Zusatzfelder (aeltere Payloads ohne diese Keys decodieren zu nil)
    let requiredSkills: [String]?
    let physicalRequirements: [String]?
    let certifications: [String]?
    let educationLevel: String?
    let workAuthorizationRequired: Bool?
    let urgency: String?
    let locationType: String?
    let breakIncluded: Bool?
    let breakMinutes: Int?
    let sameDayPay: Bool?
    let tipsIncluded: Bool?
    let repeatWork: Bool?
    let bonusAvailable: Bool?
    let bonusDescription: String?
    let cancellationPolicy: String?
    let cancellationNotes: String?
    let jobNotes: String?
    let instantMatch: Bool?
}

struct JobReviewBreakdownDTO: Decodable {
    let avgRating: Double
    let totalReviews: Int
    let communication: Double
    let paymentFairness: Double
    let workEnvironment: Double
    let jobDescriptionAccuracy: Double
    let overallExperience: Double
    let tags: [String]
}

extension JobDTO {
    func toDomain() -> Job {
        var parsedStartTime: Date? = nil
        if let iso = startTime {
            parsedStartTime = ISO8601DateFormatter().date(from: iso)
        }
        var job = Job(
            id: id, title: title, company: company, location: location,
            payText: payText, distanceText: distanceText ?? "", shiftText: shiftText,
            shortInfo: shortInfo, tags: tags, logoEmoji: logoEmoji,
            lat: lat, lng: lng, payAmount: payAmount, startTime: parsedStartTime,
            category: category, jobDescription: jobDescription, tasks: tasks,
            openSpots: openSpots, duration: duration, dressCode: dressCode,
            languages: languages, experienceLevel: experienceLevel, minAge: minAge,
            paymentMethod: paymentMethod, contractType: contractType,
            companyRating: companyRating, replyTime: replyTime, isVerified: isVerified,
            shifts: shifts?.enumerated().map { $1.toDomain(fallbackIndex: $0) },
            reviewBreakdown: reviewBreakdown.map {
                JobReviewSummary(
                    avgRating: $0.avgRating, totalReviews: $0.totalReviews,
                    communication: $0.communication, paymentFairness: $0.paymentFairness,
                    workEnvironment: $0.workEnvironment,
                    jobDescriptionAccuracy: $0.jobDescriptionAccuracy,
                    overallExperience: $0.overallExperience, tags: $0.tags
                )
            },
            matchReasons: matchReasons ?? []
        )
        job.companyIndustry = companyIndustry
        job.companyBusinessAreas = companyBusinessAreas ?? []
        job.companyCompletedJobs = companyCompletedJobs
        job.requiredSkills = requiredSkills ?? []
        job.physicalRequirements = physicalRequirements ?? []
        job.certifications = certifications ?? []
        job.educationLevel = educationLevel
        job.workAuthorizationRequired = workAuthorizationRequired ?? false
        job.urgency = urgency ?? "normal"
        job.locationType = locationType ?? "single"
        job.breakIncluded = breakIncluded ?? false
        job.breakMinutes = breakMinutes
        job.sameDayPay = sameDayPay ?? false
        job.tipsIncluded = tipsIncluded ?? false
        job.repeatWork = repeatWork ?? false
        job.bonusAvailable = bonusAvailable ?? false
        job.bonusDescription = bonusDescription
        job.cancellationPolicy = cancellationPolicy
        job.cancellationNotes = cancellationNotes
        job.jobNotes = jobNotes
        job.instantMatch = instantMatch ?? false
        return job
    }
}

struct EmployerStatsDTO: Decodable {
    let activeJobs: Int
    let newApplicants: Int
    let monthlySpend: Double   // inkl. Plattform-Gebuehr
    var monthlySpendWages: Double? = nil
    var monthlySpendFees: Double? = nil
    let applicationsThisWeek: Int
    let instantMatchesThisWeek: Int?
    let jobsFilledThisWeek: Int
    let topCategory: String
}
