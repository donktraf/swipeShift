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
        ZStack {
            SS.background().ignoresSafeArea()

            VStack {
                Spacer()

                SSCard {
                    VStack(spacing: 18) {
                        Text("How will you use SwipeShift?")
                            .font(.system(size: 30, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text("Choose one to get started")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)

                        VStack(spacing: 14) {
                            roleCard(
                                icon: "person",
                                title: "I'm looking for work",
                                subtitle: "Browse jobs, create your profile, and get matched with employers",
                                tint: SS.primary.opacity(0.18)
                            ) {
                                pendingRole = "worker"
                                showConfirm = true
                            }

                            roleCard(
                                icon: "doc.text",
                                title: "I'm hiring",
                                subtitle: "Post jobs, review candidates, and build your team",
                                tint: Color.purple.opacity(0.16)
                            ) {
                                pendingRole = "employer"
                                showConfirm = true
                            }
                        }
                    }
                }

                Spacer()
            }
        }
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

    private func roleCard(icon: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            guard !isSubmitting else { return }
            action()
        } label: {
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint)
                    .frame(width: 76, height: 76)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(SS.primary)
                    )

                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.white.opacity(0.70))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }
}
