//
//  CompanyPublicInfoViews.swift
//  swipeShift
//
//  Teil-Views fuer CompanyProfileView: Slogan/Gruendungsjahr, Social-Links,
//  Ansprechpartner, Adresse mit Karte. Leere Felder werden nicht angezeigt.
//

import SwiftUI

private func clean(_ value: String?) -> String? {
    guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
    return v
}

/// Slogan + "Founded <Jahr>" unter dem Firmennamen
struct CompanyTaglineView: View {
    let tagline: String?
    let yearFounded: Int?

    var body: some View {
        VStack(spacing: DS.Spacing.xxs) {
            if let t = clean(tagline) {
                Text(t)
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text2)
                    .multilineTextAlignment(.center)
            }
            if let y = yearFounded {
                // Ohne Tausendertrennzeichen ("2015", nicht "2.015")
                Label("Founded \(String(y))", systemImage: "calendar")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.muted)
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
        HStack(spacing: DS.Spacing.sm) {
            ForEach(links.items, id: \.name) { item in
                Link(destination: item.url) {
                    Image(systemName: item.icon)
                        .font(DS.Font.make(16, .semibold, relativeTo: .body))
                        .foregroundStyle(DS.Color.primaryText)
                        .frame(width: 44, height: 44)
                        .background(DS.Color.primarySoft, in: Circle())
                }
                .buttonStyle(.dsPressable)
                .accessibilityLabel(item.name)
            }
            Spacer()
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}

/// Abschnitt "Connect": Ansprechpartner + Social-Links
struct CompanyPeopleAndLinksCard: View {
    let company: CompanyProfileDTO

    var body: some View {
        DSSection("Connect") {
            if let name = clean(company.contactName) {
                DSRow(
                    "Contact",
                    value: [name, clean(company.contactRole)].compactMap { $0 }.joined(separator: ", "),
                    systemIcon: "person.crop.circle.fill",
                    showsDivider: false
                )
            }
            if let links = company.socialLinks, company.hasSocialLinks {
                DSDivider().opacity(company.hasContactPerson ? 1 : 0)
                CompanySocialLinksView(links: links)
            }
        }
    }
}

/// Adresse (Strasse, PLZ) mit kleiner Karte + "Open in Maps", wenn Koordinaten vorhanden
struct CompanyAddressCard: View {
    let company: CompanyProfileDTO

    private var addressText: String {
        [clean(company.streetAddress), clean(company.zipCode)].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        DSSection("Address", ruled: false) {
            DSRow(addressText, systemIcon: "mappin.and.ellipse", showsDivider: false)
            LocationMapPreview(lat: company.addressLat, lng: company.addressLng, title: company.name)
                .padding(.top, DS.Spacing.xs)
        }
    }
}
