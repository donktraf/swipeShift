//
//  GoogleLoginSuccessfulView.swift
//  swipeShift
//

import SwiftUI

struct GoogleLoginSuccessfulView: View {
    @EnvironmentObject var userStore: UserStore

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(DS.Color.success)
                    .frame(width: 80, height: 80)
                    .background(DS.Color.successSoft, in: Circle())
                    .padding(.top, DS.Spacing.xxl)
                    .accessibilityHidden(true)

                VStack(spacing: DS.Spacing.xs) {
                    Text("Account created!")
                        .dsFont(.display)
                        .foregroundStyle(DS.Color.text)
                        .multilineTextAlignment(.center)

                    Text("Welcome, \(userStore.currentUser?.firstName ?? userStore.currentUser?.email ?? "")")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Color.text2)
                        .multilineTextAlignment(.center)
                }

                DSSection("What happens now?", ruled: true) {
                    VStack(spacing: 0) {
                        successRow(number: "1", title: "Account created automatically", subtitle: "No password needed – use Google to login")
                        successRow(number: "2", title: "Email verified ✓", subtitle: "Google verified your email already")
                        successRow(number: "3", title: "Quick onboarding", subtitle: "Tell us if you're looking for work or hiring")
                    }
                }

                Button("Continue to Setup") {
                    // Nur Flag zuruecksetzen.
                    // ContentView reagiert darauf und zeigt OnboardingRootView
                    userStore.showSocialSuccess = false
                }
                .buttonStyle(.ds(.primary))
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.bottom, DS.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .dsBackground()
    }

    private func successRow(number: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Text(number)
                .font(DS.Font.make(14, .bold))
                .foregroundStyle(DS.Color.primaryText)
                .frame(width: 28, height: 28)
                .background(DS.Color.primarySoft, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsFont(.headline).foregroundStyle(DS.Color.text)
                Text(subtitle).dsFont(.callout).foregroundStyle(DS.Color.text2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}
