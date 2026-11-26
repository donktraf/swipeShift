//
//  VerifyEmailView.swift
//  swipeShift
//
//  Created by DON on 10.01.26.
//

import SwiftUI
import UIKit

struct VerifyEmailView: View {
    @EnvironmentObject var userStore: UserStore

    @State private var isRefreshing = false
    @State private var localInfo: String? = nil
    @State private var localError: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: "envelope")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(DS.Color.primaryText)
                    .frame(width: 80, height: 80)
                    .background(DS.Color.primarySoft, in: Circle())
                    .padding(.top, DS.Spacing.xxl)
                    .accessibilityHidden(true)

                VStack(spacing: DS.Spacing.xs) {
                    Text("Check your email").dsFont(.display).foregroundStyle(DS.Color.text)

                    Text("We sent a verification link to")
                        .dsFont(.body)
                        .foregroundStyle(DS.Color.text2)

                    Text(userStore.currentUser?.email ?? "")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Color.text)
                        .multilineTextAlignment(.center)
                }

                // Naechste Schritte
                DSSection("Next steps", ruled: true) {
                    VStack(spacing: 0) {
                        stepRow("1", "Open the email we just sent you")
                        stepRow("2", "Click \"Verify Email\" button")
                        stepRow("3", "Complete your profile setup")
                    }
                }

                VStack(spacing: DS.Spacing.xs) {
                    if let localInfo {
                        message(localInfo, color: DS.Color.success)
                    }
                    if let localError {
                        message(localError, color: DS.Color.danger)
                    }
                    if userStore.verificationMailFailed {
                        message("We couldn't send the verification email. Tap Resend to try again.", color: DS.Color.warning)
                    }
                    if let err = userStore.resendError {
                        message(err, color: DS.Color.danger)
                    }
                    if let err = userStore.errorMessage {
                        message(err, color: DS.Color.danger)
                    }
                }

                VStack(spacing: DS.Spacing.xs) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Text(isRefreshing ? "Checking..." : "I've verified my email")
                    }
                    .buttonStyle(.ds(.primary))
                    .disabled(isRefreshing)

                    ResendVerificationButton()
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.bottom, DS.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .dsBackground()
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .dsFont(.callout)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func stepRow(_ n: String, _ text: String) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Text(n)
                .font(DS.Font.make(13, .bold))
                .foregroundStyle(DS.Color.primaryText)
                .frame(width: 28, height: 28)
                .background(DS.Color.primarySoft, in: Circle())

            Text(text).dsFont(.body).foregroundStyle(DS.Color.text)

            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.xs)
        .frame(minHeight: 44)
        .overlay(alignment: .top) { if n != "1" { DSDivider() } }
        .accessibilityElement(children: .combine)
    }

    private func refresh() async {
        localError = nil
        localInfo = nil
        isRefreshing = true
        await userStore.refreshMeIfPossible()
        isRefreshing = false

        if let u = userStore.currentUser, u.isEmailVerified == false {
            localError = "Not verified yet. Please check your inbox and spam folder."
        }
    }
}
