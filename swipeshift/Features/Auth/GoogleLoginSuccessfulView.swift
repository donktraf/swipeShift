//
//  GoogleLoginSuccessfulView.swift
//  swipeShift
//

import SwiftUI

struct GoogleLoginSuccessfulView: View {
    @EnvironmentObject var userStore: UserStore

    var body: some View {
        ZStack {
            SS.background().ignoresSafeArea()

            VStack {
                Spacer()

                SSCard {
                    VStack(spacing: 18) {
                        Circle()
                            .fill(Color.green.opacity(0.18))
                            .frame(width: 88, height: 88)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundColor(.green)
                            )

                        Text("Account created!")
                            .font(.system(size: 30, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text("Welcome, \(userStore.currentUser?.firstName ?? userStore.currentUser?.email ?? "")")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        VStack(alignment: .leading, spacing: 14) {
                            Text("What happens now?")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(SS.primary)

                            successRow(number: "1", title: "Account created automatically", subtitle: "No password needed – use Google to login")
                            successRow(number: "2", title: "Email verified ✓", subtitle: "Google verified your email already")
                            successRow(number: "3", title: "Quick onboarding", subtitle: "Tell us if you're looking for work or hiring")
                        }
                        .padding(16)
                        .background(Color(white: 0.97))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                        )

                        Button {
                            // ✅ Nur Flag zurücksetzen.
                            // ContentView reagiert darauf und zeigt OnboardingRootView
                            userStore.showSocialSuccess = false
                        } label: {
                            Text("Continue to Setup")
                        }
                        .buttonStyle(SSPrimaryButtonStyle())
                    }
                }

                Spacer()
            }
        }
    }

    private func successRow(number: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(SS.primary.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(number)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(SS.primary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}
