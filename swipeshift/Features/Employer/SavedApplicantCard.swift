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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ApplicantAvatar(photoUrl: item.workerPhoto)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.workerName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        if summary?.isAdult == true { AdultBadge() }
                    }
                    if let city = item.workerCity, !city.isEmpty {
                        Label(city, systemImage: "mappin")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    if let summary {
                        HStack(spacing: 8) {
                            ApplicantRatingLabel(average: summary.ratingAverage, count: summary.reviewCount)
                            Text(ApplicantFormat.jobsText(summary.completedJobs))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Button {
                    Task { await onUnsave() }
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 18))
                        .foregroundColor(SS.primary)
                }
                .buttonStyle(.plain)
            }

            if let strongest = summary?.strongestExperience {
                ApplicantTagRow(tags: [strongest])
            }

            if let bio = item.bioShort {
                Text(bio)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("\(item.logoEmoji) \(item.jobTitle) at \(item.company)")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.8))
                .lineLimit(1)

            NavigationLink {
                DetailedWorkerView(
                    applicant: item.asApplicant,
                    onAccept: {}, onDecline: {},
                    showActions: false,
                    chatConversationId: item.applyStatus == "accepted" ? item.conversationId : nil
                )
            } label: {
                Text("View profile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SS.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(SS.primary.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
