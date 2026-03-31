//
//  ReviewsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Mock Review

private struct WorkerReview: Identifiable {
    let id = UUID()
    let companyName: String
    let jobType: String
    let date: String
    let overallRating: Double
    let feedback: String
    let communication: Int
    let teamwork: Int
    let reliability: Int
    let underPressure: Int
}

// MARK: - ReviewsView

struct ReviewsView: View {
    // TODO: aus Backend laden (GET /users/:id/reviews)
    private let overallRating: Double = 4.6
    private let totalJobs: Int = 23

    private let reviews: [WorkerReview] = [
        WorkerReview(companyName: "Club Tresor", jobType: "Bartender",
                     date: "Mar 15, 2026", overallRating: 5.0,
                     feedback: "Super reliable and friendly. Would hire again!",
                     communication: 5, teamwork: 5, reliability: 5, underPressure: 4),
        WorkerReview(companyName: "Eventify GmbH", jobType: "Event Staff",
                     date: "Mar 10, 2026", overallRating: 4.0,
                     feedback: "Did a great job, was punctual.",
                     communication: 4, teamwork: 4, reliability: 5, underPressure: 3),
        WorkerReview(companyName: "GourmetEvents", jobType: "Catering Staff",
                     date: "Feb 28, 2026", overallRating: 4.5,
                     feedback: "Very professional and helpful.",
                     communication: 4, teamwork: 5, reliability: 5, underPressure: 4),
        WorkerReview(companyName: "LogiCore", jobType: "Warehouse",
                     date: "Feb 20, 2026", overallRating: 4.0,
                     feedback: "Good performance, sometimes a little slow.",
                     communication: 3, teamwork: 4, reliability: 4, underPressure: 4),
        WorkerReview(companyName: "FashionHub", jobType: "Retail Assistant",
                     date: "Feb 5, 2026", overallRating: 5.0,
                     feedback: "Excellent! Best temp worker we've had.",
                     communication: 5, teamwork: 5, reliability: 5, underPressure: 5),
    ]

    @State private var showAllReviews = false

    private var avgCommunication: Double { avg(reviews.map { Double($0.communication) }) }
    private var avgTeamwork:      Double { avg(reviews.map { Double($0.teamwork) }) }
    private var avgReliability:   Double { avg(reviews.map { Double($0.reliability) }) }
    private var avgUnderPressure: Double { avg(reviews.map { Double($0.underPressure) }) }

    var body: some View {
        SubScreenShell(title: "Your Ratings") {
            VStack(spacing: 20) {
                overallSection
                skillsSection
                reviewsSection
            }
        }
    }

    // MARK: - Overall Rating

    private var overallSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", overallRating))
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.primary)
                    Text("von 5")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    starsRow(rating: overallRating, size: 22)
                    Text("Basierend auf \(totalJobs) Jobs")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    // Rating distribution (mini bars)
                    VStack(spacing: 3) {
                        ForEach([5, 4, 3, 2, 1], id: \.self) { star in
                            HStack(spacing: 6) {
                                Text("\(star)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .frame(width: 8)
                                let fraction = ratingFraction(star: star)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.gray.opacity(0.15))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.yellow)
                                            .frame(width: geo.size.width * fraction)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                    .frame(width: 120)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - Skills Breakdown

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Skills Performance")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            SkillBar(label: "Communication",          rating: avgCommunication)
            Divider().padding(.leading, 14)
            SkillBar(label: "Teamwork",               rating: avgTeamwork)
            Divider().padding(.leading, 14)
            SkillBar(label: "Reliability",            rating: avgReliability)
            Divider().padding(.leading, 14)
            SkillBar(label: "Working under Pressure", rating: avgUnderPressure)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - Reviews List

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reviews")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)

            let displayedReviews = showAllReviews ? reviews : Array(reviews.prefix(3))
            ForEach(displayedReviews) { review in
                ReviewCard(review: review)
            }
            .padding(.horizontal, 16)

            if reviews.count > 3 {
                Button {
                    withAnimation { showAllReviews.toggle() }
                } label: {
                    Text(showAllReviews ? "Show less" : "All \(reviews.count) Reviews")
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

    // MARK: - Helpers

    private func avg(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func ratingFraction(star: Int) -> CGFloat {
        let count = reviews.filter { Int($0.overallRating.rounded()) == star }.count
        return CGFloat(count) / CGFloat(max(reviews.count, 1))
    }

    private func starsRow(rating: Double, size: CGFloat) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= rating ? "star.fill" :
                      (Double(i) - 0.5 <= rating ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: size))
                    .foregroundColor(.yellow)
            }
        }
    }
}

// MARK: - Skill Bar

private struct SkillBar: View {
    let label: String
    let rating: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .frame(width: 150, alignment: .leading)
                .padding(.leading, 14)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SS.primary)
                        .frame(width: geo.size.width * (rating / 5.0))
                }
            }
            .frame(height: 8)

            Text(String(format: "%.1f", rating))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 30)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Review Card

private struct ReviewCard: View {
    let review: WorkerReview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.companyName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("\(review.jobType) · \(review.date)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: Double(i) <= review.overallRating ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                    }
                }
            }

            if !review.feedback.isEmpty {
                Text("\"\(review.feedback)\"")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .italic()
            }

            // Skill mini-ratings
            HStack(spacing: 12) {
                MiniSkill(label: "Comm.", value: review.communication)
                MiniSkill(label: "Team", value: review.teamwork)
                MiniSkill(label: "Rely.", value: review.reliability)
                MiniSkill(label: "Press.", value: review.underPressure)
            }
        }
        .padding(14)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

private struct MiniSkill: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(SS.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}
