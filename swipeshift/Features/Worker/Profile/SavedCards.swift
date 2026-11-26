//
//  SavedCards.swift
//  swipeShift
//
//  Karten fuer SavedView: gespeicherte Firmen (Standort, Branche, Kurzbeschreibung,
//  "View open jobs" / "View profile") und gespeicherte Jobs (Tags, Entfernung,
//  "Company" / "Apply").
//

import SwiftUI

// MARK: - Saved Company Card

struct SavedCompanyCard: View {
    let company:  SavedCompanyItem
    let onUnsave: () -> Void

    private var subtitle: String? {
        let parts = [company.industry, company.location]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    DSAvatar(text: company.logoEmoji, size: 48, shape: .roundedSquare)
                        .overlay(alignment: .bottomTrailing) {
                            if company.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14)).foregroundStyle(DS.Color.primary)
                                    .background(DS.Color.surface, in: Circle())
                                    .offset(x: 4, y: 4)
                                    .accessibilityLabel("Verified")
                            }
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(company.companyName)
                            .dsFont(.callout).foregroundStyle(DS.Color.text)

                        if let subtitle {
                            Text(subtitle)
                                .dsFont(.caption).foregroundStyle(DS.Color.muted).lineLimit(1)
                        }

                        HStack(spacing: DS.Spacing.xs) {
                            if let rating = company.rating {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10)).foregroundStyle(DS.Color.warning)
                                    Text(String(format: "%.1f", rating))
                                        .dsFont(.caption).foregroundStyle(DS.Color.text2)
                                }
                            }
                            Text("\(company.openJobs) open job\(company.openJobs == 1 ? "" : "s")")
                                .dsFont(.caption).foregroundStyle(DS.Color.muted)
                        }

                        if let activity = company.lastActivity {
                            Label(activity.label, systemImage: activity.kind == "worked" ? "checkmark.circle" : "clock")
                                .dsFont(.caption).foregroundStyle(DS.Color.muted)
                        }
                    }

                    Spacer(minLength: DS.Spacing.xs)

                    Button {
                        DS.Haptics.light()
                        Task {
                            try? await APIClient.shared.unsaveCompany(name: company.companyName)
                            onUnsave()
                        }
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 18)).foregroundStyle(DS.Color.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityLabel("Remove from saved")
                }

                if let about = company.about, !about.isEmpty {
                    Text(about)
                        .dsFont(.caption).foregroundStyle(DS.Color.text2)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: DS.Spacing.xs) {
                    NavigationLink {
                        JobListView(companyFilter: company.companyName)
                    } label: {
                        Label("View open jobs", systemImage: "briefcase.fill")
                    }
                    .buttonStyle(.ds(.secondary, size: .medium))
                    NavigationLink {
                        CompanyProfileView(companyName: company.companyName, logoEmoji: company.logoEmoji)
                    } label: {
                        Label("View profile", systemImage: "building.2")
                    }
                    .buttonStyle(.ds(.secondary, size: .medium))
                }
            }
        }
    }
}

// MARK: - Saved Job Card

struct SavedJobCard: View {
    let job:      WorkerSavedJob
    let onUnsave: () -> Void
    let onApply:  () -> Void
    /// "Not interested": entfernt Save + blendet den Job aus den Feeds aus (SavedView zeigt Undo)
    let onNotInterested: () -> Void

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    DSAvatar(text: job.logoEmoji, size: 48, shape: .roundedSquare)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.title)
                            .dsFont(.callout).foregroundStyle(DS.Color.text)
                        if let status = job.appliedStatus {
                            DSBadge(status, status == "Confirmed" ? .upcoming : .tone(.primary))
                        }
                        Text(job.company).dsFont(.caption).foregroundStyle(DS.Color.text2)
                        HStack(spacing: DS.Spacing.xs) {
                            Label(job.shiftText, systemImage: "calendar")
                            Label(job.payText,   systemImage: "dollarsign.circle")
                        }
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                        if let miles = job.distanceMiles {
                            Label(String(format: "%.1f mi away", miles), systemImage: "location")
                                .dsFont(.caption).foregroundStyle(DS.Color.muted)
                        }
                    }

                    Spacer(minLength: DS.Spacing.xs)

                    VStack(spacing: 0) {
                        Button {
                            DS.Haptics.light()
                            Task {
                                try? await APIClient.shared.unsaveJob(jobId: job.jobId)
                                onUnsave()
                            }
                        } label: {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 18)).foregroundStyle(DS.Color.primary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.dsPressable)
                        .accessibilityLabel("Remove from saved")

                        Menu {
                            Button(role: .destructive, action: onNotInterested) {
                                Label("Not interested", systemImage: "hand.thumbsdown")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.Color.muted)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("More options")
                    }
                }

                // Max. 3 Tags
                if let tags = job.tags, !tags.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(DS.Font.make(11, .medium, relativeTo: .caption2))
                                .foregroundStyle(DS.Color.primaryText)
                                .padding(.horizontal, DS.Spacing.xs).padding(.vertical, 3)
                                .background(DS.Color.primarySoft, in: Capsule())
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: DS.Spacing.xs) {
                    NavigationLink {
                        CompanyProfileView(companyName: job.company, logoEmoji: job.logoEmoji)
                    } label: {
                        Label("Company", systemImage: "building.2")
                    }
                    .buttonStyle(.ds(.secondary, size: .medium))
                    // Nur wenn noch nicht beworben und der Job offen ist (Backend: canApply)
                    if job.canApply == true {
                        Button(action: onApply) {
                            Label("Apply", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.ds(.primary, size: .medium))
                    }
                }
            }
        }
    }
}
