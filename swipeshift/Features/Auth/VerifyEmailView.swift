//
//  VerifyEmailView.swift
//  swipeShift
//
//  Created by DON on 10.01.26.
//
/*
import SwiftUI
import UIKit

struct VerifyEmailView: View {
    @EnvironmentObject var userStore: UserStore

    @State private var isResending = false
    @State private var isRefreshing = false
    @State private var localInfo: String? = nil
    @State private var localError: String? = nil

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 42))
                    .padding(.bottom, 6)

                Text("Verify your email")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("We sent a verification link to:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(userStore.currentUser?.email ?? "")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Please open the email and tap the link to finish setup.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let localInfo {
                Text(localInfo)
                    .font(.footnote)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let localError {
                Text(localError)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let err = userStore.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 12) {
                Button {
                    openMailApp()
                } label: {
                    Text("Open Mail App")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                        .cornerRadius(14)
                }

                Button {
                    Task { await resend() }
                } label: {
                    Text(isResending ? "Sending..." : "Resend email")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.12))
                        .foregroundColor(.primary)
                        .fontWeight(.semibold)
                        .cornerRadius(14)
                }
                .disabled(isResending)

                Button {
                    // Minimal/sauber für MVP: Logout -> User kann neu registrieren / andere Mail nutzen
                    userStore.logout()
                    userStore.showLogin = true
                } label: {
                    Text("Change email")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.12))
                        .foregroundColor(.primary)
                        .fontWeight(.semibold)
                        .cornerRadius(14)
                }

                Button {
                    Task { await refresh() }
                } label: {
                    Text(isRefreshing ? "Checking..." : "I already verified")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.12))
                        .foregroundColor(.primary)
                        .fontWeight(.semibold)
                        .cornerRadius(14)
                }
                .disabled(isRefreshing)

                Button(role: .destructive) {
                    userStore.logout()
                } label: {
                    Text("Log out")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.10))
                        .foregroundColor(.red)
                        .fontWeight(.semibold)
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)

            Spacer()
        }
        .padding(.top, 24)
    }

    private func openMailApp() {
        // Apple Mail
        if let url = URL(string: "message://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
        // Fallback: Gmail (falls installiert) – optional
        if let gmail = URL(string: "googlegmail://"), UIApplication.shared.canOpenURL(gmail) {
            UIApplication.shared.open(gmail)
            return
        }
        localError = "Could not open a mail app. Please open your email manually."
    }

    private func resend() async {
        localError = nil
        localInfo = nil
        isResending = true
        await userStore.resendVerification()
        isResending = false
        if userStore.errorMessage == nil {
            localInfo = "Verification email sent (if the address exists)."
        }
    }

    private func refresh() async {
        localError = nil
        localInfo = nil
        isRefreshing = true
        await userStore.refreshMeIfPossible()
        isRefreshing = false

        // Wenn es danach immer noch false ist, sag’s klar:
        if let u = userStore.currentUser, u.isEmailVerified == false {
            localError = "Not verified yet. Please check your inbox and spam folder."
        }
    }
}
*/

import SwiftUI
import UIKit

struct VerifyEmailView: View {
    @EnvironmentObject var userStore: UserStore

    @State private var isResending = false
    @State private var isRefreshing = false
    @State private var localInfo: String? = nil
    @State private var localError: String? = nil

    var body: some View {
        ZStack {
            SS.background().ignoresSafeArea()

            VStack {
                Spacer()

                SSCard {
                    VStack(spacing: 18) {
                        Circle()
                            .fill(SS.primary.opacity(0.12))
                            .frame(width: 88, height: 88)
                            .overlay(
                                Image(systemName: "envelope")
                                    .font(.system(size: 34, weight: .semibold))
                                    .foregroundColor(SS.primary)
                            )

                        Text("Check your email")
                            .font(.system(size: 32, weight: .bold))

                        Text("We sent a verification link to")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)

                        Text(userStore.currentUser?.email ?? "")
                            .font(.system(size: 18, weight: .semibold))
                            .multilineTextAlignment(.center)

                        // steps card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Next steps:")
                                .font(.system(size: 16, weight: .semibold))

                            stepRow("1.", "Open the email we just sent you")
                            stepRow("2.", "Click \"Verify Email\" button")
                            stepRow("3.", "Complete your profile setup")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(white: 0.97))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                        )

                        if let localInfo {
                            Text(localInfo)
                                .font(.footnote)
                                .foregroundColor(.green)
                                .multilineTextAlignment(.center)
                        }

                        if let localError {
                            Text(localError)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        if let err = userStore.errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task { await refresh() }
                        } label: {
                            Text(isRefreshing ? "Checking..." : "I've verified my email")
                        }
                        .buttonStyle(SSPrimaryButtonStyle(isEnabled: !isRefreshing))
                        .disabled(isRefreshing)

                        Button {
                            Task { await resend() }
                        } label: {
                            Text(isResending ? "Sending..." : "Resend verification email")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.95))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        .foregroundColor(.white)
                    }
                }

                Spacer()
            }
        }
    }

    private func stepRow(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)

            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private func resend() async {
        localError = nil
        localInfo = nil
        isResending = true
        await userStore.resendVerification()
        isResending = false
        if userStore.errorMessage == nil {
            localInfo = "Verification email sent (if the address exists)."
        }
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
