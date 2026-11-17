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
    var hasIban: Bool
    var ibanMasked: String?
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
        /// nil = unveraendert lassen; leerer String = IBAN loeschen
        var iban: String?
        var paypalEmail: String?
        var frequency: String?
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
