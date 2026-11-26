//
//  AssignWorkersView.swift
//  swipeShift
//

import SwiftUI

// MARK: - DTOs (API Response)

struct JobApplicantDTO: Identifiable, Decodable {
    let applyId:         String
    let userId:          String
    let status:          String
    let workerName:      String
    let profilePhotoUrl: String?
    let rating:          Double
    let location:        String?
    var autoAccepted:    Bool? = nil
    var id: String { applyId }
}

struct JobApplicantsResponse: Decodable {
    let applicants: [JobApplicantDTO]
}

struct AssignableJobDTO: Identifiable, Decodable {
    let id: String
    let title: String
    let logoEmoji: String
    let category: String
    let location: String
    let openSpots: Int
    let shifts: [ShiftSlotDTO]
    var assignedWorkers: [AssignedWorkerDTO]
    /// Kosten fuer den Employer (Backend utils/jobCost.js): je Worker Lohn + Plattform-Gebuehr, sowie fuer die aktuell Zugewiesenen
    var feePercent: Double? = nil
    var costPerWorker: Double? = nil
    var costPerWorkerWage: Double? = nil
    var costPerWorkerFee: Double? = nil
    var assignedCost: Double? = nil

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
    var autoAccepted: Bool? = nil
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
        SubScreenShell(title: "Assign Workers", padded: true) {
            VStack(spacing: DS.Spacing.md) {
                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(StaffingFilter.allCases, id: \.self) { filter in
                            DSChip(filter.rawValue, isSelected: selectedFilter == filter) {
                                selectedFilter = filter
                            }
                        }
                    }
                }

                if isLoading && jobs.isEmpty {
                    skeleton
                } else if let err = errorMessage {
                    errorView(err)
                } else if filteredJobs.isEmpty {
                    emptyView
                } else {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(filteredJobs) { job in
                            JobAssignCard(
                                job: job,
                                isExpanded: expandedJobIds.contains(job.id),
                                onToggleJob: { toggleJob(job.id) },
                                onUnassign: { applyId in unassign(jobId: job.id, applyId: applyId) },
                                onAssign:   { worker   in assign(jobId: job.id, worker: worker) }
                            )
                        }
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var skeleton: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                DSSkeletonBlock(height: 76, radius: DS.Radius.card)
            }
        }
        .accessibilityLabel("Loading jobs")
    }

    // MARK: - Empty / Error

    private var emptyView: some View {
        DSEmptyState(
            systemIcon: "person.2.slash",
            title: "No Jobs",
            message: "All your jobs are fully staffed."
        )
        .padding(.top, DS.Spacing.xl)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(DS.Color.warning)
            Text(msg)
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text2)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
        }
        .padding(.top, DS.Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func toggleJob(_ id: String) {
        withAnimation(DS.Motion.standard.animation) {
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

    private func assign(jobId: String, worker: AssignedWorkerDTO) {
        withAnimation {
            if let ji = jobs.firstIndex(where: { $0.id == jobId }) {
                jobs[ji].assignedWorkers.append(worker)
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
    var onAssign: ((AssignedWorkerDTO) -> Void)? = nil

    @State private var showAddWorker = false

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                // Job Header
                Button {
                    DS.Haptics.selection()
                    onToggleJob()
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        DSAvatar(text: job.logoEmoji, size: 44)

                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(job.title)
                                .dsFont(.headline)
                                .foregroundStyle(DS.Color.text)
                            Text(job.location)
                                .dsFont(.caption)
                                .foregroundStyle(DS.Color.muted)
                        }

                        Spacer(minLength: DS.Spacing.xs)

                        VStack(alignment: .trailing, spacing: DS.Spacing.xxs) {
                            DSBadge(job.openCount > 0 ? "\(job.openCount) open" : "Staffed",
                                    .tone(job.openCount > 0 ? .warning : .success))
                            Text("\(job.assignedWorkers.count)/\(job.openSpots) workers")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Color.muted)
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Color.muted)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressable)
                .accessibilityHint(isExpanded ? "Collapses the job" : "Expands the job")

                // Expandiert
                if isExpanded {
                    DSDivider()
                    expandedContent
                }
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Schichten (read-only)
            if !job.shifts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SHIFTS")
                        .dsFont(.sectionLabel)
                        .foregroundStyle(DS.Color.muted)
                        .padding(.bottom, DS.Spacing.xxs)

                    ForEach(Array(job.shifts.enumerated()), id: \.offset) { index, s in
                        if index > 0 { DSDivider() }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.date)
                                    .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                                    .foregroundStyle(DS.Color.text)
                                Text("\(s.timeRange) · \(s.duration)")
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Color.text2)
                            }
                            Spacer()
                            Text(s.totalPay)
                                .font(DS.Font.make(13, .semibold, relativeTo: .caption))
                                .foregroundStyle(DS.Color.primaryText)
                        }
                        .padding(.vertical, DS.Spacing.xs)
                    }
                }
            }

            // Kosten (Lohn geht komplett an den Worker, Gebuehr kommt obendrauf)
            if let perWorker = job.costPerWorker, let wage = job.costPerWorkerWage, let fee = job.costPerWorkerFee {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Cost per worker: \(Money.format(perWorker, fractionDigits: 2))")
                        .font(DS.Font.make(13, .semibold, relativeTo: .caption))
                        .foregroundStyle(DS.Color.text)
                    Text("\(Money.format(wage, fractionDigits: 2)) wage + \(Money.format(fee, fractionDigits: 2)) platform fee (\(PlatformFees.percentLabel(job.feePercent ?? PlatformFees.defaultPlatformPercent)))")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.text2)
                    if let assigned = job.assignedCost, !job.assignedWorkers.isEmpty {
                        Text("Assigned (\(job.assignedWorkers.count)): \(Money.format(assigned, fractionDigits: 2)) incl. fee")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.text2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Spacing.sm)
                .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }

            // Zugewiesene Mitarbeiter
            VStack(alignment: .leading, spacing: 0) {
                Text("ASSIGNED WORKERS")
                    .dsFont(.sectionLabel)
                    .foregroundStyle(DS.Color.muted)
                    .padding(.bottom, DS.Spacing.xxs)

                if job.assignedWorkers.isEmpty {
                    Text("No workers assigned yet.")
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.text2)
                        .padding(.vertical, DS.Spacing.xs)
                } else {
                    ForEach(job.assignedWorkers) { worker in
                        workerRow(worker)
                    }
                }
            }

            Button { showAddWorker = true } label: {
                Label("Add Worker", systemImage: "plus")
            }
            .buttonStyle(.ds(.soft, size: .medium))
            .sheet(isPresented: $showAddWorker) {
                AddWorkerSheet(jobId: job.id, jobTitle: job.title) { newWorker in
                    onAssign?(newWorker)
                }
            }
        }
    }

    private func workerRow(_ worker: AssignedWorkerDTO) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSAvatar(text: worker.photoEmoji, size: 36, shape: .circle, tone: .neutral)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(worker.name)
                        .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                        .foregroundStyle(DS.Color.text)
                    if worker.autoAccepted == true { InstantMatchPill() }
                }
                if worker.rating > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Color.warning)
                        Text(String(format: "%.1f", worker.rating))
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.text2)
                    }
                }
            }

            Spacer()

            Button {
                DS.Haptics.warning()
                onUnassign(worker.applyId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(DS.Color.danger)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPressable)
            .accessibilityLabel("Remove \(worker.name)")
        }
        .padding(.vertical, DS.Spacing.xxs)
    }
}

// MARK: - AddWorkerSheet

private struct AddWorkerSheet: View {
    let jobId: String
    let jobTitle: String
    let onAssigned: (AssignedWorkerDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var applicants: [JobApplicantDTO] = []
    @State private var isLoading = true
    @State private var assigningId: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(0..<3, id: \.self) { _ in
                            DSSkeletonBlock(height: 64, radius: DS.Radius.card)
                        }
                    }
                    .padding(DS.Spacing.screenEdge)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else if applicants.isEmpty {
                    DSEmptyState(
                        systemIcon: "person.crop.circle.badge.questionmark",
                        title: "No pending applicants",
                        message: "All applicants have already been accepted or declined."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(applicants.enumerated()), id: \.element.id) { index, applicant in
                                if index > 0 { DSDivider() }
                                applicantRow(applicant)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.screenEdge)
                    }
                }
            }
            .dsBackground()
            .navigationTitle("Add Worker to \(jobTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadApplicants() }
    }

    private func applicantRow(_ applicant: JobApplicantDTO) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSAvatar(text: DSAvatar.initials(from: applicant.workerName), size: 44, shape: .circle)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(applicant.workerName)
                    .dsFont(.headline)
                    .foregroundStyle(DS.Color.text)
                if applicant.rating > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Color.warning)
                        Text(String(format: "%.1f", applicant.rating))
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.text2)
                    }
                }
                if let loc = applicant.location {
                    Label(loc, systemImage: "mappin")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                }
            }

            Spacer()

            Button {
                Task { await assign(applicant) }
            } label: {
                if assigningId == applicant.applyId {
                    ProgressView().tint(DS.Color.onPrimary)
                } else {
                    Text("Assign")
                }
            }
            .buttonStyle(.ds(.primary, size: .medium, fullWidth: false))
            .disabled(assigningId != nil)
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    private func loadApplicants() async {
        isLoading = true
        do {
            applicants = try await APIClient.shared.fetchPendingApplicantsForJob(jobId: jobId)
        } catch { }
        isLoading = false
    }

    private func assign(_ applicant: JobApplicantDTO) async {
        assigningId = applicant.applyId
        do {
            try await APIClient.shared.acceptApplicant(applyId: applicant.applyId)
            DS.Haptics.success()
            let newWorker = AssignedWorkerDTO(
                applyId:    applicant.applyId,
                userId:     applicant.userId,
                name:       applicant.workerName,
                photoEmoji: "👤",
                rating:     applicant.rating
            )
            applicants.removeAll { $0.applyId == applicant.applyId }
            onAssigned(newWorker)
            if applicants.isEmpty { dismiss() }
        } catch { }
        assigningId = nil
    }
}
