//
//  AllPostedJobsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Inline-Bewerber (Jobkarte)

/// Unbeantwortete manuelle Bewerbung, direkt auf der Jobkarte (GET /jobs/mine, max. 2 pro Job)
struct InlineApplicant: Identifiable, Decodable, Hashable {
    let applyId: String
    let userId: String
    let name: String
    let profilePhotoUrl: String?
    let ratingAverage: Double?
    let reviewCount: Int
    /// Chat erst nach Annahme nutzbar
    let conversationId: String?
    /// Shift-Fit-Hinweis (optional, aeltere Backends liefern sie nicht)
    var availableDays: [String]? = nil
    var availableTimes: [String]? = nil
    var hasScheduleConflict: Bool? = nil
    var reliability: ReliabilitySummary? = nil
    /// Vom Worker gebuchte Schichten
    var bookedShifts: [BookedShift]? = nil

    var id: String { applyId }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }
}

private enum InlineDecision: Identifiable {
    case accept(InlineApplicant), decline(InlineApplicant)
    var id: String {
        switch self {
        case .accept(let a):  return "accept-\(a.applyId)"
        case .decline(let a): return "decline-\(a.applyId)"
        }
    }
}

/// Bestaetigungs-Alert fuer Accept/Decline direkt auf der Jobkarte (gleiche Texte wie im Worker-Profil)
private struct InlineDecisionAlert: ViewModifier {
    @Binding var decision: InlineDecision?
    let onDecide: (InlineApplicant, Bool) -> Void

    private var title: String {
        if case .accept = decision { return "Accept applicant?" }
        return "Decline applicant?"
    }

    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } })) {
            switch decision {
            case .accept(let a)?:
                Button("Accept") { onDecide(a, true) }
                Button("Cancel", role: .cancel) {}
            case .decline(let a)?:
                Button("Decline", role: .destructive) { onDecide(a, false) }
                Button("Cancel", role: .cancel) {}
            case nil:
                EmptyView()
            }
        } message: {
            switch decision {
            case .accept(let a)?:  Text("\(a.name) will be confirmed for the shift.")
            case .decline(let a)?: Text("The application from \(a.name) will be declined.")
            case nil:              Text("")
            }
        }
    }
}

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
    /// Automatisch angenommene Bewerbungen (Instant Match), nicht in applicantCount enthalten
    var instantMatchCount: Int? = nil
    /// Alle Bewerbungen (steuert "View Applicants"); applicantCount zaehlt nur unbeantwortete
    var totalApplicationCount: Int? = nil
    /// Bewerbungen seit dem letzten Oeffnen der Bewerberliste ("N new matches")
    var newMatchCount: Int? = nil
    var inlineApplicants: [InlineApplicant]? = nil
    /// Angenommene Worker, deren Anwesenheit noch erfasst werden soll (Schicht vorbei, 48-h-Fenster offen)
    var attendancePendingCount: Int? = nil
    /// Schichtbeginn (ISO 8601), fuer den Shift-Fit-Hinweis der Inline-Bewerber
    var startTime: String? = nil
    let createdAt: String
    let updatedAt: String?
    /// Eingefrorener Gebuehren-Satz (nil bei Entwuerfen → aktueller Satz aus FeeConfig)
    var platformFeePercent: Double? = nil

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

    var startDate: Date? {
        guard let raw = startTime else { return nil }
        return Self.isoWithFraction.date(from: raw) ?? Self.isoPlain.date(from: raw)
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

        var badgeStyle: DSBadge.Style {
            switch self {
            case .active:     return .published
            case .inProgress: return .inProgress
            case .draft:      return .draft
            case .completed:  return .completed
            case .cancelled:  return .cancelled
            }
        }
    }
}

// MARK: - AllPostedJobsView

struct AllPostedJobsView: View {
    @State private var jobs: [EmployerJob] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab: PostedJobTab = .active

    // Aktions-Alerts
    @State private var jobToCancel: EmployerJob? = nil
    @State private var cancelReason = ""
    @State private var jobToPublish: EmployerJob? = nil
    @State private var jobToDelete: EmployerJob? = nil
    @State private var jobToEdit: EmployerJob? = nil
    /// Wird nach dem Schliessen des Publish-Sheets zu jobToEdit (zwei Sheets nacheinander)
    @State private var pendingEdit: EmployerJob? = nil
    @State private var jobForApplicants: EmployerJob? = nil
    @State private var actionError: String? = nil

    // Inline Accept/Decline auf der Jobkarte (gleiche Bestaetigung wie im Worker-Profil)
    @State private var inlineDecision: InlineDecision? = nil
    @State private var inlineStates: [String: Bool] = [:]   // applyId → true = accepted, false = declined
    @StateObject private var chatNavigation = ApplicantChatNavigation()
    @EnvironmentObject private var messageStore: MessageStore

    // Payment Navigation
    @State private var jobForPayment: EmployerJob? = nil
    @State private var jobForAttendance: EmployerJob? = nil
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Posted jobs")
                    .dsFont(.display)
                    .foregroundStyle(DS.Color.text)
                    .accessibilityAddTraits(.isHeader)

                tabBar

                if isLoading && jobs.isEmpty {
                    skeletonList

                } else if let err = errorMessage {
                    errorView(err)

                } else if filtered.isEmpty {
                    emptyView

                } else {
                    VStack(spacing: DS.Spacing.sm) {
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
                                },
                                onRecordAttendance: { jobForAttendance = job },
                                inlineStates: inlineStates,
                                onInlineAccept:  { inlineDecision = .accept($0) },
                                onInlineDecline: { inlineDecision = .decline($0) },
                                onInlineMessage: { id in
                                    chatNavigation.openChat(conversationId: id, messageStore: messageStore)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xl)
        }
        .dsTabBarInset()
        .dsBackground()
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
        .navigationDestination(item: $jobForAttendance) { job in
            AttendanceScreen(jobId: job.id, jobTitle: job.title) { Task { await load() } }
        }
        .navigationDestination(item: $jobForApplicants) { job in
            AllApplicantsView(jobId: job.id, jobTitle: job.title)
        }
        // Beim Zurueckkehren aus der Bewerberliste: "New Matches" ist dort zurueckgesetzt worden
        .onChange(of: jobForApplicants) { _, new in
            if new == nil { Task { await load() } }
        }
        .applicantChatNavigation(chatNavigation)
        .modifier(InlineDecisionAlert(decision: $inlineDecision) { applicant, accept in
            Task { await decideInline(applicant, accept: accept) }
        })
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
        // Publish confirmation (inkl. Pflicht-Zustimmung zu den Employer-AGB)
        .sheet(item: $jobToPublish, onDismiss: {
            if let job = pendingEdit { pendingEdit = nil; jobToEdit = job }
        }) { job in
            PublishDraftSheet(
                jobTitle: job.title,
                frozenFeePercent: job.platformFeePercent,
                publish: {
                    try await APIClient.shared.updateJobStatus(jobId: job.id, status: "published", termsAccepted: true)
                },
                onPublished: {
                    jobToPublish = nil
                    Task { await load() }
                },
                onEditDraft: {
                    pendingEdit = job
                    jobToPublish = nil
                },
                onCancel: { jobToPublish = nil }
            )
        }
    }

    // MARK: - Tab Bar (Pills)

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(PostedJobTab.allCases, id: \.self) { tab in
                    let count = countFor(tab)
                    let isOn = selectedTab == tab
                    Button {
                        DS.Haptics.selection()
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.rawValue)
                                .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                            if count > 0 {
                                Text("\(count)")
                                    .font(DS.Font.make(11, .extrabold, relativeTo: .caption2))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isOn ? DS.Color.onPrimary.opacity(0.25) : DS.Color.surface2, in: Capsule())
                            }
                        }
                        .foregroundStyle(isOn ? DS.Color.onPrimary : DS.Color.text2)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(isOn ? DS.Color.primary : DS.Color.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(isOn ? DS.Color.primary : DS.Color.border, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.dsPressable)
                    .dsAnimation(.snappy, value: selectedTab)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Loading / Empty / Error

    private var skeletonList: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        HStack(spacing: DS.Spacing.sm) {
                            DSAvatar(text: "JB", size: 46)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Event staff for a weekend").dsFont(.headline)
                                Text("Downtown, Los Angeles").dsFont(.caption)
                            }
                        }
                        Text("Applicants 3 new · Spots 4 · Pay $22 / hr").dsFont(.caption)
                    }
                }
            }
        }
        .dsSkeleton(true)
    }

    private var emptyView: some View {
        DSEmptyState(
            systemIcon: "briefcase",
            title: "No jobs in this category",
            message: "Jobs with this status will show up here."
        )
        .padding(.top, DS.Spacing.xl)
    }

    private func errorView(_ msg: String) -> some View {
        DSEmptyState(
            systemIcon: "exclamationmark.triangle",
            title: "Couldn't load jobs",
            message: msg,
            actionTitle: "Try Again",
            action: { Task { await load() } }
        )
        .padding(.top, DS.Spacing.lg)
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
    private func decideInline(_ applicant: InlineApplicant, accept: Bool) async {
        do {
            if accept { try await APIClient.shared.acceptApplicant(applyId: applicant.applyId) }
            else      { try await APIClient.shared.declineApplicant(applyId: applicant.applyId) }
            withAnimation { inlineStates[applicant.applyId] = accept }
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func updateStatus(_ job: EmployerJob, to status: String, reason: String? = nil, termsAccepted: Bool = false) async {
        do {
            try await APIClient.shared.updateJobStatus(jobId: job.id, status: status, reason: reason, termsAccepted: termsAccepted)
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
    let onRecordAttendance: () -> Void
    let inlineStates: [String: Bool]
    let onInlineAccept:  (InlineApplicant) -> Void
    let onInlineDecline: (InlineApplicant) -> Void
    let onInlineMessage: (String) -> Void

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                header
                statsRow

                // Inline-Bewerber (nur veroeffentlichte Jobs)
                if job.status == "published", let inline = job.inlineApplicants, !inline.isEmpty {
                    DSDivider()
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        ForEach(inline) { applicant in inlineRow(applicant) }
                        if job.applicantCount > inline.count {
                            Button(action: onViewApplicants) {
                                Text("View all \(job.applicantCount) applicants")
                                    .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                                    .foregroundStyle(DS.Color.primaryText)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.dsPressable)
                        }
                    }
                }

                // Anwesenheit erfassen: Schicht vorbei, Worker noch ohne Eintrag (48-h-Fenster)
                if let pending = job.attendancePendingCount, pending > 0 {
                    DSDivider()
                    Button(action: onRecordAttendance) {
                        Label("Record attendance (\(pending))", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.ds(.soft, size: .medium))
                }

                actionRow
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            DSAvatar(text: job.logoEmoji, size: 46)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(job.title)
                    .dsFont(.headline)
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(2)

                HStack(spacing: DS.Spacing.xs) {
                    DSBadge(job.statusEnum.label, job.statusEnum.badgeStyle)
                    if job.status == "published", let n = job.newMatchCount, n > 0 {
                        DSBadge("\(n) new match\(n == 1 ? "" : "es")", .tone(.primary))
                    }
                }

                if job.status == "draft", let saved = job.lastSavedDate {
                    Text("Last saved \(saved.formatted(.relative(presentation: .named)))")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.warning)
                }
                Text(job.location)
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text2)
                    .lineLimit(1)
                Text(job.shiftText)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.muted)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Stats

    /// Veroeffentlicht: unbeantwortete Bewerbungen ("3 new"); sonst Gesamtzahl ohne "new" ("–" bei 0)
    private var applicantsLabel: String {
        if job.status == "published" { return "\(job.applicantCount) new" }
        let total = job.totalApplicationCount ?? job.applicantCount
        return total > 0 ? "\(total)" : "–"
    }

    private var statsRow: some View {
        HStack(spacing: DS.Spacing.xs) {
            statCell(label: "Applicants", value: applicantsLabel)
            if let instant = job.instantMatchCount, instant > 0 {
                statCell(label: "Instant", value: "\(instant)")
            }
            statCell(label: "Spots", value: "\(job.openSpots)")
            statCell(label: "Pay", value: job.payText)
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DS.Font.make(11, .semibold, relativeTo: .caption2))
                .foregroundStyle(DS.Color.muted)
            Text(value)
                .font(DS.Font.make(14, .bold, relativeTo: .callout))
                .foregroundStyle(DS.Color.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, DS.Spacing.xs + 2)
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Aktionen

    @ViewBuilder
    private var actionRow: some View {
        let showPayBtn = job.status == "inProgress" || job.status == "completed"
        let showActionRow = job.status == "draft" || job.status == "published" || job.status == "inProgress" || showPayBtn
        if showActionRow {
            DSDivider()
            HStack(spacing: DS.Spacing.xs) {
                if job.status == "draft" {
                    Button("Edit", action: onEdit).buttonStyle(.ds(.soft, size: .medium))
                    Button("Publish", action: onPublish).buttonStyle(.ds(.primary, size: .medium))
                    Button("Delete", action: onDelete).buttonStyle(.ds(.destructiveSoft, size: .medium))
                }
                if job.status == "published" && (job.totalApplicationCount ?? (job.applicantCount + (job.instantMatchCount ?? 0))) > 0 {
                    Button("View Applicants", action: onViewApplicants).buttonStyle(.ds(.soft, size: .medium))
                }
                if job.status != "cancelled" && job.status != "completed" && job.status != "draft" {
                    Button("Cancel", action: onCancel).buttonStyle(.ds(.destructiveSoft, size: .medium))
                }
                if showPayBtn {
                    Button("View Payments", action: onViewPayments).buttonStyle(.ds(.soft, size: .medium))
                }
            }
        }
    }

    // MARK: Inline-Bewerber

    private func inlineRow(_ applicant: InlineApplicant) -> some View {
        let decision = inlineStates[applicant.applyId]
        return HStack(spacing: DS.Spacing.xs + 2) {
            ApplicantAvatar(photoUrl: applicant.profilePhotoUrl, size: 36, initials: applicant.initials)
            VStack(alignment: .leading, spacing: 2) {
                Text(applicant.name)
                    .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(1)
                ApplicantRatingLabel(average: applicant.ratingAverage, count: applicant.reviewCount)
                if let reliability = applicant.reliability { ReliabilityLabel(summary: reliability, font: 11) }
                if let booked = applicant.bookedShifts, !booked.isEmpty {
                    Text("Shifts: \(booked.summaryLabel)")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                        .lineLimit(1)
                }
                if decision == nil, let fit = ApplicantShiftFit.evaluate(
                    hasConflict: applicant.hasScheduleConflict == true,
                    availableDays: applicant.availableDays ?? [],
                    availableTimes: applicant.availableTimes ?? [],
                    start: job.startDate
                ) {
                    ApplicantShiftFitLabel(fit: fit, compact: true)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            switch decision {
            case nil:
                inlineButton("Decline", systemImage: "xmark", style: .destructiveSoft) { onInlineDecline(applicant) }
                inlineButton("Accept", systemImage: "checkmark", style: .primary) { onInlineAccept(applicant) }
            case true?:
                // Chat erst nach Annahme
                if let conversationId = applicant.conversationId {
                    inlineButton("Message", systemImage: "bubble.left.and.bubble.right", style: .soft) {
                        onInlineMessage(conversationId)
                    }
                } else {
                    DSBadge("Accepted", .upcoming)
                }
            case false?:
                DSBadge("Declined", .cancelled)
            }
        }
    }

    private func inlineButton(_ title: String, systemImage: String, style: DSButtonVariant, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .frame(minWidth: 20)
        }
        .buttonStyle(.ds(style, size: .medium, fullWidth: false))
        .accessibilityLabel(title)
    }
}

// MARK: - PublishDraftSheet

/// Bestaetigung zum Veroeffentlichen eines Entwurfs; "Publish" erst nach Zustimmung zu den Employer-AGB.
/// Das Sheet fuehrt die Anfrage selbst aus, damit Fehler (z.B. unvollstaendiger Entwurf) hier erscheinen.
private struct PublishDraftSheet: View {
    let jobTitle: String
    var frozenFeePercent: Double? = nil
    let publish: () async throws -> Void
    let onPublished: () -> Void
    let onEditDraft: () -> Void
    let onCancel: () -> Void

    @ObservedObject private var feeConfig = FeeConfig.shared
    @State private var termsAccepted = false
    @State private var isPublishing = false
    @State private var errorText: String? = nil
    @State private var incomplete = false

    private static let fieldLabels: [String: String] = [
        "title": "title", "category": "category", "location": "location",
        "shift": "a shift with start and end time", "payAmount": "hourly rate", "openSpots": "number of workers",
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.md) {
                VStack(spacing: DS.Spacing.xs) {
                    Text("Publish job?")
                        .dsFont(.title)
                        .foregroundStyle(DS.Color.text)
                    Text("\"\(jobTitle)\" will be published immediately and visible to workers.")
                        .dsFont(.body)
                        .foregroundStyle(DS.Color.text2)
                        .multilineTextAlignment(.center)
                }

                Text("A \(PlatformFees.percentLabel(frozenFeePercent ?? feeConfig.platformFeePercent)) platform fee is added on top of the wages and billed after each shift. Workers receive the full hourly rate.")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.muted)
                    .multilineTextAlignment(.center)

                TermsConsentRow(isAccepted: $termsAccepted)

                if let errorText {
                    Text(errorText)
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.danger)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: DS.Spacing.xs) {
                    if incomplete {
                        Button("Edit draft") { onEditDraft() }
                            .buttonStyle(.ds(.primary))
                    } else {
                        Button {
                            Task { await run() }
                        } label: {
                            if isPublishing { ProgressView().tint(DS.Color.onPrimary) } else { Text("Publish") }
                        }
                        .buttonStyle(.ds(.primary))
                        .disabled(!termsAccepted || isPublishing)
                    }
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.ds(.secondary))
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)
        }
        .dsBackground()
        .presentationDetents([.fraction(0.6), .large])
        .presentationDragIndicator(.visible)
        .task { await feeConfig.refresh() }
    }

    @MainActor
    private func run() async {
        isPublishing = true
        errorText = nil
        defer { isPublishing = false }
        do {
            try await publish()
            DS.Haptics.success()
            onPublished()
        } catch let apiError as APIError where apiError.code == "INCOMPLETE_JOB" {
            DS.Haptics.warning()
            let names = (apiError.missing ?? []).map { Self.fieldLabels[$0] ?? $0 }
            errorText = names.isEmpty ? apiError.message : "This draft is missing: \(names.joined(separator: ", "))."
            incomplete = true
        } catch {
            DS.Haptics.warning()
            errorText = error.localizedDescription
        }
    }
}
