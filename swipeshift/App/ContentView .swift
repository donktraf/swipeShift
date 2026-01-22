//
//  ContentView.swift
//  L1 Demo
//
//  Created by DON on 07.12.25.@
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var userStore: UserStore

    var body: some View {
        Group {
            if let user = userStore.currentUser {

                if user.isEmailVerified == false {
                    VerifyEmailView()
                } else if user.onboarding != .complete {
                    NavigationStack {
                        OnboardingRootView()
                    }
                } else {
                    if let role = user.role {
                        switch role {
                        case .worker: WorkerHomeView()
                        case .employer: EmployerHomeView()
                        }
                    } else {
                        OnboardingRootView()
                    }
                }

            } else {
                MainView()
            }
        }
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
        
        /*if let user = userStore.currentUser, user.isEmailVerified == false {
            EmailVerifyBanner()
                .environmentObject(userStore)
        }*/
        
        
    }
}


#Preview {
    ContentView()
        .environmentObject(UserStore())
        .environmentObject(JobStore())
}

