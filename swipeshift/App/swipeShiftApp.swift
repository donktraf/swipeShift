//
//  swipeShiftApp.swift
//  swipe Shift
//
//  Created by DON on 07.12.25.
//

import SwiftUI

@main
struct swipeShiftApp: App {

    @StateObject private var userStore = UserStore()
    @StateObject private var jobStore = JobStore()
    @StateObject private var messageStore = MessageStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(userStore)
                .environmentObject(jobStore)
                .environmentObject(messageStore)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "swipeshift",
              url.host == "reset-password" else { return }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = comps?.queryItems?.first(where: { $0.name == "token" })?.value
        let email = comps?.queryItems?.first(where: { $0.name == "email" })?.value

        guard let token, let email else { return }

        // Token im Hintergrund speichern — kein automatisches Sheet
        userStore.pendingResetToken = token
        userStore.pendingResetEmail = email
        print("🔗 Reset token stored for:", email)
    }
}
