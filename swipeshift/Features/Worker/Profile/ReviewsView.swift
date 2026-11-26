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
    /// nil, solange keine Bewertung "Work quality" enthaelt (Bestandsdaten) → Durchschnitt nur ueber vorhandene Werte
    private var avgWorkQuality: Double? {
        let values = reviews.compactMap { $0.workQuality }.filter { $0 > 0 }
        return values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
    }
    private var topWorkerCount: Int { reviewsData?.topWorkerCount ?? reviews.filter(\.isTopWorker).count }

    var body: some View {
        SubScreenShell(title: "Your Ratings", padded: true) {
            if isLoading && reviewsData == nil {
                VStack(spacing: DS.Spacing.md) {
                    DSSkeletonBlock(height: 140, radius: DS.Radius.card)
                    DSSkeletonBlock(height: 160, radius: DS.Radius.card)
                    DSSkeletonBlock(height: 100, radius: DS.Radius.card)
                }
                .accessibilityLabel("Loading ratings")
            } else if let err = errorMessage {
                VStack(spacing: DS.Spacing.sm) {
                    Text(err).dsFont(.callout).foregroundStyle(DS.Color.muted)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Spacing.xxl)
            } else if reviews.isEmpty {
                DSEmptyState(systemIcon: "star.slash", title: "No reviews yet",
                             message: "Ratings from employers will show up here after your jobs.")
            } else {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    overallSection
                    skillsSection
                    reviewsSection
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: - Overall Rating

    private var overallSection: some View {
        DSCard {
            HStack(spacing: DS.Spacing.xl) {
                VStack(spacing: DS.Spacing.xxs) {
                    Text(String(format: "%.1f", reviewsData?.overallRating ?? 0))
                        .font(DS.Font.make(48, .extrabold, relativeTo: .largeTitle)).foregroundStyle(DS.Color.text)
                    Text("von 5")
                        .dsFont(.callout).foregroundStyle(DS.Color.muted)
                }
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    starsRow(rating: reviewsData?.overallRating ?? 0, size: 20)
                    Text("Basierend auf \(reviewsData?.totalJobs ?? 0) Jobs")
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                    if topWorkerCount > 0 {
                        TopWorkerBadge(text: "Top Worker ×\(topWorkerCount)")
                    }
                    VStack(spacing: 3) {
                        ForEach([5, 4, 3, 2, 1], id: \.self) { star in
                            HStack(spacing: DS.Spacing.xs) {
                                Text("\(star)")
                                    .font(DS.Font.make(10, .medium, relativeTo: .caption2)).foregroundStyle(DS.Color.muted).frame(width: 8)
                                let fraction = ratingFraction(star: star)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(DS.Color.surface2)
                                        Capsule().fill(DS.Color.warning)
                                            .frame(width: geo.size.width * fraction)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Skills Breakdown

    private var skillsSection: some View {
        DSSection("Skills Performance") {
            SkillBar(label: "Communication",          rating: avgCommunication, showsDivider: false)
            SkillBar(label: "Teamwork",               rating: avgTeamwork)
            SkillBar(label: "Reliability",            rating: avgReliability)
            SkillBar(label: "Working under Pressure", rating: avgUnderPressure)
            if let quality = avgWorkQuality {
                SkillBar(label: "Work Quality", rating: quality)
            }
        }
    }

    // MARK: - Reviews List

    private var reviewsSection: some View {
        DSSection("Reviews", ruled: false) {
            VStack(spacing: DS.Spacing.sm) {
                let displayed = showAllReviews ? reviews : Array(reviews.prefix(3))
                ForEach(displayed) { review in
                    ReviewCard(review: review)
                }

                if reviews.count > 3 {
                    Button {
                        showAllReviews.toggle()
                    } label: {
                        Text(showAllReviews ? "Show less" : "All \(reviews.count) Reviews")
                    }
                    .buttonStyle(.ds(.soft, size: .medium))
                }
            }
            .padding(.top, DS.Spacing.xxs)
            .dsAnimation(.standard, value: showAllReviews)
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
                    .font(.system(size: size)).foregroundStyle(DS.Color.warning)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating \(String(format: "%.1f", rating)) of 5")
    }
}

// MARK: - Skill Bar

private struct SkillBar: View {
    let label: String
    let rating: Double
    var showsDivider: Bool = true
    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(label).dsFont(.body).foregroundStyle(DS.Color.text)
                .frame(width: 150, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Color.surface2)
                    Capsule().fill(DS.Color.primary)
                        .frame(width: geo.size.width * (rating / 5.0))
                }
            }
            .frame(height: 8)
            Text(String(format: "%.1f", rating))
                .font(DS.Font.make(13, .semibold, relativeTo: .footnote)).foregroundStyle(DS.Color.text2)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .overlay(alignment: .top) { if showsDivider { DSDivider() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%.1f of 5", rating))
    }
}

// MARK: - Review Card

private struct ReviewCard: View {
    let review: WorkerReviewItem
    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(review.companyName)
                            .dsFont(.callout).foregroundStyle(DS.Color.text)
                        if review.isTopWorker { TopWorkerBadge(text: "Top Worker") }
                        Text("\(review.jobType) · \(review.date.formatted(date: .abbreviated, time: .omitted))")
                            .dsFont(.caption).foregroundStyle(DS.Color.muted)
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: Double(i) <= review.avgRating ? "star.fill" : "star")
                                .font(.system(size: 12)).foregroundStyle(DS.Color.warning)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(String(format: "%.1f", review.avgRating)) of 5 stars")
                }
                if !review.feedback.isEmpty {
                    Text("\"\(review.feedback)\"")
                        .dsFont(.body).foregroundStyle(DS.Color.text2).italic()
                }
                HStack(spacing: DS.Spacing.md) {
                    MiniSkill(label: "Comm.",  value: review.communication)
                    MiniSkill(label: "Team",   value: review.teamwork)
                    MiniSkill(label: "Rely.",  value: review.reliability)
                    MiniSkill(label: "Press.", value: review.underPressure)
                    if let quality = review.workQuality { MiniSkill(label: "Quality", value: quality) }
                }
            }
        }
    }
}

private struct MiniSkill: View {
    let label: String; let value: Int
    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(DS.Font.make(13, .bold, relativeTo: .footnote)).foregroundStyle(DS.Color.primaryText)
            Text(label).font(DS.Font.make(10, .medium, relativeTo: .caption2)).foregroundStyle(DS.Color.muted)
        }
    }
}

/// Auszeichnung "Top Worker" (Arbeitgeber hat die Leistung hervorgehoben)
struct TopWorkerBadge: View {
    let text: String
    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(systemName: "star.circle.fill").font(.system(size: 11))
            Text(text).font(DS.Font.make(11, .bold, relativeTo: .caption2))
        }
        .foregroundStyle(DS.Tone.warning.foreground)
        .padding(.horizontal, DS.Spacing.xs).padding(.vertical, 3)
        .background(DS.Tone.warning.soft, in: Capsule())
        .accessibilityLabel(text)
    }
}
