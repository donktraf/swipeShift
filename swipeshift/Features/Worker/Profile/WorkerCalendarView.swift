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
            VStack(spacing: 20) {
                modeToggle.padding(.horizontal, 16)

                if isLoading && entries.isEmpty {
                    ProgressView().tint(.white).padding(.top, 40)
                } else if loadFailed && entries.isEmpty {
                    errorState
                } else if entries.isEmpty {
                    emptyState
                } else {
                    if conflictCount > 0 { conflictBanner.padding(.horizontal, 16) }
                    if mode == .month { monthView } else { weekView }
                    entryLists
                }
            }
        }
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
            entries = CalendarEntry.markingConflicts(items.compactMap(CalendarEntry.init(item:)))
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
        HStack(spacing: 0) {
            ForEach([(CalendarMode.month, "Month"), (CalendarMode.week, "Week")], id: \.0) { item, label in
                Button { mode = item } label: {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(mode == item ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(mode == item ? SS.primary : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .systemBackground))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    // MARK: - Month View

    private var monthView: some View {
        VStack(spacing: 16) {
            navigationHeader(
                title: displayedMonth.formatted(.dateTime.month(.wide).year()),
                onPrevious: { displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth },
                onNext: { displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth }
            )

            VStack(spacing: 0) {
                HStack {
                    ForEach(["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 8)

                let days = daysInMonth(for: displayedMonth)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(days.indices, id: \.self) { idx in
                        if let day = days[idx].0, let date = days[idx].1 {
                            CalendarDayCell(day: day, date: date, entries: entriesOn(date))
                                .onTapGesture {
                                    // Tag mit genau einem Job → direkt Details; sonst Liste unten nutzen
                                    let dayEntries = entriesOn(date)
                                    if dayEntries.count == 1 { selectedEntry = dayEntries[0] }
                                }
                        } else {
                            Color.clear.frame(height: 36)
                        }
                    }
                }
                legend.padding(.top, 12)
            }
            .padding(14)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([ApplicationStatus.confirmed, .applied, .completed, .cancelled], id: \.self) { status in
                HStack(spacing: 4) {
                    Circle().fill(status.calendarColor).frame(width: 7, height: 7)
                    Text(status.calendarLabel).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Week View

    private var weekView: some View {
        let weekDays = weekDays(offset: weekOffset)
        return VStack(spacing: 16) {
            navigationHeader(
                title: weekRangeLabel(weekDays),
                onPrevious: { weekOffset -= 1 },
                onNext: { weekOffset += 1 }
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(weekDays, id: \.self) { date in
                        CalendarWeekDayColumn(date: date, entries: entriesOn(date)) { selectedEntry = $0 }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Lists (kommend + vergangen getrennt)

    private var entryLists: some View {
        VStack(alignment: .leading, spacing: 20) {
            entrySection(title: "Upcoming Jobs", entries: upcomingEntries,
                         emptyText: "No upcoming jobs. Apply for shifts to fill your calendar.")
            if !pastEntries.isEmpty {
                entrySection(title: "Past Jobs", entries: pastEntries, emptyText: nil)
            }
        }
    }

    private func entrySection(title: String, entries: [CalendarEntry], emptyText: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            if entries.isEmpty, let emptyText {
                Text(emptyText)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            ForEach(entries) { entry in
                Button { selectedEntry = entry } label: { CalendarEntryRow(entry: entry) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
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
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.orange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Empty / Error

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 44)).foregroundColor(.white.opacity(0.35))
            Text("No jobs scheduled yet")
                .font(.system(size: 16, weight: .semibold)).foregroundColor(.white.opacity(0.8))
            Text("Apply for shifts and they will show up here.")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.55))
            NavigationLink {
                JobListView()
            } label: {
                Label("Find jobs nearby", systemImage: "location.magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(SS.primary)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Text("Your calendar could not be loaded.")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
            Button("Retry") { Task { await loadEntries() } }
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
        }
        .padding(.top, 40)
    }

    private func navigationHeader(title: String, onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) -> some View {
        HStack {
            chevronButton("chevron.left", label: "Previous", action: onPrevious)
            Spacer()
            Text(title).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            Spacer()
            chevronButton("chevron.right", label: "Next", action: onNext)
        }
        .padding(.horizontal, 16)
    }

    private func chevronButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
        }
        .accessibilityLabel(label)
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
