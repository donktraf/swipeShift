import Foundation

/// Geburtsdatum als reines Datum ("yyyy-MM-dd") — durchgehend in der lokalen Zeitzone,
/// damit der im DatePicker gewaehlte Tag beim Senden und Laden identisch bleibt.
enum DateOnly {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }

    /// Akzeptiert "yyyy-MM-dd" und volle ISO-Strings (nur die ersten 10 Zeichen zaehlen)
    static func date(from string: String) -> Date? { formatter.date(from: String(string.prefix(10))) }
}
