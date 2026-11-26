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
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(group.title)
                .dsFont(.sectionLabel).foregroundStyle(DS.Color.muted)
            ForEach(group.items) { EarningRow(item: $0) }
        }
    }
}

struct EarningRow: View {
    let item: WorkerEarningItem

    private var statusBadge: DSBadge {
        switch item.displayStatus {
        case .upcoming:  return DSBadge("Upcoming", .upcoming)
        case .completed: return DSBadge("Completed", .completed)
        case .paid:      return DSBadge("Paid", .tone(.warning))
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
        DSCard {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.jobTitle).dsFont(.callout).foregroundStyle(DS.Color.text)
                    Text("\(item.company) · \(item.bookedShifts?.cardLabel ?? item.shiftText)")
                        .dsFont(.caption).foregroundStyle(DS.Color.muted)
                    if let rateLine {
                        Text(rateLine).dsFont(.caption).foregroundStyle(DS.Color.muted)
                    }
                }
                Spacer(minLength: DS.Spacing.xs)
                VStack(alignment: .trailing, spacing: DS.Spacing.xxs) {
                    Text(Money.format(item.amount))
                        .font(DS.Font.make(15, .bold)).foregroundStyle(DS.Color.text)
                    statusBadge
                }
            }
        }
    }
}
