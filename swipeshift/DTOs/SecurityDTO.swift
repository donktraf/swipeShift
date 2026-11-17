//
//  SecurityDTO.swift
//  swipeShift
//
//  Aktive Sitzungen (Geraete) + 2FA per E-Mail-Code.
//

import Foundation
import UIKit

/// Antwort aller Login-Endpunkte. Bei aktivierter 2FA kommt statt Token + User eine Challenge.
struct LoginResponseDTO: Decodable {
    let token: String?
    let user: UserDTO?
    let isNewUser: Bool?

    let twoFactorRequired: Bool?
    let challengeId: String?
    let emailHint: String?
}

/// Offene 2FA-Abfrage (Code wurde per E-Mail verschickt).
struct TwoFactorChallenge: Identifiable, Equatable {
    /// Stabile ID fuers Sheet — bleibt bei "Resend" gleich, damit das Sheet nicht neu aufgeht
    let id = UUID()
    var challengeId: String     // wechselt bei "Resend"
    var emailHint: String
}

/// Ergebnis eines Login-Versuchs.
enum LoginOutcome {
    case signedIn(user: UserDTO, isNewUser: Bool)
    case twoFactorRequired(TwoFactorChallenge)
}

struct TwoFactorCodeSentDTO: Decodable {
    let challengeId: String
    let emailHint: String
}

struct DeviceSessionDTO: Decodable, Identifiable {
    let id: String
    let deviceName: String?
    let deviceModel: String?
    let osVersion: String?
    let createdAt: Date
    let lastActiveAt: Date
    let isCurrent: Bool

    var displayName: String {
        deviceName ?? deviceModel ?? "Unknown device"
    }

    var iconName: String {
        let name = (deviceName ?? deviceModel ?? "").lowercased()
        if name.contains("ipad") { return "ipad" }
        if name.contains("mac") { return "laptopcomputer" }
        return "iphone"
    }
}

struct DeviceSessionsResponseDTO: Decodable {
    let sessions: [DeviceSessionDTO]
}

/// Strukturierter Fehler vom Backend ({ error, code }).
struct APIErrorBody: Decodable {
    let error: String?
    let code: String?
}

extension Notification.Name {
    /// Backend meldet: diese Sitzung wurde beendet (anderes Geraet hat abgemeldet, Passwort-Reset, ...)
    static let sessionRevoked = Notification.Name("SwipeShift.sessionRevoked")
}

/// Geraete-Infos, die beim Login mitgeschickt werden, damit "Active Sessions" sie anzeigen kann.
enum DeviceInfo {
    static var name: String { UIDevice.current.model }               // "iPhone" / "iPad"
    static var osVersion: String { "iOS \(UIDevice.current.systemVersion)" }

    /// Hardware-Kennung, z.B. "iPhone16,1" (im Simulator die simulierte Kennung)
    static var model: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(sim) (Simulator)"
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    static func apply(to request: inout URLRequest) {
        request.setValue(name, forHTTPHeaderField: "X-Device-Name")
        request.setValue(model, forHTTPHeaderField: "X-Device-Model")
        request.setValue(osVersion, forHTTPHeaderField: "X-OS-Version")
    }
}
