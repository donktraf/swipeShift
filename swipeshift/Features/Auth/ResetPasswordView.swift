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
        VStack(spacing: 16) {
            Text("Set new password")
                .font(.title2)
                .fontWeight(.bold)

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            #if DEBUG
            TextField("Token (debug only)", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13))
                .padding(10)
                .background(Color.yellow.opacity(0.15))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.4), lineWidth: 1))
            #endif

            SecureField("New password", text: $newPassword)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            SecureField("Confirm new password", text: $confirmPassword)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            if let localError {
                Text(localError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let backendError = userStore.errorMessage {
                Text(backendError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let successText {
                Text(successText)
                    .font(.footnote)
                    .foregroundColor(.green)
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
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSubmit ? Color.blue : Color.gray.opacity(0.5))
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                    .cornerRadius(14)
            }
            .disabled(!canSubmit || isSubmitting)

            Spacer()
        }
        .padding(24)
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canSubmit: Bool {
        // ✅ token muss intern vorhanden sein, aber user muss ihn nicht sehen
        !email.isEmpty && !token.isEmpty && !newPassword.isEmpty && !confirmPassword.isEmpty
    }
}
