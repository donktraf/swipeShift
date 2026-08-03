//
//  SavedView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Saved Tab

private enum SavedTab { case jobs, companies }

// MARK: - SavedView

struct SavedView: View {
    @State private var selectedTab:     SavedTab = .jobs
    @State private var savedJobs:       [WorkerSavedJob]    = []
    @State private var savedCompanies:  [SavedCompanyItem]  = []
    @State private var isLoading        = false
    @State private var errorMessage:    String? = nil

    var body: some View {
        SubScreenShell(title: "Saved") {
            VStack(spacing: 16) {
                tabSelector.padding(.horizontal, 16)

                if selectedTab == .jobs {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else if let err = errorMessage {
                        VStack(spacing: 12) {
                            Text(err).font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center).padding(.horizontal, 24)
                            Button("Retry") { Task { await load() } }
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(SS.primary)
                        }.padding(.top, 60)
                    } else if savedJobs.isEmpty {
                        emptyState
                    } else {
                        savedJobsList
                    }
                } else {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else if savedCompanies.isEmpty {
                        emptyState
                    } else {
                        savedCompaniesList
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: selectedTab) { _, _ in Task { await load() } }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach([(SavedTab.jobs, "Jobs"), (SavedTab.companies, "Companies")], id: \.0) { tab, label in
                Button { selectedTab = tab } label: {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? .white : .secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
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

    // MARK: - Saved Jobs List (nach Datum gruppiert)

    private var savedJobsList: some View {
        let grouped = Dictionary(grouping: savedJobs) { dateLabel($0.savedAt) }
        let keys    = grouped.keys.sorted { a, b in
            let dateA = savedJobs.first { dateLabel($0.savedAt) == a }?.savedAt ?? .distantPast
            let dateB = savedJobs.first { dateLabel($0.savedAt) == b }?.savedAt ?? .distantPast
            return dateA > dateB
        }
        return VStack(spacing: 10) {
            ForEach(keys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 8) {
                    Text(key)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 16)
                    ForEach(grouped[key] ?? []) { job in
                        SavedJobCard(job: job) {
                            withAnimation { savedJobs.removeAll { $0.id == job.id } }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 40)).foregroundColor(.white.opacity(0.3))
            Text("You haven't saved anything yet.")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.6))
            Text("Start exploring jobs and companies and save the ones you like.")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center).padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }

    // MARK: - Saved Companies List

    private var savedCompaniesList: some View {
        VStack(spacing: 10) {
            ForEach(savedCompanies) { company in
                SavedCompanyCard(company: company) {
                    withAnimation { savedCompanies.removeAll { $0.id == company.id } }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Helpers

    private func load() async {
        isLoading = true; errorMessage = nil
        do {
            if selectedTab == .jobs {
                savedJobs = try await APIClient.shared.fetchWorkerSaved()
            } else {
                savedCompanies = try await APIClient.shared.fetchSavedCompanies()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func dateLabel(_ date: Date) -> String {
        let cal  = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        switch days {
        case 0:  return "Today"
        case 1:  return "Yesterday"
        case 2...6: return "\(days) days ago"
        default: return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

// MARK: - Saved Company Card

private struct SavedCompanyCard: View {
    let company:  SavedCompanyItem
    let onUnsave: () -> Void

    var body: some View {
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
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Saved Job Card

private struct SavedJobCard: View {
    let job:        WorkerSavedJob
    let onUnsave:   () -> Void

    var body: some View {
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
                    Label(job.payText,   systemImage: "eurosign.circle")
                }
                .font(.system(size: 11)).foregroundColor(.secondary)
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
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
