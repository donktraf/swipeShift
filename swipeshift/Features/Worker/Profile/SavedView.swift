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
        SubScreenShell(title: "Saved", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                tabSelector

                if isLoading && savedJobs.isEmpty && savedCompanies.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(0..<3, id: \.self) { _ in
                            DSSkeletonBlock(height: 110, radius: DS.Radius.card)
                        }
                    }
                    .accessibilityLabel("Loading saved items")
                } else if let err = errorMessage {
                    VStack(spacing: DS.Spacing.sm) {
                        Text(err).dsFont(.callout).foregroundStyle(DS.Color.muted)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.xxl)
                } else if selectedTab == .jobs {
                    if savedJobs.isEmpty { emptyState } else { savedJobsList }
                } else {
                    if savedCompanies.isEmpty { emptyState } else { savedCompaniesList }
                }
            }
            .dsAnimation(.standard, value: savedJobs.count)
            .dsAnimation(.standard, value: savedCompanies.count)
        }
        .refreshable { await load() }
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
            HStack(spacing: DS.Spacing.sm) {
                Text("Removed from saved")
                    .dsFont(.body).foregroundStyle(DS.Color.bg)
                Spacer()
                Button("Undo") { undoNotInterested(job) }
                    .font(DS.Font.make(14, .bold, relativeTo: .callout)).foregroundStyle(DS.Color.bg)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, DS.Spacing.md).padding(.vertical, DS.Spacing.xxs)
            .background(DS.Color.text, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.Spacing.screenEdge).padding(.bottom, DS.Spacing.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func startApply(_ saved: WorkerSavedJob) {
        Task {
            do { applyJob = try await APIClient.shared.fetchJob(jobId: saved.jobId) }
            catch { actionError = "The job could not be loaded. Please try again." }
        }
    }

    // MARK: - Tab Selector (segmentierte Pills)

    private var tabSelector: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach([(SavedTab.jobs, "Jobs"), (SavedTab.companies, "Companies")], id: \.0) { tab, label in
                Button {
                    DS.Haptics.selection()
                    selectedTab = tab
                } label: {
                    Text(label)
                        .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                        .foregroundStyle(selectedTab == tab ? DS.Color.onPrimary : DS.Color.text2)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selectedTab == tab ? DS.Color.primary : Color.clear, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.dsPressable)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(DS.Spacing.xxs)
        .background(DS.Color.surface2, in: Capsule())
        .dsAnimation(.snappy, value: selectedTab)
    }

    // MARK: - Saved Jobs List (nach Datum gruppiert)

    private var savedJobsList: some View {
        let grouped = Dictionary(grouping: savedJobs) { dateLabel($0.savedAt) }
        let keys    = grouped.keys.sorted { a, b in
            let dateA = savedJobs.first { dateLabel($0.savedAt) == a }?.savedAt ?? .distantPast
            let dateB = savedJobs.first { dateLabel($0.savedAt) == b }?.savedAt ?? .distantPast
            return dateA > dateB
        }
        return VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            ForEach(keys, id: \.self) { key in
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(key)
                        .dsFont(.sectionLabel)
                        .foregroundStyle(DS.Color.muted)
                    ForEach(grouped[key] ?? []) { job in
                        SavedJobCard(
                            job: job,
                            onUnsave: { savedJobs.removeAll { $0.id == job.id } },
                            onApply: { startApply(job) },
                            onNotInterested: { notInterested(job) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DSEmptyState(
            systemIcon: "bookmark",
            title: "You haven't saved anything yet.",
            message: "Start exploring jobs and companies and save the ones you like."
        )
    }

    // MARK: - Saved Companies List

    private var savedCompaniesList: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(savedCompanies) { company in
                SavedCompanyCard(company: company) {
                    savedCompanies.removeAll { $0.id == company.id }
                }
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
