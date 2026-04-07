//
//  CompanyProfileView.swift
//  swipeShift
//

import SwiftUI

// MARK: - CompanyProfileView

struct CompanyProfileView: View {
    let companyName: String
    let logoEmoji:   String         // Sofort sichtbar während API lädt

    @State private var profile:    CompanyProfileDTO? = nil
    @State private var isLoading   = true
    @State private var errorMsg:   String? = nil
    @State private var showAllReviews = false

    var body: some View {
        SubScreenShell(title: "Company Profile") {
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
                    if p.rating != nil { ratingsSection(p) }
                    if !p.locations.isEmpty { locationsSection(p) }
                    if let web = p.website, !web.isEmpty { contactSection(web) }
                    viewOpenJobsButton(p)
                    Spacer().frame(height: 20)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorMsg  = nil
        do {
            profile = try await APIClient.shared.fetchCompany(name: companyName)
        } catch {
            errorMsg = "Company profile could not be loaded."
        }
        isLoading = false
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

    // MARK: - Ratings (kein Review-Modell im MVP → nur Gesamt-Rating)

    private func ratingsSection(_ p: CompanyProfileDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RATING")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)

            if let rating = p.rating {
                HStack(spacing: 12) {
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.leading, 14)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 3) {
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: Double(i) <= rating ? "star.fill" : "star")
                                    .font(.system(size: 14)).foregroundColor(.yellow)
                            }
                        }
                        Text("Based on completed jobs")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
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

    private func contactSection(_ website: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CONTACT")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
            HStack(spacing: 14) {
                Image(systemName: "globe")
                    .font(.system(size: 15)).foregroundColor(SS.primary)
                    .frame(width: 28).padding(.leading, 14)
                Text(website)
                    .font(.system(size: 14)).foregroundColor(SS.primary)
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
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
