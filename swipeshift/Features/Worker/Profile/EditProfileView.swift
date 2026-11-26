//
//  EditProfileView.swift
//  swipeShift
//

import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.dismiss) private var dismiss

    // Basis-Infos
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -22, to: Date()) ?? Date()
    @State private var location: String = ""
    @State private var bio: String = ""

    // Mobilität
    @State private var willingToRelocate: Bool = false
    @State private var maxDistance: Int = 10
    @State private var transport: String = "Public Transport"

    // Verfügbarkeit
    @State private var availableDays: [String: Bool] = [
        "Mon": true, "Tue": true, "Wed": false,
        "Thu": true, "Fri": true, "Sat": false, "Sun": false
    ]
    @State private var sameDayAvailable: Bool = true
    @State private var availableTimes: Set<WorkerAvailableTime> = []
    @State private var shiftTypes: Set<WorkerShiftType> = []
    /// Vorerfahrung je Kategorie (fehlender Key = None)
    @State private var experienceLevels: [String: ExperienceLevel] = [:]

    // Job Preferences
    @State private var selectedCategories: Set<String> = ["Hospitality", "Events"]
    @State private var payRangeMin: Int = 12
    @State private var payRangeMax: Int = 20

    // Skills (1-5)
    @State private var communication: Int = 4
    @State private var teamwork: Int = 4
    @State private var reliability: Int = 5
    @State private var underPressure: Int = 3

    // Legal
    @State private var workPermit: Bool = false
    @State private var termsAccepted: Bool = false
    @State private var ratingSystemAccepted: Bool = false
    /// AGB sind Kontovoraussetzung: einmal zugestimmt, nicht mehr abwaehlbar
    @State private var termsLocked: Bool = false

    @State private var isSaving: Bool = false
    /// Prefill nur einmal, damit erneutes onAppear ungespeicherte Eingaben nicht ueberschreibt
    @State private var didPrefill: Bool = false
    @State private var saveError: String? = nil
    /// Geladenes Geburtsdatum (yyyy-MM-dd); nur bei Aenderung wird es mitgesendet
    @State private var loadedDOB: String? = nil

    @State private var showImagePicker = false
    @State private var selectedImage: UIImage? = nil

    private let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let distanceOptions = [5, 10, 15, 20, 25]
    private let transportOptions = ["Public Transport", "Car", "Bicycle", "On foot"]
    private let allCategories = ["Hospitality", "Events", "Logistics", "Retail",
                                  "Customer Service", "Warehouse", "Office", "Cleaning"]

    var body: some View {
        SubScreenShell(title: "Edit Profile", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                photoBanner
                basicInfoSection
                locationSection
                availabilitySection
                jobPreferencesSection
                experienceSection
                skillsSection
                legalSection
                bioSection
                saveButton
            }
        }
        .onAppear { prefillFromUser() }
    }

    // MARK: - Photo Banner

    private var photoBanner: some View {
        VStack(spacing: DS.Spacing.sm) {
            if let img = selectedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "person.fill")
                    .font(DS.Font.make(34, .semibold, relativeTo: nil))
                    .foregroundStyle(DS.Color.primaryText)
                    .frame(width: 80, height: 80)
                    .background(DS.Color.primarySoft, in: Circle())
                    .accessibilityHidden(true)
            }
            Button("Change Photo") { showImagePicker = true }
                .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
    }

    // MARK: - Basic Info

    private var basicInfoSection: some View {
        EditSection(title: "Personal Details") {
            DSTextField("First Name", placeholder: "John", text: $firstName)
                .textContentType(.givenName)
            DSTextField("Last Name", placeholder: "Smith", text: $lastName)
                .textContentType(.familyName)
            DSTextField("Email", placeholder: "john@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            DSTextField("Phone", placeholder: "+1 555 000 0000", text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            EditRow(label: "Date of Birth") {
                DatePicker("Date of Birth", selection: $dateOfBirth, in: ...latestAllowedBirthDate, displayedComponents: .date)
                    .labelsHidden()
                    .tint(DS.Color.primary)
            }
        }
    }

    /// Geburtsdatum liegt mind. 18 Jahre zurueck
    private var isAdult: Bool { dateOfBirth <= latestAllowedBirthDate }

    /// Juengstes erlaubtes Geburtsdatum (18+)
    private var latestAllowedBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }

    // MARK: - Location & Mobility

    private var locationSection: some View {
        EditSection(title: "Location & Mobility") {
            DSTextField("Location", placeholder: "New York, USA", text: $location)
                .textContentType(.addressCity)
            DSToggleRow("Willing to work in another city", showsDivider: false, isOn: $willingToRelocate)
            EditRow(label: "Max. Travel Distance") {
                Picker("Max. Travel Distance", selection: $maxDistance) {
                    ForEach(distanceOptions, id: \.self) { d in
                        Text("\(d) mi").tag(d)
                    }
                }
                .pickerStyle(.menu)
                .tint(DS.Color.primaryText)
            }
            EditRow(label: "Transport") {
                Picker("Transport", selection: $transport) {
                    ForEach(transportOptions, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .tint(DS.Color.primaryText)
            }
        }
    }

    // MARK: - Availability

    private var availabilitySection: some View {
        EditSection(title: "Availability") {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Available Days")
                    .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(DS.Color.text2)
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(dayOrder, id: \.self) { day in
                        let isOn = availableDays[day] ?? false
                        Button {
                            DS.Haptics.selection()
                            availableDays[day] = !isOn
                        } label: {
                            Text(day.prefix(1).uppercased() + day.dropFirst().lowercased())
                                .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                                .foregroundStyle(isOn ? DS.Color.onPrimary : DS.Color.text2)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(isOn ? DS.Color.primary : DS.Color.surface2,
                                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                        }
                        .buttonStyle(.dsPressable)
                        .accessibilityLabel(day)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }

            ProfileChipPicker(
                title: "Available Times",
                options: WorkerAvailableTime.allCases,
                label: { $0.title },
                selection: $availableTimes
            )

            DSToggleRow("Available for same-day jobs", showsDivider: false, isOn: $sameDayAvailable)
        }
    }

    // MARK: - Job Preferences

    private var jobPreferencesSection: some View {
        EditSection(title: "Job Preferences") {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Preferred Categories")
                    .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(DS.Color.text2)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: DS.Spacing.xs), GridItem(.flexible())],
                    spacing: DS.Spacing.xs
                ) {
                    ForEach(allCategories, id: \.self) { cat in
                        let isOn = selectedCategories.contains(cat)
                        DSChip(cat, isSelected: isOn) {
                            if isOn { selectedCategories.remove(cat) }
                            else { selectedCategories.insert(cat) }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Preferred Hourly Pay ($/hr)")
                    .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(DS.Color.text2)
                HStack(spacing: DS.Spacing.md) {
                    payStepper(label: "Min", value: $payRangeMin, range: 1...payRangeMax)
                    payStepper(label: "Max", value: $payRangeMax, range: payRangeMin...200)
                }
            }

            // "Same-day" bleibt der Schalter oben (Verfuegbarkeit) - hier nur die uebrigen Schicht-Typen
            ProfileChipPicker(
                title: "Shift Types",
                options: WorkerShiftType.allCases,
                label: { $0.title },
                selection: $shiftTypes
            )
        }
    }

    private func payStepper(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(label).dsFont(.caption).foregroundStyle(DS.Color.muted)
            HStack {
                Text(Money.format(value.wrappedValue))
                    .font(DS.Font.make(15, .bold))
                    .foregroundStyle(DS.Color.text)
                Spacer(minLength: DS.Spacing.xs)
                DSStepper(value: value, range: range, accessibilityName: "\(label) hourly pay")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Experience

    private var experienceSection: some View {
        EditSection(title: "Experience") {
            Text("How long have you worked in each category?")
                .dsFont(.caption)
                .foregroundStyle(DS.Color.muted)
            ExperienceEditor(categories: allCategories, levels: $experienceLevels)
        }
    }

    // MARK: - Skills

    private var skillsSection: some View {
        EditSection(title: "Skills") {
            SkillRatingRow(label: "Communication",          rating: $communication)
            SkillRatingRow(label: "Teamwork",               rating: $teamwork)
            SkillRatingRow(label: "Reliability",            rating: $reliability)
            SkillRatingRow(label: "Working under Pressure", rating: $underPressure)
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        EditSection(title: "Legal") {
            if isAdult {
                AgeConfirmedRow()
            } else {
                AgeWarningRow()
            }
            LegalToggle(label: "I have a valid work permit",    isOn: $workPermit)
            LegalToggle(label: "I agree to the Terms of Service", isOn: $termsAccepted, locked: termsLocked)
            LegalToggle(label: "I accept the Rating System guidelines", isOn: $ratingSystemAccepted)
        }
    }

    // MARK: - Bio

    private var bioSection: some View {
        EditSection(title: "Bio (optional)") {
            DSTextEditor("Bio", placeholder: "Tell employers a bit about you", text: $bio, minLines: 3, maxLines: 8, maxLength: 300)
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(DS.Color.onPrimary)
                } else {
                    Text("Save")
                }
            }
        }
        .buttonStyle(.ds(.primary))
        .disabled(isSaving)
        .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Helpers

    private func prefillFromUser() {
        guard !didPrefill, let user = userStore.currentUser else { return }
        didPrefill = true
        firstName = user.firstName ?? ""
        lastName  = user.lastName  ?? ""
        email     = user.email
        location  = user.location  ?? ""
        bio       = user.bio       ?? ""
        phone     = user.phone     ?? ""

        if let dobStr = user.dateOfBirth, let dob = DateOnly.date(from: dobStr) {
            dateOfBirth = dob
            loadedDOB = DateOnly.string(from: dob)
        }

        if let av = user.availability, !av.isEmpty {
            for item in av { availableDays[item.name] = item.available }
        }

        if let interests = user.jobInterests, !interests.isEmpty {
            selectedCategories = Set(interests)
        }

        willingToRelocate   = user.willingToRelocate   ?? false
        maxDistance         = user.maxTravelDistance   ?? 10
        let rawTransport    = user.transport ?? ""
        transport           = transportOptions.first { $0.lowercased() == rawTransport.lowercased() } ?? "Public Transport"
        sameDayAvailable    = user.availableForSameDay ?? false

        if let cats = user.preferredCategories, !cats.isEmpty {
            selectedCategories = Set(cats)
        }

        if let min = user.payRangeMin { payRangeMin = Int(min) }
        if let max = user.payRangeMax { payRangeMax = Int(max) }

        if let s = user.skills {
            communication  = s.communication
            teamwork       = s.teamwork
            reliability    = s.reliability
            underPressure  = s.underPressure
        }

        workPermit = user.workAuthorization ?? false

        availableTimes = Set((user.availableTimes ?? []).compactMap(WorkerAvailableTime.init(rawValue:)))
        shiftTypes     = Set((user.shiftTypes ?? []).compactMap(WorkerShiftType.init(rawValue:)))
        experienceLevels = Dictionary(
            (user.experience ?? []).map { ($0.category, $0.level) },
            uniquingKeysWith: { first, _ in first }
        )

        let consents = user.legalConsents ?? [:]
        termsAccepted        = consents["terms"] ?? false
        termsLocked          = termsAccepted
        ratingSystemAccepted = consents["ratingSystem"] ?? false
    }

    private func save() async {
        isSaving = true
        saveError = nil
        // Nur senden, wenn geaendert (Altnutzer < 18 koennen sonst andere Felder weiter speichern)
        let currentDOB = DateOnly.string(from: dateOfBirth)
        let dobString: String? = currentDOB == loadedDOB ? nil : currentDOB

        let availability = dayOrder.map { AvailabilityDTO(name: $0, available: availableDays[$0] ?? false) }
        let skills = WorkerSkillsDTO(
            communication: communication,
            teamwork:      teamwork,
            reliability:   reliability,
            underPressure: underPressure
        )

        do {
            var uploadedPhotoUrl: String? = nil
            if let img = selectedImage {
                uploadedPhotoUrl = try await APIClient.shared.uploadProfilePhoto(img)
            }

            try await APIClient.shared.updateProfile(UpdateProfileRequest(
                firstName:           firstName.isEmpty ? nil : firstName,
                lastName:            lastName.isEmpty  ? nil : lastName,
                location:            location.isEmpty  ? nil : location,
                bio:                 bio.isEmpty       ? nil : bio,
                dateOfBirth:         dobString,
                availability:        availability,
                jobInterests:        Array(selectedCategories),
                phone:               phone.isEmpty     ? nil : phone,
                willingToRelocate:   willingToRelocate,
                maxTravelDistance:   maxDistance,
                transport:           transport,
                availableForSameDay: sameDayAvailable,
                preferredCategories: Array(selectedCategories),
                payRangeMin:         Double(payRangeMin),
                payRangeMax:         Double(payRangeMax),
                skills:              skills,
                workAuthorization:   workPermit,
                profilePhotoUrl:     uploadedPhotoUrl,
                legalConsents:       ["terms": termsAccepted, "ratingSystem": ratingSystemAccepted],
                availableTimes:      WorkerAvailableTime.allCases.filter { availableTimes.contains($0) }.map(\.rawValue),
                shiftTypes:          WorkerShiftType.allCases.filter { shiftTypes.contains($0) }.map(\.rawValue),
                experience:          allCategories.compactMap { cat in
                    experienceLevels[cat].map { WorkerExperienceEntry(category: cat, level: $0) }
                }
            ))
            await userStore.refreshMe()
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Helper Views

/// Flache Gruppe: Sektionslabel + Felder mit 16er Abstand, Trennlinie unten (keine Box).
private struct EditSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        DSSection(title) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) { content }
                .padding(.vertical, DS.Spacing.sm)
        }
    }
}

/// Zeile mit Label links und Bedienelement rechts (Datum, Menues).
private struct EditRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(label)
                .dsFont(.body)
                .foregroundStyle(DS.Color.text)
            Spacer(minLength: DS.Spacing.xs)
            content
                .font(DS.Font.make(15, .medium))
        }
        .frame(minHeight: 44)
    }
}

private struct SkillRatingRow: View {
    let label: String
    @Binding var rating: Int

    var body: some View {
        HStack {
            Text(label)
                .dsFont(.body)
                .foregroundStyle(DS.Color.text)
            Spacer(minLength: DS.Spacing.xs)
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        DS.Haptics.selection()
                        rating = i
                    } label: {
                        Image(systemName: i <= rating ? "star.fill" : "star")
                            .font(DS.Font.make(18, .regular, relativeTo: nil))
                            .foregroundStyle(i <= rating ? DS.Color.warning : DS.Color.border)
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(i) of 5")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(rating) of 5")
    }
}

/// Hinweis, wenn das gespeicherte Geburtsdatum unter 18 liegt
private struct AgeWarningRow: View {
    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSIconTile(systemName: "exclamationmark.triangle.fill", tone: .warning)
            Text("Please check your date of birth – you must be at least 18.")
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text)
            Spacer(minLength: 0)
        }
    }
}

/// Schreibgeschuetzte Zeile: 18+ wird ueber das Geburtsdatum bestaetigt (serverseitig geprueft)
private struct AgeConfirmedRow: View {
    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSIconTile(systemName: "checkmark.seal.fill", tone: .primary)
            Text("Age 18+ confirmed via your date of birth")
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text)
            Spacer(minLength: 0)
        }
    }
}

private struct LegalToggle: View {
    let label: String
    @Binding var isOn: Bool
    var locked: Bool = false

    var body: some View {
        Button {
            DS.Haptics.selection()
            isOn.toggle()
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(DS.Font.make(22, .regular, relativeTo: nil))
                    .foregroundStyle(isOn ? DS.Color.primary : DS.Color.muted)
                Text(label)
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.6 : 1)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
