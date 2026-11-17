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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Text(company.logoEmoji)
                        .font(.system(size: 26)).frame(width: 48, height: 48)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if company.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12)).foregroundColor(SS.primary)
                            .background(Color.white.clipShape(Circle()))
                            .offset(x: 3, y: 3)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(company.companyName)
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        if let rating = company.rating {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10)).foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                            }
                        }
                        Text("\(company.openJobs) open job\(company.openJobs == 1 ? "" : "s")")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    Task {
                        try? await APIClient.shared.unsaveCompany(name: company.companyName)
                        onUnsave()
                    }
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 18)).foregroundColor(SS.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            if let about = company.about, !about.isEmpty {
                Text(about)
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }

            Divider().padding(.horizontal, 12)
            HStack(spacing: 0) {
                NavigationLink {
                    JobListView(companyFilter: company.companyName)
                } label: {
                    SavedCardActionLabel(title: "View open jobs", icon: "briefcase.fill")
                }
                .buttonStyle(.plain)
                Divider().frame(height: 20)
                NavigationLink {
                    CompanyProfileView(companyName: company.companyName, logoEmoji: company.logoEmoji)
                } label: {
                    SavedCardActionLabel(title: "View profile", icon: "building.2")
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Saved Job Card

struct SavedJobCard: View {
    let job:      WorkerSavedJob
    let onUnsave: () -> Void
    let onApply:  () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(job.logoEmoji)
                    .font(.system(size: 26)).frame(width: 48, height: 48)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(job.title)
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                        if let status = job.appliedStatus {
                            Text(status)
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(status == "Confirmed" ? Color.green : SS.primary)
                                .clipShape(Capsule())
                        }
                    }
                    Text(job.company).font(.system(size: 12)).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Label(job.shiftText, systemImage: "calendar")
                        Label(job.payText,   systemImage: "dollarsign.circle")
                    }
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    if let miles = job.distanceMiles {
                        Label(String(format: "%.1f mi away", miles), systemImage: "location")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    Task {
                        try? await APIClient.shared.unsaveJob(jobId: job.jobId)
                        onUnsave()
                    }
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 18)).foregroundColor(SS.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            // Max. 3 Tags
            if let tags = job.tags, !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .medium)).foregroundColor(SS.primary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(SS.primary.opacity(0.1))
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }

            Divider().padding(.horizontal, 12)
            HStack(spacing: 0) {
                NavigationLink {
                    CompanyProfileView(companyName: job.company, logoEmoji: job.logoEmoji)
                } label: {
                    SavedCardActionLabel(title: "Company", icon: "building.2")
                }
                .buttonStyle(.plain)
                // Nur wenn noch nicht beworben und der Job offen ist (Backend: canApply)
                if job.canApply == true {
                    Divider().frame(height: 20)
                    Button(action: onApply) {
                        SavedCardActionLabel(title: "Apply", icon: "paperplane.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

private struct SavedCardActionLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .semibold)).foregroundColor(SS.primary)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .contentShape(Rectangle())
    }
}
