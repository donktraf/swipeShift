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

    /// Nur fuer noch offene Bewerbungen sinnvoll
    private var shiftFit: ApplicantShiftFit? {
        guard !isDecided else { return nil }
        return ApplicantShiftFit.evaluate(
            hasConflict: applicant.hasScheduleConflict == true,
            availableDays: summary?.availableDays ?? [],
            availableTimes: summary?.availableTimes ?? [],
            start: applicant.job?.startTime
        )
    }

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                workerInfo
                if let summary { summaryBlock(summary) }

                if let job = applicant.job {
                    DSDivider()
                    jobInfo(job)
                }

                if !isDecided { decisionButtons }
                if let onChat {
                    ApplicantChatButton(action: onChat)
                }
            }
        }
        .opacity(localState == .declined ? 0.65 : 1)
        .dsAnimation(.standard, value: isDecided)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Teile

    private var workerInfo: some View {
        HStack(spacing: DS.Spacing.sm) {
            ApplicantAvatar(photoUrl: applicant.user?.profilePhotoUrl)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(applicant.user?.fullName ?? "Unknown")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(1)
                    if summary?.isAdult == true { AdultBadge() }
                    Spacer(minLength: 0)
                    if applicant.autoAccepted == true { InstantMatchPill() }
                    stateBadge
                    if let onSave {
                        Button {
                            DS.Haptics.light()
                            onSave()
                        } label: {
                            Image(systemName: "bookmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DS.Color.primaryText)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.dsPressable)
                        .accessibilityLabel("Save applicant")
                    }
                }
                if let location = applicant.user?.location {
                    Label(location, systemImage: "mappin")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                }
            }
        }
    }

    private func summaryBlock(_ summary: ApplicantSummary) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                ApplicantRatingLabel(average: summary.ratingAverage, count: summary.reviewCount)
                Text(ApplicantFormat.jobsText(summary.completedJobs))
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.text2)
                Spacer(minLength: 0)
                if let appliedAt = applicant.appliedAt {
                    Text(ApplicantFormat.appliedAgo(appliedAt))
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                }
            }
            if let reliability = summary.reliability { ReliabilityLabel(summary: reliability) }
            ApplicantTagRow(tags: summary.tags)
            if let fit = shiftFit { ApplicantShiftFitLabel(fit: fit) }
            if let availability = summary.availabilityText {
                Label(availability, systemImage: "clock")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.text2)
            }
        }
    }

    private func jobInfo(_ job: ApplicantJob) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSAvatar(text: job.logoEmoji, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                    .foregroundStyle(DS.Color.text)
                HStack(spacing: DS.Spacing.xs) {
                    Label(applicant.bookedShifts?.cardLabel ?? job.shiftText, systemImage: "calendar")
                    Label(job.payText, systemImage: "banknote")
                }
                .dsFont(.caption)
                .foregroundStyle(DS.Color.text2)
            }
        }
    }

    private var decisionButtons: some View {
        HStack(spacing: DS.Spacing.xs) {
            Button(action: onDecline) {
                Label("Decline", systemImage: "xmark")
            }
            .buttonStyle(.ds(.destructiveSoft, size: .medium))

            Button(action: onAccept) {
                Label("Accept", systemImage: "checkmark")
            }
            .buttonStyle(.ds(.primary, size: .medium))
        }
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch localState {
        case .accepted: DSBadge("Accepted", .tone(.success))
        case .declined: DSBadge("Declined", .cancelled)
        case nil:       DSBadge("Pending", .tone(.primary))
        }
    }
}

/// Kleine Markierung fuer automatisch angenommene Bewerber/Worker (Instant Match)
struct InstantMatchPill: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
            Text("Instant Match").font(DS.Font.make(11, .bold, relativeTo: .caption))
        }
        .foregroundStyle(DS.Color.primaryText)
        .padding(.horizontal, DS.Spacing.xs).padding(.vertical, 3)
        .background(DS.Color.primarySoft, in: Capsule())
    }
}
