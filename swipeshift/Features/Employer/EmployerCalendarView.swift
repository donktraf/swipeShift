//
//  EmployerCalendarView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Models

private enum EmployerCalendarMode { case month, week }

private enum ShiftFilter: String, CaseIterable {
    case all           = "All Jobs"
    case needsWorkers  = "Needs Workers"
    case fullyStaffed  = "Fully Staffed"
}

private struct EmployerCalJob: Identifiable {
    let id = UUID()
    let title: String
    let location: String
    let logoEmoji: String
    let date: Date
    let startHour: Int    // 0–23
    let durationHours: Int
    let openSpots: Int
    let totalSpots: Int

    var isFullyStaffed: Bool { openSpots == 0 }
    var status: ShiftStatus { isFullyStaffed ? .fullyStaffed : (openSpots == totalSpots ? .needsWorkers : .partiallyStaffed) }

    var timeLabel: String {
        let end = startHour + durationHours
        return String(format: "%02d:00–%02d:00", startHour, end)
    }
}

private enum ShiftStatus {
    case needsWorkers, partiallyStaffed, fullyStaffed

    var color: Color {
        switch self {
        case .needsWorkers:     return .orange
        case .partiallyStaffed: return SS.primary
        case .fullyStaffed:     return .green
        }
    }

    var label: String {
        switch self {
        case .needsWorkers:     return "Needs Workers"
        case .partiallyStaffed: return "Partially Staffed"
        case .fullyStaffed:     return "Fully Staffed"
        }
    }
}

// MARK: - EmployerCalendarView

struct EmployerCalendarView: View {
    @State private var mode: EmployerCalendarMode = .month
    @State private var selectedFilter: ShiftFilter = .all
    @State private var displayedMonth: Date = .now
    @State private var selectedDate: Date = .now

    private let calendar = Calendar.current

    private var mockJobs: [EmployerCalJob] {
        let today = Date()
        return [
            EmployerCalJob(title: "Event Staff",  location: "Marienplatz",  logoEmoji: "🎪", date: today,                                            startHour: 18, durationHours: 5, openSpots: 1, totalSpots: 3),
            EmployerCalJob(title: "Barkeeper",     location: "Schwabing",    logoEmoji: "🍹", date: today,                                            startHour: 20, durationHours: 6, openSpots: 0, totalSpots: 2),
            EmployerCalJob(title: "Warehouse Worker", location: "Munich North", logoEmoji: "📦", date: calendar.date(byAdding: .day, value: 1, to: today)!, startHour: 6,  durationHours: 8, openSpots: 2, totalSpots: 4),
            EmployerCalJob(title: "Retail Helper", location: "Pasing",      logoEmoji: "🛍️", date: calendar.date(byAdding: .day, value: 2,  to: today)!, startHour: 10, durationHours: 6, openSpots: 0, totalSpots: 1),
            EmployerCalJob(title: "Cleaning",       location: "Sendling",    logoEmoji: "🧹", date: calendar.date(byAdding: .day, value: 3,  to: today)!, startHour: 8,  durationHours: 4, openSpots: 1, totalSpots: 2),
            EmployerCalJob(title: "Event Staff",   location: "Olympiapark", logoEmoji: "🎪", date: calendar.date(byAdding: .day, value: 5,  to: today)!, startHour: 14, durationHours: 8, openSpots: 3, totalSpots: 5),
            EmployerCalJob(title: "Security",      location: "Haidhausen",  logoEmoji: "🔒", date: calendar.date(byAdding: .day, value: 7,  to: today)!, startHour: 22, durationHours: 8, openSpots: 0, totalSpots: 2),
            EmployerCalJob(title: "Barkeeper",     location: "Maxvorstadt",  logoEmoji: "🍹", date: calendar.date(byAdding: .day, value: 9,  to: today)!, startHour: 19, durationHours: 5, openSpots: 1, totalSpots: 2),
        ]
    }

    private var filteredJobs: [EmployerCalJob] {
        mockJobs.filter { job in
            switch selectedFilter {
            case .all:          return true
            case .needsWorkers: return job.openSpots > 0
            case .fullyStaffed: return job.isFullyStaffed
            }
        }
    }

    // Datum-Set der Tage mit Jobs (für Monatsgitter-Punkte)
    private var jobDates: Set<String> {
        Set(filteredJobs.map { dateKey($0.date) })
    }

    var body: some View {
        SubScreenShell(title: "Calendar") {
            VStack(spacing: 0) {
                // Controls: Toggle + Filter
                controlsRow
                    .padding(.bottom, 12)

                if mode == .month {
                    monthContent
                } else {
                    weekContent
                }
            }
        }
    }

    // MARK: - Controls

    private var controlsRow: some View {
        HStack(spacing: 10) {
            // Monat/Woche Toggle
            HStack(spacing: 0) {
                modeButton("Month", target: .month)
                modeButton("Week", target: .week)
            }
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())

            // Filter
            Menu {
                ForEach(ShiftFilter.allCases, id: \.self) { f in
                    Button(f.rawValue) { selectedFilter = f }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 13))
                    Text(selectedFilter.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                    if selectedFilter != .all {
                        Circle().fill(.white).frame(width: 6, height: 6)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selectedFilter != .all ? SS.primary.opacity(0.9) : Color.white.opacity(0.2))
                .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func modeButton(_ label: String, target: EmployerCalendarMode) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.18)) { mode = target } } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(mode == target ? SS.primary : .white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(mode == target ? Color.white : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Month Content

    private var monthContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                monthGrid
                upcomingJobsList
                Spacer().frame(height: 24)
            }
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            // Month Nav
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)

            // Weekday Headers
            HStack(spacing: 0) {
                ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)

            // Day cells
            let days = monthDays()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday    = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let hasJob     = jobDates.contains(dateKey(date))

        return Button { selectedDate = date } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundColor(isSelected ? SS.primary : isToday ? .white : .white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(isSelected ? Color.white : isToday ? Color.white.opacity(0.2) : Color.clear)
                    .clipShape(Circle())

                Circle()
                    .fill(hasJob ? Color.orange : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .frame(height: 42)
    }

    private var upcomingJobsList: some View {
        let dayJobs = filteredJobs.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 16)

            if dayJobs.isEmpty {
                Text("No jobs on this day.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(dayJobs) { job in
                        EmployerCalJobCard(job: job)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Week Content

    private var weekContent: some View {
        let weekDays = currentWeekDays()
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Day Headers
                HStack(spacing: 0) {
                    // Time gutter
                    Color.clear.frame(width: 40)
                    ForEach(weekDays, id: \.self) { day in
                        let isToday = calendar.isDateInToday(day)
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.short)))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(calendar.component(.day, from: day))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(isToday ? SS.primary : .white)
                                .frame(width: 28, height: 28)
                                .background(isToday ? Color.white : Color.clear)
                                .clipShape(Circle())
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))

                // Timetable (06:00–02:00 next day)
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // Hour lines
                        VStack(spacing: 0) {
                            ForEach(6..<26, id: \.self) { hour in
                                HStack(alignment: .top, spacing: 0) {
                                    Text(String(format: "%02d:00", hour % 24))
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.35))
                                        .frame(width: 40, alignment: .leading)
                                        .padding(.leading, 8)
                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                }
                                .frame(height: 56)
                            }
                        }

                        // Job overlays
                        HStack(alignment: .top, spacing: 0) {
                            Color.clear.frame(width: 40)
                            ForEach(weekDays, id: \.self) { day in
                                let dayJobs = filteredJobs.filter { calendar.isDate($0.date, inSameDayAs: day) }
                                ZStack(alignment: .topLeading) {
                                    Color.clear
                                    ForEach(dayJobs) { job in
                                        let topOffset = CGFloat(max(job.startHour - 6, 0)) * 56
                                        let height = CGFloat(job.durationHours) * 56 - 4
                                        weekJobBlock(job)
                                            .frame(height: max(height, 28))
                                            .offset(y: topOffset + 2)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 400)
            }
        }
    }

    private func weekJobBlock(_ job: EmployerCalJob) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(job.title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
            Text(job.timeLabel)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.8))
            Text("\(job.totalSpots - job.openSpots)/\(job.totalSpots)")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(job.status.color.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 2)
    }

    // MARK: - Helpers

    private func shiftMonth(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = d
        }
    }

    private func monthDays() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: monthInterval.start).weekday else {
            return []
        }
        // Adjust: Monday=0
        let offset = (firstWeekday + 5) % 7
        var days: [Date?] = Array(repeating: nil, count: offset)

        var current = monthInterval.start
        while current < monthInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        // Pad to full rows
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private func currentWeekDays() -> [Date] {
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday + 5) % 7   // Monday=0
        guard let monday = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func dateKey(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day())
    }
}

// MARK: - EmployerCalJobCard

private struct EmployerCalJobCard: View {
    let job: EmployerCalJob

    var body: some View {
        HStack(spacing: 12) {
            // Status-Stripe
            RoundedRectangle(cornerRadius: 3)
                .fill(job.status.color)
                .frame(width: 4)
                .padding(.vertical, 2)

            Text(job.logoEmoji)
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(Color.gray.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(job.timeLabel) · \(job.location)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(job.totalSpots - job.openSpots)/\(job.totalSpots)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(job.status.color)
                Text(job.status.label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
