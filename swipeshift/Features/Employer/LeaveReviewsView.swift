//
//  LeaveReviewsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - LeaveReviewsView

struct LeaveReviewsView: View {
    @State private var selectedTab: ReviewTab = .pending
    @State private var pendingList: [PendingReviewItem] = []
    @State private var draftList:   [ReviewDraftItem]   = []
    @State private var pastList:    [PastReviewItem]    = []
    @State private var isLoading    = false
    @State private var errorMessage: String? = nil

    @State private var showSortSheet    = false
    @State private var showFilterSheet  = false
    @State private var selectedSort: ReviewSort     = .mostRecent
    @State private var filters = ReviewFilters()
    @State private var reviewToEdit: ReviewFormContext? = nil
    @State private var draftToDelete: ReviewDraftItem? = nil
    @State private var actionError: String? = nil

    /// Was das Formular-Sheet braucht: Pending-Eintrag + optional vorhandener Entwurf
    struct ReviewFormContext: Identifiable {
        let item: PendingReviewItem
        let draft: ReviewDraftValues?
        var id: String { item.applyId }
    }

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

    /// Entwuerfe tragen noch kein Rating → nur Kategorie + Schicht-Datum filtern (neueste Bearbeitung zuerst)
    private var filteredDrafts: [ReviewDraftItem] {
        draftList
            .filter { filters.matches(category: $0.review.jobCategory) && filters.matches(shiftDate: $0.review.shiftDate) }
            .sorted { $0.updatedAt > $1.updatedAt }
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
        let all = pendingList.map(\.jobCategory) + draftList.map(\.review.jobCategory) + pastList.map(\.jobCategory)
        return Array(Set(all.filter { !$0.isEmpty && $0 != "—" })).sorted()
    }

    private var currentCount: Int {
        switch selectedTab {
        case .pending: return pendingList.count
        case .drafts:  return draftList.count
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
        .sheet(item: $reviewToEdit) { ctx in
            ReviewFormSheet(
                review: ctx.item,
                initialDraft: ctx.draft,
                onSuccess: { Task { await loadData() } },
                onDraftChanged: { Task { await loadData() } }
            )
        }
        .confirmationDialog(
            "Delete this draft?",
            isPresented: Binding(get: { draftToDelete != nil }, set: { if !$0 { draftToDelete = nil } }),
            titleVisibility: .visible,
            presenting: draftToDelete
        ) { draft in
            Button("Delete Draft", role: .destructive) { Task { await deleteDraft(draft) } }
            Button("Cancel", role: .cancel) {}
        } message: { draft in
            Text("Your unsent review for \(draft.review.workerName) will be discarded.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
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
                            PendingReviewCard(item: item) { reviewToEdit = ReviewFormContext(item: item, draft: nil) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        case .drafts:
            if filteredDrafts.isEmpty && !draftList.isEmpty && activeFilters > 0 {
                noMatchesView
            } else if filteredDrafts.isEmpty {
                emptyView(icon: "doc.text", message: "No drafts saved.\nUse \"Save as Draft\" in the review form to finish a review later.")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(filteredDrafts) { item in
                            DraftReviewCard(
                                item: item,
                                onOpen:   { reviewToEdit = ReviewFormContext(item: item.review, draft: item.draft) },
                                onDelete: { draftToDelete = item }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
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
                    case .drafts:  return draftList.count
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
        isLoading = pendingList.isEmpty && draftList.isEmpty && pastList.isEmpty
        errorMessage = nil
        do {
            async let pending = APIClient.shared.fetchPendingReviews()
            async let drafts  = APIClient.shared.fetchReviewDrafts()
            async let past    = APIClient.shared.fetchPastReviews()
            (pendingList, draftList, pastList) = try await (pending, drafts, past)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteDraft(_ draft: ReviewDraftItem) async {
        do {
            try await APIClient.shared.deleteReviewDraft(applyId: draft.review.applyId)
            await loadData() // der Eintrag taucht danach wieder unter "Pending" auf
        } catch {
            actionError = error.localizedDescription
        }
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

// MARK: - DraftReviewCard

private struct DraftReviewCard: View {
    let item: ReviewDraftItem
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.gray.opacity(0.12)).frame(width: 44, height: 44)
                        Text(item.review.logoEmoji).font(.system(size: 20))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.review.workerName)
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                            Text("Draft")
                                .font(.system(size: 10, weight: .bold)).foregroundColor(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15)).clipShape(Capsule())
                        }
                        Text(item.review.jobTitle)
                            .font(.system(size: 12)).foregroundColor(.secondary)
                        Text("Last edited \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal, 14)

            Button(role: .destructive, action: onDelete) {
                HStack {
                    Image(systemName: "trash").font(.system(size: 13))
                    Text("Delete Draft").font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
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
                    if item.isTopWorker { TopWorkerBadge(text: "Top Worker") }
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
                if let quality = item.workQuality { miniRatingRow("Work Quality", value: quality) }
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
    /// Wird nach erfolgreichem Speichern eines Entwurfs aufgerufen (Liste neu laden)
    let onDraftChanged: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var communication: Int
    @State private var teamwork:      Int
    @State private var reliability:   Int
    @State private var underPressure: Int
    @State private var workQuality:   Int
    @State private var comment:       String
    @State private var wouldRehire:   Bool
    @State private var topWorker:     Bool
    @State private var isSubmitting       = false
    @State private var isSavingDraft      = false
    @State private var draftSaved         = false
    @State private var submitError: String? = nil

    init(review: PendingReviewItem,
         initialDraft: ReviewDraftValues? = nil,
         onSuccess: @escaping () -> Void,
         onDraftChanged: (() -> Void)? = nil) {
        self.review = review
        self.onSuccess = onSuccess
        self.onDraftChanged = onDraftChanged
        _communication = State(initialValue: initialDraft?.communication ?? 0)
        _teamwork      = State(initialValue: initialDraft?.teamwork ?? 0)
        _reliability   = State(initialValue: initialDraft?.reliability ?? 0)
        _underPressure = State(initialValue: initialDraft?.underPressure ?? 0)
        _workQuality   = State(initialValue: initialDraft?.workQuality ?? 0)
        _comment       = State(initialValue: initialDraft?.comment ?? "")
        _wouldRehire   = State(initialValue: initialDraft?.wouldRehire ?? true)
        _topWorker     = State(initialValue: initialDraft?.topWorker ?? false)
    }

    private var isValid: Bool {
        communication > 0 && teamwork > 0 && reliability > 0 && underPressure > 0 && workQuality > 0
    }

    private var isBusy: Bool { isSubmitting || isSavingDraft }

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
                        Divider().padding(.leading, 20)
                        starRatingRow(label: "Work Quality",    binding: $workQuality)
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

                    // Top Worker
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Highlight as Top Worker").font(.system(size: 15, weight: .semibold))
                            Text("Exceptional performance")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $topWorker).labelsHidden().tint(SS.primary)
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
                    .disabled(!isValid || isBusy)
                    .buttonStyle(SSPrimaryButtonStyle(isEnabled: isValid && !isBusy))
                    .padding(.horizontal, 16)

                    Button {
                        Task { await saveDraft() }
                    } label: {
                        if isSavingDraft {
                            ProgressView()
                        } else {
                            Text("Save as Draft")
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(SS.primary)
                        }
                    }
                    .disabled(isBusy)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
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
        .overlay(alignment: .bottom) {
            if draftSaved {
                Label("Draft saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(SS.primary).clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Could not save review", isPresented: Binding(
            get: { submitError != nil },
            set: { if !$0 { submitError = nil } }
        )) {
            Button("OK", role: .cancel) { submitError = nil }
        } message: {
            Text(submitError ?? "")
        }
    }

    private func saveDraft() async {
        isSavingDraft = true
        submitError   = nil
        do {
            try await APIClient.shared.saveReviewDraft(
                applyId: review.applyId,
                values: ReviewDraftValues(
                    communication: communication,
                    teamwork:      teamwork,
                    reliability:   reliability,
                    underPressure: underPressure,
                    workQuality:   workQuality,
                    comment:       comment,
                    wouldRehire:   wouldRehire,
                    topWorker:     topWorker
                )
            )
            onDraftChanged?()
            withAnimation { draftSaved = true }
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            submitError = error.localizedDescription
        }
        isSavingDraft = false
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
                workQuality:   workQuality,
                comment:       comment,
                wouldRehire:   wouldRehire,
                topWorker:     topWorker
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
