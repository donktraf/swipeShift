//
//  AssignWorkersView.swift
//  swipeShift
//

import SwiftUI

// MARK: - DTOs (API Response)

struct AssignableJobDTO: Identifiable, Decodable {
    let id: String
    let title: String
    let logoEmoji: String
    let category: String
    let location: String
    let openSpots: Int
    let shifts: [ShiftSlotDTO]
    var assignedWorkers: [AssignedWorkerDTO]

    var isFullyStaffed: Bool { assignedWorkers.count >= openSpots }
    var openCount: Int { max(0, openSpots - assignedWorkers.count) }
}

struct ShiftSlotDTO: Decodable {
    let date: String
    let timeRange: String
    let duration: String
    let totalPay: String
}

struct AssignedWorkerDTO: Identifiable, Decodable {
    let applyId: String
    let userId: String
    let name: String
    let photoEmoji: String
    let rating: Double
    var id: String { applyId }
}

// MARK: - AssignWorkersView

struct AssignWorkersView: View {
    @State private var jobs: [AssignableJobDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var expandedJobIds: Set<String> = []
    @State private var selectedFilter: StaffingFilter = .all

    enum StaffingFilter: String, CaseIterable {
        case all          = "All"
        case needsWorkers = "Open"
        case fullyStaffed = "Staffed"
    }

    private var filteredJobs: [AssignableJobDTO] {
        jobs.filter { job in
            switch selectedFilter {
            case .all:          return true
            case .needsWorkers: return !job.isFullyStaffed
            case .fullyStaffed: return job.isFullyStaffed
            }
        }
    }

    var body: some View {
        SubScreenShell(title: "Assign Workers") {
            VStack(spacing: 0) {
                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(StaffingFilter.allCases, id: \.self) { filter in
                            filterChip(filter)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)

                if isLoading {
                    ProgressView()
                        .padding(.top, 60)
                } else if let err = errorMessage {
                    errorView(err)
                } else if filteredJobs.isEmpty {
                    emptyView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(filteredJobs) { job in
                                JobAssignCard(
                                    job: job,
                                    isExpanded: expandedJobIds.contains(job.id),
                                    onToggleJob: { toggleJob(job.id) },
                                    onUnassign: { applyId in unassign(jobId: job.id, applyId: applyId) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Filter Chip

    private func filterChip(_ filter: StaffingFilter) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { selectedFilter = filter } } label: {
            Text(filter.rawValue)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selectedFilter == filter ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedFilter == filter ? SS.primary : Color(uiColor: .systemBackground))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / Error

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.3))
            Text("No Jobs")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("All your jobs are fully staffed.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
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

    private func toggleJob(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedJobIds.contains(id) { expandedJobIds.remove(id) }
            else { expandedJobIds.insert(id) }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            jobs = try await APIClient.shared.fetchAssignedWorkers()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func unassign(jobId: String, applyId: String) {
        Task {
            do {
                try await APIClient.shared.unassignWorker(applyId: applyId)
                withAnimation {
                    if let ji = jobs.firstIndex(where: { $0.id == jobId }) {
                        jobs[ji].assignedWorkers.removeAll { $0.applyId == applyId }
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - JobAssignCard

private struct JobAssignCard: View {
    let job: AssignableJobDTO
    let isExpanded: Bool
    let onToggleJob: () -> Void
    let onUnassign: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Job Header
            Button(action: onToggleJob) {
                HStack(spacing: 12) {
                    Text(job.logoEmoji)
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(job.location)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(job.openCount > 0 ? Color.orange : Color.green)
                                .frame(width: 7, height: 7)
                            Text(job.openCount > 0 ? "\(job.openCount) open" : "Staffed")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(job.openCount > 0 ? .orange : .green)
                        }
                        Text("\(job.assignedWorkers.count)/\(job.openSpots) workers")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // Expandiert
            if isExpanded {
                Divider().padding(.horizontal, 14)

                VStack(spacing: 0) {
                    // Schichten (read-only)
                    if !job.shifts.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Shifts")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .padding(.bottom, 4)

                            ForEach(Array(job.shifts.enumerated()), id: \.offset) { _, s in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.date)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text("\(s.timeRange) · \(s.duration)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(s.totalPay)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(SS.primary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                Divider().padding(.leading, 14)
                            }
                        }
                    }

                    // Zugewiesene Mitarbeiter
                    Text("Assigned Workers")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    if job.assignedWorkers.isEmpty {
                        Text("No workers assigned yet.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(job.assignedWorkers) { worker in
                            workerRow(worker)
                        }
                    }

                    // Add Worker — TODO: Bewerber-Liste öffnen
                    Button {
                        // TODO: Bewerber-Liste für diesen Job öffnen
                    } label: {
                        Label("Add Worker", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SS.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(SS.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
                    .buttonStyle(.plain)
                }
                .background(Color.gray.opacity(0.03))
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func workerRow(_ worker: AssignedWorkerDTO) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 34, height: 34)
                Text(worker.photoEmoji)
                    .font(.system(size: 16))
            }
            .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(worker.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                if worker.rating > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", worker.rating))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                onUnassign(worker.applyId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
        }
        .padding(.vertical, 8)
    }
}
