//
//  EmployerPublicProfileFields.swift
//  swipeShift
//
//  Oeffentliche Firmeninfos fuer EditEmployerProfileView (Tab "Company"):
//  Slogan, Gruendungsjahr, Social-Links, Adresse (mit Ortssuche), Ansprechpartner, Flags.
//  Ausgelagert, damit EditEmployerProfileView nicht weiter waechst.
//

import SwiftUI

/// Formularzustand der oeffentlichen Firmeninfos (Prefill + Request-Mapping an einer Stelle)
struct EmployerPublicProfileForm: Equatable {
    var tagline = ""
    var yearFounded = ""
    var instagram = ""
    var linkedin = ""
    var facebook = ""
    var tiktok = ""
    var streetAddress = ""
    var zipCode = ""
    var addressLat: Double? = nil
    var addressLng: Double? = nil
    var contactName = ""
    var contactRole = ""
    var postsInMultipleStates = false
    var remoteFriendly = false

    init() {}

    init(user u: UserDTO) {
        tagline       = u.tagline ?? ""
        yearFounded   = u.yearFounded.map(String.init) ?? ""
        instagram     = u.socialLinks?.instagram ?? ""
        linkedin      = u.socialLinks?.linkedin ?? ""
        facebook      = u.socialLinks?.facebook ?? ""
        tiktok        = u.socialLinks?.tiktok ?? ""
        streetAddress = u.streetAddress ?? ""
        zipCode       = u.zipCode ?? ""
        addressLat    = u.addressLat
        addressLng    = u.addressLng
        contactName   = u.publicContactName ?? ""
        contactRole   = u.publicContactRole ?? ""
        postsInMultipleStates = u.postsInMultipleStates ?? false
        remoteFriendly        = u.remoteFriendly ?? false
    }

    /// Schreibt die Felder in den Request. Leere Strings loeschen das Feld im Backend.
    func apply(to request: inout UpdateEmployerProfileRequest) {
        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        request.tagline       = trimmed(tagline)
        request.yearFounded   = trimmed(yearFounded)
        request.socialLinks   = SocialLinksDTO(
            instagram: trimmed(instagram), linkedin: trimmed(linkedin),
            facebook: trimmed(facebook), tiktok: trimmed(tiktok)
        )
        request.streetAddress = trimmed(streetAddress)
        request.zipCode       = trimmed(zipCode)
        request.addressLat    = addressLat.map { .value($0) } ?? .null
        request.addressLng    = addressLng.map { .value($0) } ?? .null
        request.publicContactName = trimmed(contactName)
        request.publicContactRole = trimmed(contactRole)
        request.postsInMultipleStates = postsInMultipleStates
        request.remoteFriendly        = remoteFriendly
    }
}

struct EmployerPublicProfileSection: View {
    @Binding var form: EmployerPublicProfileForm

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            DSSection("Public Profile", ruled: false) {
                fields {
                    DSTextField("Tagline", placeholder: "Short slogan (max. 80)", text: $form.tagline)
                        .onChange(of: form.tagline) { _, new in
                            if new.count > 80 { form.tagline = String(new.prefix(80)) }
                        }
                    DSTextField("Founded", placeholder: "Year, e.g. 2015", text: $form.yearFounded)
                        .keyboardType(.numberPad)
                        .onChange(of: form.yearFounded) { _, new in
                            let digits = new.filter(\.isNumber)
                            let limited = String(digits.prefix(4))
                            if limited != new { form.yearFounded = limited }
                        }
                }
            }

            DSSection("Social Links", ruled: false) {
                fields {
                    DSTextField("Instagram", placeholder: "@handle or link", text: $form.instagram)
                        .modifier(SocialFieldStyle())
                    DSTextField("LinkedIn", placeholder: "Link or @handle", text: $form.linkedin)
                        .modifier(SocialFieldStyle())
                    DSTextField("Facebook", placeholder: "Link or @handle", text: $form.facebook)
                        .modifier(SocialFieldStyle())
                    DSTextField("TikTok", placeholder: "@handle or link", text: $form.tiktok)
                        .modifier(SocialFieldStyle())
                }
            }

            DSSection("Address", ruled: false) {
                fields {
                    AddressSearchField(
                        street: $form.streetAddress,
                        lat: $form.addressLat,
                        lng: $form.addressLng,
                        onSuggestionZip: { zip in if form.zipCode.isEmpty { form.zipCode = zip } }
                    )
                    Text("Your address is shown on your public company profile.")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                    DSTextField("ZIP Code", placeholder: "12345 or 12345-6789", text: $form.zipCode)
                        .keyboardType(.numbersAndPunctuation)
                    if form.addressLat != nil {
                        Label("Location pinned on map", systemImage: "mappin.and.ellipse")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.muted)
                    }
                }
            }

            DSSection("Public Contact Person", ruled: false) {
                fields {
                    DSTextField("Name", placeholder: "Jane Doe", text: $form.contactName)
                    DSTextField("Role", placeholder: "Hiring Manager", text: $form.contactRole)
                }
            }

            DSSection("Hiring") {
                DSToggleRow("Posts jobs in multiple states", showsDivider: false, isOn: $form.postsInMultipleStates)
                DSToggleRow("Remote-friendly roles", isOn: $form.remoteFriendly)
            }
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
    }

    private func fields<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) { content() }
            .padding(.top, DS.Spacing.xxs)
    }
}

private struct SocialFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}

// MARK: - Adress-Suche (gleiche Mechanik wie Location in PostJobView: LocationGeocoder)

private struct AddressSearchField: View {
    @Binding var street: String
    @Binding var lat: Double?
    @Binding var lng: Double?
    var onSuggestionZip: (String) -> Void

    @StateObject private var geocoder = LocationGeocoder()
    @State private var showSuggestions = false
    @State private var searchTask: Task<Void, Never>? = nil
    /// Untertitel der gewaehlten Adresse (Ort/Region) als Hinweis unter dem Feld
    @State private var selectedHint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSTextField("Street", placeholder: "Search or type address", text: userEditedStreet)
                .textContentType(.fullStreetAddress)
            if let hint = selectedHint, !showSuggestions {
                Text(hint)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.muted)
            }
            if showSuggestions && !geocoder.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(geocoder.suggestions) { s in
                        Button { select(s) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).dsFont(.body).foregroundStyle(DS.Color.text)
                                if !s.subtitle.isEmpty {
                                    Text(s.subtitle).dsFont(.caption).foregroundStyle(DS.Color.muted)
                                }
                            }
                            .padding(.vertical, DS.Spacing.xs)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        DSDivider()
                    }
                }
            }
        }
    }

    /// Nur echte Tipp-Eingaben setzen die Koordinaten zurueck (Prefill schreibt direkt in den State)
    private var userEditedStreet: Binding<String> {
        Binding(
            get: { street },
            set: { newValue in
                guard newValue != street else { return }
                street = newValue
                selectedHint = nil
                lat = nil
                lng = nil
                showSuggestions = true
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if Task.isCancelled { return }
                    await MainActor.run { geocoder.updateQuery(newValue) }
                }
            }
        )
    }

    private func select(_ s: LocationSuggestion) {
        // Strasse nur uebernehmen, wenn der Vorschlag eine Adresse ist (Hausnummer im Titel
        // bzw. im ersten Teil des Untertitels); bei Orten/Firmennamen bleibt die Eingabe stehen.
        let subtitleFirst = s.subtitle.split(separator: ",").first.map(String.init) ?? ""
        if s.title.contains(where: \.isNumber) {
            street = s.title
        } else if subtitleFirst.contains(where: \.isNumber) {
            street = subtitleFirst.trimmingCharacters(in: .whitespaces)
        }
        lat = s.lat
        lng = s.lng
        selectedHint = s.subtitle.isEmpty ? nil : s.subtitle
        showSuggestions = false
        geocoder.updateQuery("")
        // Der Picker liefert keine PLZ-Komponente; wenn der Untertitel eine enthaelt, uebernehmen
        if let range = s.subtitle.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) {
            onSuggestionZip(String(s.subtitle[range]))
        }
    }
}
