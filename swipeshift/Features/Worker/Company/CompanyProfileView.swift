//
//  CompanyProfileView.swift
//  swipeShift
//

import SwiftUI

// MARK: - CompanyProfileView

struct CompanyProfileView: View {
    let companyName: String
    let logoEmoji:   String         // Sofort sichtbar während API lädt

    @Environment(\.dismiss) private var dismiss

    @State private var profile:         CompanyProfileDTO? = nil
    @State private var isLoading        = true
    @State private var errorMsg:        String? = nil
    @State private var showAllReviews   = false
    @State private var expandedReviews  = false
    @State private var isSaved          = false
    @State private var isSaveLoading    = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if isLoading {
                loadingView
            } else if let errorMsg {
                VStack {
                    Spacer()
                    DSEmptyState(
                        systemIcon: "exclamationmark.circle",
                        title: "Something went wrong",
                        message: errorMsg
                    )
                    Spacer()
                }
            } else if let p = profile {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                        companyHeader(p)
                        if !p.businessAreas.isEmpty { areasSection(p) }
                        if let about = p.about, !about.isEmpty { aboutSection(about) }
                        ratingsSection(p)
                        if !p.locations.isEmpty { locationsSection(p) }
                        if p.hasAddress { CompanyAddressCard(company: p) }
                        if p.hasContactPerson || p.hasSocialLinks { CompanyPeopleAndLinksCard(company: p) }
                        if hasContact(p) { contactSection(p) }
                        viewOpenJobsButton(p)
                    }
                    .padding(.horizontal, DS.Spacing.screenEdge)
                    .padding(.top, DS.Spacing.xs)
                    .padding(.bottom, DS.Spacing.xxl)
                }
                .transition(.opacity)
            }
        }
        .dsBackground()
        .navigationBarHidden(true)
        .task { await load() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            DSIconButton(systemName: "chevron.left", label: "Back") { dismiss() }
            Spacer()
            Text("Company Profile")
                .dsFont(.headline)
                .foregroundStyle(DS.Color.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            bookmarkButton
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.vertical, DS.Spacing.xs)
    }

    private var bookmarkButton: some View {
        DSIconButton(
            systemName: isSaved ? "bookmark.fill" : "bookmark",
            label: isSaved ? "Remove from saved" : "Save company"
        ) { toggleSave() }
        .disabled(isSaveLoading)
    }

    // MARK: - Skeleton beim Laden

    private var loadingView: some View {
        VStack(spacing: DS.Spacing.md) {
            DSAvatar(text: logoEmoji, size: 88)
            DSSkeletonBlock(width: 180, height: 22)
            DSSkeletonBlock(width: 120, height: 14)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.xs) {
                ForEach(0..<4, id: \.self) { _ in
                    DSSkeletonBlock(height: 76, radius: DS.Radius.tile)
                }
            }
            .padding(.top, DS.Spacing.xs)
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.top, DS.Spacing.md)
        .accessibilityLabel("Loading company profile")
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorMsg  = nil
        do {
            async let profileFetch = APIClient.shared.fetchCompany(name: companyName)
            async let savedFetch   = APIClient.shared.fetchSavedCompanies()
            let (p, saved) = try await (profileFetch, savedFetch)
            profile = p
            isSaved = saved.contains { $0.companyName.lowercased() == companyName.lowercased() }
        } catch {
            errorMsg = "Company profile could not be loaded."
        }
        isLoading = false
    }

    private func toggleSave() {
        guard !isSaveLoading else { return }
        isSaveLoading = true
        let wasSaved = isSaved
        isSaved = !wasSaved
        Task {
            do {
                if wasSaved {
                    try await APIClient.shared.unsaveCompany(name: companyName)
                } else {
                    try await APIClient.shared.saveCompany(name: companyName)
                }
            } catch {
                isSaved = wasSaved
            }
            isSaveLoading = false
        }
    }

    // MARK: - Header

    private func companyHeader(_ p: CompanyProfileDTO) -> some View {
        VStack(spacing: DS.Spacing.md) {
            VStack(spacing: DS.Spacing.xs) {
                DSAvatar(text: p.logoEmoji, size: 88)

                HStack(spacing: DS.Spacing.xs) {
                    Text(p.name)
                        .dsFont(.title)
                        .foregroundStyle(DS.Color.text)
                        .multilineTextAlignment(.center)
                    if p.isVerified {
                        DSBadge("Verified", .tone(.primary))
                    }
                }
                if p.hasTaglineInfo {
                    CompanyTaglineView(tagline: p.tagline, yearFounded: p.yearFounded)
                }
                if let loc = p.locations.first {
                    Label(loc, systemImage: "mappin")
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.muted)
                }
                if let replyText = ResponseTimeText.make(hours: p.typicalResponseHours, fallback: p.replyTime) {
                    Label(replyText, systemImage: "clock")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                }
                // UX-Notiz (Notion): bei wenig Daten "New on platform" statt wackeliger Zahlen
                if p.responseRate == nil && p.typicalResponseHours == nil {
                    DSBadge("New on platform", .tone(.neutral))
                        .accessibilityHint("Not enough applications yet to show response statistics")
                }
            }
            .frame(maxWidth: .infinity)

            // Kennzahlen als getoente Kacheln
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Spacing.xs), GridItem(.flexible())], spacing: DS.Spacing.xs) {
                DSTile(label: "Jobs done", value: "\(p.completedJobs)+", tone: .primary)
                if let rating = p.rating {
                    DSTile(label: "Rating", value: String(format: "%.1f", rating), tone: .warning)
                }
                if let rate = p.responseRate {
                    DSTile(label: "Response rate", value: "\(Int((rate * 100).rounded()))%", tone: .success)
                }
                DSTile(label: "Open jobs", value: "\(p.activeJobs)", tone: .neutral)
            }
        }
    }

    // MARK: - Areas

    private func areasSection(_ p: CompanyProfileDTO) -> some View {
        FlowTagsView(tags: p.businessAreas)
    }

    // MARK: - About

    private func aboutSection(_ about: String) -> some View {
        DSSection("About the company", ruled: false) {
            Text(about)
                .dsFont(.body)
                .foregroundStyle(DS.Color.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Spacing.xxs)
        }
    }

    // MARK: - Ratings

    private func starName(_ i: Int, _ rating: Double) -> String {
        Double(i) <= rating ? "star.fill" : (Double(i) - 0.5 <= rating ? "star.leadinghalf.filled" : "star")
    }

    private func ratingsSection(_ p: CompanyProfileDTO) -> some View {
        DSSection("Ratings & Reviews", ruled: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // Overall score + Balken
                if let rating = p.rating {
                    HStack(spacing: DS.Spacing.md) {
                        VStack(spacing: DS.Spacing.xxs) {
                            Text(String(format: "%.1f", rating))
                                .font(DS.Font.make(40, .extrabold, relativeTo: .largeTitle))
                                .foregroundStyle(DS.Color.text)
                            HStack(spacing: 2) {
                                ForEach(1...5, id: \.self) { i in
                                    Image(systemName: starName(i, rating))
                                        .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                                        .foregroundStyle(DS.Color.warning)
                                }
                            }
                            .accessibilityHidden(true)
                            if let bd = p.reviewBreakdown {
                                Text("\(bd.totalReviews) review\(bd.totalReviews == 1 ? "" : "s")")
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Color.muted)
                            }
                        }
                        .fixedSize()

                        if let bd = p.reviewBreakdown {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                breakdownBar("Communication",    value: bd.communication)
                                breakdownBar("Payment",          value: bd.paymentFairness)
                                breakdownBar("Work Environment", value: bd.workEnvironment)
                                breakdownBar("Job Description",  value: bd.jobDescriptionAccuracy)
                                breakdownBar("Overall",          value: bd.overallExperience)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    VStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "star.slash")
                            .font(DS.Font.make(28, .regular, relativeTo: .title))
                            .foregroundStyle(DS.Color.muted)
                        Text("No reviews yet")
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                }

                // Anteil "would work here again" (Backend blendet bei < 3 Antworten aus)
                if let percent = p.wouldWorkAgainPercent {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(DS.Color.success)
                        Text("\(percent)% would work here again")
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.text)
                        Spacer(minLength: 0)
                    }
                    .padding(DS.Spacing.inset)
                    .background(DS.Color.successSoft, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }

                // Rating-Tags (Backend: nur bei >= 3 Bewertungen und Kategorie-Schnitt >= 4.5)
                if let tags = p.ratingTags, !tags.isEmpty {
                    FlowTagsView(tags: tags)
                }

                // Einzelne Bewertungen
                if let reviews = p.workerReviews, !reviews.isEmpty {
                    let shown = expandedReviews ? reviews : Array(reviews.prefix(2))
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(shown, id: \.id) { r in
                            reviewCard(r)
                        }
                    }

                    if reviews.count > 2 {
                        Button(expandedReviews ? "Show less" : "View all \(reviews.count) reviews") {
                            expandedReviews.toggle()
                        }
                        .buttonStyle(.ds(.soft, size: .medium))
                    }
                }
            }
            .dsAnimation(.standard, value: expandedReviews)
        }
    }

    private func breakdownBar(_ label: String, value: Double) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(label)
                .font(DS.Font.make(11, .medium, relativeTo: .caption2))
                .foregroundStyle(DS.Color.muted)
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Color.surface2)
                    Capsule().fill(DS.Color.primary)
                        .frame(width: geo.size.width * CGFloat(min(max(value / 5.0, 0), 1)))
                }
            }
            .frame(height: 6)
            Text(String(format: "%.1f", value))
                .font(DS.Font.make(11, .semibold, relativeTo: .caption2))
                .foregroundStyle(DS.Color.text2)
                .frame(width: 26, alignment: .trailing)
        }
    }

    private func reviewCard(_ r: WorkerReviewDTO) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.xs) {
                    DSAvatar(text: String(r.workerName.prefix(1)).uppercased(), size: 36, shape: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.workerName)
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.text)
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: i <= r.overallExperience ? "star.fill" : "star")
                                    .font(DS.Font.make(10, .semibold, relativeTo: .caption2))
                                    .foregroundStyle(DS.Color.warning)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(r.overallExperience) of 5 stars")
                    }
                    Spacer(minLength: DS.Spacing.xs)
                    Text(r.createdAt, style: .date)
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                }
                if let c = r.comment, !c.isEmpty {
                    Text(c)
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.text2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Locations

    private func locationsSection(_ p: CompanyProfileDTO) -> some View {
        DSSection("Locations") {
            ForEach(p.locations.indices, id: \.self) { i in
                DSRow(
                    p.locations[i],
                    systemIcon: i == 0 ? "building.2.fill" : "mappin.circle",
                    iconTone: i == 0 ? .primary : .neutral,
                    showsDivider: i > 0
                ) {
                    if i == 0 { DSBadge("HQ", .tone(.primary)) }
                }
            }
        }
    }

    // MARK: - Contact

    private func nonEmpty(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        return v
    }

    private func hasContact(_ p: CompanyProfileDTO) -> Bool {
        nonEmpty(p.phone) != nil || nonEmpty(p.email) != nil || nonEmpty(p.website) != nil
    }

    private func contactSection(_ p: CompanyProfileDTO) -> some View {
        let rows: [ContactRow] = [
            nonEmpty(p.phone).map { ContactRow(icon: "phone.fill", kind: "Phone", text: $0, url: ContactLink.phone($0)) },
            nonEmpty(p.email).map { ContactRow(icon: "envelope.fill", kind: "Email", text: $0, url: ContactLink.email($0)) },
            nonEmpty(p.website).map { ContactRow(icon: "globe", kind: "Website", text: $0, url: ContactLink.website($0)) }
        ].compactMap { $0 }

        return DSSection("Contact") {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                contactRow(row, showsDivider: index > 0)
            }
        }
    }

    @ViewBuilder
    private func contactRow(_ row: ContactRow, showsDivider: Bool) -> some View {
        let content = DSRow(
            row.kind, value: row.text, accentValue: row.url != nil,
            systemIcon: row.icon, showsDivider: showsDivider
        )
        if let url = row.url {
            Link(destination: url) { content }
                .buttonStyle(.dsPressable)
        } else {
            content
        }
    }

    // MARK: - Open Jobs Button

    private func viewOpenJobsButton(_ p: CompanyProfileDTO) -> some View {
        NavigationLink {
            JobListView(companyFilter: p.name)
        } label: {
            Label("View Open Jobs (\(p.activeJobs))", systemImage: "briefcase.fill")
        }
        .buttonStyle(.ds(.primary))
    }
}

// MARK: - Kontakt-Links

private struct ContactRow {
    let icon: String
    let kind: String
    let text: String
    let url: URL?
}

/// Baut tel:/mailto:/https-URLs aus frei eingegebenen Kontaktdaten des Employers.
enum ContactLink {
    static func phone(_ raw: String) -> URL? {
        // Nur Ziffern und fuehrendes "+" behalten (z.B. "+49 711 / 123-45" → "+4971112345")
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let prefix = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : ""
        return URL(string: "tel:\(prefix)\(digits)")
    }

    static func email(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@"), !trimmed.contains(" ") else { return nil }
        return URL(string: "mailto:\(trimmed)")
    }

    /// Feld heisst "websiteOrInstagram" — "@handle" wird zu instagram.com/handle,
    /// fehlendes Schema wird zu https:// ergaenzt.
    static func website(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if trimmed.hasPrefix("@") {
            return URL(string: "https://instagram.com/\(trimmed.dropFirst())")
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return URL(string: trimmed) }
        return URL(string: "https://\(trimmed)")
    }
}

// MARK: - Antwortzeit-Text

/// "Usually replies within …" aus der gemessenen Median-Antwortzeit, sonst statischer Fallback
enum ResponseTimeText {
    static func make(hours: Double?, fallback: String?) -> String? {
        guard let hours else {
            guard let fallback, !fallback.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return fallback
        }
        if hours < 1 { return "Usually replies within an hour" }
        if hours < 24 {
            let rounded = Int(hours.rounded(.up))
            return "Usually replies within \(rounded) hours"
        }
        let days = Int((hours / 24).rounded(.up))
        return days == 1 ? "Usually replies within a day" : "Usually replies within \(days) days"
    }
}
