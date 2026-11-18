//
//  ApplicantCard.swift
//  swipeShift
//
//  Bewerberkarte der Bewerber-Liste (aus AllApplicantsView ausgelagert).
//

import SwiftUI

struct ApplicantCard: View {
    let applicant:  Applicant
    let localState: AllApplicantsView.ApplicantLocalState?
    let onAccept:   () -> Void
    let onDecline:  () -> Void
    var onSave:     (() -> Void)? = nil
    /// nur gesetzt, wenn angenommen und eine Conversation existiert
    var onChat:     (() -> Void)? = nil

    private var isDecided: Bool { localState != nil }
    private var summary: ApplicantSummary? { applicant.summary }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            workerInfo
            if let summary { summaryBlock(summary) }

            Divider().padding(.horizontal, 14)

            if let job = applicant.job { jobInfo(job) }

            if !isDecided { decisionButtons }
            if let onChat {
                ApplicantChatButton(action: onChat)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(isDecided ? 0.03 : 0.05), radius: 5, x: 0, y: 2)
        .opacity(localState == .declined ? 0.65 : 1)
        .animation(.easeInOut(duration: 0.25), value: isDecided)
    }

    // MARK: - Teile

    private var workerInfo: some View {
        HStack(spacing: 12) {
            ApplicantAvatar(photoUrl: applicant.user?.profilePhotoUrl)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(applicant.user?.fullName ?? "Unknown")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    if summary?.isAdult == true { AdultBadge() }
                    Spacer()
                    if applicant.autoAccepted == true { InstantMatchPill() }
                    stateBadge
                    if let onSave {
                        Button(action: onSave) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 16))
                                .foregroundColor(SS.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let location = applicant.user?.location {
                    Label(location, systemImage: "mappin")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
    }

    private func summaryBlock(_ summary: ApplicantSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ApplicantRatingLabel(average: summary.ratingAverage, count: summary.reviewCount)
                Text(ApplicantFormat.jobsText(summary.completedJobs))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                if let appliedAt = applicant.appliedAt {
                    Text(ApplicantFormat.appliedAgo(appliedAt))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            ApplicantTagRow(tags: summary.tags)
            if let availability = summary.availabilityText {
                Label(availability, systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func jobInfo(_ job: ApplicantJob) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(job.logoEmoji)
                    .font(.system(size: 20))
                    .frame(width: 36, height: 36)
                    .background(Color.gray.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    HStack(spacing: 8) {
                        Label(job.shiftText, systemImage: "calendar")
                        Label(job.payText,   systemImage: "banknote")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 14)
        }
    }

    private var decisionButtons: some View {
        HStack(spacing: 8) {
            Button(action: onDecline) {
                Label("Decline", systemImage: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button(action: onAccept) {
                Label("Accept", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SS.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch localState {
        case .accepted:
            badge("Accepted", fg: .white, bg: .green)
        case .declined:
            badge("Declined", fg: .white, bg: .red)
        case nil:
            badge("Pending", fg: SS.primary, bg: SS.primary.opacity(0.1))
        }
    }

    private func badge(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }
}

/// Kleine Markierung fuer automatisch angenommene Bewerber/Worker (Instant Match)
struct InstantMatchPill: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
            Text("Instant Match").font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(SS.primary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(SS.primary.opacity(0.12))
        .clipShape(Capsule())
    }
}
