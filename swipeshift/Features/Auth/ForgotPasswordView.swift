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
    @State private var infoText: String? = nil

    init(prefilledEmail: String = "") {
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Reset password")
                .font(.title2)
                .fontWeight(.bold)

            Text("Enter your email. If it exists, we’ll send a reset link/token.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            if let infoText {
                Text(infoText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

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

                    // ✅ Immer gleiche Info (Security)
                    infoText = "If that email exists, you’ll receive instructions shortly."
                }
            } label: {
                Text(isSubmitting ? "Sending..." : "Send reset email")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(email.isEmpty ? Color.gray.opacity(0.5) : Color.blue)
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                    .cornerRadius(14)
            }
            .disabled(email.isEmpty || isSubmitting)

            NavigationLink {
                ResetPasswordView(prefilledEmail: email)
            } label: {
                Text("I already have a token")
                    .font(.footnote)
                    .foregroundColor(.blue)
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(24)
        .navigationTitle("Forgot Password")
        .navigationBarTitleDisplayMode(.inline)
    }
}
