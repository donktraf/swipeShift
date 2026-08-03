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
    @State private var ageConfirmed: Bool = false
    @State private var workPermit: Bool = false
    @State private var termsAccepted: Bool = false

    @State private var isSaving: Bool = false

    @State private var showImagePicker = false
    @State private var selectedImage: UIImage? = nil

    private let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let distanceOptions = [5, 10, 15, 20, 25]
    private let transportOptions = ["Public Transport", "Car", "Bicycle", "On foot"]
    private let allCategories = ["Hospitality", "Events", "Logistics", "Retail",
                                  "Customer Service", "Warehouse", "Office", "Cleaning"]

    var body: some View {
        SubScreenShell(title: "Edit Profile") {
            VStack(spacing: 20) {
                photoBanner
                basicInfoSection
                locationSection
                availabilitySection
                jobPreferencesSection
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
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 80, height: 80)
                if let img = selectedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            Button("Change Photo") { showImagePicker = true }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
    }

    // MARK: - Basic Info

    private var basicInfoSection: some View {
        EditSection(title: "Personal Details") {
            EditRow(label: "First Name") {
                TextField("John", text: $firstName)
                    .textContentType(.givenName)
            }
            EditRow(label: "Last Name") {
                TextField("Smith", text: $lastName)
                    .textContentType(.familyName)
            }
            EditRow(label: "Email") {
                TextField("john@example.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
            }
            EditRow(label: "Phone") {
                TextField("+1 555 000 0000", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            }
            EditRow(label: "Date of Birth") {
                DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Location & Mobility

    private var locationSection: some View {
        EditSection(title: "Location & Mobility") {
            EditRow(label: "Location") {
                TextField("New York, USA", text: $location)
                    .textContentType(.addressCity)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Willing to work in another city")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                Toggle("", isOn: $willingToRelocate)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 6)
            EditRow(label: "Max. Travel Distance") {
                Picker("", selection: $maxDistance) {
                    ForEach(distanceOptions, id: \.self) { d in
                        Text("\(d) km").tag(d)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            EditRow(label: "Transport") {
                Picker("", selection: $transport) {
                    ForEach(transportOptions, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Availability

    private var availabilitySection: some View {
        EditSection(title: "Availability") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Available Days")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ForEach(dayOrder, id: \.self) { day in
                        let isOn = availableDays[day] ?? false
                        Button {
                            availableDays[day] = !isOn
                        } label: {
                            Text(day.prefix(1).uppercased() + day.dropFirst().lowercased())
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isOn ? .white : .secondary)
                                .frame(width: 36, height: 36)
                                .background(isOn ? SS.primary : Color.gray.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)

            HStack {
                Text("Available for same-day jobs")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                Spacer()
                Toggle("", isOn: $sameDayAvailable)
                    .labelsHidden()
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Job Preferences

    private var jobPreferencesSection: some View {
        EditSection(title: "Job Preferences") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preferred Categories")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(allCategories, id: \.self) { cat in
                        let isOn = selectedCategories.contains(cat)
                        Button {
                            if isOn { selectedCategories.remove(cat) }
                            else { selectedCategories.insert(cat) }
                        } label: {
                            Text(cat)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(isOn ? .white : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(isOn ? SS.primary : Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Preferred Hourly Pay (€/h)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("Min").font(.system(size: 11)).foregroundColor(.secondary)
                        Stepper("€\(payRangeMin)", value: $payRangeMin, in: 1...payRangeMax, step: 1)
                            .labelsHidden()
                        Text("€\(payRangeMin)").font(.system(size: 14, weight: .semibold))
                    }
                    Divider().frame(height: 40)
                    VStack(spacing: 2) {
                        Text("Max").font(.system(size: 11)).foregroundColor(.secondary)
                        Stepper("€\(payRangeMax)", value: $payRangeMax, in: payRangeMin...200, step: 1)
                            .labelsHidden()
                        Text("€\(payRangeMax)").font(.system(size: 14, weight: .semibold))
                    }
                    Spacer()
                }
            }
            .padding(.vertical, 4)
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
            LegalToggle(label: "I am at least 18 years old",    isOn: $ageConfirmed)
            LegalToggle(label: "I have a valid work permit",    isOn: $workPermit)
            LegalToggle(label: "I agree to the Terms of Service", isOn: $termsAccepted)
        }
    }

    // MARK: - Bio

    private var bioSection: some View {
        EditSection(title: "Bio (optional)") {
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $bio)
                    .frame(minHeight: 80)
                    .font(.system(size: 14))
                    .onChange(of: bio) { _, new in
                        if new.count > 300 { bio = String(new.prefix(300)) }
                    }
                Text("\(bio.count)/300")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("Save")
                }
            }
        }
        .buttonStyle(SSPrimaryButtonStyle(isEnabled: !isSaving))
        .padding(.horizontal, 16)
        .disabled(isSaving)
    }

    // MARK: - Helpers

    private func prefillFromUser() {
        guard let user = userStore.currentUser else { return }
        firstName = user.firstName ?? ""
        lastName  = user.lastName  ?? ""
        email     = user.email
        location  = user.location  ?? ""
        bio       = user.bio       ?? ""
        phone     = user.phone     ?? ""

        if let dobStr = user.dateOfBirth,
           let dob = ISO8601DateFormatter().date(from: dobStr) {
            dateOfBirth = dob
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
    }

    private func save() async {
        isSaving = true
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dobString = fmt.string(from: dateOfBirth)

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
                profilePhotoUrl:     uploadedPhotoUrl
            ))
            await userStore.refreshMe()
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
        }
    }
}

// MARK: - Helper Views

private struct EditSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
            content
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

private struct EditRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
                .padding(.leading, 14)
            content
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 12)
        if true { Divider().padding(.leading, 14) }
    }
}

private struct SkillRatingRow: View {
    let label: String
    @Binding var rating: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .padding(.leading, 14)
            Spacer()
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundColor(i <= rating ? .yellow : .gray.opacity(0.3))
                        .onTapGesture { rating = i }
                }
            }
            .padding(.trailing, 14)
        }
        .padding(.vertical, 10)
        if true { Divider().padding(.leading, 14) }
    }
}

private struct LegalToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button { isOn.toggle() } label: {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(isOn ? SS.primary : .gray.opacity(0.4))
                    .padding(.leading, 14)
            }
            .buttonStyle(.plain)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .padding(.trailing, 14)
            Spacer()
        }
        .padding(.vertical, 10)
        if true { Divider().padding(.leading, 14) }
    }
}
