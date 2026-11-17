//
//  ApplicationMonthGroups.swift
//  swipeShift
//
//  Gruppierung der Bewerbungen nach Monat ("November 2026") inkl. Summe der Verdienste.
//  Monat = Monat der Schicht (Fallback: Bewerbungsdatum). Verdienst = `earnings` vom Backend
//  (Stundenlohn x Schichtstunden, gleiche Formel wie die Finanzuebersicht).
//

import Foundation

/// Datums-Formate der Bewerbungsliste (App nur auf Englisch → feste Locale)
enum ApplicationFormat {
    static let locale = Locale(identifier: "en_US")
    /// "Nov 3"
    static let shortDate = Date.FormatStyle(locale: locale).month(.abbreviated).day()
    /// "November 2026"
    static let monthTitle = Date.FormatStyle(locale: locale).month(.wide).year()
}

struct ApplicationMonthGroup: Identifiable {
    let id: String                       // "2026-11"
    let title: String                    // "November 2026"
    let items: [WorkerApplicationItem]
    /// Summe der Verdienste der Gruppe (nil, wenn keine Verdienstangabe vorhanden ist)
    let totalEarnings: Double?

    /// - Parameter newestFirst: false = aelteste/naechste Schicht zuerst (Confirmed/Applied),
    ///   true = juengste zuerst (Completed/Cancelled)
    /// - Parameter includeEarnings: false fuer Stornierte (kein Verdienst)
    static func make(from items: [WorkerApplicationItem], newestFirst: Bool,
                     includeEarnings: Bool, calendar: Calendar = .current) -> [ApplicationMonthGroup] {
        func date(_ item: WorkerApplicationItem) -> Date { item.startTime ?? item.appliedAt }
        func key(_ item: WorkerApplicationItem) -> String {
            let c = calendar.dateComponents([.year, .month], from: date(item))
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }

        let sorted = items.sorted { newestFirst ? date($0) > date($1) : date($0) < date($1) }
        var order: [String] = []
        var buckets: [String: [WorkerApplicationItem]] = [:]
        for item in sorted {
            let k = key(item)
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(item)
        }

        return order.map { k in
            let groupItems = buckets[k] ?? []
            let amounts = groupItems.compactMap(\.earnings)
            return ApplicationMonthGroup(
                id: k,
                title: date(groupItems[0]).formatted(ApplicationFormat.monthTitle),
                items: groupItems,
                totalEarnings: includeEarnings && !amounts.isEmpty ? amounts.reduce(0, +) : nil
            )
        }
    }
}
