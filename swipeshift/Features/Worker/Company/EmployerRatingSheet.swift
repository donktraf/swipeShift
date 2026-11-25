//
//  EmployerRatingSheet.swift
//  swipeShift
//

import SwiftUI

struct EmployerRatingSheet: View {
    let applyId:     String
    let companyName: String
    let jobTitle:    String
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var communication:          Int = 0
    @State private var paymentFairness:        Int = 0
    @State private var workEnvironment:        Int = 0
    @State private var jobDescriptionAccuracy: Int = 0
    @State private var overallExperience:      Int = 0
    @State private var wouldWorkAgain:         Bool? = nil
    @State private var publishConsent          = false
    @State private var comment                 = ""
    @State private var isSubmitting            = false
    @State private var errorMessage:           String? = nil

    private var isValid: Bool {
        communication > 0 && paymentFairness > 0 &&
        workEnvironment > 0 && jobDescriptionAccuracy > 0 && overallExperience > 0 &&
        wouldWorkAgain != nil && publishConsent
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    // Header
                    HStack(spacing: DS.Spacing.sm) {
                        DSAvatar(text: DSAvatar.initials(from: companyName), size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(companyName)
                                .dsFont(.headline)
                                .foregroundStyle(DS.Color.text)
                            Text(jobTitle)
                                .dsFont(.caption)
                                .foregroundStyle(DS.Color.muted)
                        }
                        Spacer(minLength: 0)
                    }

                    // Rating categories (flach)
                    DSSection("Your rating") {
                        ratingRow("Communication", value: $communication,
                                  desc: "Did they respond clearly and on time?", showsDivider: false)
                        ratingRow("Payment Fairness", value: $paymentFairness,
                                  desc: "Was the pay fair and on time?")
                        ratingRow("Work Environment", value: $workEnvironment,
                                  desc: "How was the atmosphere on site?")
                        ratingRow("Job Description Accuracy", value: $jobDescriptionAccuracy,
                                  desc: "Did the job match what was posted?")
                        ratingRow("Overall Experience", value: $overallExperience,
                                  desc: "How would you rate this employer overall?")
                    }

                    // Would work again
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("Would you work for this company again?")
                            .dsFont(.headline)
                            .foregroundStyle(DS.Color.text)
                        HStack(spacing: DS.Spacing.xs) {
                            workAgainButton("Yes", icon: "hand.thumbsup.fill", value: true)
                            workAgainButton("No", icon: "hand.thumbsdown.fill", value: false)
                        }
                    }

                    // Comment
                    DSTextEditor(
                        "Comment (optional)",
                        placeholder: "Share your experience…",
                        text: $comment,
                        minLines: 3, maxLines: 6, maxLength: 400
                    )

                    // Zustimmung zur Veroeffentlichung (Pflicht)
                    Button {
                        DS.Haptics.selection()
                        publishConsent.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: DS.Spacing.sm) {
                            Image(systemName: publishConsent ? "checkmark.square.fill" : "square")
                                .font(DS.Font.make(22, .regular, relativeTo: .title3))
                                .foregroundStyle(publishConsent ? DS.Color.primary : DS.Color.muted)
                            Text("I confirm this rating is honest and based on my own experience. It will be shown on the company profile.")
                                .dsFont(.callout)
                                .foregroundStyle(DS.Color.text)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityAddTraits(publishConsent ? .isSelected : [])

                    // Submit
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(DS.Color.onPrimary)
                        } else {
                            Text("Submit Review")
                        }
                    }
                    .buttonStyle(.ds(.primary))
                    .disabled(!isValid || isSubmitting)
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.top, DS.Spacing.xs)
                .padding(.bottom, DS.Spacing.xl)
            }
            .dsBackground()
            .navigationTitle("Rate Employer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(DS.Color.primary)
                }
            }
        }
        .alert("Could not submit review", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func workAgainButton(_ title: String, icon: String, value: Bool) -> some View {
        let selected = wouldWorkAgain == value
        return Button { wouldWorkAgain = value } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.ds(selected ? .primary : .secondary, size: .medium))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Rating Row

    private func ratingRow(_ label: String, value: Binding<Int>, desc: String, showsDivider: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(label)
                .dsFont(.body)
                .fontWeight(.semibold)
                .foregroundStyle(DS.Color.text)
            Text(desc)
                .dsFont(.caption)
                .foregroundStyle(DS.Color.muted)
            HStack(spacing: DS.Spacing.xxs) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        if value.wrappedValue != i { DS.Haptics.selection() }
                        value.wrappedValue = i
                    } label: {
                        Image(systemName: i <= value.wrappedValue ? "star.fill" : "star")
                            .font(DS.Font.make(26, .regular, relativeTo: .title2))
                            .foregroundStyle(i <= value.wrappedValue ? DS.Color.warning : DS.Color.border)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                    .accessibilityAddTraits(i == value.wrappedValue ? .isSelected : [])
                }
                Spacer(minLength: 0)
                if value.wrappedValue > 0 {
                    Text(ratingLabel(value.wrappedValue))
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.text2)
                }
            }
            .dsAnimation(.snappy, value: value.wrappedValue)
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if showsDivider { DSDivider() }
        }
    }

    private func ratingLabel(_ v: Int) -> String {
        switch v {
        case 1: return "Poor"
        case 2: return "Fair"
        case 3: return "Good"
        case 4: return "Great"
        case 5: return "Excellent"
        default: return ""
        }
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await APIClient.shared.submitEmployerReview(
                .init(
                    applyId:                applyId,
                    communication:          communication,
                    paymentFairness:        paymentFairness,
                    workEnvironment:        workEnvironment,
                    jobDescriptionAccuracy: jobDescriptionAccuracy,
                    overallExperience:      overallExperience,
                    wouldWorkAgain:         wouldWorkAgain ?? false,
                    publishConsent:         publishConsent,
                    comment:               comment.isEmpty ? nil : comment
                )
            )
            DS.Haptics.success()
            onSubmitted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
