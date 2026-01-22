import Foundation
import Combine
import MapKit

struct LocationSuggestion: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let fullText: String
    let lat: Double
    let lng: Double
}

final class LocationGeocoder: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    @Published var suggestions: [LocationSuggestion] = []

    private let completer = MKLocalSearchCompleter()
    private var lastQuery: String = ""
    private var isSearching = false

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lastQuery = q

        if q.isEmpty {
            suggestions = []
            return
        }

        completer.queryFragment = q
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(6))
        Task { @MainActor in
            await resolveCompleterResults(results)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }

    @MainActor
    private func resolveCompleterResults(_ results: [MKLocalSearchCompletion]) async {
        if isSearching { return }
        isSearching = true
        defer { isSearching = false }

        var items: [LocationSuggestion] = []

        for r in results {
            if completer.queryFragment != lastQuery { break }

            let request = MKLocalSearch.Request(completion: r)
            let search = MKLocalSearch(request: request)

            do {
                let response = try await search.start()
                if let mapItem = response.mapItems.first,
                   let coord = mapItem.placemark.location?.coordinate {

                    let title = r.title
                    let subtitle = r.subtitle
                    let full = subtitle.isEmpty ? title : "\(title), \(subtitle)"

                    items.append(
                        LocationSuggestion(
                            title: title,
                            subtitle: subtitle,
                            fullText: full,
                            lat: coord.latitude,
                            lng: coord.longitude
                        )
                    )
                }
            } catch {
                continue
            }
        }

        var seen = Set<String>()
        self.suggestions = items.filter { seen.insert($0.fullText).inserted }
    }
}
