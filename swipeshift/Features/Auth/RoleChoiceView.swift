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
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                DSProgressSteps(steps: ["Role", "Profile"], current: 0)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("How will you use SwipeShift?")
                        .dsFont(.display)
                        .foregroundStyle(DS.Color.text)

                    Text("Choose one to get started")
                        .dsFont(.body)
                        .foregroundStyle(DS.Color.text2)
                }

                VStack(spacing: DS.Spacing.sm) {
                    roleCard(
                        icon: "person",
                        title: "I'm looking for work",
                        subtitle: "Browse jobs, create your profile, and get matched with employers",
                        tone: .primary
                    ) {
                        pendingRole = "worker"
                        showConfirm = true
                    }

                    roleCard(
                        icon: "doc.text",
                        title: "I'm hiring",
                        subtitle: "Post jobs, review candidates, and build your team",
                        tone: .warning
                    ) {
                        pendingRole = "employer"
                        showConfirm = true
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.vertical, DS.Spacing.xxl)
        }
        .dsBackground()
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

    private func roleCard(icon: String, title: String, subtitle: String, tone: DS.Tone, action: @escaping () -> Void) -> some View {
        DSCard(action: {
            guard !isSubmitting else { return }
            action()
        }) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(tone.foreground)
                    .frame(width: 56, height: 56)
                    .background(tone.soft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                    .accessibilityHidden(true)

                Text(title).dsFont(.title).foregroundStyle(DS.Color.text)

                Text(subtitle)
                    .dsFont(.body)
                    .foregroundStyle(DS.Color.text2)
                    .multilineTextAlignment(.leading)
            }
        }
        .disabled(isSubmitting)
        .accessibilityElement(children: .combine)
    }
}
