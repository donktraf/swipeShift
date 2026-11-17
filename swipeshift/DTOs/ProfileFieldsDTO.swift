//
//  ProfileFieldsDTO.swift
//  swipeShift
//
//  Zusatzfelder der Profile (Worker: Tageszeiten, Schicht-Typen, Erfahrung;
//  Employer: oeffentliche Firmeninfos). Whitelists gespiegelt aus backend utils/profileFields.js.
//

import Foundation

/// Tageszeiten, zu denen ein Worker arbeiten kann
enum WorkerAvailableTime: String, CaseIterable, Identifiable {
    case morning, afternoon, evening, night
    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning:   return "Morning"
        case .afternoon: return "Afternoon"
        case .evening:   return "Evening"
        case .night:     return "Night"
        }
    }
    var icon: String {
        switch self {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening:   return "sunset.fill"
        case .night:     return "moon.stars.fill"
        }
    }
}

/// Bevorzugte Schicht-Typen. "Last minute" gibt es bewusst nicht als Chip:
/// das deckt der Schalter "Available for same-day jobs" (availableForSameDay) ab.
enum WorkerShiftType: String, CaseIterable, Identifiable {
    case oneDay, weekend, eventBased
    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay:     return "One-day jobs"
        case .weekend:    return "Weekend"
        case .eventBased: return "Event-based"
        }
    }
}

/// Vorerfahrung je Kategorie
enum ExperienceLevel: String, CaseIterable, Codable, Identifiable {
    case lt3m, m3to12, gt1y
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lt3m:   return "< 3 months"
        case .m3to12: return "3–12 months"
        case .gt1y:   return "1+ years"
        }
    }
}

struct WorkerExperienceEntry: Codable, Hashable, Identifiable {
    let category: String
    let level: ExperienceLevel
    var id: String { category }
}

/// Social-Links einer Firma (Backend liefert normalisierte http(s)-URLs)
struct SocialLinksDTO: Codable, Equatable {
    var instagram: String?
    var linkedin: String?
    var facebook: String?
    var tiktok: String?

    /// Fuer die Anzeige: nur belegte Netzwerke mit gueltiger URL
    var items: [(name: String, icon: String, url: URL)] {
        let all: [(String, String, String?)] = [
            ("Instagram", "camera.fill", instagram),
            ("LinkedIn", "briefcase.fill", linkedin),
            ("Facebook", "person.2.fill", facebook),
            ("TikTok", "music.note", tiktok)
        ]
        return all.compactMap { name, icon, raw in
            guard let raw, let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
            return (name, icon, url)
        }
    }
}

/// Encodiert eine Zahl oder explizit null (Standard-Optionals werden sonst weggelassen) —
/// noetig, um gespeicherte Koordinaten wieder zu loeschen.
enum NullableDouble: Encodable {
    case value(Double)
    case null

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .value(let v): try c.encode(v)
        case .null:         try c.encodeNil()
        }
    }
}

// MARK: - Tolerantes Dekodieren

/// Ein unbekannter `level` (z.B. durch eine neuere Backend-Version) darf das Dekodieren von
/// UserDTO/WorkerProfileDTO nicht scheitern lassen: solche Eintraege werden uebersprungen.
extension KeyedDecodingContainer {
    func decode(_ type: [WorkerExperienceEntry].Type, forKey key: Key) throws -> [WorkerExperienceEntry] {
        try decodeIfPresent(type, forKey: key) ?? []
    }

    func decodeIfPresent(_ type: [WorkerExperienceEntry].Type, forKey key: Key) throws -> [WorkerExperienceEntry]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        var list = try nestedUnkeyedContainer(forKey: key)
        var out: [WorkerExperienceEntry] = []
        while !list.isAtEnd {
            if let entry = try? list.decode(WorkerExperienceEntry.self) {
                out.append(entry)
            } else {
                _ = try? list.decode(DiscardedValue.self) // Element ueberspringen, Index weiterschieben
            }
        }
        return out
    }
}

private struct DiscardedValue: Decodable {
    init(from decoder: Decoder) throws {}
}
