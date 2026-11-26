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
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                if emailSent {
                    emailSentState
                } else {
                    inputState
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.vertical, DS.Spacing.lg)
        }
        .dsBackground()
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
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Reset password").dsFont(.title).foregroundStyle(DS.Color.text)
                Text("Enter your email address and we’ll send you a link to reset your password.")
                    .dsFont(.body)
                    .foregroundStyle(DS.Color.text2)
            }

            DSTextField("Email address", placeholder: "you@example.com", text: $email, error: userStore.errorMessage)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                Task {
                    isSubmitting = true
                    await userStore.forgotPasswordRemote(email: email)
                    isSubmitting = false
                    // Always show sent state (no enumeration)
                    emailSent = true
                }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    if isSubmitting {
                        ProgressView().tint(DS.Color.onPrimary)
                    }
                    Text(isSubmitting ? "Sending..." : "Send reset link")
                }
            }
            .buttonStyle(.ds(.primary))
            .disabled(email.isEmpty || isSubmitting)
        }
    }

    // MARK: - Email Sent State

    private var emailSentState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "envelope.badge.checkmark")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(DS.Color.primaryText)
                .frame(width: 72, height: 72)
                .background(DS.Color.primarySoft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                .accessibilityHidden(true)

            VStack(spacing: DS.Spacing.xs) {
                Text("Check your email").dsFont(.title).foregroundStyle(DS.Color.text)

                Text("We sent a reset link to **\(email)**.\nTap the link in the email — the app will open automatically.")
                    .dsFont(.body)
                    .foregroundStyle(DS.Color.text2)
                    .multilineTextAlignment(.center)
            }

            Text("The link expires in 30 minutes.\nIf you don’t see it, check your spam folder.")
                .dsFont(.caption)
                .foregroundStyle(DS.Color.muted)
                .multilineTextAlignment(.center)

            // Wird aktiv sobald Deep Link den Token im Hintergrund gespeichert hat
            Button {
                showReset = true
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: userStore.pendingResetToken != nil ? "checkmark.circle.fill" : "lock.open")
                    Text("I have a token")
                }
            }
            .buttonStyle(.ds(.primary))
            .disabled(userStore.pendingResetToken == nil)

            Button("Resend email") {
                emailSent = false
                userStore.errorMessage = nil
            }
            .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
        }
    }
}
