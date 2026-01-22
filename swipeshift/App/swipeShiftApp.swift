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

    // 🔑 Reset-State (global)
    @State private var resetToken: String?
    @State private var resetEmail: String?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(userStore)
                .environmentObject(jobStore)

                // ✅ Deep Link Entry Point
                .onOpenURL { url in
                    handleDeepLink(url)
                }

                // ✅ Global Reset Screen
                .sheet(
                    isPresented: Binding(
                        get: { resetToken != nil && resetEmail != nil },
                        set: { if !$0 { resetToken = nil; resetEmail = nil } }
                    )
                ) {
                    if let token = resetToken,
                       let email = resetEmail {
                        ResetPasswordView(
                            prefilledEmail: email,
                            prefilledToken: token
                        )
                        .environmentObject(userStore)
                    }
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        print("🔗 DeepLink received:", url.absoluteString)

        guard url.scheme == "swipeshift" else { return }
        guard url.host == "reset-password" else {
            print("❌ host mismatch:", url.host ?? "nil")
            return
        }
        

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = comps?.queryItems?.first(where: { $0.name == "token" })?.value
        let email = comps?.queryItems?.first(where: { $0.name == "email" })?.value

        print("✅ parsed token:", token ?? "nil")
        print("✅ parsed email:", email ?? "nil")

        guard let token, let email else { return }

        resetToken = token
        resetEmail = email
    }
}
