//
//  LeaveReviewsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Models

struct PendingReview: Identifiable {
    let id: String
    let workerName: String
    let workerPhoto: String?
    let jobTitle: String
    let jobCategory: String
    let shiftDate: Date
    let logoEmoji: String

    // Wird gesetzt sobald Bewertung abgegeben
    var draft: ReviewDraft?
}

struct ReviewDraft: Identifiable {
    let id: String
    var communication: Int    // 1–5
    var teamwork: Int
    var reliability: Int
    var underPressure: Int
    var comment: String
    var wouldRehire: Bool
    var savedAt: Date
}

// MARK: - LeaveReviewsView

struct LeaveReviewsView: View {
    @State private var selectedTab: ReviewTab = .pending
    @State private var pendingReviews: [PendingReview] = mockPendingReviews
    @State private var showSortSheet  = false
    @State private var showFilterSheet = false
    @State private var selectedSort: ReviewSort = .mostRecent
    @State private var filterRating: Int? = nil          // nil = alle
    @State private var filterWouldRehire: Bool? = nil
    @State private var reviewToEdit: PendingReview? = nil

    enum ReviewTab: String, CaseIterable {
        case pending = "Pending"
        case drafts  = "Drafts"
        case past    = "Past Reviews"
    }

    enum ReviewSort: String, CaseIterable {
        case mostRecent    = "Most Recent"
        case highestRating = "Highest Rating"
        case lowestRating  = "Lowest Rating"
    }

    // Filtert abgeschlossene Bewertungen (draft.comment vorhanden)
    private var completedReviews: [PendingReview] {
        pendingReviews.filter { $0.draft != nil }
    }
    private var draftReviews: [PendingReview] {
        pendingReviews.filter { $0.draft == nil }
    }
    private var pendingOnly: [PendingReview] {
        pendingReviews.filter { $0.draft == nil }
    }

    private var displayedReviews: [PendingReview] {
        var list: [PendingReview]
        switch selectedTab {
        case .pending: list = pendingOnly
        case .drafts:  list = draftReviews
        case .past:    list = completedReviews
        }
        // Filter
        if let minRating = filterRating {
            list = list.filter { ($0.draft?.avgRating ?? 0) >= Double(minRating) }
        }
        if let rehire = filterWouldRehire {
            list = list.filter { ($0.draft?.wouldRehire ?? false) == rehire }
        }
        // Sort
        switch selectedSort {
        case .mostRecent:
            list.sort { $0.shiftDate > $1.shiftDate }
        case .highestRating:
            list.sort { ($0.draft?.avgRating ?? 0) > ($1.draft?.avgRating ?? 0) }
        case .lowestRating:
            list.sort { ($0.draft?.avgRating ?? 5) < ($1.draft?.avgRating ?? 5) }
        }
        return list
    }

    private var activeFilters: Int {
        (filterRating != nil ? 1 : 0) + (filterWouldRehire != nil ? 1 : 0)
    }

    var body: some View {
        SubScreenShell(title: "Leave Reviews") {
            VStack(spacing: 0) {
                // Tabs
                tabBar
                    .padding(.bottom, 12)

                // Sort + Filter Row
                HStack(spacing: 8) {
                    Button { showSortSheet = true } label: {
                        sortFilterChip(
                            icon: "arrow.up.arrow.down",
                            label: selectedSort.rawValue,
                            active: selectedSort != .mostRecent
                        )
                    }
                    .buttonStyle(.plain)

                    Button { showFilterSheet = true } label: {
                        sortFilterChip(
                            icon: "line.3.horizontal.decrease.circle",
                            label: activeFilters > 0 ? "Filter (\(activeFilters))" : "Filter",
                            active: activeFilters > 0
                        )
                    }
                    .buttonStyle(.plain)

                    if activeFilters > 0 {
                        Button { clearFilters() } label: {
                            Text("Reset")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.red.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // Content
                if displayedReviews.isEmpty {
                    emptyView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(displayedReviews) { review in
                                switch selectedTab {
                                case .pending, .drafts:
                                    PendingReviewCard(review: review) {
                                        reviewToEdit = review
                                    }
                                case .past:
                                    PastReviewCard(review: review)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .sheet(isPresented: $showSortSheet) { sortSheet }
        .sheet(isPresented: $showFilterSheet) { filterSheet }
        .sheet(item: $reviewToEdit) { review in
            ReviewFormSheet(review: review) { draft in
                if let idx = pendingReviews.firstIndex(where: { $0.id == review.id }) {
                    pendingReviews[idx].draft = draft
                }
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ReviewTab.allCases, id: \.self) { tab in
                let count = countFor(tab)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .bold : .regular))
                                .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(selectedTab == tab ? SS.primary : .white.opacity(0.4))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(selectedTab == tab ? Color.white : Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        Rectangle()
                            .fill(selectedTab == tab ? Color.white : Color.clear)
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func countFor(_ tab: ReviewTab) -> Int {
        switch tab {
        case .pending: return pendingOnly.count
        case .drafts:  return draftReviews.count
        case .past:    return completedReviews.count
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "star.slash")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.3))
            Text("No Reviews")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("Completed shifts will appear here for review.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Sort Sheet

    private var sortSheet: some View {
        VStack(spacing: 0) {
            Text("Sort")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 12)

            ForEach(ReviewSort.allCases, id: \.self) { option in
                Button {
                    selectedSort = option
                    showSortSheet = false
                } label: {
                    HStack {
                        Text(option.rawValue)
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedSort == option {
                            Image(systemName: "checkmark")
                                .foregroundColor(SS.primary)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 24)
            }
            Spacer()
        }
        .presentationDetents([.fraction(0.4)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Filter Sheet

    private var filterSheet: some View {
        VStack(spacing: 0) {
            Text("Filter")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Rating Filter
            VStack(alignment: .leading, spacing: 10) {
                Text("Minimum Rating")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    ForEach([1, 2, 3, 4, 5], id: \.self) { stars in
                        Button {
                            filterRating = filterRating == stars ? nil : stars
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                Text("\(stars)+")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(filterRating == stars ? .white : SS.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(filterRating == stars ? SS.primary : SS.primary.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)

            Divider()

            // Would Rehire Filter
            VStack(alignment: .leading, spacing: 10) {
                Text("Would Rehire")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                HStack(spacing: 8) {
                    ForEach([(true, "Yes"), (false, "No")], id: \.0) { (val, label) in
                        Button {
                            filterWouldRehire = filterWouldRehire == val ? nil : val
                        } label: {
                            Text(label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(filterWouldRehire == val ? .white : .primary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(filterWouldRehire == val ? SS.primary : Color(uiColor: .systemGray5))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            // Footer
            HStack(spacing: 12) {
                Button("Reset") { clearFilters() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button("Apply") { showFilterSheet = false }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SS.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .presentationDetents([.fraction(0.55)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private func clearFilters() {
        filterRating = nil
        filterWouldRehire = nil
    }

    private func sortFilterChip(icon: String, label: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(label)
                .font(.system(size: 13, weight: .semibold))
            if active {
                Circle()
                    .fill(SS.primary)
                    .frame(width: 6, height: 6)
            }
        }
        .foregroundColor(active ? SS.primary : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(active ? SS.primary.opacity(0.1) : Color(uiColor: .systemBackground))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - PendingReviewCard

private struct PendingReviewCard: View {
    let review: PendingReview
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Worker-Info
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Text(review.logoEmoji)
                        .font(.system(size: 20))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(review.workerName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(review.jobTitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(review.shiftDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(14)

            Divider().padding(.horizontal, 14)

            // Bewertungs-Button
            Button(action: onReview) {
                HStack {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                    Text("Leave a Review")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(SS.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(12)
            }
            .buttonStyle(.plain)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - PastReviewCard

private struct PastReviewCard: View {
    let review: PendingReview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Text(review.logoEmoji)
                        .font(.system(size: 20))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(review.workerName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(review.jobTitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let draft = review.draft {
                    // Gesamtbewertung
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", draft.avgRating))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(14)

            if let draft = review.draft {
                Divider().padding(.horizontal, 14)

                // Skills
                VStack(spacing: 6) {
                    miniRatingRow("Communication",  value: draft.communication)
                    miniRatingRow("Teamwork",        value: draft.teamwork)
                    miniRatingRow("Reliability",     value: draft.reliability)
                    miniRatingRow("Under Pressure",  value: draft.underPressure)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if !draft.comment.isEmpty {
                    Divider().padding(.horizontal, 14)
                    Text(draft.comment)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(14)
                }

                Divider().padding(.horizontal, 14)

                HStack {
                    Image(systemName: draft.wouldRehire ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(draft.wouldRehire ? .green : .red)
                        .font(.system(size: 14))
                    Text(draft.wouldRehire ? "Would rehire" : "Would not rehire")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(draft.savedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private func miniRatingRow(_ label: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= value ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundColor(i <= value ? .yellow : Color.gray.opacity(0.3))
                }
            }
            Spacer()
        }
    }
}

// MARK: - ReviewFormSheet

struct ReviewFormSheet: View {
    let review: PendingReview
    let onSave: (ReviewDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var communication: Int = 0
    @State private var teamwork: Int      = 0
    @State private var reliability: Int   = 0
    @State private var underPressure: Int = 0
    @State private var comment: String    = ""
    @State private var wouldRehire        = true

    private var isValid: Bool {
        communication > 0 && teamwork > 0 && reliability > 0 && underPressure > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // Worker Info Header
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.12))
                                .frame(width: 50, height: 50)
                            Text(review.logoEmoji)
                                .font(.system(size: 24))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(review.workerName)
                                .font(.system(size: 16, weight: .semibold))
                            Text(review.jobTitle)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Divider()

                    // Star Ratings
                    VStack(spacing: 0) {
                        starRatingRow(label: "Communication",   binding: $communication)
                        Divider().padding(.leading, 20)
                        starRatingRow(label: "Teamwork",         binding: $teamwork)
                        Divider().padding(.leading, 20)
                        starRatingRow(label: "Reliability",      binding: $reliability)
                        Divider().padding(.leading, 20)
                        starRatingRow(label: "Under Pressure",   binding: $underPressure)
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    // Would Rehire
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Would rehire?")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Would you book this worker again?")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $wouldRehire)
                            .labelsHidden()
                            .tint(SS.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    // Kommentar
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Comment (optional)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)

                        TextEditor(text: $comment)
                            .frame(minHeight: 100)
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 16)
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(comment.count)/600")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 24)
                                    .padding(.bottom, 8)
                            }
                            .onChange(of: comment) { _, new in
                                if new.count > 600 { comment = String(new.prefix(600)) }
                            }
                    }

                    // Speichern Button
                    Button {
                        let draft = ReviewDraft(
                            id: UUID().uuidString,
                            communication: communication,
                            teamwork: teamwork,
                            reliability: reliability,
                            underPressure: underPressure,
                            comment: comment,
                            wouldRehire: wouldRehire,
                            savedAt: .now
                        )
                        onSave(draft)
                        dismiss()
                    } label: {
                        Text("Save Review")
                    }
                    .disabled(!isValid)
                    .buttonStyle(SSPrimaryButtonStyle(isEnabled: isValid))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Leave a Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func starRatingRow(label: String, binding: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.primary)
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= binding.wrappedValue ? "star.fill" : "star")
                        .font(.system(size: 22))
                        .foregroundColor(star <= binding.wrappedValue ? .yellow : Color.gray.opacity(0.3))
                        .onTapGesture { binding.wrappedValue = star }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - ReviewDraft Extension

extension ReviewDraft {
    var avgRating: Double {
        Double(communication + teamwork + reliability + underPressure) / 4.0
    }
}

// MARK: - Mock Data

private let mockPendingReviews: [PendingReview] = [
    PendingReview(
        id: "r1",
        workerName: "Jonas Weber",
        workerPhoto: nil,
        jobTitle: "Eventhelfer",
        jobCategory: "Events",
        shiftDate: Calendar.current.date(byAdding: .day, value: -2, to: .now)!,
        logoEmoji: "🎪"
    ),
    PendingReview(
        id: "r2",
        workerName: "Maria Schulz",
        workerPhoto: nil,
        jobTitle: "Barkeeper",
        jobCategory: "Hospitality",
        shiftDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)!,
        logoEmoji: "🍹"
    ),
    PendingReview(
        id: "r3",
        workerName: "Lukas Bauer",
        workerPhoto: nil,
        jobTitle: "Lagerist",
        jobCategory: "Logistics",
        shiftDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
        logoEmoji: "📦"
    ),
]
