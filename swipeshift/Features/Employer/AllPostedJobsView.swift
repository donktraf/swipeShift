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
    /// Schichtbeginn (ISO 8601), fuer den Shift-Fit-Hinweis der Inline-Bewerber
    var startTime: String? = nil
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
                                },
                                inlineStates: inlineStates,
                                onInlineAccept:  { inlineDecision = .accept($0) },
                                onInlineDecline: { inlineDecision = .decline($0) },
                                onInlineMessage: { id in
                                    chatNavigation.openChat(conversationId: id, messageStore: messageStore)
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
    let inlineStates: [String: Bool]
    let onInlineAccept:  (InlineApplicant) -> Void
    let onInlineDecline: (InlineApplicant) -> Void
    let onInlineMessage: (String) -> Void

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
                        if job.status == "published", let n = job.newMatchCount, n > 0 {
                            Text("\(n) new match\(n == 1 ? "" : "es")")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(SS.primary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(SS.primary.opacity(0.12))
                                .clipShape(Capsule())
                        }
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
                statCell(label: "Applicants", value: applicantsLabel, icon: "person.2.fill")
                if let instant = job.instantMatchCount, instant > 0 {
                    Divider().frame(height: 30)
                    statCell(label: "Instant", value: "\(instant)", icon: "bolt.fill")
                }
                Divider().frame(height: 30)
                statCell(label: "Spots", value: "\(job.openSpots)", icon: "person.badge.plus")
                Divider().frame(height: 30)
                statCell(label: "Pay", value: job.payText, icon: "banknote")
            }
            .padding(.vertical, 10)

            // Inline-Bewerber (nur veroeffentlichte Jobs)
            if job.status == "published", let inline = job.inlineApplicants, !inline.isEmpty {
                Divider().padding(.horizontal, 14)
                VStack(spacing: 10) {
                    ForEach(inline) { applicant in inlineRow(applicant) }
                    if job.applicantCount > inline.count {
                        Button(action: onViewApplicants) {
                            Text("View all \(job.applicantCount) applicants")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(SS.primary)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }

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
                    if job.status == "published" && (job.totalApplicationCount ?? (job.applicantCount + (job.instantMatchCount ?? 0))) > 0 {
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

    private func inlineRow(_ applicant: InlineApplicant) -> some View {
        let decision = inlineStates[applicant.applyId]
        return HStack(spacing: 10) {
            ApplicantAvatar(photoUrl: applicant.profilePhotoUrl, size: 36, initials: applicant.initials)
            VStack(alignment: .leading, spacing: 2) {
                Text(applicant.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                ApplicantRatingLabel(average: applicant.ratingAverage, count: applicant.reviewCount)
                if decision == nil, let fit = ApplicantShiftFit.evaluate(
                    hasConflict: applicant.hasScheduleConflict == true,
                    availableDays: applicant.availableDays ?? [],
                    availableTimes: applicant.availableTimes ?? [],
                    start: job.startDate
                ) {
                    ApplicantShiftFitLabel(fit: fit, compact: true)
                }
            }
            Spacer(minLength: 6)
            switch decision {
            case nil:
                inlineButton("Decline", systemImage: "xmark", filled: false) { onInlineDecline(applicant) }
                inlineButton("Accept", systemImage: "checkmark", filled: true) { onInlineAccept(applicant) }
            case true?:
                // Chat erst nach Annahme
                if let conversationId = applicant.conversationId {
                    inlineButton("Message", systemImage: "bubble.left.and.bubble.right", filled: false) {
                        onInlineMessage(conversationId)
                    }
                } else {
                    Text("Accepted").font(.system(size: 12, weight: .semibold)).foregroundColor(.green)
                }
            case false?:
                Text("Declined").font(.system(size: 12, weight: .semibold)).foregroundColor(.red)
            }
        }
    }

    private func inlineButton(_ title: String, systemImage: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(filled ? .white : (title == "Decline" ? .red : SS.primary))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(filled ? SS.primary : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(filled ? Color.clear : (title == "Decline" ? Color.red.opacity(0.35) : SS.primary.opacity(0.4)), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    /// Veroeffentlicht: unbeantwortete Bewerbungen ("3 new"); sonst Gesamtzahl ohne "new" ("–" bei 0)
    private var applicantsLabel: String {
        if job.status == "published" { return "\(job.applicantCount) new" }
        let total = job.totalApplicationCount ?? job.applicantCount
        return total > 0 ? "\(total)" : "–"
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

// MARK: - PublishDraftSheet

/// Bestaetigung zum Veroeffentlichen eines Entwurfs; "Publish" erst nach Zustimmung zu den Employer-AGB.
/// Das Sheet fuehrt die Anfrage selbst aus, damit Fehler (z.B. unvollstaendiger Entwurf) hier erscheinen.
private struct PublishDraftSheet: View {
    let jobTitle: String
    let publish: () async throws -> Void
    let onPublished: () -> Void
    let onEditDraft: () -> Void
    let onCancel: () -> Void

    @State private var termsAccepted = false
    @State private var isPublishing = false
    @State private var errorText: String? = nil
    @State private var incomplete = false

    private static let fieldLabels: [String: String] = [
        "title": "title", "category": "category", "location": "location",
        "shift": "a shift with start and end time", "payAmount": "hourly rate", "openSpots": "number of workers",
    ]

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Text("Publish job?")
                    .font(.system(size: 20, weight: .bold))
                Text("\"\(jobTitle)\" will be published immediately and visible to workers.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            TermsConsentRow(isAccepted: $termsAccepted)
                .padding(.horizontal, 16)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 10) {
                if incomplete {
                    Button("Edit draft") { onEditDraft() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SS.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Button {
                        Task { await run() }
                    } label: {
                        Group {
                            if isPublishing { ProgressView().tint(.white) } else { Text("Publish") }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(termsAccepted ? SS.primary : Color.gray.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!termsAccepted || isPublishing)
                }
                Button("Cancel") { onCancel() }
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .presentationDetents([.fraction(0.55), .large])
    }

    @MainActor
    private func run() async {
        isPublishing = true
        errorText = nil
        defer { isPublishing = false }
        do {
            try await publish()
            onPublished()
        } catch let apiError as APIError where apiError.code == "INCOMPLETE_JOB" {
            let names = (apiError.missing ?? []).map { Self.fieldLabels[$0] ?? $0 }
            errorText = names.isEmpty ? apiError.message : "This draft is missing: \(names.joined(separator: ", "))."
            incomplete = true
        } catch {
            errorText = error.localizedDescription
        }
    }
}
