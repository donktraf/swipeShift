//
//  PushNotificationManager.swift
//  swipeShift
//
//  Push-Benachrichtigungen (APNs): Berechtigung, Geraetetoken-Registrierung am Backend und
//  Tap-Routing. UIKit nur dort, wo APNs es verlangt (AppDelegate-Callbacks).
//
//  TODO (bezahlter Apple-Developer-Account): Push-Notifications-Capability im Xcode-Target hinzufuegen
//  (erzeugt den Entitlement `aps-environment`) und die APNS_*-Variablen im Backend setzen
//  (siehe swipeshift-backend/.env.example). Bis dahin schlaegt registerForRemoteNotifications()
//  fehl — das wird nur geloggt, die App laeuft normal weiter und das Backend sendet keinen Push.
//

import Foundation
import UIKit
import UserNotifications
import Combine

/// Ziel eines angetippten Pushs. Das Backend schickt `type` plus optionale IDs auf oberster Ebene des Payloads.
struct PushRoute: Equatable {
    let type: String          // chat | job | applicants | payments | reviews | account
    let jobId: String?
    let conversationId: String?
    /// Empfaenger-Konto (vom Backend im Payload); Taps fremder Konten werden verworfen
    let userId: String?

    init?(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String, !type.isEmpty else { return nil }
        self.type = type
        self.jobId = userInfo["jobId"] as? String
        self.conversationId = userInfo["conversationId"] as? String
        self.userId = userInfo["userId"] as? String
    }

    /// Gehoert der Tap zum aktuell eingeloggten Konto? (ohne userId im Payload: ja)
    func belongs(to currentUserId: String?) -> Bool {
        guard let userId else { return true }
        return userId == currentUserId
    }
}

@MainActor
final class PushNotificationManager: ObservableObject {
    static let shared = PushNotificationManager()

    /// Systemstatus der Benachrichtigungs-Berechtigung (fuer die Hinweise in den Einstellungen)
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Von der Home-View zu verarbeiten (Tab wechseln / Job oeffnen); danach auf nil setzen
    @Published var pendingRoute: PushRoute?
    /// Chat, den MessagesView oeffnen soll (nach Wechsel auf den Messages-Tab)
    @Published var pendingConversationId: String?

    private var deviceToken: String?
    private let askedKey = "SwipeShift.pushPermissionAsked"
    private let registeredTokenKey = "SwipeShift.registeredPushToken"

    private init() {}

    #if DEBUG
    private let environment = "sandbox"
    #else
    private let environment = "production"
    #endif

    // MARK: - Berechtigung

    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Beim ersten Erscheinen des Homes (eingeloggt + Onboarding fertig) einmalig nach der Berechtigung fragen;
    /// danach nur noch registrieren (das Geraetetoken kann sich aendern).
    func onHomeAppeared() async {
        await refreshAuthorizationStatus()
        if authorizationStatus == .notDetermined, !UserDefaults.standard.bool(forKey: askedKey) {
            await requestPermission()
        } else if isAuthorized {
            UIApplication.shared.registerForRemoteNotifications()
            await syncRegistration()
        }
    }

    /// Fragt nach der Berechtigung (System-Dialog erscheint nur beim ersten Mal)
    func requestPermission() async {
        UserDefaults.standard.set(true, forKey: askedKey)
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    private var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    // MARK: - Geraetetoken

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(deviceToken, forKey: DeviceInfo.pushTokenKey) // fuer X-Push-Token bei Login/Register
        Task { await syncRegistration() }
    }

    func didFailToRegister(_ error: Error) {
        // Erwartet, solange die Push-Capability/der Entitlement fehlt (siehe TODO oben) — nur loggen
        print("Push: remote notification registration failed:", error.localizedDescription)
    }

    /// Token am Backend anmelden (nur eingeloggt); gebunden an die aktuelle Sitzung
    func syncRegistration() async {
        await retryPendingUnregisters()
        guard let deviceToken, APIClient.shared.token != nil else { return }
        do {
            try await APIClient.shared.registerPushDevice(token: deviceToken, environment: environment)
            UserDefaults.standard.set(deviceToken, forKey: registeredTokenKey)
        } catch {
            print("Push: device registration failed:", error.localizedDescription)
        }
    }

    /// Beim Logout: Abmeldung zuerst PERSISTIEREN (Keychain: Token + alter Auth-Token), dann versuchen.
    /// Schlaegt sie offline fehl, wird sie beim naechsten Start/Login wiederholt, bis das Backend antwortet.
    /// Zusaetzlich verwirft das Backend beim Login mit X-Push-Token Zuordnungen anderer User.
    func unregister(authToken: String?) {
        pendingRoute = nil
        pendingConversationId = nil
        guard let authToken, let token = deviceToken ?? UserDefaults.standard.string(forKey: registeredTokenKey) else { return }
        UserDefaults.standard.removeObject(forKey: registeredTokenKey)
        var pending = loadPendingUnregisters()
        pending.append(PendingUnregister(token: token, authToken: authToken))
        savePendingUnregisters(pending)
        Task { await retryPendingUnregisters() }
    }

    private struct PendingUnregister: Codable, Equatable {
        let token: String
        let authToken: String
    }

    private func loadPendingUnregisters() -> [PendingUnregister] {
        guard let data = TokenStore.shared.loadPendingUnregisterData() else { return [] }
        return (try? JSONDecoder().decode([PendingUnregister].self, from: data)) ?? []
    }

    private func savePendingUnregisters(_ list: [PendingUnregister]) {
        if list.isEmpty { TokenStore.shared.deletePendingUnregisterData(); return }
        if let data = try? JSONEncoder().encode(list) { TokenStore.shared.savePendingUnregisterData(data) }
    }

    private var isRetryingUnregisters = false

    /// Offene Abmeldungen erneut senden (App-Start, Login, Home); Eintrag faellt erst nach Antwort des Backends weg
    func retryPendingUnregisters() async {
        guard !isRetryingUnregisters else { return }
        isRetryingUnregisters = true
        defer { isRetryingUnregisters = false }
        for entry in loadPendingUnregisters() {
            do {
                try await APIClient.shared.unregisterPushDevice(token: entry.token, authToken: entry.authToken)
                savePendingUnregisters(loadPendingUnregisters().filter { $0 != entry })
            } catch {
                print("Push: unregister pending, will retry:", error.localizedDescription)
            }
        }
    }

    // MARK: - Tap

    func handleTap(userInfo: [AnyHashable: Any]) {
        pendingRoute = PushRoute(userInfo: userInfo)
    }
}

// MARK: - AppDelegate (nur fuer APNs-Callbacks und Notification-Center-Delegate)

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in await PushNotificationManager.shared.retryPendingUnregisters() } // Rest eines Offline-Logouts
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushNotificationManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushNotificationManager.shared.didFailToRegister(error) }
    }

    // Im Vordergrund trotzdem als Banner zeigen
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run { PushNotificationManager.shared.handleTap(userInfo: userInfo) }
    }
}
