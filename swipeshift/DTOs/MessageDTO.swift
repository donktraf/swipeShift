//
//  MessageDTO.swift
//  swipeShift
//

import Foundation

// MARK: - Konversation vom Backend

struct ConversationDTO: Decodable, Identifiable {
    let id:              String
    let applyId:         String
    let jobId:           String
    let jobTitle:        String
    let company:         String      // Worker: company name; Employer: worker name
    let logoEmoji:       String
    let status:          String      // "today" | "upcoming" | "completed" | "cancelled"
    let jobDate:         Date
    let lastMessage:     String
    let lastMessageTime: Date
    let isRead:          Bool
    let messages:        [ChatMessageDTO]
    let presence:        ChatPresenceDTO?

    func toDomain() -> Conversation {
        Conversation(
            id:              id,
            applyId:         applyId,
            jobId:           jobId,
            jobTitle:        jobTitle,
            company:         company,
            logoEmoji:       logoEmoji,
            status:          ConversationStatus(rawValue: status) ?? .upcoming,
            jobDate:         jobDate,
            lastMessage:     lastMessage,
            lastMessageTime: lastMessageTime,
            isRead:          isRead,
            messages:        messages.map { $0.toDomain() },
            presence:        presence?.toDomain() ?? .unknown
        )
    }
}

// MARK: - Einzelne Nachricht vom Backend

struct ChatMessageDTO: Decodable, Identifiable {
    let id:              String
    let text:            String
    let isFromUser:      Bool
    let timestamp:       Date
    let isSystemMessage: Bool
    let isReadByOther:   Bool?

    func toDomain() -> ChatMessage {
        ChatMessage(
            id:              id,
            text:            text,
            isFromUser:      isFromUser,
            timestamp:       timestamp,
            isSystemMessage: isSystemMessage,
            isReadByOther:   isReadByOther ?? false
        )
    }
}

// MARK: - Presence der Gegenseite (Typing / Online / Lesezeitpunkt)

struct ChatPresenceDTO: Decodable {
    let otherIsTyping:   Bool
    let otherIsOnline:   Bool
    let otherLastSeenAt: Date?
    let otherLastReadAt: Date?

    func toDomain() -> ChatPresence {
        ChatPresence(
            otherIsTyping:   otherIsTyping,
            otherIsOnline:   otherIsOnline,
            otherLastSeenAt: otherLastSeenAt,
            otherLastReadAt: otherLastReadAt
        )
    }
}

/// Antwort von GET /messages/:conversationId
struct ChatMessagesResponseDTO: Decodable {
    let messages: [ChatMessageDTO]
    let presence: ChatPresenceDTO?
}

// MARK: - Company Profile

struct CompanyProfileDTO: Decodable {
    let name:             String
    let logoEmoji:        String
    let isVerified:       Bool
    let rating:           Double?
    let completedJobs:    Int
    let activeJobs:       Int
    let businessAreas:    [String]
    let locations:        [String]
    let replyTime:        String?
    /// 0...1, nil = zu wenig Daten (siehe backend utils/responseStats.js)
    let responseRate:         Double?
    /// Median bis zur ersten Antwort in Stunden, nil = zu wenig Daten
    let typicalResponseHours: Double?
    /// 0...100, nil = zu wenig Antworten (< 3), siehe backend utils/reviewLogic.js
    let wouldWorkAgainPercent: Int?
    let about:            String?
    let website:          String?
    let phone:            String?
    let email:            String?
    let industry:         String?
    let companySize:      String?
    let openJobs:         [CompanyOpenJobDTO]
    let reviewBreakdown:  ReviewBreakdownDTO?
    let workerReviews:    [WorkerReviewDTO]?
}

struct CompanyOpenJobDTO: Decodable, Identifiable {
    let id:        String
    let title:     String
    let payText:   String
    let shiftText: String
    let category:  String?
}

struct ReviewBreakdownDTO: Decodable {
    let communication:          Double
    let paymentFairness:        Double
    let workEnvironment:        Double
    let jobDescriptionAccuracy: Double
    let overallExperience:      Double
    let totalReviews:           Int
}

struct WorkerReviewDTO: Identifiable, Decodable {
    let id:                     String
    let workerName:             String
    let communication:          Int
    let paymentFairness:        Int
    let workEnvironment:        Int
    let jobDescriptionAccuracy: Int
    let overallExperience:      Int
    let comment:                String?
    let createdAt:              Date
}

// MARK: - Saved Company

struct SavedCompanyItem: Identifiable, Decodable {
    let id:          String
    let companyName: String
    let logoEmoji:   String
    let isVerified:  Bool
    let openJobs:    Int
    let rating:      Double?
    let savedAt:     Date
}

// MARK: - Employer Financials

struct EmployerFinancialsDTO: Decodable {
    let totalSpending:      Double
    let upcomingPayments:   Double
    let completedJobsCount: Int
    let paidOut:            Double
    let monthlySpend:       Double
    let chartData:          [DailySpendDTO]
    let byCategory:         [String: Double]
    let upcomingJobs:       [FinancialJobDTO]
    let completedJobsList:  [FinancialJobDTO]
}

struct DailySpendDTO: Decodable {
    let day:       String
    let upcoming:  Double
    let completed: Double
    let paidOut:   Double
}

struct FinancialJobDTO: Decodable, Identifiable {
    let id:        String
    let title:     String
    let logoEmoji: String
    let shiftText: String
    let amount:    Double
    let status:    String
}
