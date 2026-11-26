//
//  WorkerCalendarView.swift
//  swipeShift
//
//  Kalender des Workers: Monat/Woche, kommende + vergangene Jobs, Detail-Sheet mit
//  "View Job Details" / "Open Chat", Zahlungsstatus, Stornierungsgrund, Overlap-Warnung.
//  Bausteine: WorkerCalendarComponents.swift
//

import SwiftUI

// MARK: - Calendar Mode

private enum CalendarMode { case month, week }

// MARK: - WorkerCalendarView

struct WorkerCalendarView: View {
    @EnvironmentObject var messageStore: MessageStore

    @State private var mode: CalendarMode = .month
    @State private var displayedMonth: Date = Date()
    @State private var weekOffset = 0
    @State private var entries: [CalendarEntry] = []
    @State private var isLoading = false
    @State private var loadFailed = false

    // Navigation aus dem Detail-Sheet
    @State private var selectedEntry: CalendarEntry?
    @StateObject private var navigation = ApplicationNavigation()

    private let calendar = Calendar.current

    private var upcomingEntries: [CalendarEntry] {
        entries.filter { !$0.isPast() }.sorted { $0.start < $1.start }
    }

    private var pastEntries: [CalendarEntry] {
        entries.filter { $0.isPast() }.sorted { $0.start > $1.start }
    }

    private var conflictCount: Int { upcomingEntries.filter(\.hasConflict).count }

    var body: some View {
        SubScreenShell(title: "Calendar") {
            VStack(spacing: DS.Spacing.xl) {
                modeToggle.padding(.horizontal, DS.Spacing.screenEdge)

                if isLoading && entries.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        DSSkeletonBlock(height: 300, radius: DS.Radius.card)
                        DSSkeletonBlock(height: 80, radius: DS.Radius.card)
                    }
                    .padding(.horizontal, DS.Spacing.screenEdge)
                    .accessibilityLabel("Loading calendar")
                } else if loadFailed && entries.isEmpty {
                    errorState
                } else if entries.isEmpty {
                    emptyState
                } else {
                    if conflictCount > 0 { conflictBanner.padding(.horizontal, DS.Spacing.screenEdge) }
                    if mode == .month { monthView } else { weekView }
                    entryLists
                }
            }
        }
        .refreshable { await loadEntries() }
        // Bei jedem Erscheinen neu laden → Annahme/Stornierung/Abschluss sind sofort sichtbar
        .task { await loadEntries() }
        .sheet(item: $selectedEntry) { entry in
            CalendarEntryDetailSheet(
                entry: entry,
                onViewJob: { openJob(entry) },
                onOpenChat: { openChat(entry) },
                onCancelled: { Task { await loadEntries() } }
            )
        }
        .applicationNavigation(navigation)
    }

    // MARK: - Loading + Actions

    private func loadEntries() async {
        isLoading = true
        loadFailed = false
        do {
            let items = try await APIClient.shared.fetchWorkerApplications()
            entries = CalendarEntry.markingConflicts(items.flatMap(CalendarEntry.entries(from:)))
        } catch {
            if (error as? URLError)?.code != .cancelled { loadFailed = true }
        }
        isLoading = false
    }

    private func openJob(_ entry: CalendarEntry) {
        selectedEntry = nil
        navigation.openJob(jobId: entry.jobId)
    }

    private func openChat(_ entry: CalendarEntry) {
        selectedEntry = nil
        navigation.openChat(conversationId: entry.conversationId, messageStore: messageStore)
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach([(CalendarMode.month, "Month"), (CalendarMode.week, "Week")], id: \.0) { item, label in
                Button {
                    DS.Haptics.selection()
                    mode = item
                } label: {
                    Text(label)
                        .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                        .foregroundStyle(mode == item ? DS.Color.onPrimary : DS.Color.text2)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(mode == item ? DS.Color.primary : Color.clear, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.dsPressable)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(DS.Spacing.xxs)
        .background(DS.Color.surface2, in: Capsule())
        .dsAnimation(.snappy, value: mode)
    }

    // MARK: - Month View

    private var monthView: some View {
        VStack(spacing: DS.Spacing.md) {
            navigationHeader(
                title: displayedMonth.formatted(.dateTime.month(.wide).year()),
                onPrevious: { displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth },
                onNext: { displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth }
            )

            DSCard {
                VStack(spacing: 0) {
                    HStack {
                        ForEach(["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], id: \.self) { label in
                            Text(label)
                                .font(DS.Font.make(11, .semibold, relativeTo: .caption2))
                                .foregroundStyle(DS.Color.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.bottom, DS.Spacing.xs)

                    let days = daysInMonth(for: displayedMonth)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                        ForEach(days.indices, id: \.self) { idx in
                            if let day = days[idx].0, let date = days[idx].1 {
                                CalendarDayCell(day: day, date: date, entries: entriesOn(date))
                                    .onTapGesture {
                                        // Tag mit genau einem Job → direkt Details; sonst Liste unten nutzen
                                        let dayEntries = entriesOn(date)
                                        if dayEntries.count == 1 {
                                            DS.Haptics.light()
                                            selectedEntry = dayEntries[0]
                                        }
                                    }
                            } else {
                                Color.clear.frame(height: 36)
                            }
                        }
                    }
                    legend.padding(.top, DS.Spacing.sm)
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
        }
    }

    private var legend: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach([ApplicationStatus.confirmed, .applied, .completed, .cancelled], id: \.self) { status in
                HStack(spacing: DS.Spacing.xxs) {
                    Circle().fill(status.calendarColor).frame(width: 7, height: 7)
                    Text(status.calendarLabel).font(DS.Font.make(10, .medium, relativeTo: .caption2)).foregroundStyle(DS.Color.muted)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Week View

    private var weekView: some View {
        let weekDays = weekDays(offset: weekOffset)
        return VStack(spacing: DS.Spacing.md) {
            navigationHeader(
                title: weekRangeLabel(weekDays),
                onPrevious: { weekOffset -= 1 },
                onNext: { weekOffset += 1 }
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    ForEach(weekDays, id: \.self) { date in
                        CalendarWeekDayColumn(date: date, entries: entriesOn(date)) { selectedEntry = $0 }
                    }
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
            }
        }
    }

    // MARK: - Lists (kommend + vergangen getrennt)

    private var entryLists: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            entrySection(title: "Upcoming Jobs", entries: upcomingEntries,
                         emptyText: "No upcoming jobs. Apply for shifts to fill your calendar.")
            if !pastEntries.isEmpty {
                entrySection(title: "Past Jobs", entries: pastEntries, emptyText: nil)
            }
        }
    }

    private func entrySection(title: String, entries: [CalendarEntry], emptyText: String?) -> some View {
        DSSection(title, ruled: false) {
            VStack(spacing: DS.Spacing.sm) {
                if entries.isEmpty, let emptyText {
                    Text(emptyText)
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(entries) { entry in
                    Button { selectedEntry = entry } label: { CalendarEntryRow(entry: entry) }
                        .buttonStyle(.dsPressable)
                }
            }
            .padding(.top, DS.Spacing.xxs)
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
    }

}

// MARK: - Helpers (Extension haelt den Struct-Body unter dem SwiftLint-Limit)

extension WorkerCalendarView {
    // MARK: - Conflict Banner

    private var conflictBanner: some View {
        Label(
            conflictCount == 1
                ? "1 upcoming shift overlaps with another job."
                : "\(conflictCount) upcoming shifts overlap with other jobs.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
        .foregroundStyle(DS.Color.warning)
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.warningSoft, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }

    // MARK: - Empty / Error

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.xs) {
            DSEmptyState(systemIcon: "calendar.badge.plus", title: "No jobs scheduled yet",
                         message: "Apply for shifts and they will show up here.")
            NavigationLink {
                JobListView()
            } label: {
                Label("Find jobs nearby", systemImage: "location.magnifyingglass")
            }
            .buttonStyle(.ds(.primary, size: .medium, fullWidth: false))
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
    }

    private var errorState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Text("Your calendar could not be loaded.")
                .dsFont(.callout).foregroundStyle(DS.Color.muted)
            Button("Retry") { Task { await loadEntries() } }
                .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
        }
        .padding(.top, DS.Spacing.xl)
    }

    private func navigationHeader(title: String, onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) -> some View {
        HStack {
            DSIconButton(systemName: "chevron.left", label: "Previous", action: onPrevious)
            Spacer()
            Text(title).dsFont(.headline).foregroundStyle(DS.Color.text)
            Spacer()
            DSIconButton(systemName: "chevron.right", label: "Next", action: onNext)
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
    }

    private func entriesOn(_ date: Date) -> [CalendarEntry] {
        entries.filter { calendar.isDate($0.start, inSameDayAs: date) }.sorted { $0.start < $1.start }
    }

    /// (Tag?, Datum?) mit fuehrenden Leerfeldern fuer den Wochentag-Versatz (Montag zuerst)
    private func daysInMonth(for date: Date) -> [(Int?, Date?)] {
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = 1
        guard let firstDay = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else { return [] }

        let weekday = (calendar.component(.weekday, from: firstDay) + 5) % 7
        var result: [(Int?, Date?)] = Array(repeating: (nil, nil), count: weekday)
        for day in range {
            var dayComponents = components
            dayComponents.day = day
            if let dayDate = calendar.date(from: dayComponents) { result.append((day, dayDate)) }
        }
        return result
    }

    private func weekDays(offset: Int) -> [Date] {
        let today = calendar.startOfDay(for: Date())
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -weekday + offset * 7, to: today) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func weekRangeLabel(_ days: [Date]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }
}
