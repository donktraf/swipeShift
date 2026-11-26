//
//  ApplicantShiftFit.swift
//  swipeShift
//
//  "Available for this shift" auf der Bewerberkarte. Der Zeitkonflikt (anderer angenommener Job zur
//  selben Zeit) kommt vom Backend (hasScheduleConflict); Wochentag/Tageszeit werden hier mit der
//  Geraete-Zeitzone gegen die angegebene Verfuegbarkeit des Workers geprueft (der Server kennt keine Zeitzone).
//

import SwiftUI

enum ApplicantShiftFit: Equatable {
    case available      // passt zur angegebenen Verfuegbarkeit
    case outside        // ausserhalb der angegebenen Verfuegbarkeit
    case conflict       // hat zur selben Zeit einen anderen angenommenen Job (hat Vorrang)

    var text: String {
        switch self {
        case .available: return "Available for this shift"
        case .outside:   return "Outside stated availability"
        case .conflict:  return "Has another job at this time"
        }
    }
    var icon: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .outside:   return "exclamationmark.circle.fill"
        case .conflict:  return "xmark.octagon.fill"
        }
    }
    var tone: DS.Tone {
        switch self {
        case .available: return .success
        case .outside:   return .warning
        case .conflict:  return .danger
        }
    }
    var color: Color { tone.foreground }

    private static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] // Calendar.weekday 1 = Sonntag

    /// Tageszeit-Bucket zur Startstunde: morning 5–12, afternoon 12–17, evening 17–22, night 22–5
    static func timeBucket(forHour hour: Int) -> String {
        switch hour {
        case 5..<12:  return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default:      return "night"
        }
    }

    /// Bewertet nur den Schichtbeginn (Geraete-Zeitzone): Nachtschichten ueber Mitternacht werden gegen den Starttag geprueft.
    /// nil = nichts anzeigen (keine Verfuegbarkeit angegeben und kein Konflikt, oder Startzeit unbekannt)
    static func evaluate(hasConflict: Bool,
                         availableDays: [String],
                         availableTimes: [String],
                         start: Date?,
                         calendar: Calendar = .current) -> ApplicantShiftFit? {
        if hasConflict { return .conflict }
        guard let start, !(availableDays.isEmpty && availableTimes.isEmpty) else { return nil }
        if !availableDays.isEmpty {
            let name = weekdayNames[calendar.component(.weekday, from: start) - 1]
            if !availableDays.contains(name) { return .outside }
        }
        if !availableTimes.isEmpty {
            let bucket = timeBucket(forHour: calendar.component(.hour, from: start))
            if !availableTimes.contains(bucket) { return .outside }
        }
        return .available
    }
}

/// Kleine Zeile mit Icon + Text in der Ampelfarbe
struct ApplicantShiftFitLabel: View {
    let fit: ApplicantShiftFit
    /// Kompakt (Jobkarte): kleiner Punkt + kurzer Text in einer Zeile
    var compact: Bool = false

    var body: some View {
        if compact {
            HStack(spacing: 5) {
                Circle().fill(fit.color).frame(width: 6, height: 6)
                Text(fit.text)
                    .font(DS.Font.make(11, .semibold, relativeTo: .caption))
                    .foregroundStyle(fit.color)
                    .lineLimit(1)
            }
        } else {
            Label(fit.text, systemImage: fit.icon)
                .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                .foregroundStyle(fit.color)
        }
    }
}
