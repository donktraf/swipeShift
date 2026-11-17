//
//  CompanyPublicInfoViews.swift
//  swipeShift
//
//  Teil-Views fuer CompanyProfileView: Slogan/Gruendungsjahr, Social-Links,
//  Ansprechpartner, Adresse mit Karte. Leere Felder werden nicht angezeigt.
//

import SwiftUI
import MapKit

private func clean(_ value: String?) -> String? {
    guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
    return v
}

/// Slogan + "Founded <Jahr>" unter dem Firmennamen
struct CompanyTaglineView: View {
    let tagline: String?
    let yearFounded: Int?

    var body: some View {
        VStack(spacing: 4) {
            if let t = clean(tagline) {
                Text(t)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if let y = yearFounded {
                // Ohne Tausendertrennzeichen ("2015", nicht "2.015")
                Label("Founded \(String(y))", systemImage: "calendar")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

extension CompanyProfileDTO {
    var hasTaglineInfo: Bool { clean(tagline) != nil || yearFounded != nil }
    var hasSocialLinks: Bool { !(socialLinks?.items.isEmpty ?? true) }
    var hasContactPerson: Bool { clean(contactName) != nil }
    var hasAddress: Bool { clean(streetAddress) != nil || clean(zipCode) != nil }
}

/// Tappbare Social-Icons
struct CompanySocialLinksView: View {
    let links: SocialLinksDTO

    var body: some View {
        HStack(spacing: 12) {
            ForEach(links.items, id: \.name) { item in
                Link(destination: item.url) {
                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(SS.primary)
                        .frame(width: 42, height: 42)
                        .background(SS.primary.opacity(0.1))
                        .clipShape(Circle())
                }
                .accessibilityLabel(item.name)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Karte "Online & Contact person": Social-Links + oeffentlicher Ansprechpartner
struct CompanyPeopleAndLinksCard: View {
    let company: CompanyProfileDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CONNECT")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
            if let name = clean(company.contactName) {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 18)).foregroundColor(SS.primary)
                        .frame(width: 28).padding(.leading, 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contact").font(.system(size: 11)).foregroundColor(.secondary)
                        Text([name, clean(company.contactRole)].compactMap { $0 }.joined(separator: ", "))
                            .font(.system(size: 14)).foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            if let links = company.socialLinks, company.hasSocialLinks {
                if company.hasContactPerson { Divider().padding(.leading, 56) }
                CompanySocialLinksView(links: links)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

/// Adresse (Strasse, PLZ) mit kleiner Karte + "Open in Maps", wenn Koordinaten vorhanden
struct CompanyAddressCard: View {
    let company: CompanyProfileDTO

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = company.addressLat, let lng = company.addressLng,
              abs(lat) <= 90, abs(lng) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private var addressText: String {
        [clean(company.streetAddress), clean(company.zipCode)].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ADDRESS")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
            HStack(spacing: 14) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 16)).foregroundColor(SS.primary)
                    .frame(width: 28).padding(.leading, 14)
                Text(addressText).font(.system(size: 14)).foregroundColor(.primary)
                Spacer()
            }
            .padding(.vertical, 12)

            if let coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )), interactionModes: []) {
                    Marker(company.name, coordinate: coordinate).tint(SS.primary)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 14)
                .allowsHitTesting(false)

                Button { openInMaps(coordinate) } label: {
                    Label("Open in Maps", systemImage: "map")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SS.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private func openInMaps(_ coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = company.name
        item.openInMaps()
    }
}
