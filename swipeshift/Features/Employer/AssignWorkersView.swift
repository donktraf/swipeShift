//
//  AssignWorkersView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Models

struct AssignableJob: Identifiable {
    let id: String
    let title: String
    let logoEmoji: String
    let category: String
    let location: String
    var shifts: [AssignableShift]
}

struct AssignableShift: Identifiable {
    let id: String
    let date: Date
    let startTime: String
    let endTime: String
    let totalSpots: Int
    var assignedWorkers: [AssignedWorker]

    var openSpots: Int { totalSpots - assignedWorkers.count }
    var isFullyStaffed: Bool { openSpots <= 0 }

    var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).day(.defaultDigits).month(.abbreviated))
    }
}

struct AssignedWorker: Identifiable {
    let id: String
    let name: String
    let photoEmoji: String
    let rating: Double
}

// MARK: - AssignWorkersView

struct AssignWorkersView: View {
    @State private var jobs: [AssignableJob] = mockAssignableJobs
    @State private var expandedJobIds: Set<String> = []
    @State private var expandedShiftIds: Set<String> = []
    @State private var selectedFilter: StaffingFilter = .all

    enum StaffingFilter: String, CaseIterable {
        case all           = "All"
        case needsWorkers  = "Open"
        case fullyStaffed  = "Staffed"
    }

    private var filteredJobs: [AssignableJob] {
        jobs.filter { job in
            switch selectedFilter {
            case .all: return true
            case .needsWorkers:
                return job.shifts.contains { !$0.isFullyStaffed }
            case .fullyStaffed:
                return job.shifts.allSatisfy { $0.isFullyStaffed }
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

                if filteredJobs.isEmpty {
                    emptyView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(filteredJobs) { job in
                                JobAssignCard(
                                    job: job,
                                    isExpanded: expandedJobIds.contains(job.id),
                                    expandedShifts: expandedShiftIds,
                                    onToggleJob: { toggleJob(job.id) },
                                    onToggleShift: { toggleShift($0) },
                                    onUnassign: { jobId, shiftId, workerId in
                                        unassign(jobId: jobId, shiftId: shiftId, workerId: workerId)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
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

    // MARK: - Empty View

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

    // MARK: - Helpers

    private func toggleJob(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedJobIds.contains(id) { expandedJobIds.remove(id) }
            else { expandedJobIds.insert(id) }
        }
    }

    private func toggleShift(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedShiftIds.contains(id) { expandedShiftIds.remove(id) }
            else { expandedShiftIds.insert(id) }
        }
    }

    private func unassign(jobId: String, shiftId: String, workerId: String) {
        guard let ji = jobs.firstIndex(where: { $0.id == jobId }),
              let si = jobs[ji].shifts.firstIndex(where: { $0.id == shiftId }) else { return }
        withAnimation {
            jobs[ji].shifts[si].assignedWorkers.removeAll { $0.id == workerId }
        }
    }
}

// MARK: - JobAssignCard

private struct JobAssignCard: View {
    let job: AssignableJob
    let isExpanded: Bool
    let expandedShifts: Set<String>
    let onToggleJob: () -> Void
    let onToggleShift: (String) -> Void
    let onUnassign: (String, String, String) -> Void

    private var totalOpen: Int { job.shifts.reduce(0) { $0 + $1.openSpots } }
    private var totalStaffed: Int { job.shifts.reduce(0) { $0 + $1.assignedWorkers.count } }
    private var totalSpots: Int { job.shifts.reduce(0) { $0 + $1.totalSpots } }

    var body: some View {
        VStack(spacing: 0) {
            // Job Header — tippbar zum Ausklappen
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

                    // Staffing-Badge
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(totalOpen > 0 ? Color.orange : Color.green)
                                .frame(width: 7, height: 7)
                            Text(totalOpen > 0 ? "\(totalOpen) open" : "Staffed")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(totalOpen > 0 ? .orange : .green)
                        }
                        Text("\(totalStaffed)/\(totalSpots) workers")
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

            // Schichten (expandiert)
            if isExpanded {
                Divider().padding(.horizontal, 14)

                VStack(spacing: 0) {
                    ForEach(job.shifts) { shift in
                        shiftRow(shift)
                        if shift.id != job.shifts.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    @ViewBuilder
    private func shiftRow(_ shift: AssignableShift) -> some View {
        let isShiftExpanded = expandedShifts.contains(shift.id)

        VStack(spacing: 0) {
            // Schicht-Header
            Button { onToggleShift(shift.id) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shift.dateLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("\(shift.startTime) – \(shift.endTime)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Staffing Progress
                    HStack(spacing: 6) {
                        staffingPills(shift)

                        if !shift.isFullyStaffed {
                            Text("\(shift.openSpots) open")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                        } else {
                            Text("Fully Staffed")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.green)
                        }
                    }

                    Image(systemName: isShiftExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Zugewiesene Mitarbeiter (expandiert)
            if isShiftExpanded {
                VStack(spacing: 0) {
                    if shift.assignedWorkers.isEmpty {
                        Text("No workers assigned yet.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(shift.assignedWorkers) { worker in
                            workerRow(worker, shift: shift)
                        }
                    }

                    // Mitarbeiter hinzufügen (TODO: Bewerber-Liste öffnen)
                    Button {
                        // TODO: Bewerber-Liste für diese Schicht öffnen
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
    }

    private func workerRow(_ worker: AssignedWorker, shift: AssignableShift) -> some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 34, height: 34)
                Text(worker.photoEmoji)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(worker.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", worker.rating))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                onUnassign(job.id, shift.id, worker.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func staffingPills(_ shift: AssignableShift) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<shift.totalSpots, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < shift.assignedWorkers.count ? Color.green : Color.gray.opacity(0.2))
                    .frame(width: 14, height: 6)
            }
        }
    }
}

// MARK: - Mock Data

private let mockAssignableJobs: [AssignableJob] = [
    AssignableJob(
        id: "j1",
        title: "Event Staff — Sommerfest",
        logoEmoji: "🎪",
        category: "Events",
        location: "Munich City Center",
        shifts: [
            AssignableShift(
                id: "s1",
                date: Calendar.current.date(byAdding: .day, value: 1, to: .now)!,
                startTime: "18:00",
                endTime: "23:00",
                totalSpots: 3,
                assignedWorkers: [
                    AssignedWorker(id: "w1", name: "Jonas Weber",  photoEmoji: "👨‍💼", rating: 4.8),
                    AssignedWorker(id: "w2", name: "Maria Schulz", photoEmoji: "👩‍💼", rating: 4.6),
                ]
            ),
            AssignableShift(
                id: "s2",
                date: Calendar.current.date(byAdding: .day, value: 2, to: .now)!,
                startTime: "16:00",
                endTime: "22:00",
                totalSpots: 2,
                assignedWorkers: []
            ),
        ]
    ),
    AssignableJob(
        id: "j2",
        title: "Warehouse — Night Shift",
        logoEmoji: "📦",
        category: "Logistics",
        location: "Munich North",
        shifts: [
            AssignableShift(
                id: "s3",
                date: .now,
                startTime: "22:00",
                endTime: "06:00",
                totalSpots: 4,
                assignedWorkers: [
                    AssignedWorker(id: "w3", name: "Lukas Bauer",  photoEmoji: "👷", rating: 4.5),
                    AssignedWorker(id: "w4", name: "Anna Müller",  photoEmoji: "👩‍🔧", rating: 4.9),
                    AssignedWorker(id: "w5", name: "Tim Fischer",  photoEmoji: "🧑‍💼", rating: 4.2),
                    AssignedWorker(id: "w6", name: "Lena Braun",   photoEmoji: "👩‍💼", rating: 4.7),
                ]
            ),
        ]
    ),
    AssignableJob(
        id: "j3",
        title: "Bartender — Pool Bar",
        logoEmoji: "🍹",
        category: "Hospitality",
        location: "Munich Schwabing",
        shifts: [
            AssignableShift(
                id: "s4",
                date: Calendar.current.date(byAdding: .day, value: 3, to: .now)!,
                startTime: "19:00",
                endTime: "02:00",
                totalSpots: 2,
                assignedWorkers: [
                    AssignedWorker(id: "w7", name: "Max Hoffmann", photoEmoji: "🧑‍🍳", rating: 4.8),
                ]
            ),
        ]
    ),
]
