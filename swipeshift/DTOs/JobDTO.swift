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

    func toDomain() -> JobShift {
        JobShift(id: id ?? UUID().uuidString, date: date, timeRange: timeRange, duration: duration, totalPay: totalPay)
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
            shifts: shifts?.map { $0.toDomain() },
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
        return job
    }
}

struct EmployerStatsDTO: Decodable {
    let activeJobs: Int
    let newApplicants: Int
    let monthlySpend: Double
    let applicationsThisWeek: Int
    let jobsFilledThisWeek: Int
    let topCategory: String
}
