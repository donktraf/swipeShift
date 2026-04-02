//
//  ForgotPasswordView.swift
//  swipeShift
//
//  Created by DON on 31.12.25.
//

import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.dismiss) var dismiss

    @State private var email: String
    @State private var isSubmitting = false
    @State private var emailSent = false
    @State private var showReset = false

    init(prefilledEmail: String = "") {
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        VStack(spacing: 24) {
            if emailSent {
                emailSentState
            } else {
                inputState
            }
            Spacer()
        }
        .padding(24)
        .navigationTitle("Forgot Password")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showReset) {
            ResetPasswordView(
                prefilledEmail: userStore.pendingResetEmail ?? email,
                prefilledToken: userStore.pendingResetToken ?? ""
            )
            .environmentObject(userStore)
        }
    }

    // MARK: - Input State

    private var inputState: some View {
        VStack(spacing: 16) {
            Text("Reset password")
                .font(.title2)
                .fontWeight(.bold)

            Text("Enter your email address and we’ll send you a link to reset your password.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            TextField("Email address", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            if let error = userStore.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task {
                    isSubmitting = true
                    await userStore.forgotPasswordRemote(email: email)
                    isSubmitting = false
                    // Always show sent state (no enumeration)
                    emailSent = true
                }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    }
                    Text(isSubmitting ? "Sending..." : "Send reset link")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(email.isEmpty ? Color.gray.opacity(0.4) : SS.primary)
                .foregroundColor(.white)
                .fontWeight(.semibold)
                .cornerRadius(14)
            }
            .disabled(email.isEmpty || isSubmitting)
        }
    }

    // MARK: - Email Sent State

    private var emailSentState: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge.checkmark")
                .font(.system(size: 56))
                .foregroundColor(SS.primary)

            VStack(spacing: 8) {
                Text("Check your email")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("We sent a reset link to **\(email)**.\nTap the link in the email — the app will open automatically.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("The link expires in 30 minutes.\nIf you don’t see it, check your spam folder.")
                .font(.footnote)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)

            // Wird aktiv sobald Deep Link den Token im Hintergrund gespeichert hat
            Button {
                showReset = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: userStore.pendingResetToken != nil ? "checkmark.circle.fill" : "lock.open")
                        .foregroundColor(userStore.pendingResetToken != nil ? .green : .secondary)
                    Text("I have a token")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(userStore.pendingResetToken != nil ? SS.primary : Color.gray.opacity(0.15))
                .foregroundColor(userStore.pendingResetToken != nil ? .white : .secondary)
                .cornerRadius(14)
            }
            .disabled(userStore.pendingResetToken == nil)

            Button {
                emailSent = false
                userStore.errorMessage = nil
            } label: {
                Text("Resend email")
                    .font(.system(size: 14))
                    .foregroundColor(SS.primary)
            }
        }
    }
}
