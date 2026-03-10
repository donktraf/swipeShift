//
//  ContentView.swift
//  swipeShift
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var userStore: UserStore

    var body: some View {
        Group {
            if let user = userStore.currentUser {

                // ✅ FALL 1: Email noch nicht verifiziert (nur Email-User)
                // Social-User (Google/Apple) haben isEmailVerified == true
                // also kommen sie hier nie rein
                if user.isEmailVerified == false {
                    VerifyEmailView()

                // ✅ FALL 2: Neuer Social-User → Success Screen
                } else if userStore.showSocialSuccess {
                    GoogleLoginSuccessfulView()
                        .environmentObject(userStore)

                // ✅ FALL 3: Onboarding noch nicht abgeschlossen
                } else if user.onboarding != .complete {
                    NavigationStack {
                        OnboardingRootView()
                    }

                // ✅ FALL 4: Alles fertig → Home
                } else {
                    if let role = user.role {
                        switch role {
                        case .worker: WorkerHomeView()
                        case .employer: EmployerHomeView()
                        }
                    } else {
                        NavigationStack {
                            OnboardingRootView()
                        }
                    }
                }

            } else {
                // Nicht eingeloggt
                MainView()
            }
        }
        // ✅ showLogin bleibt für Password-Reset-Flow
        .fullScreenCover(isPresented: $userStore.showLogin) {
            NavigationStack {
                LoginView(prefilledEmail: userStore.loginPrefillEmail)
                    .environmentObject(userStore)
            }
        }
        .onAppear {
            print("👀 ContentView appeared")
            print("👤 currentUser:", userStore.currentUser?.email ?? "nil")
        }
        .onChange(of: userStore.currentUser?.email) { _, newValue in
            print("🔁 currentUser changed to:", newValue ?? "nil")
        }
        .task {
            await userStore.bootstrapSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await userStore.refreshMeIfPossible() }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(UserStore())
        .environmentObject(JobStore())
}
