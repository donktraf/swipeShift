//
//  EmployerCalendarView.swift
//  swipeShift
//

import SwiftUI

// MARK: - DTO

struct EmployerCalendarJobDTO: Identifiable, Decodable {
    let id: String
    let title: String
    let location: String
    let logoEmoji: String
    let startTime: Date
    let endTime: Date?
    let openSpots: Int
    let assignedCount: Int
    let category: String?
    let payText: String
    let shiftText: String
    /// Eigene Hinweise fuer die Worker (Job.jobNotes)
    var jobNotes: String? = nil
    /// Schichtkosten, gleiche Berechnung wie Finanzen (abgeschlossen = geschuldet, sonst geplant)
    let shiftCost: Double
    let workers: [EmployerCalendarWorkerDTO]
    let averageWorkerRating: Double?
}

// MARK: - Models

private enum EmployerCalendarMode { case month, week }

private enum ShiftFilter: String, CaseIterable {
    case all           = "All Jobs"
    case needsWorkers  = "Needs Workers"
    case fullyStaffed  = "Fully Staffed"
}

private struct EmployerCalJob: Identifiable {
    let id: String
    let title: String
    let location: String
    let logoEmoji: String
    let date: Date
    let startHour: Int    // 0–23
    let durationHours: Int
    let openSpots: Int      // remaining open spots
    let totalSpots: Int     // total spots posted
    let category: String?
    let payText: String
    let shiftText: String
    let jobNotes: String?
    let shiftCost: Double
    let workers: [EmployerCalendarWorkerDTO]
    let averageWorkerRating: Double?

    var isFullyStaffed: Bool { openSpots == 0 }
    var status: ShiftStatus { isFullyStaffed ? .fullyStaffed : (openSpots == totalSpots ? .needsWorkers : .partiallyStaffed) }

    var timeLabel: String {
        let end = (startHour + durationHours) % 24
        return String(format: "%02d:00–%02d:00", startHour, end)
    }

    init(dto: EmployerCalendarJobDTO) {
        let cal = Calendar.current
        self.id            = dto.id
        self.title         = dto.title
        self.location      = dto.location
        self.logoEmoji     = dto.logoEmoji
        self.date          = dto.startTime
        self.startHour     = cal.component(.hour, from: dto.startTime)
        self.totalSpots    = dto.openSpots
        self.category      = dto.category
        self.payText       = dto.payText
        self.shiftText     = dto.shiftText
        self.jobNotes      = dto.jobNotes
        self.shiftCost     = dto.shiftCost
        self.workers       = dto.workers
        self.averageWorkerRating = dto.averageWorkerRating
        self.openSpots     = max(dto.openSpots - dto.assignedCount, 0)

        if let end = dto.endTime {
            let diff = end.timeIntervalSince(dto.startTime)
            self.durationHours = max(Int(diff / 3600), 1)
        } else {
            self.durationHours = 4
        }
    }
}

private enum ShiftStatus {
    case needsWorkers, partiallyStaffed, fullyStaffed

    var tone: DS.Tone {
        switch self {
        case .needsWorkers:     return .warning
        case .partiallyStaffed: return .primary
        case .fullyStaffed:     return .success
        }
    }

    var color: Color { tone.foreground }

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
    @State private var allJobs: [EmployerCalJob] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let calendar = Calendar.current

    private var filteredJobs: [EmployerCalJob] {
        allJobs.filter { job in
            switch selectedFilter {
            case .all:          return true
            case .needsWorkers: return job.openSpots > 0
            case .fullyStaffed: return job.isFullyStaffed
            }
        }
    }

    private var jobDates: Set<String> {
        Set(filteredJobs.map { dateKey($0.date) })
    }

    var body: some View {
        SubScreenShell(title: "Calendar", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                controlsRow

                if isLoading && allJobs.isEmpty {
                    skeleton
                } else if let errorMessage, allJobs.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        Text(errorMessage)
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.text2)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.xl)
                } else if mode == .month {
                    monthContent
                } else {
                    weekContent
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private var skeleton: some View {
        VStack(spacing: DS.Spacing.sm) {
            DSSkeletonBlock(height: 300, radius: DS.Radius.card)
            DSSkeletonBlock(height: 80, radius: DS.Radius.card)
        }
        .accessibilityLabel("Loading calendar")
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let dtos = try await APIClient.shared.fetchEmployerCalendar()
            allJobs = dtos.map { EmployerCalJob(dto: $0) }
        } catch {
            errorMessage = "The calendar could not be loaded. Check your connection and try again."
        }
        isLoading = false
    }

    // MARK: - Controls

    private var controlsRow: some View {
        HStack(spacing: DS.Spacing.xs) {
            // Monat/Woche Toggle
            DSChip("Month", isSelected: mode == .month) { mode = .month }
            DSChip("Week", isSelected: mode == .week) { mode = .week }

            Spacer(minLength: 0)

            // Filter
            Menu {
                ForEach(ShiftFilter.allCases, id: \.self) { f in
                    Button(f.rawValue) { selectedFilter = f }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedFilter.rawValue)
                        .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                    if selectedFilter != .all {
                        Circle().fill(DS.Color.onPrimary).frame(width: 6, height: 6)
                    }
                }
                .foregroundStyle(selectedFilter != .all ? DS.Color.onPrimary : DS.Color.text2)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(
                    selectedFilter != .all ? DS.Color.primary : DS.Color.surface,
                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(selectedFilter != .all ? DS.Color.primary : DS.Color.border, lineWidth: 1)
                )
            }
            .accessibilityLabel("Filter: \(selectedFilter.rawValue)")
        }
    }

    // MARK: - Month Content

    private var monthContent: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            monthGrid
            upcomingJobsList
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            // Month Nav
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Color.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressable)
                .accessibilityLabel("Previous month")

                Spacer()

                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .dsFont(.headline)
                    .foregroundStyle(DS.Color.text)

                Spacer()

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Color.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressable)
                .accessibilityLabel("Next month")
            }

            // Weekday Headers
            HStack(spacing: 0) {
                ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { d in
                    Text(d)
                        .font(DS.Font.make(11, .semibold, relativeTo: .caption2))
                        .foregroundStyle(DS.Color.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, DS.Spacing.xs)

            // Day cells
            let days = monthDays()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: DS.Spacing.xxs) {
                ForEach(days, id: \.self) { date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday    = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let hasJob     = jobDates.contains(dateKey(date))

        return Button {
            DS.Haptics.selection()
            selectedDate = date
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(DS.Font.make(14, isToday || isSelected ? .bold : .regular, relativeTo: .callout))
                    .foregroundStyle(isSelected ? DS.Color.onPrimary : isToday ? DS.Color.primaryText : DS.Color.text)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? DS.Color.primary : isToday ? DS.Color.primarySoft : Color.clear, in: Circle())

                Circle()
                    .fill(hasJob ? DS.Color.warning : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsPressable)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(hasJob ? "Has jobs" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var upcomingJobsList: some View {
        let dayJobs = filteredJobs.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        return DSSection(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)), ruled: false) {
            if dayJobs.isEmpty {
                Text("No jobs on this day.")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.muted)
                    .padding(.vertical, DS.Spacing.xs)
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(dayJobs) { job in
                        EmployerCalJobCard(job: job)
                    }
                }
                .padding(.top, DS.Spacing.xs)
            }
        }
    }

    // MARK: - Week Content

    private var weekContent: some View {
        let weekDays = currentWeekDays()
        return VStack(spacing: 0) {
            // Day Headers
            HStack(spacing: 0) {
                // Time gutter
                Color.clear.frame(width: 40)
                ForEach(weekDays, id: \.self) { day in
                    let isToday = calendar.isDateInToday(day)
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.short)))
                            .font(DS.Font.make(11, .medium, relativeTo: .caption2))
                            .foregroundStyle(DS.Color.muted)
                        Text("\(calendar.component(.day, from: day))")
                            .font(DS.Font.make(14, .bold, relativeTo: .callout))
                            .foregroundStyle(isToday ? DS.Color.onPrimary : DS.Color.text)
                            .frame(width: 28, height: 28)
                            .background(isToday ? DS.Color.primary : Color.clear, in: Circle())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.surface2)

            // Timetable (06:00–02:00 next day)
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Hour lines
                    VStack(spacing: 0) {
                        ForEach(6..<26, id: \.self) { hour in
                            HStack(alignment: .top, spacing: 0) {
                                Text(String(format: "%02d:00", hour % 24))
                                    .font(DS.Font.make(10, .medium, relativeTo: .caption2))
                                    .foregroundStyle(DS.Color.muted)
                                    .frame(width: 40, alignment: .leading)
                                DSDivider()
                                    .frame(maxHeight: .infinity, alignment: .top)
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
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Color.border, lineWidth: 1)
        )
    }

    private func weekJobBlock(_ job: EmployerCalJob) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(job.title)
                .font(DS.Font.make(10, .bold, relativeTo: .caption2))
                .lineLimit(1)
            Text(job.timeLabel)
                .font(DS.Font.make(9, .medium, relativeTo: .caption2))
            Text("\(job.totalSpots - job.openSpots)/\(job.totalSpots)")
                .font(DS.Font.make(9, .medium, relativeTo: .caption2))
        }
        .foregroundStyle(job.status.tone.foreground)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(job.status.tone.soft, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(job.status.tone.foreground).frame(width: 3).padding(.vertical, 2)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.title), \(job.timeLabel), \(job.status.label)")
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
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                header
                details
                if let notes = job.jobNotes {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Label("Your notes for workers", systemImage: "note.text")
                            .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                            .foregroundStyle(DS.Color.primaryText)
                        Text(notes)
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !job.workers.isEmpty {
                    DSDivider()
                    CalendarShiftWorkersSection(
                        workers: job.workers,
                        averageRating: job.averageWorkerRating,
                        jobId: job.id, jobTitle: job.title, payText: job.payText,
                        shiftText: job.shiftText, location: job.location, logoEmoji: job.logoEmoji
                    )
                }
            }
        }
    }

    /// Kategorie + Schichtkosten
    private var details: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let category = job.category, !category.isEmpty {
                DSBadge(category, .tone(.primary))
            }
            Label("Shift cost \(Money.format(job.shiftCost)) incl. fee", systemImage: "banknote")
                .dsFont(.caption)
                .foregroundStyle(DS.Color.text2)
            Spacer()
        }
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSAvatar(text: job.logoEmoji, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .dsFont(.headline)
                    .foregroundStyle(DS.Color.text)
                Text("\(job.timeLabel) · \(job.location)")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.text2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: DS.Spacing.xxs) {
                Text("\(job.totalSpots - job.openSpots)/\(job.totalSpots)")
                    .font(DS.Font.make(14, .bold, relativeTo: .callout))
                    .foregroundStyle(job.status.tone.foreground)
                DSBadge(job.status.label, .tone(job.status.tone))
            }
        }
    }
}
