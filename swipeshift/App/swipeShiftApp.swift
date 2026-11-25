//
//  swipeShiftApp.swift
//  swipe Shift
//
//  Created by DON on 07.12.25.
//

import SwiftUI
import GoogleSignIn

@main
struct swipeShiftApp: App {

    // APNs-Callbacks (Geraetetoken, Tap auf Push) — siehe PushNotificationManager
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var userStore = UserStore()
    @StateObject private var jobStore = JobStore()
    @StateObject private var messageStore = MessageStore()

    // Erscheinungsbild pro Geraet (Einstellungen → App Preferences)
    @AppStorage(AppColorSchemePreference.storageKey) private var colorSchemeRaw = AppColorSchemePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(userStore)
                .environmentObject(jobStore)
                .environmentObject(messageStore)
                .preferredColorScheme(AppColorSchemePreference(rawValue: colorSchemeRaw)?.colorScheme)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    // Universal Link (https://swipeshift.app/jobs/<id>)
                    if let url = activity.webpageURL { handleDeepLink(url) }
                }
        }
    }

    /// Extrahiert die Job-ID aus `swipeshift://job/<id>` oder `https://(www.)swipeshift.app/jobs/<id>`.
    /// Gibt nil zurueck bei fremdem Host/Schema, zusaetzlichen Pfadsegmenten oder ungueltiger ID.
    static func jobId(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let candidate: String?
        switch url.scheme?.lowercased() {
        case "swipeshift":
            guard url.host?.lowercased() == "job", parts.count == 1 else { return nil }
            candidate = parts[0]
        case "https":
            guard let host = url.host?.lowercased(),
                  host == "swipeshift.app" || host == "www.swipeshift.app",
                  parts.count == 2, parts[0] == "jobs" else { return nil }
            candidate = parts[1]
        #if DEBUG
        case "http":
            // Nur DEBUG: lokaler Website-Server (AppConfig.websiteURL)
            guard url.host?.lowercased() == "localhost", url.port == 8788,
                  parts.count == 2, parts[0] == "jobs" else { return nil }
            candidate = parts[1]
        #endif
        default:
            return nil
        }
        guard let id = candidate, id.count <= 64,
              id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        return id
    }

    private func handleDeepLink(_ url: URL) {
        // Google Sign-In redirect
        if GIDSignIn.sharedInstance.handle(url) { return }

        // Geteilter Job: swipeshift://job/<id> → WorkerHomeView oeffnet das Job-Detail
        // bzw. Universal Link https://swipeshift.app/jobs/<id>
        if let jobId = Self.jobId(from: url) {
            jobStore.pendingDeepLinkJobId = jobId
            return
        }

        // Password-Reset Deep Link
        guard url.scheme == "swipeshift",
              url.host == "reset-password" else { return }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = comps?.queryItems?.first(where: { $0.name == "token" })?.value
        let email = comps?.queryItems?.first(where: { $0.name == "email" })?.value

        guard let token, let email else { return }

        userStore.pendingResetToken = token
        userStore.pendingResetEmail = email
        print("🔗 Reset token stored for:", email)
    }
}
