//
//  OnboardingRootView.swift
//  swipeShift
//
//  Created by DON on 04.01.26.
//

import SwiftUI

struct OnboardingRootView: View {
    @EnvironmentObject var userStore: UserStore

    var body: some View {
        VStack {
            if let user = userStore.currentUser {

                // Optional: falls du Email-Verifizierung als "Blocker" willst
                // if user.isEmailVerified == false {
                //     VerifyEmailView()
                // } else {

                switch user.onboarding {
                case .pendingRole:
                    RoleChoiceView()

                case .pendingProfile:
                    if user.role == .worker {
                        WorkerOnboardingView()
                    } else if user.role == .employer {
                        EmployerOnboardingView()
                    } else {
                        RoleChoiceView() // Safety fallback
                    }

                case .complete:
                    ProgressView() // sollte hier eigentlich nie auftauchen
                }

                // } // <- nur wenn du den VerifyEmail Block aktivierst

            } else {
                ProgressView()
            }
        }
    }
}
