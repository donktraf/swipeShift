//
//  ReviewFilterSheet.swift
//  swipeShift
//
//  Filter fuer LeaveReviewsView (Employer): Mindest-Rating, Would Rehire, Job-Kategorie,
//  Schicht-Datum (Presets + eigener Zeitraum). Rein clientseitig — /employer/reviews und
//  /employer/reviews/pending liefern jobCategory + shiftDate bereits mit.
//

import SwiftUI

// MARK: - Filter-Model

enum ReviewDateRange: String, CaseIterable, Identifiable {
    case last7Days   = "Last 7 Days"
    case last30Days  = "Last 30 Days"
    case last3Months = "Last 3 Months"
    case custom      = "Custom"

    var id: String { rawValue }
}

struct ReviewFilters: Equatable {
    /// Nur "Past Reviews" (Pending hat noch kein Rating)
    var minRating: Int?
    var wouldRehire: Bool?
    /// Gilt fuer Pending + Past
    var category: String?
    var dateRange: ReviewDateRange?
    var customFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var customTo: Date = Date()

    var activeCount: Int {
        [minRating != nil, wouldRehire != nil, category != nil, dateRange != nil].filter { $0 }.count
    }

    func matches(category jobCategory: String) -> Bool {
        guard let category else { return true }
        return jobCategory.caseInsensitiveCompare(category) == .orderedSame
    }

    /// Prueft das Schicht-Datum (ganze Kalendertage, Ende inklusive)
    func matches(shiftDate: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let dateRange else { return true }
        let start: Date
        var end = now
        switch dateRange {
        case .last7Days:   start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:  start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .last3Months: start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .custom:
            start = customFrom
            end = customTo
        }
        let from = calendar.startOfDay(for: start)
        let toExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        return shiftDate >= from && shiftDate < toExclusive
    }
}

// MARK: - Sheet

struct ReviewFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var filters: ReviewFilters
    /// Kategorien aus den geladenen Reviews (nur tatsaechlich vorkommende)
    let categories: [String]

    /// Entwurf: Aenderungen greifen erst bei "Apply"
    @State private var draft = ReviewFilters()

    var body: some View {
        VStack(spacing: 0) {
            Text("Filter")
                .dsFont(.headline)
                .foregroundStyle(DS.Color.text)
                .padding(.top, DS.Spacing.lg).padding(.bottom, DS.Spacing.sm)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    ratingSection
                    rehireSection
                    categorySection
                    dateSection
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.bottom, DS.Spacing.md)
            }

            footer
        }
        .dsBackground()
        .onAppear { draft = filters }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    private var ratingSection: some View {
        section("Minimum Rating", note: "Past Reviews only") {
            HStack(spacing: DS.Spacing.xs) {
                ForEach([1, 2, 3, 4, 5], id: \.self) { stars in
                    DSChip("\(stars)+ ★", isSelected: draft.minRating == stars) {
                        draft.minRating = draft.minRating == stars ? nil : stars
                    }
                }
            }
        }
    }

    private var rehireSection: some View {
        section("Would Rehire", note: "Past Reviews only") {
            HStack(spacing: DS.Spacing.xs) {
                ForEach([(true, "Yes"), (false, "No")], id: \.0) { value, label in
                    DSChip(label, isSelected: draft.wouldRehire == value) {
                        draft.wouldRehire = draft.wouldRehire == value ? nil : value
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        section("Job Category") {
            if categories.isEmpty {
                Text("No categories in your reviews yet.")
                    .dsFont(.callout).foregroundStyle(DS.Color.muted)
            } else {
                FlowChips(items: categories) { category in
                    DSChip(category, isSelected: draft.category == category) {
                        draft.category = draft.category == category ? nil : category
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        section("Shift Date") {
            FlowChips(items: ReviewDateRange.allCases) { range in
                DSChip(range.rawValue, isSelected: draft.dateRange == range) {
                    draft.dateRange = draft.dateRange == range ? nil : range
                }
            }
            if draft.dateRange == .custom {
                VStack(spacing: DS.Spacing.xs) {
                    DatePicker("From", selection: $draft.customFrom, displayedComponents: .date)
                    DatePicker("To", selection: $draft.customTo, in: draft.customFrom..., displayedComponents: .date)
                }
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text)
                .tint(DS.Color.primary)
                .padding(.top, DS.Spacing.xxs)
                .onChange(of: draft.customFrom) { _, newFrom in
                    if draft.customTo < newFrom { draft.customTo = newFrom }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button("Reset") { draft = ReviewFilters() }
                .buttonStyle(.ds(.secondary))
            Button("Apply") {
                filters = draft
                dismiss()
            }
            .buttonStyle(.ds(.primary))
        }
        .padding(.horizontal, DS.Spacing.screenEdge).padding(.top, DS.Spacing.xs).padding(.bottom, DS.Spacing.lg)
    }

    // MARK: Building Blocks

    private func section<Content: View>(
        _ title: String,
        note: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .dsFont(.sectionLabel).foregroundStyle(DS.Color.muted)
                    .accessibilityAddTraits(.isHeader)
                if let note {
                    Text("· \(note)").dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
            }
            content()
        }
    }
}

// MARK: - Umbrechende Chip-Reihe

/// Einfaches Flow-Layout, damit viele Kategorien in mehrere Zeilen umbrechen
private struct FlowChips<Item: Hashable, ChipView: View>: View {
    let items: [Item]
    @ViewBuilder let chip: (Item) -> ChipView

    var body: some View {
        FlowLayout(spacing: DS.Spacing.xs) {
            ForEach(items, id: \.self) { chip($0) }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews: subviews, maxWidth: bounds.width) {
            for (index, x) in zip(row.indices, row.xs) {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
                )
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var xs: [CGFloat] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextX = current.indices.isEmpty ? 0 : current.width + spacing
            if !current.indices.isEmpty && nextX + size.width > maxWidth {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            let x = current.indices.isEmpty ? 0 : current.width + spacing
            current.indices.append(index)
            current.xs.append(x)
            current.width = x + size.width
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
