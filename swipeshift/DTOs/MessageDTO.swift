//
//  MessageDTO.swift
//  swipeShift
//

import Foundation

// MARK: - Konversation vom Backend

struct ConversationDTO: Decodable, Identifiable {
    let id:              String
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

    func toDomain() -> Conversation {
        Conversation(
            id:              id,
            jobTitle:        jobTitle,
            company:         company,
            logoEmoji:       logoEmoji,
            status:          ConversationStatus(rawValue: status) ?? .upcoming,
            jobDate:         jobDate,
            lastMessage:     lastMessage,
            lastMessageTime: lastMessageTime,
            isRead:          isRead,
            messages:        messages.map { $0.toDomain() }
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

    func toDomain() -> ChatMessage {
        ChatMessage(
            id:              id,
            text:            text,
            isFromUser:      isFromUser,
            timestamp:       timestamp,
            isSystemMessage: isSystemMessage
        )
    }
}

// MARK: - Company Profile

struct CompanyProfileDTO: Decodable {
    let name:           String
    let logoEmoji:      String
    let isVerified:     Bool
    let rating:         Double?
    let completedJobs:  Int
    let activeJobs:     Int
    let businessAreas:  [String]
    let locations:      [String]
    let replyTime:      String?
    let about:          String?
    let website:        String?
    let industry:       String?
    let companySize:    String?
    let openJobs:       [CompanyOpenJobDTO]
}

struct CompanyOpenJobDTO: Decodable, Identifiable {
    let id:        String
    let title:     String
    let payText:   String
    let shiftText: String
    let category:  String?
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
