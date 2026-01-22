//
//  RoleChoiceView.swift
//  swipeShift
//
//  Created by DON on 04.01.26.
//

import SwiftUI

struct RoleChoiceView: View {
    @EnvironmentObject var userStore: UserStore

    @State private var isSubmitting = false

    @State private var pendingRole: String? = nil
    @State private var showConfirm: Bool = false

    var body: some View {
        VStack(spacing: 18) {

            VStack(spacing: 8) {
                Text("Set up your account")
                    .font(.largeTitle).bold()

                Text("Choose how you want to use SwipeShift.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            VStack(spacing: 14) {
                Button {
                    pendingRole = "worker"
                    showConfirm = true
                } label: {
                    Text(isSubmitting ? "Saving..." : "I’m looking for work")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                        .cornerRadius(14)
                }
                .disabled(isSubmitting)

                Button {
                    pendingRole = "employer"
                    showConfirm = true
                } label: {
                    Text(isSubmitting ? "Saving..." : "I’m hiring")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                        .cornerRadius(14)
                }
                .disabled(isSubmitting)
            }
            .padding(.horizontal, 24)

            if let err = userStore.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
        .navigationTitle("Onboarding")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Confirm role", isPresented: $showConfirm) {
            Button("Change", role: .cancel) { pendingRole = nil }

            Button("Continue") {
                guard let role = pendingRole else { return }
                Task {
                    isSubmitting = true
                    await userStore.setRole(role: role)
                    isSubmitting = false
                }
            }
        } message: {
            Text("You chose: \(pendingRole == "worker" ? "Worker" : "Employer"). Continue?")
        }
    }
}
