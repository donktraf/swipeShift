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
        VStack(spacing: 20) {
            card(title: "Public Profile") {
                row("Tagline") {
                    TextField("Short slogan (max. 80)", text: $form.tagline)
                        .onChange(of: form.tagline) { _, new in
                            if new.count > 80 { form.tagline = String(new.prefix(80)) }
                        }
                }
                row("Founded") {
                    TextField("Year, e.g. 2015", text: $form.yearFounded)
                        .keyboardType(.numberPad)
                        .onChange(of: form.yearFounded) { _, new in
                            let digits = new.filter(\.isNumber)
                            let limited = String(digits.prefix(4))
                            if limited != new { form.yearFounded = limited }
                        }
                }
            }

            card(title: "Social Links") {
                row("Instagram") { socialField("@handle or link", text: $form.instagram) }
                row("LinkedIn")  { socialField("Link or @handle", text: $form.linkedin) }
                row("Facebook")  { socialField("Link or @handle", text: $form.facebook) }
                row("TikTok")    { socialField("@handle or link", text: $form.tiktok) }
            }

            card(title: "Address") {
                AddressSearchField(
                    street: $form.streetAddress,
                    lat: $form.addressLat,
                    lng: $form.addressLng,
                    onSuggestionZip: { zip in if form.zipCode.isEmpty { form.zipCode = zip } }
                )
                Text("Your address is shown on your public company profile.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                row("ZIP Code") {
                    TextField("12345 or 12345-6789", text: $form.zipCode)
                        .keyboardType(.numbersAndPunctuation)
                }
                if form.addressLat != nil {
                    Label("Location pinned on map", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }

            card(title: "Public Contact Person") {
                row("Name") { TextField("Jane Doe", text: $form.contactName) }
                row("Role") { TextField("Hiring Manager", text: $form.contactRole) }
            }

            card(title: "Hiring") {
                toggleRow("Posts jobs in multiple states", isOn: $form.postsInMultipleStates)
                toggleRow("Remote-friendly roles", isOn: $form.remoteFriendly)
            }
        }
    }

    // MARK: - Helpers

    private func socialField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
            content()
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 14)).foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)
                    .padding(.leading, 14)
                content()
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .padding(.trailing, 14)
            }
            .padding(.vertical, 12)
            Divider().padding(.leading, 14)
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Toggle(label, isOn: isOn)
                .font(.system(size: 14))
                .tint(SS.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider().padding(.leading, 14)
        }
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
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text("Street")
                    .font(.system(size: 14)).foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)
                    .padding(.leading, 14)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Search or type address", text: userEditedStreet)
                        .font(.system(size: 14))
                        .textContentType(.fullStreetAddress)
                    if let hint = selectedHint, !showSuggestions {
                        Text(hint)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                    if showSuggestions && !geocoder.suggestions.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(geocoder.suggestions) { s in
                                Button { select(s) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title).font(.system(size: 14)).foregroundColor(.primary)
                                        if !s.subtitle.isEmpty {
                                            Text(s.subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.trailing, 14)
            }
            .padding(.vertical, 12)
            Divider().padding(.leading, 14)
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
