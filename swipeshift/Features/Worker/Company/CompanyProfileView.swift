//
//  CompanyProfileView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Company Model (Mock bis Backend-Endpunkt GET /companies/:id existiert)

struct CompanyProfile {
    let name: String
    let logoEmoji: String
    let isVerified: Bool
    let location: String
    let overallRating: Double
    let reviewCount: Int
    let completedJobs: Int
    let businessAreas: [String]
    let about: String
    let phone: String?
    let email: String?
    let website: String?
    let locations: [(name: String, isHQ: Bool)]
    let ratingTags: [String]
    // Rating-Aufschlüsselung
    let communicationRating: Double
    let paymentFairnessRating: Double
    let workEnvironmentRating: Double
    let jobDescriptionAccuracy: Double
    let overallExperience: Double

    // Mock-Daten basierend auf Unternehmensname
    static func mock(name: String, logoEmoji: String, rating: Double?) -> CompanyProfile {
        CompanyProfile(
            name: name,
            logoEmoji: logoEmoji,
            isVerified: true,
            location: "Berlin, Deutschland",
            overallRating: rating ?? 4.4,
            reviewCount: 38,
            completedJobs: 124,
            businessAreas: ["Events", "Hospitality", "Customer Service"],
            about: "\(name) is one of the leading providers of flexible staffing in the region. We offer short-term assignments across various sectors and place great value on fair pay and professional working conditions.",
            phone: "+49 30 123 456 78",
            email: "jobs@\(name.lowercased().replacingOccurrences(of: " ", with: "")).de",
            website: "www.\(name.lowercased().replacingOccurrences(of: " ", with: "")).de",
            locations: [
                ("Berlin Mitte (HQ)", true),
                ("Berlin Prenzlauer Berg", false),
                ("Hamburg", false),
            ],
            ratingTags: ["Friendly Team", "Fair Pay", "Good Communication", "Flexible Hours", "On-time Payment"],
            communicationRating: 4.5,
            paymentFairnessRating: 4.2,
            workEnvironmentRating: 4.6,
            jobDescriptionAccuracy: 4.3,
            overallExperience: rating ?? 4.4
        )
    }
}

// MARK: - Mock Review für Unternehmen

private struct CompanyReview: Identifiable {
    let id = UUID()
    let workerName: String
    let jobType: String
    let date: String
    let rating: Double
    let comment: String
}

// MARK: - CompanyProfileView

struct CompanyProfileView: View {
    let company: CompanyProfile

    @State private var showAllReviews = false

    private let mockReviews: [CompanyReview] = [
        CompanyReview(workerName: "Max M.", jobType: "Bartender", date: "Mar 2026",
                      rating: 5.0, comment: "Great organisation, punctual payment. Highly recommended!"),
        CompanyReview(workerName: "Laura K.", jobType: "Event Staff", date: "Feb 2026",
                      rating: 4.0, comment: "Nice team, good briefing. Would recommend."),
        CompanyReview(workerName: "Tom S.", jobType: "Catering", date: "Jan 2026",
                      rating: 4.5, comment: "Fair pay, friendly atmosphere."),
    ]

    var body: some View {
        SubScreenShell(title: "Company Profile") {
            VStack(spacing: 20) {
                companyHeader
                ratingTagsSection
                aboutSection
                ratingsBreakdown
                reviewsSection
                locationsSection
                contactSection
                viewOpenJobsButton
                Spacer().frame(height: 20)
            }
        }
    }

    // MARK: - Header

    private var companyHeader: some View {
        VStack(spacing: 14) {
            // Logo
            ZStack(alignment: .bottomTrailing) {
                Text(company.logoEmoji)
                    .font(.system(size: 48))
                    .frame(width: 90, height: 90)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                if company.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundColor(SS.primary)
                        .background(Color.white.clipShape(Circle()))
                        .offset(x: 4, y: 4)
                }
            }

            // Name + Location
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(company.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    if company.isVerified {
                        Text("Verified")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(SS.primary)
                            .clipShape(Capsule())
                    }
                }

                Label(company.location, systemImage: "mappin")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }

            // Stats Row
            HStack(spacing: 0) {
                CompanyStatCell(value: "\(company.completedJobs)+", label: "Jobs Done")
                Divider().frame(height: 30).background(Color.white.opacity(0.3))
                CompanyStatCell(
                    value: String(format: "%.1f", company.overallRating),
                    label: "\(company.reviewCount) Reviews"
                )
                Divider().frame(height: 30).background(Color.white.opacity(0.3))
                CompanyStatCell(value: company.businessAreas.count.description, label: "Areas")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rating Tags

    private var ratingTagsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(company.ratingTags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.system(size: 10))
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ABOUT THE COMPANY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(company.about)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                Divider().padding(.horizontal, 14)

                // Business Areas
                VStack(alignment: .leading, spacing: 6) {
                    Text("Areas")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        ForEach(company.businessAreas, id: \.self) { area in
                            Text(area)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(SS.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(SS.primary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - Ratings Breakdown

    private var ratingsBreakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BEWERTUNGEN & REVIEWS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                RatingBarRow(label: "Communication",        rating: company.communicationRating)
                Divider().padding(.leading, 14)
                RatingBarRow(label: "Payment Fairness",     rating: company.paymentFairnessRating)
                Divider().padding(.leading, 14)
                RatingBarRow(label: "Work Environment",     rating: company.workEnvironmentRating)
                Divider().padding(.leading, 14)
                RatingBarRow(label: "Job Description",      rating: company.jobDescriptionAccuracy)
                Divider().padding(.leading, 14)
                RatingBarRow(label: "Overall Experience",   rating: company.overallExperience)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - Reviews

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("REVIEWS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)

            let displayed = showAllReviews ? mockReviews : Array(mockReviews.prefix(2))
            ForEach(displayed) { review in
                CompanyReviewCard(review: review)
            }
            .padding(.horizontal, 16)

            if mockReviews.count > 2 {
                Button {
                    withAnimation { showAllReviews.toggle() }
                } label: {
                    Text(showAllReviews ? "Weniger anzeigen" : "Alle \(mockReviews.count) Reviews")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SS.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            }
        }
    }

    // MARK: - Locations

    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STANDORTE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(company.locations.indices, id: \.self) { i in
                let loc = company.locations[i]
                HStack(spacing: 12) {
                    Image(systemName: loc.isHQ ? "building.2.fill" : "mappin.circle")
                        .font(.system(size: 16))
                        .foregroundColor(loc.isHQ ? SS.primary : .secondary)
                        .frame(width: 28)
                        .padding(.leading, 14)
                    Text(loc.name)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                    if loc.isHQ {
                        Text("HQ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SS.primary)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                if i < company.locations.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - Contact

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("KONTAKT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            if let phone = company.phone {
                ContactRow(icon: "phone.fill", label: phone)
                Divider().padding(.leading, 52)
            }
            if let email = company.email {
                ContactRow(icon: "envelope.fill", label: email)
                Divider().padding(.leading, 52)
            }
            if let web = company.website {
                ContactRow(icon: "globe", label: web, color: SS.primary)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - View Open Jobs Button

    private var viewOpenJobsButton: some View {
        NavigationLink {
            // TODO: JobListView(companyFilter: company.name)
            // Zeigt gefilterte Job-Liste dieses Unternehmens
            Text("Jobs von \(company.name)")
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SS.background().ignoresSafeArea())
        } label: {
            Label("Offene Jobs ansehen", systemImage: "briefcase.fill")
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
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RatingBarRow: View {
    let label: String
    let rating: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .frame(width: 140, alignment: .leading)
                .padding(.leading, 14)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4).fill(SS.primary)
                        .frame(width: geo.size.width * CGFloat(rating / 5.0))
                }
            }
            .frame(height: 7)

            Text(String(format: "%.1f", rating))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 28)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 11)
    }
}

private struct CompanyReviewCard: View {
    let review: CompanyReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.workerName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("\(review.jobType) · \(review.date)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: Double(i) <= review.rating ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                    }
                }
            }
            Text("\"\(review.comment)\"")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(14)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

private struct ContactRow: View {
    let icon: String
    let label: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(SS.primary)
                .frame(width: 28)
                .padding(.leading, 14)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(color == .secondary ? .primary : color)
            Spacer()
        }
        .padding(.vertical, 12)
    }
}
