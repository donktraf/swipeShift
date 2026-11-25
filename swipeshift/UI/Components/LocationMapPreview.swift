//
//  LocationMapPreview.swift
//  swipeShift
//
//  Kleine, nicht interaktive Kartenvorschau mit Pin + "Open in Maps".
//  Geteilt von CompanyAddressCard (Firmenprofil) und JobDetailView.
//  Zeigt nichts an, wenn keine gueltigen Koordinaten vorliegen.
//

import SwiftUI
import MapKit

struct LocationMapPreview: View {
    let coordinate: CLLocationCoordinate2D?
    let title: String
    var height: CGFloat = 140

    init(lat: Double?, lng: Double?, title: String, height: CGFloat = 140) {
        self.coordinate = Self.coordinate(lat: lat, lng: lng)
        self.title = title
        self.height = height
    }

    /// nil bei fehlenden oder ungueltigen Werten
    static func coordinate(lat: Double?, lng: Double?) -> CLLocationCoordinate2D? {
        guard let lat, let lng, abs(lat) <= 90, abs(lng) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var body: some View {
        if let coordinate {
            VStack(spacing: DS.Spacing.xs) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )), interactionModes: []) {
                    Marker(title, coordinate: coordinate).tint(DS.Color.primary)
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(DS.Color.border, lineWidth: 1)
                )
                .allowsHitTesting(false)

                Button { openInMaps(coordinate) } label: {
                    Label("Open in Maps", systemImage: "map")
                }
                .buttonStyle(.ds(.soft, size: .medium))
            }
        }
    }

    private func openInMaps(_ coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = title
        item.openInMaps()
    }
}
