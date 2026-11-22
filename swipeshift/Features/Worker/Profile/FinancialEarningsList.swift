//
//  FinancialEarningsList.swift
//  swipeShift
//
//  Verdienstliste des Workers: pro Job Stundenlohn x Stunden = Betrag und Status
//  (Upcoming / Completed / Paid), gruppiert nach Monat der Schicht.
//  Betraege kommen fertig berechnet vom Backend (utils/jobCost.js).
//

import SwiftUI

extension WorkerEarningItem {
    enum DisplayStatus { case upcoming, completed, paid }

    /// Paid = abgeschlossen und vom Employer als bezahlt markiert
    var displayStatus: DisplayStatus {
        if status == "upcoming" { return .upcoming }
        return isPaid == true ? .paid : .completed
    }
}

struct EarningMonthGroup: Identifiable {
    let id: String          // "2026-11" bzw. "undated"
    let title: String       // "November 2026"
    let items: [WorkerEarningItem]

    /// Neueste Schicht zuerst; Eintraege ohne Datum landen unten in "Undated"
    static func make(from items: [WorkerEarningItem], calendar: Calendar = .current) -> [EarningMonthGroup] {
        let sorted = items.sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
        var order: [String] = []
        var buckets: [String: [WorkerEarningItem]] = [:]
        var titles: [String: String] = [:]
        for item in sorted {
            let key: String
            if let date = item.startTime {
                let c = calendar.dateComponents([.year, .month], from: date)
                key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
                titles[key] = date.formatted(ApplicationFormat.monthTitle)
            } else {
                key = "undated"
                titles[key] = "Undated"
            }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.map { EarningMonthGroup(id: $0, title: titles[$0] ?? $0, items: buckets[$0] ?? []) }
    }
}

struct EarningMonthSection: View {
    let group: EarningMonthGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title)
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            ForEach(group.items) { EarningRow(item: $0) }
        }
    }
}

struct EarningRow: View {
    let item: WorkerEarningItem

    private var statusLabel: (String, Color) {
        switch item.displayStatus {
        case .upcoming:  return ("Upcoming", .green)
        case .completed: return ("Completed", .secondary)
        case .paid:      return ("Paid", .orange)
        }
    }

    /// "$18/hr x 6.5 h"
    private var rateLine: String? {
        guard let rate = item.hourlyRate, let hours = item.hours else { return nil }
        let hoursText = hours.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(hours)) : String(format: "%.1f", hours)
        return "\(Money.hourly(rate)) × \(hoursText) h"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.jobTitle).font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                Text("\(item.company) · \(item.bookedShifts?.cardLabel ?? item.shiftText)")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                if let rateLine {
                    Text(rateLine).font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(item.amount)).font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
                Text(statusLabel.0)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(statusLabel.1)
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
