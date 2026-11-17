import Foundation

/// Zentrale Waehrungsformatierung (US-Dollar, App nur auf Englisch).
/// Feste Locale en_US, damit auch Geraete mit anderer Region "$18" statt "18,00 $" zeigen.
///
/// Regel (identisch zu formatAmount im Backend, utils/jobData.js):
/// ganze Betraege ohne Nachkommastellen, sonst immer 2 ("$18", "$15.50", "$1,250.75").
/// Gerundet wird nur auf Cent (halfUp), nie auf ganze Dollar.
enum Money {
    static let currencyCode = "USD"

    private static func makeFormatter(fractionDigits: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.roundingMode = .halfUp
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        return f
    }

    // Einmal konfiguriert, wiederverwendet (nur aus dem Main-Thread der UI genutzt).
    private static let wholeFormatter = makeFormatter(fractionDigits: 0)
    private static let centFormatter  = makeFormatter(fractionDigits: 2)

    /// Standard: ganz -> "$18", sonst "$15.50". Mit `fractionDigits: 2` immer Cent ("$18.00").
    static func format(_ amount: Double, fractionDigits: Int? = nil) -> String {
        let cents = (amount * 100).rounded(.toNearestOrAwayFromZero)
        let useCents = fractionDigits == 2 || (fractionDigits == nil && cents.truncatingRemainder(dividingBy: 100) != 0)
        let formatter = useCents ? centFormatter : wholeFormatter
        return formatter.string(from: NSNumber(value: cents / 100)) ?? "$\(amount)"
    }

    static func format(_ amount: Int) -> String { format(Double(amount)) }

    /// z.B. "$18/hr", "$15.50/hr"
    static func hourly(_ amount: Double) -> String { format(amount) + "/hr" }
}
