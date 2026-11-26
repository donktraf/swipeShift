//
//  RegisterView.swift
//  L1 Demo
//

import SwiftUI


enum RegistrationRole {
    case worker
    case employer
}

enum CompanySize: String, CaseIterable, Identifiable {
    case none
    case size1to10
    case size11to50
    case size50plus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "none"
        case .size1to10: return "1–10"
        case .size11to50: return "11–50"
        case .size50plus: return "50+"
        }
    }

    var apiValue: String? {
        switch self {
        case .none: return nil
        case .size1to10: return "1-10"
        case .size11to50: return "11-50"
        case .size50plus: return "50+"
        }
    }
}

struct DayAvailability {
    let name: String
    var available: Bool = false
}

enum FieldKey {
    // Worker
    case firstName
    case lastName
    case email
    case dateOfBirth
    case password
    case jobInterests
    case availability
    case confirmPassword
    case locationText
    case terms

    // Employer
    case companyName
    case employerEmail
    case employerPassword
    case employerConfirmPassword
    case employerLocation
    case employerIndustry
    case companySize
    case employerTerms
}


struct RegisterView: View {

    // MARK: - Variablen
    @EnvironmentObject var userStore: UserStore
    
    @Environment(\.dismiss) private var dismiss

    @StateObject private var locationGeocoder = LocationGeocoder()

    @State private var selectedRole: RegistrationRole = .worker

    @State private var lat: Double? = nil
    @State private var lng: Double? = nil

    // Employer-Felder
    @State private var companyName: String = ""
    @State private var employerEmail: String = ""
    @State private var employerPassword: String = ""
    @State private var employerConfirmPassword: String = ""
    @State private var employerLocationText: String = ""
    @State private var companySize: CompanySize = .size1to10
    @State private var companyLogoImage: UIImage? = nil
    @State private var showCompanyLogoPicker = false
    @State private var websiteOrInstagram: String = ""
    @State private var companyDescription: String = ""
    private let companyDescriptionLimit = 300

    @State private var employerLat: Double? = nil
    @State private var employerLng: Double? = nil
    @State private var showEmployerLocationSuggestions: Bool = false
    @State private var employerLocationSearchTask: Task<Void, Never>? = nil

    @State private var employerAcceptedTerms: Bool = false

    // Worker-Felder
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var locationText: String = ""
    @State private var workerLat: Double? = nil
    @State private var workerLng: Double? = nil
    @State private var showWorkerLocationSuggestions: Bool = false
    @State private var workerLocationSearchTask: Task<Void, Never>? = nil

    // Profile Photo
    @State private var showImagePicker = false
    @State private var profileUIImage: UIImage? = nil

    // Job Interests
    private let jobInterestOptions: [String] = [
        "Hospitality", "Events", "Retail", "Office", "Logistics", "Warehouse", "Customer Service"
    ]

    @State private var employerIndustry: String = "Hospitality"
    @State private var selectedJobInterests: Set<String> = []

    // Availability
    @State private var availability: [DayAvailability] = [
        DayAvailability(name: "Mon"),
        DayAvailability(name: "Tue"),
        DayAvailability(name: "Wed"),
        DayAvailability(name: "Thu"),
        DayAvailability(name: "Fri"),
        DayAvailability(name: "Sat"),
        DayAvailability(name: "Sun")
    ]

    // Short Bio
    @State private var shortBio: String = ""
    private let bioLimit = 200

    @State private var acceptedTerms: Bool = false

    @State private var errorMessage: String?

    // MARK: - Validierungen
    @State private var fieldErrors: [FieldKey: String] = [:]


    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {

                // MARK: - Header
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Create Account").dsFont(.display).foregroundStyle(DS.Color.text)
                    Text("Choose how you want to use the app.")
                        .dsFont(.body)
                        .foregroundStyle(DS.Color.text2)
                }

                // MARK: - Role Selection Cards
                roleSelectionSection

                // MARK: - Formular je nach Rolle
                switch selectedRole {
                case .worker:
                    workerFormSection
                case .employer:
                    employerFormSection
                }

                // Fehlermeldung vom Backend
                if let errorMessage {
                    Text(errorMessage)
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // MARK: - Registrieren Button
                Button(action: handleRegister) {
                    Text(selectedRole == .worker ? "Create Worker Account" : "Create Employer Account")
                }
                .buttonStyle(.ds(.primary))

                if let current = userStore.currentUser {
                    Text("Registered & logged in as \(current.email)")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.success)
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.xs)
            .padding(.bottom, DS.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .dsBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            // Schliessen-Button oben links
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Color.text2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.xs)
            .background(DS.Color.bg)
        }
        .navigationBarTitleDisplayMode(.inline)
    }


    // MARK: - Subviews

    private var roleSelectionSection: some View {
        HStack(spacing: DS.Spacing.sm) {
            roleCard(
                icon: "person", title: "I'm looking for work",
                subtitle: "Create a worker profile to find jobs that match you.",
                tone: .primary, isSelected: selectedRole == .worker
            ) { selectedRole = .worker }

            roleCard(
                icon: "doc.text", title: "I'm hiring for jobs",
                subtitle: "Post jobs and find talent.",
                tone: .warning, isSelected: selectedRole == .employer
            ) { selectedRole = .employer }
        }
    }

    private func roleCard(icon: String, title: String, subtitle: String, tone: DS.Tone, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            DS.Haptics.selection()
            action()
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                DSIconTile(systemName: icon, tone: tone)
                Text(title).dsFont(.headline).foregroundStyle(DS.Color.text)
                Text(subtitle).dsFont(.caption).foregroundStyle(DS.Color.text2)
                    .multilineTextAlignment(.leading)
            }
            .padding(DS.Spacing.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? DS.Color.primary : DS.Color.border, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(.dsPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Foto-/Logo-Auswahl als flache Zeile
    private func photoRow(image: UIImage?, placeholderIcon: String, emptyText: String, filledText: String,
                          chooseTitle: String, changeTitle: String, pick: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: placeholderIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DS.Color.muted)
                }
            }
            .frame(width: 56, height: 56)
            .background(DS.Color.surface2)
            .clipShape(Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(image == nil ? emptyText : filledText)
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text2)
                Button(image == nil ? chooseTitle : changeTitle, action: pick)
                    .font(DS.Font.make(15, .semibold))
                    .foregroundStyle(DS.Color.primaryText)
                    .frame(minHeight: 44, alignment: .leading)
            }

            Spacer()

            if image != nil {
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                        .foregroundStyle(DS.Color.danger)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Remove")
            }
        }
    }

    /// Ort-Suche mit Vorschlagsliste
    private func locationField(text: Binding<String>, error: String?, suggestionsVisible: Bool,
                               onChange: @escaping (String) -> Void, onPick: @escaping (LocationSuggestion) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSTextField("City / ZIP code", placeholder: "Start typing a city or ZIP", text: text, error: error)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .textContentType(.addressCity)
                .onChange(of: text.wrappedValue) { _, newValue in onChange(newValue) }

            Text("Pick a suggestion so we can save coordinates.")
                .dsFont(.caption)
                .foregroundStyle(DS.Color.muted)

            if suggestionsVisible && !locationGeocoder.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(locationGeocoder.suggestions) { s in
                        Button {
                            onPick(s)
                            hideKeyboard()
                        } label: {
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
                        .overlay(alignment: .top) { DSDivider() }
                    }
                }
                .overlay(alignment: .bottom) { DSDivider() }
            }
        }
    }

    private func termsToggle(isOn: Binding<Bool>, error: String?) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Toggle(isOn: isOn) {
                Text("I accept the Terms & Conditions and Privacy Policy.")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text)
            }
            .tint(DS.Color.primary)
            .frame(minHeight: 44)
            if let error {
                Text(error).dsFont(.caption).foregroundStyle(DS.Color.danger)
            }
        }
    }

    private func fieldError(_ message: String?) -> some View {
        Group {
            if let message {
                Text(message).dsFont(.caption).foregroundStyle(DS.Color.danger)
            }
        }
    }


    // MARK: - Worker Form Section
    private var workerFormSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {

            // MARK: - Basic Info
            DSSection("Profile photo (optional)", ruled: false) {
                photoRow(
                    image: profileUIImage, placeholderIcon: "person.fill",
                    emptyText: "No photo selected", filledText: "Photo selected",
                    chooseTitle: "Choose photo", changeTitle: "Change photo",
                    pick: { showImagePicker = true }, remove: { profileUIImage = nil }
                )
                .sheet(isPresented: $showImagePicker) {
                    ImagePicker(image: $profileUIImage)
                }
            }

            DSSection("Basic information", ruled: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        DSTextField("First name", text: $firstName, error: fieldErrors[.firstName])
                            .textInputAutocapitalization(.words)
                        DSTextField("Last name", text: $lastName, error: fieldErrors[.lastName])
                            .textInputAutocapitalization(.words)
                    }

                    DSTextField("Email", placeholder: "you@example.com", text: $email, error: fieldErrors[.email])
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    DSTextField("Password", text: $password, error: fieldErrors[.password], isSecure: true)
                        .textContentType(.oneTimeCode)

                    DSTextField("Confirm password", text: $confirmPassword, error: fieldErrors[.confirmPassword], isSecure: true)
                        .textContentType(.oneTimeCode)
                }
            }

            // MARK: - Date of birth
            DSSection("Date of birth", ruled: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    DatePicker(
                        "Date of birth",
                        selection: $dateOfBirth,
                        in: ...(Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()), // 18+
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .tint(DS.Color.primary)
                    .frame(maxWidth: .infinity)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .strokeBorder(fieldErrors[.dateOfBirth] == nil ? DS.Color.border : DS.Color.danger, lineWidth: 1)
                    )
                    fieldError(fieldErrors[.dateOfBirth])
                }
            }

            // MARK: - Location
            DSSection("Location", ruled: false) {
                locationField(
                    text: $locationText, error: fieldErrors[.locationText],
                    suggestionsVisible: showWorkerLocationSuggestions,
                    onChange: { newValue in
                        workerLat = nil
                        workerLng = nil
                        showWorkerLocationSuggestions = true

                        workerLocationSearchTask?.cancel()
                        workerLocationSearchTask = Task {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            if Task.isCancelled { return }
                            await MainActor.run {
                                locationGeocoder.updateQuery(newValue)
                            }
                        }
                    },
                    onPick: { s in
                        locationText = s.fullText
                        workerLat = s.lat
                        workerLng = s.lng
                        showWorkerLocationSuggestions = false
                    }
                )
            }

            // MARK: - Job Interests
            DSSection("Job interests", trailing: "Select one or more", ruled: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ChipFlowLayout(spacing: DS.Spacing.xs) {
                        ForEach(jobInterestOptions, id: \.self) { option in
                            DSChip(option, isSelected: selectedJobInterests.contains(option)) {
                                if selectedJobInterests.contains(option) {
                                    selectedJobInterests.remove(option)
                                } else {
                                    selectedJobInterests.insert(option)
                                }
                            }
                        }
                    }
                    fieldError(fieldErrors[.jobInterests])
                }
            }

            // MARK: - Availability
            DSSection("Availability", trailing: "Days you are usually available", ruled: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(availability.indices, id: \.self) { index in
                        DSToggleRow(availability[index].name, isOn: $availability[index].available)
                    }
                    if let msg = fieldErrors[.availability] {
                        Text(msg).dsFont(.caption).foregroundStyle(DS.Color.danger)
                            .padding(.vertical, DS.Spacing.xs)
                    }
                }
            }

            // MARK: - Short Bio
            DSTextEditor(
                "Short bio (optional)", placeholder: "Tell employers a bit about yourself.",
                text: $shortBio, minLines: 4, maxLength: bioLimit
            )

            // MARK: - Terms & Privacy
            termsToggle(isOn: $acceptedTerms, error: fieldErrors[.terms])
        }
    }


    // MARK: - Employer Form Section
    private var employerFormSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {

            // MARK: - Company Info
            DSSection("Company information", ruled: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    DSTextField("Company name", text: $companyName, error: fieldErrors[.companyName])
                        .textInputAutocapitalization(.words)

                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        DSTextField("Contact first name", text: $firstName, error: fieldErrors[.firstName])
                            .textInputAutocapitalization(.words)
                        DSTextField("Contact last name", text: $lastName, error: fieldErrors[.lastName])
                            .textInputAutocapitalization(.words)
                    }
                }
            }

            // MARK: - Account Details
            DSSection("Account details", ruled: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    DSTextField("Work email", placeholder: "you@company.com", text: $employerEmail, error: fieldErrors[.employerEmail])
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    DSTextField("Password", text: $employerPassword, error: fieldErrors[.employerPassword], isSecure: true)

                    DSTextField("Confirm password", text: $employerConfirmPassword, error: fieldErrors[.employerConfirmPassword], isSecure: true)
                }
            }

            // MARK: - Location
            DSSection("Location", ruled: false) {
                locationField(
                    text: $employerLocationText, error: fieldErrors[.employerLocation],
                    suggestionsVisible: showEmployerLocationSuggestions,
                    onChange: { newValue in
                        employerLat = nil
                        employerLng = nil
                        showEmployerLocationSuggestions = true

                        employerLocationSearchTask?.cancel()
                        employerLocationSearchTask = Task {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            if Task.isCancelled { return }
                            await MainActor.run {
                                locationGeocoder.updateQuery(newValue)
                            }
                        }
                    },
                    onPick: { s in
                        employerLocationText = s.fullText
                        employerLat = s.lat
                        employerLng = s.lng
                        showEmployerLocationSuggestions = false
                    }
                )
            }

            // MARK: - Industry / Category
            DSSection("Industry / Category", ruled: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack {
                        Picker("Industry", selection: $employerIndustry) {
                            ForEach(jobInterestOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(DS.Color.primaryText)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.xs)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .strokeBorder(DS.Color.border, lineWidth: 1)
                    )
                    fieldError(fieldErrors[.employerIndustry])
                }
            }

            // MARK: - Company Size
            DSSection("Company size", ruled: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(CompanySize.allCases) { size in
                            DSChip(size.label, isSelected: companySize == size) { companySize = size }
                        }
                    }
                    fieldError(fieldErrors[.companySize])
                }
            }

            // MARK: - Company Logo (optional)
            DSSection("Company logo (optional)", ruled: false) {
                photoRow(
                    image: companyLogoImage, placeholderIcon: "building.2",
                    emptyText: "No logo selected", filledText: "Logo selected",
                    chooseTitle: "Choose logo", changeTitle: "Change logo",
                    pick: { showCompanyLogoPicker = true }, remove: { companyLogoImage = nil }
                )
            }
            .sheet(isPresented: $showCompanyLogoPicker) {
                ImagePicker(image: $companyLogoImage)
            }

            // MARK: - Website / Instagram (optional)
            DSTextField("Website or Instagram (optional)", placeholder: "https:// or @instagram", text: $websiteOrInstagram)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            // MARK: - Short Company Description (optional)
            DSTextEditor(
                "Short company description (optional)", placeholder: "What does your company do?",
                text: $companyDescription, minLines: 4, maxLength: companyDescriptionLimit
            )

            // MARK: - Terms & Privacy (Employer)
            termsToggle(isOn: $employerAcceptedTerms, error: fieldErrors[.employerTerms])
        }
    }


    // MARK: - Aktionen

    private func isoDate(_ date: Date) -> String {
        DateOnly.string(from: date)
    }

    private func handleRegister() {
        errorMessage = nil

        switch selectedRole {

        case .worker:
            fieldErrors = FormValidator.validateWorker(
                firstName: firstName,
                lastName: lastName,
                email: email,
                dateOfBirth: dateOfBirth,
                password: password,
                confirmPassword: confirmPassword,
                locationText: locationText,
                jobInterests: selectedJobInterests,
                availability: availability,
                acceptedTerms: acceptedTerms
            )

            guard fieldErrors.isEmpty else { return }

            guard let wLat = workerLat, let wLng = workerLng else {
                fieldErrors[.locationText] = "Please select a location from the suggestions."
                return
            }

            let body = RegisterRequestDTO(
                firstName: firstName,
                lastName: lastName,
                email: email,
                password: password,
                role: "worker",
                location: locationText,
                lat: wLat,
                lng: wLng,
                dateOfBirth: isoDate(dateOfBirth),
                jobInterests: Array(selectedJobInterests),
                availability: availability.map { AvailabilityDTO(name: $0.name, available: $0.available) },
                bio: shortBio.isEmpty ? nil : shortBio,
                profilePhotoUrl: nil,
                companyName: nil,
                companySize: nil,
                industry: nil,
                companyLogoUrl: nil,
                websiteOrInstagram: nil,
                companyDescription: nil,
                acceptedTerms: acceptedTerms
            )

            Task {
                await userStore.registerRemote(request: body, pickedImage: profileUIImage)

                if let msg = userStore.errorMessage {
                    print("Register failed:", msg)
                    errorMessage = msg
                } else {
                    print("Register success (worker): \(userStore.currentUser?.email ?? "")")
                }
            }

        case .employer:
            fieldErrors = FormValidator.validateEmployer(
                companyName: companyName,
                contactFirstName: firstName,
                contactLastName: lastName,
                email: employerEmail,
                employerPassword: employerPassword,
                confirmPassword: employerConfirmPassword,
                location: employerLocationText,
                industry: employerIndustry,
                companySizeRaw: companySize,
                acceptedTerms: employerAcceptedTerms
            )

            guard fieldErrors.isEmpty else { return }

            guard let eLat = employerLat, let eLng = employerLng else {
                fieldErrors[.employerLocation] = "Please select a location from the suggestions."
                return
            }

            let body = RegisterRequestDTO(
                firstName: firstName,
                lastName: lastName,
                email: employerEmail,
                password: employerPassword,
                role: "employer",
                location: employerLocationText,
                lat: eLat,
                lng: eLng,
                dateOfBirth: nil,
                jobInterests: nil,
                availability: nil,
                bio: nil,
                profilePhotoUrl: nil,
                companyName: companyName,
                companySize: companySize.apiValue,
                industry: employerIndustry,
                companyLogoUrl: nil,
                websiteOrInstagram: websiteOrInstagram.isEmpty ? nil : websiteOrInstagram,
                companyDescription: companyDescription.isEmpty ? nil : companyDescription,
                acceptedTerms: employerAcceptedTerms
            )

            Task {
                await userStore.registerRemote(request: body, pickedImage: companyLogoImage)

                if let msg = userStore.errorMessage {
                    print("Register failed:", msg)
                    errorMessage = msg
                } else {
                    print("Register success (employer): \(userStore.currentUser?.email ?? "")")
                }
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}


// MARK: - ChipFlowLayout
/// Umbrechende Chip-Reihe (Layout-Protokoll, hat echte intrinsische Hoehe)
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

// MARK: - WrapLayout
struct WrapLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let spacing: CGFloat
    let content: (Data.Element) -> Content

    init(items: Data, spacing: CGFloat = 8, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Array(items), id: \.self) { item in
                    content(item)
                        .padding(.trailing, spacing)
                        .padding(.bottom, spacing)
                        .alignmentGuide(.leading) { d in
                            if (abs(width - d.width) > geometry.size.width) {
                                width = 0
                                height -= d.height + spacing
                            }
                            let result = width
                            width -= d.width + spacing
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            return result
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 0)
    }
}


#Preview {
    NavigationStack {
        RegisterView()
            .environmentObject(UserStore())
    }
}
