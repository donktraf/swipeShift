import Foundation

/// Zentrale Distanz-Umrechnung. US-Launch: alle Anzeigen und Filter in Meilen.
/// Intern (Haversine) wird in km gerechnet; das Backend akzeptiert fuer /jobs/nearby `unit=mi`.
enum Distance {
    static let kmPerMile = 1.609344

    static func miles(fromKm km: Double) -> Double { km / kmPerMile }

    /// Haversine-Distanz in Meilen zwischen zwei Koordinatenpaaren
    static func haversineMiles(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let r  = 6371.0 // Erdradius in km
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let Δφ = (lat2 - lat1) * .pi / 180
        let Δλ = (lng2 - lng1) * .pi / 180
        let a  = sin(Δφ/2) * sin(Δφ/2) + cos(φ1) * cos(φ2) * sin(Δλ/2) * sin(Δλ/2)
        return miles(fromKm: r * 2 * atan2(sqrt(a), sqrt(1 - a)))
    }
}
