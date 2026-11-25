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
    /// "email" | "totp" (fehlt bei aelteren Backends = email)
    let method: String?
}

/// Zweiter Faktor, mit dem 2FA abgesichert ist.
enum TwoFactorMethod: String {
    case email
    case totp
}

/// Offene 2FA-Abfrage (Code wurde per E-Mail verschickt).
struct TwoFactorChallenge: Identifiable, Equatable {
    /// Stabile ID fuers Sheet — bleibt bei "Resend" gleich, damit das Sheet nicht neu aufgeht
    let id = UUID()
    var challengeId: String     // wechselt bei "Resend"
    var emailHint: String
    var method: TwoFactorMethod = .email
}

/// Ergebnis eines Login-Versuchs.
enum LoginOutcome {
    case signedIn(user: UserDTO, isNewUser: Bool)
    case twoFactorRequired(TwoFactorChallenge)
}

struct TwoFactorCodeSentDTO: Decodable {
    let challengeId: String
    let emailHint: String?
    let method: String?

    var asChallenge: TwoFactorChallenge {
        TwoFactorChallenge(
            challengeId: challengeId,
            emailHint: emailHint ?? "your email",
            method: TwoFactorMethod(rawValue: method ?? "email") ?? .email
        )
    }
}

/// GET /auth/2fa
struct TwoFactorStatusDTO: Decodable {
    let enabled: Bool
    let method: String?
    let backupCodesRemaining: Int?
}

/// POST /auth/2fa/totp/backup-codes
struct BackupCodesDTO: Decodable {
    let backupCodes: [String]
}

/// POST /auth/2fa/totp/setup
struct TotpSetupDTO: Decodable {
    let secret: String
    let otpauthUri: String
    let issuer: String
    let account: String
}

/// POST /auth/2fa/totp/confirm — Backup-Codes kommen nur dieses eine Mal im Klartext
struct TotpConfirmDTO: Decodable {
    let backupCodes: [String]
}

struct DeviceSessionDTO: Decodable, Identifiable {
    let id: String
    let deviceName: String?
    let deviceModel: String?
    let osVersion: String?
    /// Grober Ort, den das Geraet selbst gemeldet hat ("Austin, TX")
    let city: String?
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
    /// Nur bei INCOMPLETE_JOB: fehlende Pflichtfelder
    let missing: [String]?
    /// Nur bei REAUTH_REQUIRED: verfuegbare Re-Auth-Methoden ("totp", "password", "email")
    let methods: [String]?
    /// Nur bei TOO_MANY_ATTEMPTS (Re-Auth): Wartezeit in Minuten
    let retryAfterMinutes: Int?
    /// Nur bei UNPAID_WORKERS (DELETE /auth/me): Jobs mit unbezahlten Workern
    let jobs: [UnpaidJobDTO]?
}

/// Job mit beendeten, noch unbezahlten Schichten (409 UNPAID_WORKERS beim Konto-Loeschen)
struct UnpaidJobDTO: Decodable {
    let id: String
    let title: String
    let unpaidWorkers: Int
}

/// GET /auth/me/reauth/methods
struct ReauthMethodsDTO: Decodable {
    let methods: [String]
    let emailHint: String?
}

/// POST /auth/me/reauth
struct ReauthResultDTO: Decodable {
    let validUntil: Date
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

    /// IANA-Zeitzone des Geraets (z.B. "Europe/Berlin") — das Backend braucht sie fuer die Ruhezeiten der Push-Benachrichtigungen.
    static func applyTimeZone(to request: inout URLRequest) {
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Time-Zone")
    }

    /// Aktuelles APNs-Token (nicht isoliert lesbar; vom PushNotificationManager gesetzt)
    static let pushTokenKey = "SwipeShift.currentPushToken"

    /// Backend-Sicherheitsnetz: bei Login/Register nimmt dieses Geraet ein evtl. noch beim Vorgaenger-User haengendes Token an sich
    static func applyPushToken(to request: inout URLRequest) {
        guard let token = UserDefaults.standard.string(forKey: pushTokenKey), !token.isEmpty else { return }
        request.setValue(token, forHTTPHeaderField: "X-Push-Token")
    }

    static func apply(to request: inout URLRequest) {
        applyTimeZone(to: &request)
        applyPushToken(to: &request)
        request.setValue(name, forHTTPHeaderField: "X-Device-Name")
        request.setValue(model, forHTTPHeaderField: "X-Device-Model")
        request.setValue(osVersion, forHTTPHeaderField: "X-OS-Version")
        applyCity(to: &request)
    }

    // MARK: Grober Ort ("Austin, TX")

    private static let cityKey = "SwipeShift.lastKnownDeviceCity"

    /// Zuletzt bekannter grober Ort — aus dem bereits gespeicherten Profil-Standort, keine neue
    /// Standortberechtigung, keine Koordinaten. Bleibt lokal gespeichert, damit auch ein Login
    /// (wenn noch kein User geladen ist) den Ort mitschicken kann.
    static var city: String? {
        UserDefaults.standard.string(forKey: cityKey)
    }

    /// Wird mit dem Profil-Standort aufgerufen; ein nicht auswertbarer Ort loescht den Cache.
    static func updateCity(fromLocation location: String?) {
        // Nicht auswertbarer Ort → alten Wert nicht stehen lassen (er koennte zu einem anderen Profil gehoeren)
        guard let parsed = coarseCity(from: location) else { clearCity(); return }
        UserDefaults.standard.set(parsed, forKey: cityKey)
    }

    static func clearCity() {
        UserDefaults.standard.removeObject(forKey: cityKey)
    }

    /// Fehlt der Ort, wird nichts gesendet. Nicht-ASCII-Zeichen werden prozent-kodiert (HTTP-Header).
    static func applyCity(to request: inout URLRequest) {
        guard let city,
              let encoded = city.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ",.-'")))
        else { return }
        request.setValue(encoded, forHTTPHeaderField: "X-Device-City")
    }

    /// Reduziert einen Standort-Text ("123 Main St, Austin, TX 78701, USA") auf "City, ST".
    /// Ohne erkennbaren Bundesstaat: nur bei kurzen Angaben "Stadt" bzw. "Stadt, Region" ohne Ziffern.
    static func coarseCity(from location: String?) -> String? {
        guard let location else { return nil }
        let parts = location
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        // "TX" oder "TX 78701" → Bundesstaat; davor steht die Stadt
        for (index, part) in parts.enumerated() where index > 0 {
            let token = part.split(separator: " ").first.map(String.init) ?? ""
            let rest = part.dropFirst(token.count).trimmingCharacters(in: .whitespaces)
            let isState = token.count == 2 && token == token.uppercased() && token.allSatisfy(\.isLetter)
            let restIsZip = rest.isEmpty || rest.allSatisfy { $0.isNumber || $0 == "-" }
            if isState && restIsZip {
                let city = parts[index - 1]
                guard !city.contains(where: \.isNumber) else { return nil }
                return "\(city), \(token)"
            }
        }

        guard parts.count <= 2, !location.contains(where: \.isNumber) else { return nil }
        return parts.joined(separator: ", ")
    }
}
