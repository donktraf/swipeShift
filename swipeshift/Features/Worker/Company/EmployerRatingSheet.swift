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
    @State private var comment                 = ""
    @State private var isSubmitting            = false
    @State private var errorMessage:           String? = nil

    private var isValid: Bool {
        communication > 0 && paymentFairness > 0 &&
        workEnvironment > 0 && jobDescriptionAccuracy > 0 && overallExperience > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 6) {
                        Text(companyName)
                            .font(.system(size: 18, weight: .bold))
                        Text(jobTitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    // Rating categories
                    VStack(spacing: 0) {
                        ratingRow("Communication", value: $communication,
                                  desc: "Did they respond clearly and on time?")
                        Divider().padding(.leading, 16)
                        ratingRow("Payment Fairness", value: $paymentFairness,
                                  desc: "Was the pay fair and on time?")
                        Divider().padding(.leading, 16)
                        ratingRow("Work Environment", value: $workEnvironment,
                                  desc: "How was the atmosphere on site?")
                        Divider().padding(.leading, 16)
                        ratingRow("Job Description Accuracy", value: $jobDescriptionAccuracy,
                                  desc: "Did the job match what was posted?")
                        Divider().padding(.leading, 16)
                        ratingRow("Overall Experience", value: $overallExperience,
                                  desc: "How would you rate this employer overall?")
                    }
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                    .padding(.horizontal, 16)

                    // Comment
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Comment (optional)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)

                        ZStack(alignment: .topLeading) {
                            if comment.isEmpty {
                                Text("Share your experience…")
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .font(.system(size: 14))
                                    .padding(.horizontal, 14)
                                    .padding(.top, 12)
                            }
                            TextEditor(text: $comment)
                                .font(.system(size: 14))
                                .frame(minHeight: 90, maxHeight: 160)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .scrollContentBackground(.hidden)
                        }
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15)))
                        .padding(.horizontal, 16)

                        HStack {
                            Spacer()
                            Text("\(comment.count)/400")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                        }
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Submit
                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Submit Review")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(isValid ? SS.primary : Color.secondary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid || isSubmitting)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Rate Employer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: comment) { _, new in
            if new.count > 400 { comment = String(new.prefix(400)) }
        }
    }

    // MARK: - Rating Row

    private func ratingRow(_ label: String, value: Binding<Int>, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Button { value.wrappedValue = i } label: {
                        Image(systemName: i <= value.wrappedValue ? "star.fill" : "star")
                            .font(.system(size: 26))
                            .foregroundColor(i <= value.wrappedValue ? .yellow : Color.secondary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if value.wrappedValue > 0 {
                    Text(ratingLabel(value.wrappedValue))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
                    comment:               comment.isEmpty ? nil : comment
                )
            )
            onSubmitted()
            dismiss()
        } catch {
            errorMessage = "Could not submit review. Please try again."
        }
        isSubmitting = false
    }
}
