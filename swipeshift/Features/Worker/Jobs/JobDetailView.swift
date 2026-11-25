//
//  JobDetailView.swift
//  swipeShift
//

import SwiftUI

struct JobDetailView: View {
    /// Job wie uebergeben; `job` (computed) ergaenzt ihn um den Firmenblock aus GET /jobs/:id
    private let initialJob: Job
    @State private var detailedJob: Job?

    init(job: Job) { self.initialJob = job }

    private var job: Job { detailedJob ?? initialJob }

    @EnvironmentObject var jobStore: JobStore
    @EnvironmentObject var userStore: UserStore
    @Environment(\.dismiss) private var dismiss

    @State private var showApplySheet = false

    private var isBookmarked: Bool { jobStore.savedJobIds.contains(job.id) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                headerSection
                keyFacts
                categoryAndTagsSection
                timeInfoSection
                shiftsSection
                descriptionSection
                tasksSection
                requirementsSection
                payDetailsSection
                cancellationSection
                employerNotesSection
                locationSection
                companySection
                whatHappensNextSection
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.xs)
            .padding(.bottom, DS.Spacing.xl)
        }
        .dsBackground()
        // Sticky Apply-Leiste (beachtet die Safe Area)
        .safeAreaInset(edge: .bottom, spacing: 0) { stickyApplyBar }
        .navigationBarHidden(true)
        .task {
            await jobStore.loadSavedJobIds()
        }
        .task(id: initialJob.id) {
            // Firmenblock (Branche, abgeschlossene Schichten) kommt nur vom Einzel-Endpunkt.
            // Schlaegt das fehl, bleibt der Job wie uebergeben sichtbar; der Block fehlt dann nur.
            guard initialJob.companyCompletedJobs == nil else { return }
            detailedJob = try? await APIClient.shared.fetchJob(jobId: initialJob.id)
        }
        .sheet(isPresented: $showApplySheet) {
            ApplyFlowView(
                job: job,
                onSuccess: {
                    showApplySheet = false
                    dismiss()
                },
                onExitToJobList: {
                    showApplySheet = false
                    dismiss()
                }
            )
            .environmentObject(jobStore)
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Navigations-Leiste: Close links, Share + Bookmark rechts
            HStack(spacing: DS.Spacing.xs) {
                DSIconButton(systemName: "xmark", label: "Close") { dismiss() }

                Spacer()

                // Teilen: Kurztext + Deep Link (oeffnet den Job direkt in der App)
                ShareLink(
                    item: JobShareContent.url(for: job),
                    subject: Text(job.title),
                    message: Text(JobShareContent.message(for: job))
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(DS.Font.make(17, .semibold))
                        .foregroundStyle(DS.Color.text)
                        .frame(width: 44, height: 44)
                        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .strokeBorder(DS.Color.border, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(.dsPressable)
                .accessibilityLabel("Share job")

                DSIconButton(
                    systemName: isBookmarked ? "bookmark.fill" : "bookmark",
                    label: isBookmarked ? "Remove from saved" : "Save job"
                ) {
                    Task { await jobStore.toggleSaveJob(job.id) }
                }
            }

            // Logo (tippbar -> Firmenprofil) + Titel
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                NavigationLink {
                    CompanyProfileView(companyName: job.company, logoEmoji: job.logoEmoji)
                } label: {
                    DSAvatar(text: job.logoEmoji, size: 64, shape: .roundedSquare)
                        .frame(minWidth: 64, minHeight: 64)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressable)
                .accessibilityLabel("Open company profile")
                .accessibilityHidden(false)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xxs) {
                        Text(job.title)
                            .dsFont(.title)
                            .foregroundStyle(DS.Color.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if job.isVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(DS.Font.make(14, .semibold))
                                .foregroundStyle(DS.Color.primaryText)
                                .accessibilityLabel("Verified")
                        }
                    }

                    Text(job.company)
                        .dsFont(.body)
                        .foregroundStyle(DS.Color.muted)

                    if job.isUrgent || job.instantMatch {
                        HStack(spacing: DS.Spacing.xs) {
                            if job.isUrgent { DSBadge("Urgent", .tone(.danger)) }
                            if job.instantMatch { DSBadge("Instant Match", .tone(.primary)) }
                        }
                        .padding(.top, DS.Spacing.xxs)
                    }

                    if let rating = job.companyRating {
                        HStack(spacing: DS.Spacing.xxs) {
                            Image(systemName: "star.fill")
                                .font(DS.Font.make(11, .semibold))
                                .foregroundStyle(DS.Color.warning)
                            Text(String(format: "%.1f", rating))
                                .dsFont(.caption)
                                .foregroundStyle(DS.Color.text2)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Kennzahlen-Kacheln
    private var keyFacts: some View {
        HStack(spacing: DS.Spacing.xs) {
            DSTile(label: "Pay", value: job.payText, tone: .primary)
            DSTile(label: "Distance", value: job.distanceText.isEmpty ? "—" : job.distanceText, tone: .neutral)
            DSTile(
                label: "Open spots",
                value: job.openSpots.map { "\($0)" } ?? "–",
                tone: .success
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Zeit + Details (flach)
    private var timeInfoSection: some View {
        DSSection("When") {
            if let summary = multiShiftSummary {
                DSRow("Shifts", value: summary, systemIcon: "calendar")
            } else {
                DSRow("Shift", value: job.shiftText, systemIcon: "calendar")
                if let duration = job.duration {
                    DSRow("Duration", value: duration, systemIcon: "clock")
                }
            }
            if job.breakIncluded {
                DSRow("Break", value: job.breakMinutes.map { "\($0) min" } ?? "Included", systemIcon: "cup.and.saucer")
            }
            if job.locationType == "multiple" {
                DSRow("Locations", value: "Multiple", systemIcon: "mappin.and.ellipse")
            }
        }
    }

    /// "3 shifts · Nov 25–27" bei mehreren Schichten, sonst nil
    private var multiShiftSummary: String? {
        guard let shifts = job.shifts, shifts.count > 1 else { return nil }
        var text = "\(shifts.count) shifts"
        let dates = shifts.compactMap(\.startDate)
        if let first = dates.min(), let last = dates.max() {
            let cal = Calendar.current
            let month = first.formatted(.dateTime.month(.abbreviated).day())
            if cal.isDate(first, inSameDayAs: last) {
                text += " · \(month)"
            } else if cal.component(.month, from: first) == cal.component(.month, from: last) {
                text += " · \(month)–\(last.formatted(.dateTime.day()))"
            } else {
                text += " · \(month)–\(last.formatted(.dateTime.month(.abbreviated).day()))"
            }
        }
        return text
    }

    // MARK: - Kategorie + Tags
    @ViewBuilder
    private var categoryAndTagsSection: some View {
        if job.category != nil || !job.tags.isEmpty {
            DSFlowLayout(spacing: DS.Spacing.xs) {
                if let category = job.category {
                    DSBadge(category, .tone(.primary))
                }
                ForEach(job.tags, id: \.self) { tag in
                    DSBadge(tag, .completed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Schichten
    @ViewBuilder
    private var shiftsSection: some View {
        if let shifts = job.shifts, !shifts.isEmpty {
            DSSection("Shifts") {
                ForEach(shifts) { shift in
                    DSRow(
                        shift.date,
                        subtitle: "\(shift.timeRange) · \(shift.duration)",
                        value: shift.totalPay
                    )
                }
            }
        }
    }

    // MARK: - Beschreibung
    @ViewBuilder
    private var descriptionSection: some View {
        if let desc = job.jobDescription, !desc.isEmpty {
            DSSection("Job Description", ruled: false) {
                bodyText(desc)
            }
        }
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .dsFont(.body)
            .foregroundStyle(DS.Color.text2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, DS.Spacing.xxs)
    }

    // MARK: - Aufgaben
    @ViewBuilder
    private var tasksSection: some View {
        if let tasks = job.tasks, !tasks.isEmpty {
            DSSection("Tasks") {
                ForEach(Array(tasks.enumerated()), id: \.offset) { idx, task in
                    DSRow(task, systemIcon: "checkmark", iconTone: .success, showsDivider: idx > 0)
                }
            }
        }
    }

    // MARK: - Anforderungen
    @ViewBuilder
    private var requirementsSection: some View {
        let rows = requirementRows
        if !rows.isEmpty {
            DSSection("Requirements") {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    DSRow(row.label, value: row.value, showsDivider: idx > 0)
                }
            }
        }
    }

    /// Nur Zeilen mit Wert (Divider nur zwischen Zeilen)
    private var requirementRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let dressCode = job.dressCode { rows.append(("Dress Code", dressCode)) }
        if let langs = job.languages, !langs.isEmpty { rows.append(("Languages", langs.joined(separator: ", "))) }
        if let exp = job.experienceLevel { rows.append(("Experience", exp)) }
        if let age = job.minAge { rows.append(("Min. Age", "\(age)+")) }
        if !job.requiredSkills.isEmpty { rows.append(("Skills", job.requiredSkills.joined(separator: ", "))) }
        if !job.physicalRequirements.isEmpty { rows.append(("Physical", job.physicalRequirements.joined(separator: ", "))) }
        if !job.certifications.isEmpty { rows.append(("Certifications", job.certifications.joined(separator: ", "))) }
        if let edu = job.educationLevel { rows.append(("Education", edu)) }
        if job.workAuthorizationRequired { rows.append(("Work authorization", workAuthorizationStatusText)) }
        return rows
    }

    // MARK: - Verguetung & Vertrag
    private var payDetailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSSection("Pay & Contract") {
                DSRow("Hourly Rate", value: job.payText, showsDivider: false)
                if let method = job.paymentMethod {
                    DSRow("Payment Method", value: method)
                }
                if let type_ = job.contractType {
                    DSRow("Contract Type", value: type_)
                }
                ForEach(extraPayRows, id: \.label) { row in
                    DSRow(row.label, value: row.value)
                }
            }
            Text("You earn the full hourly rate — no fees deducted.")
                .dsFont(.caption)
                .foregroundStyle(DS.Color.muted)
        }
    }

    /// Optionale Zahlungs-Extras; nur Zeilen mit Wert
    private var extraPayRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if job.sameDayPay { rows.append(("Same-day pay", "Yes")) }
        if job.tipsIncluded { rows.append(("Tips", "Included")) }
        if job.bonusAvailable {
            let desc = job.bonusDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            rows.append(("Bonus", desc.isEmpty ? "Available" : desc))
        }
        if job.repeatWork { rows.append(("Repeat work", "Possible")) }
        return rows
    }

    /// Zeigt, ob das Profil des Workers die geforderte Arbeitserlaubnis angibt
    private var workAuthorizationStatusText: String {
        userStore.currentUser?.workAuthorization == true ? "Required (on your profile)" : "Required (not on your profile)"
    }

    // MARK: - Stornierung
    @ViewBuilder
    private var cancellationSection: some View {
        let notes = job.cancellationNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if job.cancellationPolicyLabel != nil || !notes.isEmpty {
            DSSection("Cancellation") {
                if let label = job.cancellationPolicyLabel {
                    DSRow("Policy", value: label, showsDivider: false)
                }
                if !notes.isEmpty {
                    DSRow("Notes", value: notes, showsDivider: job.cancellationPolicyLabel != nil)
                }
            }
        }
    }

    // MARK: - Hinweise vom Arbeitgeber
    @ViewBuilder
    private var employerNotesSection: some View {
        if let notes = job.jobNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            DSSection("Notes from the employer", ruled: false) {
                bodyText(notes)
            }
        }
    }

    // MARK: - Adresse + Kartenvorschau
    private var locationSection: some View {
        DSSection("Location", ruled: false) {
            DSRow(job.location, systemIcon: "mappin.and.ellipse", showsDivider: false)
            // Nur mit gueltigen Koordinaten; geteilt mit dem Firmenprofil
            LocationMapPreview(lat: job.lat, lng: job.lng, title: job.company)
                .padding(.top, DS.Spacing.xs)
        }
    }

    // MARK: - Unternehmen (Karte)
    private var companySection: some View {
        DSSection("Company", ruled: false) {
            NavigationLink {
                CompanyProfileView(companyName: job.company, logoEmoji: job.logoEmoji)
            } label: {
                DSCard {
                    HStack(spacing: DS.Spacing.sm) {
                        DSAvatar(text: job.logoEmoji, size: 48)

                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            HStack(spacing: DS.Spacing.xxs) {
                                Text(job.company)
                                    .dsFont(.headline)
                                    .foregroundStyle(DS.Color.text)
                                if job.isVerified == true {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(DS.Font.make(12, .semibold))
                                        .foregroundStyle(DS.Color.primaryText)
                                        .accessibilityLabel("Verified")
                                }
                            }

                            if let rating = job.companyRating {
                                HStack(spacing: DS.Spacing.xxs) {
                                    ForEach(0..<5) { i in
                                        Image(systemName: Double(i) < rating ? "star.fill" : "star")
                                            .font(DS.Font.make(11, .semibold))
                                            .foregroundStyle(DS.Color.warning)
                                    }
                                    Text(String(format: "%.1f", rating))
                                        .dsFont(.caption)
                                        .foregroundStyle(DS.Color.muted)
                                }
                                .accessibilityElement(children: .combine)
                            }

                            if let reply = job.replyTime {
                                Text(reply).dsFont(.caption).foregroundStyle(DS.Color.muted)
                            }
                            if let facts = companyFacts {
                                Text(facts).dsFont(.caption).foregroundStyle(DS.Color.muted)
                            }
                        }

                        Spacer(minLength: DS.Spacing.xs)

                        Image(systemName: "chevron.right")
                            .font(DS.Font.make(13, .semibold))
                            .foregroundStyle(DS.Color.muted)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.dsPressable)
        }
    }

    /// "Hospitality, Events · 12 completed shifts" aus Branche/Business Areas + Zaehlung des Backends
    private var companyFacts: String? {
        var parts: [String] = []
        let areas = job.companyBusinessAreas.isEmpty
            ? [job.companyIndustry].compactMap { $0 }
            : job.companyBusinessAreas
        if !areas.isEmpty { parts.append(areas.joined(separator: ", ")) }
        if let done = job.companyCompletedJobs {
            parts.append("\(done) completed shift\(done == 1 ? "" : "s")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Was passiert als Naechstes? (getoenter Block)
    private var whatHappensNextSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("What happens next?")
                .dsFont(.headline)
                .foregroundStyle(DS.Color.text)
            NextStepRow(number: "1", text: "The employer reviews your profile and availability.")
            NextStepRow(number: "2", text: "You receive a reply directly in the chat.")
            NextStepRow(number: "3", text: "No commitment until final confirmation.")
        }
        .padding(DS.Spacing.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.primarySoft, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    // MARK: - Sticky Apply-Leiste
    private var stickyApplyBar: some View {
        VStack(spacing: 0) {
            DSDivider()
            HStack(spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.payText)
                        .dsFont(.headline)
                        .foregroundStyle(DS.Color.text)
                    Text(job.openSpots.map { "\($0) spot\($0 == 1 ? "" : "s") available" } ?? "– spots available")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                }
                .layoutPriority(1)

                Button("Apply Now") {
                    showApplySheet = true
                }
                .buttonStyle(.ds(.primary))
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.vertical, DS.Spacing.sm)
        }
        .background(DS.Color.surface.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Hilfs-Views

private struct NextStepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Text(number)
                .font(DS.Font.make(13, .bold, relativeTo: .caption))
                .foregroundStyle(DS.Color.onPrimary)
                .frame(width: 24, height: 24)
                .background(DS.Color.primary, in: Circle())
                .accessibilityHidden(true)

            Text(text)
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

/// Flow-Layout fuer Tags (umbrechend), auch im Firmenprofil und Swipe genutzt
struct FlowTagsView: View {
    let tags: [String]

    var body: some View {
        DSFlowLayout(spacing: DS.Spacing.xs) {
            ForEach(tags, id: \.self) { tag in
                DSBadge(tag, .completed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Share-Inhalt

/// Baut Text + Link fuer den Share-Button im Job-Detail.
enum JobShareContent {
    /// Web-Link `https://swipeshift.app/jobs/<id>` — oeffnet als Universal Link die App (sobald das
    /// Associated-Domains-Entitlement gesetzt ist), sonst die Website-Fallback-Seite, die
    /// `swipeshift://job/<id>` oeffnet. Ausgewertet in `swipeShiftApp.jobId(from:)`.
    /// TODO: Universal Links aktivieren: Associated Domains `applinks:swipeshift.app` in Xcode
    /// (benoetigt bezahlten Apple-Developer-Account) + apple-app-site-association auf der Domain.
    static func url(for job: Job) -> URL {
        AppConfig.websiteURL.appendingPathComponent("jobs").appendingPathComponent(job.id)
    }

    static func message(for job: Job) -> String {
        let details = [job.payText, job.shiftText, job.location]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let headline = "Check out this job on SwipeShift: \(job.title) at \(job.company)"
        return details.isEmpty ? headline : "\(headline)\n\(details)"
    }
}
