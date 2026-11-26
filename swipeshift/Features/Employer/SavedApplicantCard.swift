//
//  SavedApplicantCard.swift
//  swipeShift
//
//  Karte in "Saved Applicants": Foto, Stadt, Bewertung, Jobs, Erfahrungs-Badge, Kurz-Bio,
//  "View profile" → DetailedWorkerView (ohne Accept/Decline).
//

import SwiftUI

struct SavedApplicantCard: View {
    let item: SavedApplicantItem
    let onUnsave: () async -> Void

    private var summary: ApplicantSummary? { item.summary }

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    ApplicantAvatar(photoUrl: item.workerPhoto)

                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        HStack(spacing: DS.Spacing.xs) {
                            Text(item.workerName)
                                .dsFont(.headline)
                                .foregroundStyle(DS.Color.text)
                            if summary?.isAdult == true { AdultBadge() }
                        }
                        if let city = item.workerCity, !city.isEmpty {
                            Label(city, systemImage: "mappin")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Color.muted)
                        }
                        if let summary {
                            HStack(spacing: DS.Spacing.xs) {
                                ApplicantRatingLabel(average: summary.ratingAverage, count: summary.reviewCount)
                                Text(ApplicantFormat.jobsText(summary.completedJobs))
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Color.text2)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        DS.Haptics.light()
                        Task { await onUnsave() }
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DS.Color.primaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityLabel("Remove from saved applicants")
                }

                if let strongest = summary?.strongestExperience {
                    ApplicantTagRow(tags: [strongest])
                }

                if let bio = item.bioShort {
                    Text(bio)
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("\(item.logoEmoji) \(item.jobTitle) at \(item.company)")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.muted)
                    .lineLimit(1)

                NavigationLink {
                    DetailedWorkerView(
                        applicant: item.asApplicant,
                        onAccept: {}, onDecline: {},
                        jobId: item.jobId,
                        showActions: false,
                        chatConversationId: item.applyStatus == "accepted" ? item.conversationId : nil
                    )
                } label: {
                    Text("View profile")
                }
                .buttonStyle(.ds(.soft, size: .medium))
            }
        }
    }
}
