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
        SubScreenShell(title: "Leave Reviews", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                tabBar

                sortFilterRow

                if isLoading {
                    skeleton
                } else if let err = errorMessage {
                    errorView(err)
                } else {
                    contentList
                }
            }
        }
        .refreshable { await loadData() }
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

    private var skeleton: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                DSSkeletonBlock(height: 120, radius: DS.Radius.card)
            }
        }
        .accessibilityLabel("Loading reviews")
    }

    @ViewBuilder
    private var contentList: some View {
        switch selectedTab {
        case .pending:
            if filteredPending.isEmpty && !pendingList.isEmpty && activeFilters > 0 {
                noMatchesView
            } else if filteredPending.isEmpty {
                emptyView(icon: "checkmark.seal", message: "No pending reviews.\nAll shifts have been reviewed.")
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(filteredPending) { item in
                        PendingReviewCard(item: item) { reviewToEdit = ReviewFormContext(item: item, draft: nil) }
                    }
                }
            }
        case .drafts:
            if filteredDrafts.isEmpty && !draftList.isEmpty && activeFilters > 0 {
                noMatchesView
            } else if filteredDrafts.isEmpty {
                emptyView(icon: "doc.text", message: "No drafts saved.\nUse \"Save as Draft\" in the review form to finish a review later.")
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(filteredDrafts) { item in
                        DraftReviewCard(
                            item: item,
                            onOpen:   { reviewToEdit = ReviewFormContext(item: item.review, draft: item.draft) },
                            onDelete: { draftToDelete = item }
                        )
                    }
                }
            }
        case .past:
            if filteredPast.isEmpty && !pastList.isEmpty && activeFilters > 0 {
                noMatchesView
            } else if filteredPast.isEmpty {
                emptyView(icon: "star.slash", message: "No past reviews yet.")
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(filteredPast) { item in
                        PastReviewCard(item: item)
                    }
                }
            }
        }
    }

    // MARK: - Tab Bar (segmentierte Pills)

    private var tabBar: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(ReviewTab.allCases, id: \.self) { tab in
                let count: Int = {
                    switch tab {
                    case .pending: return pendingList.count
                    case .drafts:  return draftList.count
                    case .past:    return pastList.count
                    }
                }()
                Button {
                    DS.Haptics.selection()
                    selectedTab = tab
                } label: {
                    Text(count > 0 ? "\(tab.rawValue) \(count)" : tab.rawValue)
                        .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(selectedTab == tab ? DS.Color.onPrimary : DS.Color.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selectedTab == tab ? DS.Color.primary : Color.clear, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.dsPressable)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(DS.Spacing.xxs)
        .background(DS.Color.surface2, in: Capsule())
        .dsAnimation(.snappy, value: selectedTab)
    }

    // MARK: - Sort + Filter Row

    private var sortFilterRow: some View {
        HStack(spacing: DS.Spacing.xs) {
            Button { showSortSheet = true } label: {
                sortFilterChip(icon: "arrow.up.arrow.down",
                               label: selectedSort.rawValue,
                               active: selectedSort != .mostRecent)
            }
            .buttonStyle(.dsPressable)

            Button { showFilterSheet = true } label: {
                sortFilterChip(icon: "line.3.horizontal.decrease.circle",
                               label: activeFilters > 0 ? "Filter (\(activeFilters))" : "Filter",
                               active: activeFilters > 0)
            }
            .buttonStyle(.dsPressable)

            if activeFilters > 0 {
                Button { clearFilters() } label: {
                    Text("Reset")
                }
                .buttonStyle(.ds(.destructiveSoft, size: .medium, fullWidth: false))
            }
            Spacer()
        }
    }

    // MARK: - Empty + Error Views

    private func emptyView(icon: String, message: String) -> some View {
        DSEmptyState(systemIcon: icon, title: "Nothing here", message: message)
            .padding(.top, DS.Spacing.xl)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(DS.Color.warning)
            Text(msg)
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text2)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadData() } }
                .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Spacing.xl)
    }

    // MARK: - Sort Sheet

    private var sortSheet: some View {
        VStack(spacing: 0) {
            Text("Sort")
                .dsFont(.headline)
                .foregroundStyle(DS.Color.text)
                .padding(.top, DS.Spacing.lg).padding(.bottom, DS.Spacing.sm)
            VStack(spacing: 0) {
                ForEach(ReviewSort.allCases, id: \.self) { option in
                    DSRow(option.rawValue, action: {
                        DS.Haptics.selection()
                        selectedSort = option
                        showSortSheet = false
                    }) {
                        if selectedSort == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DS.Color.primaryText)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .accessibilityAddTraits(selectedSort == option ? .isSelected : [])
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            Spacer()
        }
        .dsBackground()
        .presentationDetents([.fraction(0.4)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private func clearFilters() {
        filters = ReviewFilters()
    }

    /// Es gibt Reviews, aber keine passt zu den aktiven Filtern
    private var noMatchesView: some View {
        DSEmptyState(
            systemIcon: "line.3.horizontal.decrease.circle",
            title: "No matches",
            message: "No reviews match your filters.",
            actionTitle: "Clear Filters",
            action: { clearFilters() }
        )
        .padding(.top, DS.Spacing.xl)
    }

    private func sortFilterChip(icon: String, label: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            Text(label).font(DS.Font.make(13, .semibold, relativeTo: .caption))
            if active { Circle().fill(DS.Color.primary).frame(width: 6, height: 6) }
        }
        .foregroundStyle(active ? DS.Color.primaryText : DS.Color.text2)
        .padding(.horizontal, DS.Spacing.sm)
        .frame(minHeight: 44)
        .background(active ? DS.Color.primarySoft : DS.Color.surface,
                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(active ? Color.clear : DS.Color.border, lineWidth: 1)
        )
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
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    DSAvatar(text: item.logoEmoji, size: 44, shape: .circle, tone: .neutral)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.workerName)
                            .dsFont(.headline).foregroundStyle(DS.Color.text)
                        Text(item.jobTitle)
                            .dsFont(.caption).foregroundStyle(DS.Color.text2)
                    }
                    Spacer()
                    Text(item.shiftDate.formatted(date: .abbreviated, time: .omitted))
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                }

                Button(action: onReview) {
                    Label("Leave a Review", systemImage: "star.fill")
                }
                .buttonStyle(.ds(.primary, size: .medium))
            }
        }
    }
}

// MARK: - DraftReviewCard

private struct DraftReviewCard: View {
    let item: ReviewDraftItem
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Button(action: onOpen) {
                    HStack(spacing: DS.Spacing.sm) {
                        DSAvatar(text: item.review.logoEmoji, size: 44, shape: .circle, tone: .neutral)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: DS.Spacing.xs) {
                                Text(item.review.workerName)
                                    .dsFont(.headline).foregroundStyle(DS.Color.text)
                                DSBadge("Draft", .draft)
                            }
                            Text(item.review.jobTitle)
                                .dsFont(.caption).foregroundStyle(DS.Color.text2)
                            Text("Last edited \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .dsFont(.caption).foregroundStyle(DS.Color.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.Color.muted)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressable)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete Draft", systemImage: "trash")
                }
                .buttonStyle(.ds(.destructiveSoft, size: .medium))
            }
        }
    }
}

// MARK: - PastReviewCard

private struct PastReviewCard: View {
    let item: PastReviewItem

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    DSAvatar(text: item.logoEmoji, size: 44, shape: .circle, tone: .neutral)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.workerName)
                            .dsFont(.headline).foregroundStyle(DS.Color.text)
                        if item.isTopWorker { TopWorkerBadge(text: "Top Worker") }
                        Text(item.jobTitle)
                            .dsFont(.caption).foregroundStyle(DS.Color.text2)
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(DS.Color.warning)
                        Text(String(format: "%.1f", item.avgRating))
                            .font(DS.Font.make(14, .semibold, relativeTo: .callout)).foregroundStyle(DS.Color.text)
                    }
                }

                DSDivider()

                VStack(spacing: DS.Spacing.xs) {
                    miniRatingRow("Communication",  value: item.communication)
                    miniRatingRow("Teamwork",        value: item.teamwork)
                    miniRatingRow("Reliability",     value: item.reliability)
                    miniRatingRow("Under Pressure",  value: item.underPressure)
                    if let quality = item.workQuality { miniRatingRow("Work Quality", value: quality) }
                }

                if let c = item.comment, !c.isEmpty {
                    DSDivider()
                    Text(c).dsFont(.callout).foregroundStyle(DS.Color.text2)
                }

                DSDivider()

                HStack {
                    Image(systemName: item.wouldRehire ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(item.wouldRehire ? DS.Color.success : DS.Color.danger).font(.system(size: 14))
                    Text(item.wouldRehire ? "Would rehire" : "Would not rehire")
                        .dsFont(.caption).foregroundStyle(DS.Color.text2)
                    Spacer()
                    Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
            }
        }
    }

    private func miniRatingRow(_ label: String, value: Int) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(label).dsFont(.caption).foregroundStyle(DS.Color.text2)
                .frame(width: 110, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= value ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundStyle(i <= value ? DS.Color.warning : DS.Color.border)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) of 5")
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
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // Worker Info Header
                    HStack(spacing: DS.Spacing.sm) {
                        DSAvatar(text: review.logoEmoji, size: 50, shape: .circle, tone: .neutral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(review.workerName).dsFont(.headline).foregroundStyle(DS.Color.text)
                            Text(review.jobTitle).dsFont(.caption).foregroundStyle(DS.Color.text2)
                        }
                        Spacer()
                    }

                    // Star Ratings
                    DSSection("Ratings") {
                        starRatingRow(label: "Communication",  binding: $communication)
                        starRatingRow(label: "Teamwork",        binding: $teamwork)
                        starRatingRow(label: "Reliability",     binding: $reliability)
                        starRatingRow(label: "Under Pressure",  binding: $underPressure)
                        starRatingRow(label: "Work Quality",    binding: $workQuality)
                    }

                    DSSection("Outcome") {
                        DSToggleRow("Would rehire?", subtitle: "Would you book this worker again?", isOn: $wouldRehire)
                        DSToggleRow("Highlight as Top Worker", subtitle: "Exceptional performance", isOn: $topWorker)
                    }

                    // Kommentar
                    DSTextEditor("Comment (optional)", text: $comment, minLines: 4, maxLines: 10, maxLength: 600)

                    if let err = submitError {
                        Text(err)
                            .dsFont(.callout).foregroundStyle(DS.Color.danger)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: DS.Spacing.xs) {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isSubmitting {
                                ProgressView().tint(DS.Color.onPrimary)
                            } else {
                                Text("Save Review")
                            }
                        }
                        .disabled(!isValid || isBusy)
                        .buttonStyle(.ds(.primary))

                        Button {
                            Task { await saveDraft() }
                        } label: {
                            if isSavingDraft {
                                ProgressView()
                            } else {
                                Text("Save as Draft")
                            }
                        }
                        .disabled(isBusy)
                        .buttonStyle(.ds(.secondary))
                    }
                    .padding(.bottom, DS.Spacing.lg)
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.top, DS.Spacing.xs)
            }
            .dsBackground()
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
                    .font(DS.Font.make(14, .semibold, relativeTo: .callout)).foregroundStyle(DS.Color.onPrimary)
                    .padding(.horizontal, DS.Spacing.md).padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.primary, in: Capsule())
                    .dsCardShadow()
                    .padding(.bottom, DS.Spacing.xl)
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
            DS.Haptics.success()
            onSuccess()
            dismiss()
        } catch {
            submitError  = error.localizedDescription
            isSubmitting = false
        }
    }

    private func starRatingRow(label: String, binding: Binding<Int>) -> some View {
        HStack {
            Text(label).dsFont(.body).foregroundStyle(DS.Color.text)
            Spacer()
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        DS.Haptics.selection()
                        binding.wrappedValue = star
                    } label: {
                        Image(systemName: star <= binding.wrappedValue ? "star.fill" : "star")
                            .font(.system(size: 22))
                            .foregroundStyle(star <= binding.wrappedValue ? DS.Color.warning : DS.Color.border)
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
            }
        }
        .frame(minHeight: 44)
        .overlay(alignment: .top) { DSDivider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
