//
//  AllPostedJobsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - EmployerJob Model

struct EmployerJob: Identifiable, Decodable {
    let id: String
    let title: String
    let company: String
    let location: String
    let category: String?
    let status: String
    let openSpots: Int
    let payText: String
    let shiftText: String
    let logoEmoji: String
    let applicantCount: Int
    let createdAt: String

    var statusEnum: JobStatus {
        switch status {
        case "published":  return .active
        case "inProgress": return .inProgress
        case "draft":      return .draft
        case "completed":  return .completed
        case "cancelled":  return .cancelled
        default:           return .active
        }
    }

    enum JobStatus {
        case active, inProgress, draft, completed, cancelled

        var label: String {
            switch self {
            case .active:     return "Published"
            case .inProgress: return "In Progress"
            case .draft:      return "Draft"
            case .completed:  return "Completed"
            case .cancelled:  return "Cancelled"
            }
        }

        var color: Color {
            switch self {
            case .active:     return SS.primary
            case .inProgress: return .orange
            case .draft:      return .gray
            case .completed:  return .green
            case .cancelled:  return .red
            }
        }
    }
}

// MARK: - AllPostedJobsView

struct AllPostedJobsView: View {
    @State private var jobs: [EmployerJob] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTab: PostedJobTab = .active

    // Aktions-Alerts
    @State private var jobToCancel: EmployerJob? = nil
    @State private var jobToPublish: EmployerJob? = nil

    enum PostedJobTab: String, CaseIterable {
        case active    = "Active"
        case draft     = "Draft"
        case completed = "Completed"
        case past      = "Past"
    }

    private var filtered: [EmployerJob] {
        switch selectedTab {
        case .active:
            return jobs.filter { $0.status == "published" || $0.status == "inProgress" }
        case .draft:
            return jobs.filter { $0.status == "draft" }
        case .completed:
            return jobs.filter { $0.status == "completed" }
        case .past:
            return jobs.filter { $0.status == "cancelled" }
        }
    }

    var body: some View {
        SubScreenShell(title: "Posted Jobs") {
            VStack(spacing: 16) {
                tabBar
                    .padding(.horizontal, 16)

                if isLoading {
                    ProgressView()
                        .foregroundColor(.white)
                        .padding(.top, 60)

                } else if let err = errorMessage {
                    errorView(err)

                } else if filtered.isEmpty {
                    emptyView

                } else {
                    VStack(spacing: 10) {
                        ForEach(filtered) { job in
                            PostedJobCard(
                                job: job,
                                onCancel:  { jobToCancel  = job },
                                onPublish: { jobToPublish = job }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .task { await load() }
        // Cancel confirmation
        .alert("Cancel job?", isPresented: Binding(
            get: { jobToCancel != nil },
            set: { if !$0 { jobToCancel = nil } }
        )) {
            Button("Cancel Job", role: .destructive) {
                if let job = jobToCancel { Task { await updateStatus(job, to: "cancelled") } }
            }
            Button("Dismiss", role: .cancel) { jobToCancel = nil }
        } message: {
            Text("The job will be cancelled. Applicants will no longer be shown.")
        }
        // Publish confirmation
        .alert("Publish job?", isPresented: Binding(
            get: { jobToPublish != nil },
            set: { if !$0 { jobToPublish = nil } }
        )) {
            Button("Publish") {
                if let job = jobToPublish { Task { await updateStatus(job, to: "published") } }
            }
            Button("Cancel", role: .cancel) { jobToPublish = nil }
        } message: {
            Text("The job will be published immediately and visible to workers.")
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PostedJobTab.allCases, id: \.self) { tab in
                    let count = countFor(tab)
                    Button { selectedTab = tab } label: {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(selectedTab == tab ? Color.white.opacity(0.3) : SS.primary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundColor(selectedTab == tab ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? SS.primary : Color(uiColor: .systemBackground))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: selectedTab)
                }
            }
        }
    }

    // MARK: - Empty / Error

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "briefcase.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.3))
            Text("No jobs in this category")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange.opacity(0.7))
            Text(msg)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await load() } }
                .buttonStyle(SSPrimaryButtonStyle())
                .padding(.horizontal, 60)
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    private func countFor(_ tab: PostedJobTab) -> Int {
        switch tab {
        case .active:    return jobs.filter { $0.status == "published" || $0.status == "inProgress" }.count
        case .draft:     return jobs.filter { $0.status == "draft" }.count
        case .completed: return jobs.filter { $0.status == "completed" }.count
        case .past:      return jobs.filter { $0.status == "cancelled" }.count
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            jobs = try await APIClient.shared.fetchMyJobs()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func updateStatus(_ job: EmployerJob, to status: String) async {
        do {
            try await APIClient.shared.updateJobStatus(jobId: job.id, status: status)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - PostedJobCard

private struct PostedJobCard: View {
    let job: EmployerJob
    let onCancel:  () -> Void
    let onPublish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(job.logoEmoji)
                    .font(.system(size: 26))
                    .frame(width: 46, height: 46)
                    .background(Color.gray.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(job.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        // Status Badge
                        Text(job.statusEnum.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(job.statusEnum.color)
                            .clipShape(Capsule())
                    }
                    Text(job.location)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text(job.shiftText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(14)

            Divider().padding(.horizontal, 14)

            // Stats-Zeile
            HStack(spacing: 0) {
                statCell(label: "Applicants", value: "\(job.applicantCount)", icon: "person.2.fill")
                Divider().frame(height: 30)
                statCell(label: "Spots", value: "\(job.openSpots)", icon: "person.badge.plus")
                Divider().frame(height: 30)
                statCell(label: "Pay", value: job.payText, icon: "banknote")
            }
            .padding(.vertical, 10)

            // Action Buttons (nur bei relevanten Status)
            if job.status == "draft" || job.status == "published" || job.status == "inProgress" {
                Divider().padding(.horizontal, 14)
                HStack(spacing: 8) {
                    if job.status == "draft" {
                        actionButton(label: "Publish", color: SS.primary, action: onPublish)
                    }
                    if job.status != "cancelled" && job.status != "completed" {
                        actionButton(label: "Cancel", color: .red, action: onCancel)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    private func statCell(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(SS.primary.opacity(0.7))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionButton(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
