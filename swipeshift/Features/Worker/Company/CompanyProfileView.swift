//
//  CompanyProfileView.swift
//  swipeShift
//

import SwiftUI

// MARK: - CompanyProfileView

struct CompanyProfileView: View {
    let companyName: String
    let logoEmoji:   String         // Sofort sichtbar während API lädt

    @State private var profile:         CompanyProfileDTO? = nil
    @State private var isLoading        = true
    @State private var errorMsg:        String? = nil
    @State private var showAllReviews   = false
    @State private var expandedReviews  = false
    @State private var isSaved          = false
    @State private var isSaveLoading    = false

    var body: some View {
        SubScreenShell(title: "Company Profile", trailing: { bookmarkButton }) {
            if isLoading {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else if let errorMsg {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.circle").font(.system(size: 40)).foregroundColor(.secondary)
                    Text(errorMsg).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            } else if let p = profile {
                VStack(spacing: 20) {
                    companyHeader(p)
                    if !p.businessAreas.isEmpty { areasSection(p) }
                    if let about = p.about, !about.isEmpty { aboutSection(about) }
                    ratingsSection(p)
                    if !p.locations.isEmpty { locationsSection(p) }
                    if hasContact(p) { contactSection(p) }
                    viewOpenJobsButton(p)
                    Spacer().frame(height: 20)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Bookmark Button

    private var bookmarkButton: some View {
        Button { toggleSave() } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isSaved ? SS.primary : .white)
                .padding(10)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
        }
        .disabled(isSaveLoading)
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
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Text(p.logoEmoji)
                    .font(.system(size: 48))
                    .frame(width: 90, height: 90)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                if p.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundColor(SS.primary)
                        .background(Color.white.clipShape(Circle()))
                        .offset(x: 4, y: 4)
                }
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(p.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    if p.isVerified {
                        Text("Verified")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(SS.primary).clipShape(Capsule())
                    }
                }
                if let loc = p.locations.first {
                    Label(loc, systemImage: "mappin")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                if let replyTime = p.replyTime {
                    Text(replyTime)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            HStack(spacing: 0) {
                CompanyStatCell(value: "\(p.completedJobs)+", label: "Jobs Done")
                if let rating = p.rating {
                    Divider().frame(height: 30).background(Color.white.opacity(0.3))
                    CompanyStatCell(value: String(format: "%.1f", rating), label: "Rating")
                }
                Divider().frame(height: 30).background(Color.white.opacity(0.3))
                CompanyStatCell(value: "\(p.activeJobs)", label: "Open Jobs")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Areas

    private func areasSection(_ p: CompanyProfileDTO) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(p.businessAreas, id: \.self) { area in
                    Text(area)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - About

    private func aboutSection(_ about: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ABOUT THE COMPANY")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
            Text(about)
                .font(.system(size: 14)).foregroundColor(.primary).lineSpacing(3)
                .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - Ratings

    private func ratingsSection(_ p: CompanyProfileDTO) -> some View {
        VStack(spacing: 0) {
            // Overall score header
            if let rating = p.rating {
                HStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.primary)
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: Double(i) <= rating ? "star.fill" : (Double(i) - 0.5 <= rating ? "star.leadinghalf.filled" : "star"))
                                    .font(.system(size: 12)).foregroundColor(.yellow)
                            }
                        }
                        if let bd = p.reviewBreakdown {
                            Text("\(bd.totalReviews) review\(bd.totalReviews == 1 ? "" : "s")")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 14)

                    if let bd = p.reviewBreakdown {
                        Divider().frame(height: 70)
                        VStack(alignment: .leading, spacing: 5) {
                            breakdownBar("Communication",       value: bd.communication)
                            breakdownBar("Payment",             value: bd.paymentFairness)
                            breakdownBar("Work Environment",    value: bd.workEnvironment)
                            breakdownBar("Job Description",     value: bd.jobDescriptionAccuracy)
                            breakdownBar("Overall",             value: bd.overallExperience)
                        }
                        .padding(.trailing, 14)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 28)).foregroundColor(.secondary.opacity(0.4))
                    Text("No reviews yet")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            // Individual review cards
            if let reviews = p.workerReviews, !reviews.isEmpty {
                Divider().padding(.horizontal, 14)
                Text("REVIEWS")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)

                let shown = expandedReviews ? reviews : Array(reviews.prefix(2))
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Divider().padding(.leading, 14) }
                    reviewCard(r)
                }

                if reviews.count > 2 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expandedReviews.toggle() }
                    } label: {
                        Text(expandedReviews ? "Show less" : "View all \(reviews.count) reviews")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SS.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private func breakdownBar(_ label: String, value: Double) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10)).foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3).fill(SS.primary.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(value / 5.0))
                }
            }
            .frame(height: 5)
            Text(String(format: "%.1f", value))
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
    }

    private func reviewCard(_ r: WorkerReviewDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(SS.primary.opacity(0.1)).frame(width: 34, height: 34)
                    Text(String(r.workerName.prefix(1)))
                        .font(.system(size: 14, weight: .bold)).foregroundColor(SS.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.workerName).font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= r.overallExperience ? "star.fill" : "star")
                                .font(.system(size: 10)).foregroundColor(.yellow)
                        }
                    }
                }
                Spacer()
                Text(r.createdAt, style: .date)
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            if let c = r.comment, !c.isEmpty {
                Text(c)
                    .font(.system(size: 13)).foregroundColor(.primary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: - Locations

    private func locationsSection(_ p: CompanyProfileDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LOCATIONS")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)

            ForEach(p.locations.indices, id: \.self) { i in
                HStack(spacing: 12) {
                    Image(systemName: i == 0 ? "building.2.fill" : "mappin.circle")
                        .font(.system(size: 16))
                        .foregroundColor(i == 0 ? SS.primary : .secondary)
                        .frame(width: 28).padding(.leading, 14)
                    Text(p.locations[i])
                        .font(.system(size: 14)).foregroundColor(.primary)
                    if i == 0 {
                        Text("HQ").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(SS.primary).clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                if i < p.locations.count - 1 { Divider().padding(.leading, 52) }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
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
            nonEmpty(p.phone).map { ContactRow(icon: "phone.fill", text: $0, url: ContactLink.phone($0)) },
            nonEmpty(p.email).map { ContactRow(icon: "envelope.fill", text: $0, url: ContactLink.email($0)) },
            nonEmpty(p.website).map { ContactRow(icon: "globe", text: $0, url: ContactLink.website($0)) }
        ].compactMap { $0 }

        return VStack(alignment: .leading, spacing: 0) {
            Text("CONTACT")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().padding(.leading, 56) }
                contactRow(icon: row.icon, text: row.text, url: row.url)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private func contactRow(icon: String, text: String, url: URL?) -> some View {
        let label = HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15)).foregroundColor(SS.primary)
                .frame(width: 28).padding(.leading, 14)
            Text(text)
                .font(.system(size: 14)).foregroundColor(url == nil ? .primary : SS.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())

        if let url {
            Link(destination: url) { label }
        } else {
            label
        }
    }

    // MARK: - Open Jobs Button

    private func viewOpenJobsButton(_ p: CompanyProfileDTO) -> some View {
        NavigationLink {
            JobListView(companyFilter: p.name)
        } label: {
            Label("View Open Jobs (\(p.activeJobs))", systemImage: "briefcase.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(SS.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

// MARK: - Sub-Views

private struct CompanyStatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            Text(label).font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Kontakt-Links

private struct ContactRow {
    let icon: String
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
