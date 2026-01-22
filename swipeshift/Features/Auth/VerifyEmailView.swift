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
