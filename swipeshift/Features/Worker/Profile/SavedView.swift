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
    @State private var applyJob:        Job? = nil
    @State private var actionError:     String? = nil
    /// Zuletzt per "Not interested" entfernter Job → kurzes Undo
    @State private var undoJob:         WorkerSavedJob? = nil
    @State private var undoHadSkip      = false
    @State private var undoDismissTask: Task<Void, Never>? = nil

    var body: some View {
        SubScreenShell(title: "Saved") {
            VStack(spacing: 16) {
                tabSelector.padding(.horizontal, 16)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if let err = errorMessage {
                    VStack(spacing: 12) {
                        Text(err).font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center).padding(.horizontal, 24)
                        Button("Retry") { Task { await load() } }
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(SS.primary)
                    }.padding(.top, 60)
                } else if selectedTab == .jobs {
                    if savedJobs.isEmpty { emptyState } else { savedJobsList }
                } else {
                    if savedCompanies.isEmpty { emptyState } else { savedCompaniesList }
                }
            }
        }
        .overlay(alignment: .bottom) { undoBanner }
        .task { await load() }
        .onChange(of: selectedTab) { _, _ in Task { await load() } }
        // Bestehender Apply Flow; danach neu laden, damit "Apply" verschwindet
        .sheet(item: $applyJob) { job in
            ApplyFlowView(
                job: job,
                onSuccess: { applyJob = nil; Task { await load() } },
                onExitToJobList: { applyJob = nil }
            )
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Not interested + Undo

    private func notInterested(_ job: WorkerSavedJob) {
        Task {
            do {
                let hadSkip = try await APIClient.shared.markNotInterested(jobId: job.jobId)
                withAnimation { savedJobs.removeAll { $0.id == job.id } }
                undoHadSkip = hadSkip
                showUndo(for: job)
            } catch {
                actionError = "Couldn't update this job. Please try again."
            }
        }
    }

    private func showUndo(for job: WorkerSavedJob) {
        undoDismissTask?.cancel()
        withAnimation { undoJob = job }
        undoDismissTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { undoJob = nil } }
        }
    }

    /// Undo = Skip entfernen + erneut speichern
    private func undoNotInterested(_ job: WorkerSavedJob) {
        undoDismissTask?.cancel()
        withAnimation { undoJob = nil }
        Task {
            do {
                try await APIClient.shared.unskip(jobId: job.jobId, restoreSkip: undoHadSkip)
                try await APIClient.shared.saveJob(jobId: job.jobId)
                await load()
            } catch {
                actionError = "Couldn't restore this job. Please try again."
            }
        }
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let job = undoJob {
            HStack(spacing: 12) {
                Text("Removed from saved")
                    .font(.system(size: 14)).foregroundColor(.white)
                Spacer()
                Button("Undo") { undoNotInterested(job) }
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16).padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func startApply(_ saved: WorkerSavedJob) {
        Task {
            do { applyJob = try await APIClient.shared.fetchJob(jobId: saved.jobId) }
            catch { actionError = "The job could not be loaded. Please try again." }
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
                        SavedJobCard(
                            job: job,
                            onUnsave: { withAnimation { savedJobs.removeAll { $0.id == job.id } } },
                            onApply: { startApply(job) },
                            onNotInterested: { notInterested(job) }
                        )
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
