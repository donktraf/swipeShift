//
//  ResetPasswordView.swift
//  swipeShift
//
//  Created by DON on 31.12.25.
//

import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.dismiss) var dismiss

    @State private var email: String
    @State private var token: String          // bleibt intern, aber unsichtbar
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isSubmitting = false
    @State private var successText: String? = nil
    @State private var localError: String? = nil

    init(prefilledEmail: String = "", prefilledToken: String = "") {
        _email = State(initialValue: prefilledEmail)
        _token = State(initialValue: prefilledToken)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Set new password").dsFont(.title).foregroundStyle(DS.Color.text)

                DSTextField("Email", placeholder: "you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                DSTextField("New password", text: $newPassword, isSecure: true)

                DSTextField("Confirm new password", text: $confirmPassword, error: localError ?? userStore.errorMessage, isSecure: true)

                if let successText {
                    Text(successText)
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.success)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }

                Button {
                    localError = nil
                    successText = nil

                    guard newPassword.count >= 6 else {
                        localError = "Password must be at least 6 characters."
                        return
                    }
                    guard newPassword == confirmPassword else {
                        localError = "Passwords do not match."
                        return
                    }

                    Task {
                        isSubmitting = true
                        await userStore.resetPasswordRemote(email: email, token: token, newPassword: newPassword)
                        isSubmitting = false

                        if userStore.errorMessage == nil {
                            successText = "Password updated. You can now log in."
                        }
                        
                        // ✅ Login danach öffnen + Email vorfüllen
                        userStore.loginPrefillEmail = email
                        userStore.showLogin = true

                        // ✅ Reset-Sheet schließen (triggert auch dein Binding-set -> resetToken/resetEmail werden nil)
                        dismiss()
                    }
                } label: {
                    Text(isSubmitting ? "Saving..." : "Update password")
                }
                .buttonStyle(.ds(.primary))
                .disabled(!canSubmit || isSubmitting)
                .padding(.top, DS.Spacing.xs)
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.vertical, DS.Spacing.lg)
        }
        .dsBackground()
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canSubmit: Bool {
        // token muss intern vorhanden sein, aber user muss ihn nicht sehen
        !email.isEmpty && !token.isEmpty && !newPassword.isEmpty && !confirmPassword.isEmpty
    }
}
