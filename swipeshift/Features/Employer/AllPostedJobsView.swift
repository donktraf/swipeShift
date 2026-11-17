//
//  AllPostedJobsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - EmployerJob Model

struct EmployerJob: Identifiable, Decodable, Hashable {
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
    let updatedAt: String?

    /// Zeitpunkt der letzten Aenderung (Fallback createdAt)
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    var lastSavedDate: Date? {
        for raw in [updatedAt, createdAt].compactMap({ $0 }) {
            if let d = Self.isoWithFraction.date(from: raw) ?? Self.isoPlain.date(from: raw) { return d }
        }
        return nil
    }

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
    @State private var cancelReason = ""
    @State private var jobToPublish: EmployerJob? = nil
    @State private var jobToDelete: EmployerJob? = nil
    @State private var jobToEdit: EmployerJob? = nil
    @State private var jobForApplicants: EmployerJob? = nil
    @State private var actionError: String? = nil

    // Payment Navigation
    @State private var jobForPayment: EmployerJob? = nil
    @State private var showPayments = false

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
            // Zuletzt bearbeitete Entwuerfe zuerst
            return jobs.filter { $0.status == "draft" }
                .sorted { ($0.lastSavedDate ?? .distantPast) > ($1.lastSavedDate ?? .distantPast) }
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
                                onCancel:       { jobToCancel  = job },
                                onPublish:      { jobToPublish = job },
                                onEdit:         { jobToEdit = job },
                                onDelete:       { jobToDelete = job },
                                onViewApplicants: { jobForApplicants = job },
                                onViewPayments: {
                                    jobForPayment = job
                                    showPayments  = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .navigationDestination(isPresented: $showPayments) {
            if let job = jobForPayment {
                JobPaymentView(
                    jobId:       job.id,
                    jobTitle:    job.title,
                    jobEmoji:    job.logoEmoji,
                    jobLocation: job.location
                )
            }
        }
        .navigationDestination(item: $jobForApplicants) { job in
            AllApplicantsView(jobId: job.id, jobTitle: job.title)
        }
        .sheet(item: $jobToEdit, onDismiss: { Task { await load() } }) { job in
            PostJobView(editingJobId: job.id)
        }
        // Fehler bei Edit/Delete/Publish/Cancel
        .alert("Something went wrong", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        // Delete confirmation (nur Drafts)
        .alert("Delete this draft?", isPresented: Binding(
            get: { jobToDelete != nil },
            set: { if !$0 { jobToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let job = jobToDelete { Task { await deleteDraft(job) } }
                jobToDelete = nil
            }
            Button("Cancel", role: .cancel) { jobToDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
        // Cancel confirmation
        .alert("Cancel job?", isPresented: Binding(
            get: { jobToCancel != nil },
            set: { if !$0 { jobToCancel = nil; cancelReason = "" } }
        )) {
            // Optionaler Grund — Worker sehen ihn im Kalender und in "Job Applications"
            TextField("Reason (optional)", text: $cancelReason)
            Button("Cancel Job", role: .destructive) {
                if let job = jobToCancel {
                    let reason = cancelReason
                    Task { await updateStatus(job, to: "cancelled", reason: reason) }
                }
                cancelReason = ""
            }
            Button("Dismiss", role: .cancel) { jobToCancel = nil; cancelReason = "" }
        } message: {
            Text("The job will be cancelled. Applicants and assigned workers will see the cancellation and your reason (optional) in their calendar.")
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
    private func updateStatus(_ job: EmployerJob, to status: String, reason: String? = nil) async {
        do {
            try await APIClient.shared.updateJobStatus(jobId: job.id, status: status, reason: reason)
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func deleteDraft(_ job: EmployerJob) async {
        do {
            try await APIClient.shared.deleteJob(id: job.id)
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - PostedJobCard

private struct PostedJobCard: View {
    let job: EmployerJob
    let onCancel:       () -> Void
    let onPublish:      () -> Void
    let onEdit:         () -> Void
    let onDelete:       () -> Void
    let onViewApplicants: () -> Void
    let onViewPayments: () -> Void

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
                    if job.status == "draft", let saved = job.lastSavedDate {
                        Text("Last saved \(saved.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
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
            let showPayBtn = job.status == "inProgress" || job.status == "completed"
            let showActionRow = job.status == "draft" || job.status == "published" || job.status == "inProgress" || showPayBtn
            if showActionRow {
                Divider().padding(.horizontal, 14)
                HStack(spacing: 8) {
                    if job.status == "draft" {
                        actionButton(label: "Edit", color: SS.primary, action: onEdit)
                        actionButton(label: "Publish", color: SS.primary, action: onPublish)
                        actionButton(label: "Delete", color: .red, action: onDelete)
                    }
                    if job.status == "published" && job.applicantCount > 0 {
                        actionButton(label: "View Applicants", color: SS.primary, action: onViewApplicants)
                    }
                    if job.status != "cancelled" && job.status != "completed" && job.status != "draft" {
                        actionButton(label: "Cancel", color: .red, action: onCancel)
                    }
                    if showPayBtn {
                        actionButton(label: "View Payments", color: .teal, action: onViewPayments)
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
