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
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 20).padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    ratingSection
                    Divider()
                    rehireSection
                    Divider()
                    categorySection
                    Divider()
                    dateSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            footer
        }
        .onAppear { draft = filters }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    private var ratingSection: some View {
        section("Minimum Rating", note: "Past Reviews only") {
            HStack(spacing: 8) {
                ForEach([1, 2, 3, 4, 5], id: \.self) { stars in
                    chip(selected: draft.minRating == stars) {
                        draft.minRating = draft.minRating == stars ? nil : stars
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 11))
                            Text("\(stars)+").font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
            }
        }
    }

    private var rehireSection: some View {
        section("Would Rehire", note: "Past Reviews only") {
            HStack(spacing: 8) {
                ForEach([(true, "Yes"), (false, "No")], id: \.0) { value, label in
                    chip(selected: draft.wouldRehire == value) {
                        draft.wouldRehire = draft.wouldRehire == value ? nil : value
                    } label: {
                        Text(label).font(.system(size: 13, weight: .semibold))
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        section("Job Category") {
            if categories.isEmpty {
                Text("No categories in your reviews yet.")
                    .font(.system(size: 13)).foregroundColor(.secondary)
            } else {
                FlowChips(items: categories) { category in
                    chip(selected: draft.category == category) {
                        draft.category = draft.category == category ? nil : category
                    } label: {
                        Text(category).font(.system(size: 13, weight: .semibold))
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        section("Shift Date") {
            FlowChips(items: ReviewDateRange.allCases) { range in
                chip(selected: draft.dateRange == range) {
                    draft.dateRange = draft.dateRange == range ? nil : range
                } label: {
                    Text(range.rawValue).font(.system(size: 13, weight: .semibold))
                }
            }
            if draft.dateRange == .custom {
                VStack(spacing: 8) {
                    DatePicker("From", selection: $draft.customFrom, displayedComponents: .date)
                    DatePicker("To", selection: $draft.customTo, in: draft.customFrom..., displayedComponents: .date)
                }
                .font(.system(size: 14))
                .tint(SS.primary)
                .padding(.top, 4)
                .onChange(of: draft.customFrom) { _, newFrom in
                    if draft.customTo < newFrom { draft.customTo = newFrom }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Reset") { draft = ReviewFilters() }
                .font(.system(size: 15, weight: .semibold)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color(uiColor: .systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Button("Apply") {
                filters = draft
                dismiss()
            }
            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(SS.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
    }

    // MARK: Building Blocks

    private func section<Content: View>(
        _ title: String,
        note: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                if let note {
                    Text("· \(note)").font(.system(size: 12)).foregroundColor(.secondary.opacity(0.7))
                }
            }
            content()
        }
    }

    private func chip<Label: View>(
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundColor(selected ? .white : SS.primary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? SS.primary : SS.primary.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Umbrechende Chip-Reihe

/// Einfaches Flow-Layout, damit viele Kategorien in mehrere Zeilen umbrechen
private struct FlowChips<Item: Hashable, ChipView: View>: View {
    let items: [Item]
    @ViewBuilder let chip: (Item) -> ChipView

    var body: some View {
        FlowLayout(spacing: 8) {
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
