//
//  WorkerCalendarView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Calendar Mode

private enum CalendarMode { case month, week }

// MARK: - Calendar Job (Mock)

private struct CalendarJob: Identifiable {
    let id = UUID()
    let title: String
    let company: String
    let date: Date
    let timeRange: String
    let status: ApplicationStatus  // confirmed = grün, applied = grau
}

// MARK: - WorkerCalendarView

struct WorkerCalendarView: View {
    @State private var mode: CalendarMode = .month
    @State private var displayedMonth: Date = Date()

    private let calendar = Calendar.current

    // TODO: aus Backend laden
    private var mockJobs: [CalendarJob] {
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let inThree = calendar.date(byAdding: .day, value: 3, to: today)!
        let inSeven = calendar.date(byAdding: .day, value: 7, to: today)!
        return [
            CalendarJob(title: "Barkeeper",    company: "Club Tresor",   date: today,    timeRange: "22:00–04:00", status: .confirmed),
            CalendarJob(title: "Event Staff",  company: "Eventify GmbH", date: tomorrow, timeRange: "14:00–22:00", status: .confirmed),
            CalendarJob(title: "Warehouse",    company: "LogiCore",      date: inThree,  timeRange: "06:00–14:00", status: .applied),
            CalendarJob(title: "Retail",       company: "FashionHub",    date: inSeven,  timeRange: "10:00–18:00", status: .applied),
        ]
    }

    var body: some View {
        SubScreenShell(title: "Calendar") {
            VStack(spacing: 20) {
                modeToggle
                    .padding(.horizontal, 16)

                if mode == .month {
                    monthView
                } else {
                    weekView
                }
            }
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach([(CalendarMode.month, "Monat"), (CalendarMode.week, "Woche")], id: \.0) { m, label in
                Button { mode = m } label: {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(mode == m ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(mode == m ? SS.primary : Color.clear)
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
            // Month Header
            HStack {
                Button {
                    displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth)!
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }

                Spacer()

                Text(monthLabel(for: displayedMonth))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth)!
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)

            // Calendar Grid
            VStack(spacing: 0) {
                // Weekday headers
                HStack {
                    ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { d in
                        Text(d)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 8)

                // Days grid
                let days = daysInMonth(for: displayedMonth)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(days.indices, id: \.self) { idx in
                        let (day, date) = days[idx]
                        if let day, let date {
                            DayCell(day: day, date: date, jobs: jobsOn(date: date))
                        } else {
                            Color.clear.frame(height: 36)
                        }
                    }
                }

                Divider().padding(.top, 12)
            }
            .padding(14)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)

            // Upcoming Jobs List
            let upcoming = mockJobs.filter { $0.date >= calendar.startOfDay(for: Date()) }
                                    .sorted { $0.date < $1.date }
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Bevorstehende Jobs")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)

                    ForEach(upcoming) { job in
                        CalendarJobRow(job: job)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Week View

    private var weekView: some View {
        let weekDays = currentWeekDays()
        return VStack(spacing: 16) {
            // Week navigation header
            HStack {
                Text(weekRangeLabel(days: weekDays))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(weekDays, id: \.self) { date in
                        WeekDayColumn(date: date, jobs: jobsOn(date: date))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Helpers

    private func jobsOn(date: Date) -> [CalendarJob] {
        mockJobs.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    /// Returns array of (day number?, date?) with leading nil padding for weekday offset
    private func daysInMonth(for date: Date) -> [(Int?, Date?)] {
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = 1
        guard let firstDay = calendar.date(from: components) else { return [] }

        let weekday = (calendar.component(.weekday, from: firstDay) + 5) % 7 // Mon=0
        let range = calendar.range(of: .day, in: .month, for: firstDay)!

        var result: [(Int?, Date?)] = Array(repeating: (nil, nil), count: weekday)
        for d in range {
            var c = components; c.day = d
            if let dayDate = calendar.date(from: c) {
                result.append((d, dayDate))
            }
        }
        return result
    }

    private func currentWeekDays() -> [Date] {
        let today = Date()
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -weekday, to: today) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func weekRangeLabel(days: [Date]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "dd. MMM"
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let day: Int
    let date: Date
    let jobs: [CalendarJob]

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(day)")
                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(isToday ? SS.primary : Color.clear)
                .clipShape(Circle())

            if !jobs.isEmpty {
                HStack(spacing: 2) {
                    ForEach(jobs.prefix(2)) { job in
                        Circle()
                            .fill(job.status == .confirmed ? Color.green : Color.gray.opacity(0.5))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .frame(height: 44)
    }
}

// MARK: - Calendar Job Row

private struct CalendarJobRow: View {
    let job: CalendarJob

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(job.status == .confirmed ? Color.green : SS.primary)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(job.company) · \(job.timeRange)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(job.status == .confirmed ? "Confirmed" : "Applied")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(job.status == .confirmed ? Color.green : SS.primary)
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Week Day Column

private struct WeekDayColumn: View {
    let date: Date
    let jobs: [CalendarJob]

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    private var dayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private var dayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(dayLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isToday ? SS.primary : .secondary)
                Text(dayNumber)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isToday ? SS.primary : .primary)
            }

            VStack(spacing: 6) {
                ForEach(jobs) { job in
                    Text(job.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(job.status == .confirmed ? Color.green : SS.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if jobs.isEmpty {
                    Color.clear.frame(height: 30)
                }
            }
        }
        .frame(width: 80)
        .padding(10)
        .background(Color(uiColor: .systemBackground).opacity(isToday ? 1 : 0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
