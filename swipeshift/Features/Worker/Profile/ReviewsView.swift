//
//  ReviewsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - ReviewsView

struct ReviewsView: View {
    @State private var reviewsData: WorkerReviewsResponse? = nil
    @State private var isLoading      = false
    @State private var errorMessage: String? = nil
    @State private var showAllReviews = false

    private var reviews: [WorkerReviewItem] { reviewsData?.reviews ?? [] }

    private var avgCommunication: Double { avg(reviews.map { Double($0.communication) }) }
    private var avgTeamwork:      Double { avg(reviews.map { Double($0.teamwork) }) }
    private var avgReliability:   Double { avg(reviews.map { Double($0.reliability) }) }
    private var avgUnderPressure: Double { avg(reviews.map { Double($0.underPressure) }) }

    var body: some View {
        SubScreenShell(title: "Your Ratings") {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
            } else if let err = errorMessage {
                VStack(spacing: 12) {
                    Text(err).font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Button("Retry") { Task { await load() } }
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(SS.primary)
                }.padding(.top, 60)
            } else if reviews.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 44)).foregroundColor(.white.opacity(0.3))
                    Text("No reviews yet")
                        .font(.system(size: 15)).foregroundColor(.white.opacity(0.5))
                }.frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                VStack(spacing: 20) {
                    overallSection
                    skillsSection
                    reviewsSection
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Overall Rating

    private var overallSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", reviewsData?.overallRating ?? 0))
                        .font(.system(size: 48, weight: .bold)).foregroundColor(.primary)
                    Text("von 5")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    starsRow(rating: reviewsData?.overallRating ?? 0, size: 22)
                    Text("Basierend auf \(reviewsData?.totalJobs ?? 0) Jobs")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                    VStack(spacing: 3) {
                        ForEach([5, 4, 3, 2, 1], id: \.self) { star in
                            HStack(spacing: 6) {
                                Text("\(star)")
                                    .font(.system(size: 10)).foregroundColor(.secondary).frame(width: 8)
                                let fraction = ratingFraction(star: star)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.15))
                                        RoundedRectangle(cornerRadius: 2).fill(.yellow)
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
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
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
                .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 16)

            let displayed = showAllReviews ? reviews : Array(reviews.prefix(3))
            ForEach(displayed) { review in
                ReviewCard(review: review)
            }
            .padding(.horizontal, 16)

            if reviews.count > 3 {
                Button { withAnimation { showAllReviews.toggle() } } label: {
                    Text(showAllReviews ? "Show less" : "All \(reviews.count) Reviews")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(SS.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
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

    private func load() async {
        isLoading = true; errorMessage = nil
        do { reviewsData = try await APIClient.shared.fetchWorkerReviews() }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func avg(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func ratingFraction(star: Int) -> CGFloat {
        let count = reviews.filter { Int($0.avgRating.rounded()) == star }.count
        return CGFloat(count) / CGFloat(max(reviews.count, 1))
    }

    private func starsRow(rating: Double, size: CGFloat) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= rating ? "star.fill" :
                      (Double(i) - 0.5 <= rating ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: size)).foregroundColor(.yellow)
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
            Text(label).font(.system(size: 14)).foregroundColor(.primary)
                .frame(width: 150, alignment: .leading).padding(.leading, 14)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4).fill(SS.primary)
                        .frame(width: geo.size.width * (rating / 5.0))
                }
            }
            .frame(height: 8)
            Text(String(format: "%.1f", rating))
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                .frame(width: 30).padding(.trailing, 14)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Review Card

private struct ReviewCard: View {
    let review: WorkerReviewItem
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.companyName)
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                    Text("\(review.jobType) · \(review.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: Double(i) <= review.avgRating ? "star.fill" : "star")
                            .font(.system(size: 12)).foregroundColor(.yellow)
                    }
                }
            }
            if !review.feedback.isEmpty {
                Text("\"\(review.feedback)\"")
                    .font(.system(size: 13)).foregroundColor(.secondary).italic()
            }
            HStack(spacing: 12) {
                MiniSkill(label: "Comm.",  value: review.communication)
                MiniSkill(label: "Team",   value: review.teamwork)
                MiniSkill(label: "Rely.",  value: review.reliability)
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
    let label: String; let value: Int
    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(size: 13, weight: .bold)).foregroundColor(SS.primary)
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }
}
