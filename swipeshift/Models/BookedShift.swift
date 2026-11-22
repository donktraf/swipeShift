//
//  BookedShift.swift
//  swipeShift
//
//  Von einem Worker gebuchte Schicht (Backend: Apply.shiftIds → describeBooked in utils/shiftBooking.js).
//

import Foundation

struct BookedShift: Identifiable, Decodable, Hashable {
    let id: String
    var date: String? = nil        // z.B. "Mon, Apr 28"
    var timeRange: String? = nil   // z.B. "18:00–23:00"
    var startTime: Date? = nil
    var endTime: Date? = nil

    private enum CodingKeys: String, CodingKey { case id, date, timeRange, startTime, endTime }

    /// Tolerant: ein Decoder ohne ISO-8601-Datumsstrategie darf nicht die ganze Liste scheitern lassen
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        date      = try? c.decodeIfPresent(String.self, forKey: .date)
        timeRange = try? c.decodeIfPresent(String.self, forKey: .timeRange)
        startTime = try? c.decodeIfPresent(Date.self, forKey: .startTime)
        endTime   = try? c.decodeIfPresent(Date.self, forKey: .endTime)
    }

    /// Kurzform fuer Listen: "Mon 12" (aus startTime, sonst der Datumstext des Employers)
    var shortLabel: String {
        if let startTime { return startTime.formatted(.dateTime.weekday(.abbreviated).day()) }
        return date ?? "Shift"
    }

    /// Einzelne Schicht ausgeschrieben: "Mon, Apr 28, 18:00–23:00"
    var fullLabel: String {
        [date, timeRange].compactMap { $0 }.joined(separator: ", ")
    }
}

extension Array where Element == BookedShift {
    /// "Mon 12 · Tue 13"
    var summaryLabel: String { map(\.shortLabel).joined(separator: " · ") }

    /// Text fuer Karten: eine Schicht ausgeschrieben, mehrere als Kurzliste; leer → nil (Aufrufer nutzt den Job-Text)
    var cardLabel: String? {
        switch count {
        case 0:  return nil
        case 1:  return self[0].fullLabel.isEmpty ? nil : self[0].fullLabel
        default: return "Shifts: \(summaryLabel)"
        }
    }
}
