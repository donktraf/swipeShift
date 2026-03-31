//
//  SavedView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Saved Job (Mock)

private struct SavedJob: Identifiable {
    let id = UUID()
    let title: String
    let company: String
    let logoEmoji: String
    let location: String
    let payText: String
    let date: String
    let savedAt: String
    let appliedStatus: String?  // nil = nicht beworben, "Applied" / "Confirmed"
}

// MARK: - Saved Company (Mock)

private struct SavedCompany: Identifiable {
    let id = UUID()
    let name: String
    let logoEmoji: String
    let category: String
    let location: String
    let openJobs: Int
    let rating: Double
    let isVerified: Bool
}

// MARK: - Saved Tab

private enum SavedTab { case jobs, companies }

// MARK: - SavedView

struct SavedView: View {
    @State private var selectedTab: SavedTab = .jobs

    // TODO: aus Backend laden (GET /users/:id/saved)
    private let savedJobs: [SavedJob] = [
        SavedJob(title: "Barkeeper", company: "Sky Bar", logoEmoji: "🍸",
                 location: "Berlin Mitte", payText: "€18/h",
                 date: "Mar 28", savedAt: "Today",
                 appliedStatus: "Applied"),
        SavedJob(title: "Event Coordinator", company: "EventPro", logoEmoji: "🎪",
                 location: "Charlottenburg", payText: "€20/h",
                 date: "Apr 1", savedAt: "Yesterday",
                 appliedStatus: nil),
        SavedJob(title: "Retail Assistant", company: "StyleStore", logoEmoji: "👗",
                 location: "Prenzlauer Berg", payText: "€13/h",
                 date: "Apr 5", savedAt: "2 days ago",
                 appliedStatus: "Confirmed"),
        SavedJob(title: "Office Support", company: "TechCorp", logoEmoji: "💼",
                 location: "Mitte", payText: "€15/h",
                 date: "Apr 10", savedAt: "3 days ago",
                 appliedStatus: nil),
        SavedJob(title: "Warehouse Worker", company: "LogiHub", logoEmoji: "📦",
                 location: "Wedding", payText: "€14/h",
                 date: "Apr 12", savedAt: "1 week ago",
                 appliedStatus: nil),
    ]

    private let savedCompanies: [SavedCompany] = [
        SavedCompany(name: "Club Tresor", logoEmoji: "🎵", category: "Events & Nightlife",
                     location: "Berlin Mitte", openJobs: 4, rating: 4.8, isVerified: true),
        SavedCompany(name: "Eventify GmbH", logoEmoji: "🎪", category: "Events",
                     location: "Berlin", openJobs: 7, rating: 4.5, isVerified: true),
        SavedCompany(name: "LogiCore", logoEmoji: "📦", category: "Logistics",
                     location: "Wedding", openJobs: 12, rating: 4.2, isVerified: false),
    ]

    var body: some View {
        SubScreenShell(title: "Saved") {
            VStack(spacing: 16) {
                tabSelector
                    .padding(.horizontal, 16)

                if selectedTab == .jobs {
                    savedJobsList
                } else {
                    savedCompaniesList
                }

                if selectedTab == .jobs && savedJobs.isEmpty ||
                   selectedTab == .companies && savedCompanies.isEmpty {
                    emptyState
                }
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach([(SavedTab.jobs, "Jobs"), (SavedTab.companies, "Companies")], id: \.0) { tab, label in
                Button { selectedTab = tab } label: {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? SS.primary : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .systemBackground))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    // MARK: - Saved Jobs

    private var savedJobsList: some View {
        VStack(spacing: 10) {
            // Group by savedAt date label
            let grouped = Dictionary(grouping: savedJobs, by: \.savedAt)
            let keys = ["Today", "Yesterday", "2 days ago", "3 days ago", "1 week ago"]
            ForEach(keys.filter { grouped[$0] != nil }, id: \.self) { key in
                VStack(alignment: .leading, spacing: 8) {
                    Text(key)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 16)

                    ForEach(grouped[key] ?? []) { job in
                        SavedJobCard(job: job)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Saved Companies

    private var savedCompaniesList: some View {
        VStack(spacing: 10) {
            ForEach(savedCompanies) { company in
                SavedCompanyCard(company: company)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            Text("You haven't saved anything yet.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("Start exploring jobs and companies and save the ones you like.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                // TODO: → JobListView
            } label: {
                Text("Jobs durchsuchen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SS.primary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Saved Job Card

private struct SavedJobCard: View {
    let job: SavedJob
    @State private var isSaved = true

    var body: some View {
        HStack(spacing: 12) {
            Text(job.logoEmoji)
                .font(.system(size: 26))
                .frame(width: 48, height: 48)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(job.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    if let status = job.appliedStatus {
                        Text(status)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(status == "Confirmed" ? Color.green : SS.primary)
                            .clipShape(Capsule())
                    }
                }
                Text(job.company)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Label(job.date, systemImage: "calendar")
                    Label(job.payText, systemImage: "eurosign.circle")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                isSaved.toggle()
                // TODO: DELETE /users/:id/saved/:jobId
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundColor(isSaved ? SS.primary : .gray.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Saved Company Card

private struct SavedCompanyCard: View {
    let company: SavedCompany

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(company.logoEmoji)
                    .font(.system(size: 32))
                    .frame(width: 56, height: 56)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(company.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        if company.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundColor(SS.primary)
                        }
                    }
                    Text(company.category)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", company.rating))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("\(company.openJobs) offene Jobs")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            Button {
                // TODO: → CompanyProfileView / gefilterte Job-Liste
            } label: {
                Text("Offene Jobs ansehen")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SS.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SS.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
