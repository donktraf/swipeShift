//
//  SettingsDTO.swift
//  swipeShift
//
//  Konto-Einstellungen (GET/PATCH /auth/me/settings). Dark Mode ist bewusst NICHT
//  hier, sondern pro Geraet in @AppStorage("appColorScheme").
//

import Foundation
import SwiftUI

struct NotificationChannelDTO: Codable, Equatable {
    var push: Bool
    var email: Bool
}

struct NotificationSettingsDTO: Codable, Equatable {
    var jobActivity: NotificationChannelDTO
    var payments: NotificationChannelDTO
    var messages: NotificationChannelDTO
    var account: NotificationChannelDTO
}

struct QuietHoursDTO: Codable, Equatable {
    var enabled: Bool
    var from: String   // "HH:MM"
    var to: String
}

struct PayoutSettingsDTO: Decodable, Equatable {
    var method: String          // "bank" | "paypal"
    var paypalEmail: String?
    var frequency: String       // "instant" | "weekly" | "monthly"
    var bank: BankDetailsDTO?
}

/// US-Bankdaten (Antwort): die Kontonummer kommt nie zurueck, nur die letzten 4 Ziffern.
struct BankDetailsDTO: Decodable, Equatable {
    var accountHolderName: String
    var routingNumber: String
    var accountType: String     // "checking" | "savings"
    var accountLast4: String
}

struct AccountSettingsDTO: Decodable, Equatable {
    var notifications: NotificationSettingsDTO
    var quietHours: QuietHoursDTO
    var payout: PayoutSettingsDTO
}

struct AccountSettingsResponseDTO: Decodable {
    let settings: AccountSettingsDTO
    let paused: Bool?
}

/// Teil-Aenderung fuer PATCH /auth/me/settings — nil-Felder werden nicht gesendet.
struct AccountSettingsPatch: Encodable {
    var notifications: NotificationSettingsDTO?
    var quietHours: QuietHoursDTO?
    var payout: PayoutPatch?

    struct PayoutPatch: Encodable {
        var method: String?
        /// nil = unveraendert lassen
        var bank: BankPatch?
        var paypalEmail: String?
        var frequency: String?
    }

    /// Teil-Aenderung der Bankdaten — accountNumber nur senden, wenn neu eingegeben (sonst bleibt die gespeicherte).
    struct BankPatch: Encodable {
        var accountHolderName: String?
        var routingNumber: String?
        var accountNumber: String?
        var accountType: String?
    }
}

// MARK: - Erscheinungsbild (pro Geraet)

enum AppColorSchemePreference: String, CaseIterable {
    case system, light, dark

    static let storageKey = "appColorScheme"

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
