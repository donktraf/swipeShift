//
//  LeaveReviewsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - LeaveReviewsView

struct LeaveReviewsView: View {
    @State private var selectedTab: ReviewTab = .pending
    @State private var pendingList: [PendingReviewItem] = []
    @State private var pastList:    [PastReviewItem]    = []
    @State private var isLoading    = false
    @State private var errorMessage: String? = nil

    @State private var showSortSheet    = false
    @State private var showFilterSheet  = false
    @State private var selectedSort: ReviewSort     = .mostRecent
    @State private var filters = ReviewFilters()
    @State private var reviewToEdit: PendingReviewItem? = nil

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

    private var filteredPending: [PendingReviewItem] {
        // Pending hat noch kein Rating → nur Kategorie + Schicht-Datum
        var list = pendingList.filter {
            filters.matches(category: $0.jobCategory) && filters.matches(shiftDate: $0.shiftDate)
        }
        switch selectedSort {
        case .mostRecent:    list.sort { $0.shiftDate > $1.shiftDate }
        case .highestRating: list.sort { $0.shiftDate > $1.shiftDate }
        case .lowestRating:  list.sort { $0.shiftDate < $1.shiftDate }
        }
        return list
    }

    private var filteredPast: [PastReviewItem] {
        var list = pastList.filter {
            filters.matches(category: $0.jobCategory) && filters.matches(shiftDate: $0.shiftDate)
        }
        if let min = filters.minRating     { list = list.filter { $0.avgRating >= Double(min) } }
        if let rehire = filters.wouldRehire { list = list.filter { $0.wouldRehire == rehire } }
        switch selectedSort {
        case .mostRecent:    list.sort { $0.createdAt > $1.createdAt }
        case .highestRating: list.sort { $0.avgRating > $1.avgRating }
        case .lowestRating:  list.sort { $0.avgRating < $1.avgRating }
        }
        return list
    }

    private var activeFilters: Int { filters.activeCount }

    /// Nur Kategorien, die in den geladenen Reviews vorkommen (keine leeren Filter-Optionen)
    private var availableCategories: [String] {
        let all = pendingList.map(\.jobCategory) + pastList.map(\.jobCategory)
        return Array(Set(all.filter { !$0.isEmpty && $0 != "—" })).sorted()
    }

    private var currentCount: Int {
        switch selectedTab {
        case .pending: return pendingList.count
        case .drafts:  return 0
        case .past:    return pastList.count
        }
    }

    var body: some View {
        SubScreenShell(title: "Leave Reviews") {
            VStack(spacing: 0) {
                tabBar.padding(.bottom, 12)

                sortFilterRow.padding(.horizontal, 16).padding(.bottom, 12)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let err = errorMessage {
                    errorView(err)
                } else {
                    contentList
                }
            }
        }
        .task { await loadData() }
        .sheet(isPresented: $showSortSheet)   { sortSheet }
        .sheet(isPresented: $showFilterSheet) {
            ReviewFilterSheet(filters: $filters, categories: availableCategories)
        }
        .sheet(item: $reviewToEdit) { item in
            ReviewFormSheet(review: item) {
                Task {
                    pendingList.removeAll { $0.applyId == item.applyId }
                    try? await loadPastReviews()
                }
            }
        }
    }

    // MARK: - Content List

    @ViewBuilder
    private var contentList: some View {
        switch selectedTab {
        case .pending:
            if filteredPending.isEmpty && !pendingList.isEmpty && activeFilters > 0 {
                noMatchesView
            } else if filteredPending.isEmpty {
                emptyView(icon: "checkmark.seal", message: "No pending reviews.\nAll shifts have been reviewed.")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(filteredPending) { item in
                            PendingReviewCard(item: item) { reviewToEdit = item }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        case .drafts:
            emptyView(icon: "doc.text", message: "No drafts saved.\nDrafts are not persisted between sessions.")
        case .past:
            if filteredPast.isEmpty && !pastList.isEmpty && activeFilters > 0 {
                noMatchesView
            } else if filteredPast.isEmpty {
                emptyView(icon: "star.slash", message: "No past reviews yet.")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(filteredPast) { item in
                            PastReviewCard(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ReviewTab.allCases, id: \.self) { tab in
                let count: Int = {
                    switch tab {
                    case .pending: return pendingList.count
                    case .drafts:  return 0
                    case .past:    return pastList.count
                    }
                }()
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

    // MARK: - Sort + Filter Row

    private var sortFilterRow: some View {
        HStack(spacing: 8) {
            Button { showSortSheet = true } label: {
                sortFilterChip(icon: "arrow.up.arrow.down",
                               label: selectedSort.rawValue,
                               active: selectedSort != .mostRecent)
            }
            .buttonStyle(.plain)

            Button { showFilterSheet = true } label: {
                sortFilterChip(icon: "line.3.horizontal.decrease.circle",
                               label: activeFilters > 0 ? "Filter (\(activeFilters))" : "Filter",
                               active: activeFilters > 0)
            }
            .buttonStyle(.plain)

            if activeFilters > 0 {
                Button { clearFilters() } label: {
                    Text("Reset")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Empty + Error Views

    private func emptyView(icon: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.3))
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange.opacity(0.7))
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") { Task { await loadData() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SS.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Sort Sheet

    private var sortSheet: some View {
        VStack(spacing: 0) {
            Text("Sort")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 20).padding(.bottom, 12)
            ForEach(ReviewSort.allCases, id: \.self) { option in
                Button {
                    selectedSort = option
                    showSortSheet = false
                } label: {
                    HStack {
                        Text(option.rawValue).font(.system(size: 15)).foregroundColor(.primary)
                        Spacer()
                        if selectedSort == option {
                            Image(systemName: "checkmark").foregroundColor(SS.primary)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 24)
            }
            Spacer()
        }
        .presentationDetents([.fraction(0.4)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private func clearFilters() {
        filters = ReviewFilters()
    }

    /// Es gibt Reviews, aber keine passt zu den aktiven Filtern
    private var noMatchesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36)).foregroundColor(.white.opacity(0.3))
            Text("No reviews match your filters.")
                .font(.system(size: 14)).foregroundColor(.white.opacity(0.6))
            Button("Clear Filters") { clearFilters() }
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.white.opacity(0.2)).clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func sortFilterChip(icon: String, label: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12))
            Text(label).font(.system(size: 13, weight: .semibold))
            if active { Circle().fill(SS.primary).frame(width: 6, height: 6) }
        }
        .foregroundColor(active ? SS.primary : .secondary)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(active ? SS.primary.opacity(0.1) : Color(uiColor: .systemBackground))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let pending = APIClient.shared.fetchPendingReviews()
            async let past    = APIClient.shared.fetchPastReviews()
            (pendingList, pastList) = try await (pending, past)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadPastReviews() async throws {
        pastList = try await APIClient.shared.fetchPastReviews()
    }
}

// MARK: - PendingReviewCard

private struct PendingReviewCard: View {
    let item: PendingReviewItem
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.12)).frame(width: 44, height: 44)
                    Text(item.logoEmoji).font(.system(size: 20))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.workerName)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                    Text(item.jobTitle)
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Text(item.shiftDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(14)

            Divider().padding(.horizontal, 14)

            Button(action: onReview) {
                HStack {
                    Image(systemName: "star.fill").font(.system(size: 14))
                    Text("Leave a Review").font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
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
    let item: PastReviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.12)).frame(width: 44, height: 44)
                    Text(item.logoEmoji).font(.system(size: 20))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.workerName)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                    Text(item.jobTitle)
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundColor(.yellow)
                    Text(String(format: "%.1f", item.avgRating))
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.primary)
                }
            }
            .padding(14)

            Divider().padding(.horizontal, 14)

            VStack(spacing: 6) {
                miniRatingRow("Communication",  value: item.communication)
                miniRatingRow("Teamwork",        value: item.teamwork)
                miniRatingRow("Reliability",     value: item.reliability)
                miniRatingRow("Under Pressure",  value: item.underPressure)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            if let c = item.comment, !c.isEmpty {
                Divider().padding(.horizontal, 14)
                Text(c).font(.system(size: 13)).foregroundColor(.secondary).padding(14)
            }

            Divider().padding(.horizontal, 14)

            HStack {
                Image(systemName: item.wouldRehire ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(item.wouldRehire ? .green : .red).font(.system(size: 14))
                Text(item.wouldRehire ? "Would rehire" : "Would not rehire")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
                Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private func miniRatingRow(_ label: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
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
    let review: PendingReviewItem
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var communication: Int = 0
    @State private var teamwork:      Int = 0
    @State private var reliability:   Int = 0
    @State private var underPressure: Int = 0
    @State private var comment            = ""
    @State private var wouldRehire        = true
    @State private var isSubmitting       = false
    @State private var submitError: String? = nil

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
                            Circle().fill(Color.gray.opacity(0.12)).frame(width: 50, height: 50)
                            Text(review.logoEmoji).font(.system(size: 24))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(review.workerName).font(.system(size: 16, weight: .semibold))
                            Text(review.jobTitle).font(.system(size: 13)).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.top, 8)

                    Divider()

                    // Star Ratings
                    VStack(spacing: 0) {
                        starRatingRow(label: "Communication",  binding: $communication)
                        Divider().padding(.leading, 20)
                        starRatingRow(label: "Teamwork",        binding: $teamwork)
                        Divider().padding(.leading, 20)
                        starRatingRow(label: "Reliability",     binding: $reliability)
                        Divider().padding(.leading, 20)
                        starRatingRow(label: "Under Pressure",  binding: $underPressure)
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    // Would Rehire
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Would rehire?").font(.system(size: 15, weight: .semibold))
                            Text("Would you book this worker again?")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $wouldRehire).labelsHidden().tint(SS.primary)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    // Kommentar
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Comment (optional)")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        TextEditor(text: $comment)
                            .frame(minHeight: 100).padding(12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 16)
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(comment.count)/600")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                                    .padding(.trailing, 24).padding(.bottom, 8)
                            }
                            .onChange(of: comment) { _, new in
                                if new.count > 600 { comment = String(new.prefix(600)) }
                            }
                    }

                    if let err = submitError {
                        Text(err)
                            .font(.system(size: 13)).foregroundColor(.red)
                            .multilineTextAlignment(.center).padding(.horizontal, 20)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save Review")
                        }
                    }
                    .disabled(!isValid || isSubmitting)
                    .buttonStyle(SSPrimaryButtonStyle(isEnabled: isValid && !isSubmitting))
                    .padding(.horizontal, 16).padding(.bottom, 28)
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

    private func submit() async {
        isSubmitting = true
        submitError  = nil
        do {
            try await APIClient.shared.submitReview(SubmitReviewRequest(
                applyId:       review.applyId,
                communication: communication,
                teamwork:      teamwork,
                reliability:   reliability,
                underPressure: underPressure,
                comment:       comment,
                wouldRehire:   wouldRehire
            ))
            onSuccess()
            dismiss()
        } catch {
            submitError  = error.localizedDescription
            isSubmitting = false
        }
    }

    private func starRatingRow(label: String, binding: Binding<Int>) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundColor(.primary)
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
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}
