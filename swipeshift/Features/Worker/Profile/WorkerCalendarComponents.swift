//
//  WorkerCalendarComponents.swift
//  swipeShift
//
//  Modell + Bausteine fuer WorkerCalendarView: Eintraege mit Status-Farben, Zahlungsstatus,
//  Stornierungsgrund und Overlap-Erkennung, Monats-Grid, Wochenleiste, Detail-Sheet.
//  Vorgaben: Notion "Calendar Screen" (App Development Tracker) + CLAUDE.md Wireframe.
//

import SwiftUI

// MARK: - Model

struct CalendarEntry: Identifiable, Equatable {
    /// Eindeutig je Kalendereintrag: applyId, bei mehreren gebuchten Schichten "applyId#shiftId"
    let id: String
    let applyId: String
    let jobId: String
    let title: String
    let company: String
    let logoEmoji: String
    let location: String
    let payText: String
    let shiftText: String
    let start: Date
    let end: Date?
    let status: ApplicationStatus
    let paymentStatus: String?  // "paid" | "pending" (nur completed)
    let cancellationReason: String?
    let earnings: Double?
    let conversationId: String?
    let category: String?
    let distanceMiles: Double?
    let jobNotes: String?
    /// Bestaetigte, noch nicht begonnene Schicht → "Cancel shift"; < 24 h = kurzfristige Stornierung
    let canCancel: Bool
    let lateIfCancelledNow: Bool
    /// Gesetzt bei Eintraegen einer von mehreren gebuchten Schichten → nur diese Schicht absagen
    var shiftId: String? = nil
    /// Die einzige gebuchte Schicht → Dialog weist darauf hin, dass die Bewerbung zurueckgezogen wird
    var isLastShift = false
    /// Vom Employer erfasste Anwesenheit (vergangene Schichten) + Stand eines Einspruchs
    let attendance: String?
    let disputeStatus: String?
    var hasConflict = false

    /// Ein Eintrag je GEBUCHTER Schicht (bei mehreren gebuchten Schichten); sonst ein Eintrag fuer die Bewerbung
    static func entries(from item: WorkerApplicationItem) -> [CalendarEntry] {
        if let booked = item.bookedShifts, booked.count > 1 {
            let perShift = booked.compactMap { CalendarEntry(item: item, shift: $0) }
            if !perShift.isEmpty { return perShift }
        }
        return CalendarEntry(item: item).map { [$0] } ?? []
    }

    init?(item: WorkerApplicationItem, shift: BookedShift? = nil) {
        guard let start = shift?.startTime ?? item.startTime else { return nil }
        id = shift.map { "\(item.id)#\($0.id)" } ?? item.id
        applyId = item.id
        jobId = item.jobId
        title = item.jobTitle
        company = item.company
        logoEmoji = item.logoEmoji
        location = item.location
        payText = item.payText
        shiftText = shift.flatMap { $0.fullLabel.isEmpty ? nil : $0.fullLabel } ?? item.bookedShifts?.cardLabel ?? item.shiftText
        self.start = start
        end = shift != nil ? shift?.endTime : item.endTime
        switch item.displayStatus {
        case "confirmed": status = .confirmed
        case "completed": status = .completed
        case "cancelled": status = .cancelled
        default:          status = .applied
        }
        paymentStatus = item.paymentStatus
        cancellationReason = item.cancellationReason
        earnings = shift != nil ? nil : item.earnings  // Verdienst gilt fuer die ganze Buchung, nicht je Schicht
        conversationId = item.conversationId
        // Backend liefert "—" wenn der Job keine Kategorie hat
        category = item.category == "—" ? nil : item.category
        distanceMiles = item.distanceMiles
        jobNotes = item.jobNotes
        let bookedCount = item.bookedShifts?.count ?? 0
        if let cancelShift = shift ?? (bookedCount == 1 ? item.bookedShifts?.first : nil) {
            // Mit Schichtliste immer die Einzel-Absage; Altbestand ohne Liste → ganze Buchung (shiftId nil)
            shiftId = cancelShift.id
            isLastShift = bookedCount == 1
            canCancel = cancelShift.canCancel == true
            lateIfCancelledNow = cancelShift.lateIfCancelledNow == true
        } else {
            canCancel = item.canCancel == true
            lateIfCancelledNow = item.lateIfCancelledNow == true
        }
        attendance = item.attendance
        disputeStatus = item.disputeStatus
    }

    /// Vergangen = abgeschlossen, storniert oder Schicht vorbei → ausgegraut, eigene Liste
    func isPast(now: Date = Date()) -> Bool {
        status == .completed || status == .cancelled || (end ?? start) < now
    }

    /// Chat nur nach Annahme (Notion: "Only for accepted jobs")
    var canOpenChat: Bool {
        conversationId != nil && (status == .confirmed || status == .completed)
    }

    /// "09:00 – 13:00" in Geraetezeit, sonst der Schichttext vom Backend
    var timeLabel: String {
        let startText = start.formatted(date: .omitted, time: .shortened)
        guard let end else { return shiftText }
        return "\(startText) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    /// Markiert Eintraege, deren Schichten sich ueberschneiden (nur kommende applied/confirmed).
    /// Das Backend verhindert nur Konflikte mit bereits angenommenen Jobs — zwei offene
    /// Bewerbungen oder eine aeltere Bewerbung koennen sich trotzdem ueberlappen.
    static func markingConflicts(_ entries: [CalendarEntry], now: Date = Date()) -> [CalendarEntry] {
        var result = entries
        let active = result.indices.filter { idx in
            let entry = result[idx]
            return (entry.status == .applied || entry.status == .confirmed)
                && entry.end != nil && (entry.end ?? entry.start) > now
        }
        for (pos, i) in active.enumerated() {
            for j in active[(pos + 1)...] {
                guard let endI = result[i].end, let endJ = result[j].end else { continue }
                if result[i].start < endJ && result[j].start < endI {
                    result[i].hasConflict = true
                    result[j].hasConflict = true
                }
            }
        }
        return result
    }
}

// MARK: - Status-Darstellung

extension ApplicationStatus {
    /// Wireframe: Confirmed gruen, Applied grau. Completed in Markenfarbe, Cancelled gedaempft.
    var calendarColor: Color {
        switch self {
        case .confirmed: return .green
        case .applied:   return .gray
        case .completed: return SS.primary
        case .cancelled: return .gray.opacity(0.45)
        }
    }

    var calendarLabel: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .applied:   return "Applied"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Day Cell (Monats-Grid)

struct CalendarDayCell: View {
    let day: Int
    let date: Date
    let entries: [CalendarEntry]

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var hasConflict: Bool { entries.contains(where: \.hasConflict) }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(day)")
                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(isToday ? SS.primary : Color.clear)
                .clipShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if hasConflict {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                    }
                }

            HStack(spacing: 2) {
                ForEach(entries.prefix(3)) { entry in
                    Circle()
                        .fill(entry.status.calendarColor)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day), \(entries.count) jobs\(hasConflict ? ", overlapping shifts" : "")")
    }
}

// MARK: - Entry Row (Listen)

struct CalendarEntryRow: View {
    let entry: CalendarEntry

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(entry.status.calendarColor)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if entry.status == .cancelled {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.system(size: 12))
                    }
                    Text(entry.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .strikethrough(entry.status == .cancelled)
                }
                Text("\(entry.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(entry.timeLabel)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(entry.company)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if entry.status == .cancelled, let reason = entry.cancellationReason {
                    Text(reason)
                        .font(.system(size: 11)).italic()
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                if entry.status == .completed, let a = entry.attendance.flatMap(AttendanceStatus.init(rawValue:)) {
                    let review = entry.disputeStatus == "pending"
                    Label(review ? "Under review" : a.label, systemImage: review ? "hourglass" : a.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(review ? .orange : a.color)
                }
                if entry.hasConflict {
                    Label("Overlaps with another shift", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                CalendarStatusBadge(status: entry.status)
                if let payment = entry.paymentStatus {
                    CalendarPaymentBadge(paymentStatus: payment)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .opacity(entry.isPast() ? 0.7 : 1)
        .contentShape(Rectangle())
    }
}

struct CalendarStatusBadge: View {
    let status: ApplicationStatus

    var body: some View {
        Text(status.calendarLabel)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(status == .cancelled ? .secondary : .white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(status == .cancelled ? Color(uiColor: .systemGray5) : status.calendarColor)
            .clipShape(Capsule())
    }
}

struct CalendarPaymentBadge: View {
    let paymentStatus: String

    private var isPaid: Bool { paymentStatus == "paid" }

    var body: some View {
        Label(isPaid ? "Paid" : "Pending payout", systemImage: isPaid ? "checkmark.circle.fill" : "clock")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(isPaid ? .teal : .orange)
    }
}

// MARK: - Week Day Column

struct CalendarWeekDayColumn: View {
    let date: Date
    let entries: [CalendarEntry]
    let onSelect: (CalendarEntry) -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isToday ? SS.primary : .secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isToday ? SS.primary : .primary)
            }

            VStack(spacing: 6) {
                ForEach(entries) { entry in
                    Button { onSelect(entry) } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 3) {
                                if entry.hasConflict {
                                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                                }
                                Text(entry.title).lineLimit(2)
                            }
                            .font(.system(size: 11, weight: .semibold))
                            Text(entry.start.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10))
                        }
                        .foregroundColor(entry.status == .cancelled ? .secondary : .white)
                        .strikethrough(entry.status == .cancelled)
                        .padding(.horizontal, 6).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(entry.status == .cancelled ? Color(uiColor: .systemGray5) : entry.status.calendarColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(entry.hasConflict ? Color.orange : .clear, lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(entry.isPast() ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                }
                if entries.isEmpty {
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
