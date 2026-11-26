import SwiftUI

struct WorkerOnboardingView: View {
    @EnvironmentObject var userStore: UserStore

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var location = ""
    @State private var lat: Double? = nil
    @State private var lng: Double? = nil
    
    // Suggestions (wie RegisterView)
    @StateObject private var locationGeocoder = LocationGeocoder()
    @State private var showLocationSuggestions = false
    @State private var locationSearchTask: Task<Void, Never>? = nil

    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()

    // Photo
    @State private var prefilledPhotoUrl: String? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var showImagePicker: Bool = false

    // Interests / Availability
    private let jobInterestOptions = ["Hospitality", "Events", "Retail", "Office", "Logistics", "Warehouse", "Customer Service"]
    @State private var selectedJobInterests: Set<String> = []

    @State private var availability: [AvailabilityDTO] = [
        .init(name: "Mon", available: false),
        .init(name: "Tue", available: false),
        .init(name: "Wed", available: false),
        .init(name: "Thu", available: false),
        .init(name: "Fri", available: false),
        .init(name: "Sat", available: false),
        .init(name: "Sun", available: false),
    ]

    // Bio / Terms
    @State private var bio: String = ""
    private let bioLimit = 300
    @State private var acceptedTerms: Bool = false

    // UI state
    @State private var isSubmitting = false
    @State private var localError: String?

    // Back confirm
    @State private var showConfirmBack = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                headerSection
                profileInfoSection
                dobSection
                jobInterestsSection
                availabilitySection
                bioAndTermsSection
                errorSection
                submitButtonSection
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.xs)
            .padding(.bottom, DS.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .dsBackground()
        .onAppear { prefillFromUserIfNeeded() }
        .navigationBarBackButtonHidden(true)
        .toolbar { backToolbar }
        .alert("Change role?", isPresented: $showConfirmBack) {
            Button("Cancel", role: .cancel) {}
            Button("Change role", role: .destructive) { changeRoleLocally() }
        } message: {
            Text("Your entered information will be lost.")
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSProgressSteps(steps: ["Role", "Profile"], current: 1)
            Text("Complete your worker profile")
                .dsFont(.display)
                .foregroundStyle(DS.Color.text)
            Text("We need a few details to match you with jobs.")
                .dsFont(.body)
                .foregroundStyle(DS.Color.text2)
        }
    }

    private var profileInfoSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            DSSection("Profile Information", ruled: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    profilePhotoRow

                    DSTextField("First name", text: $firstName)
                        .textInputAutocapitalization(.words)

                    DSTextField("Last name", text: $lastName)
                        .textInputAutocapitalization(.words)
                }
            }

            DSSection("Location", ruled: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    DSTextField("City / ZIP code", placeholder: "Start typing a city or ZIP", text: $location)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .textContentType(.addressCity)
                        .onChange(of: location) { _, newValue in
                            // sobald user tippt -> coords invalid
                            lat = nil
                            lng = nil
                            showLocationSuggestions = true

                            locationSearchTask?.cancel()
                            locationSearchTask = Task {
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                if Task.isCancelled { return }
                                await MainActor.run {
                                    locationGeocoder.updateQuery(newValue)
                                }
                            }
                        }

                    Text("Pick a suggestion so we can save coordinates.")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)

                    if showLocationSuggestions && !locationGeocoder.suggestions.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(locationGeocoder.suggestions) { s in
                                Button {
                                    location = s.fullText
                                    lat = s.lat
                                    lng = s.lng
                                    showLocationSuggestions = false
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

                    if let lat, let lng {
                        Text("Saved coordinates: \(lat), \(lng)")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.muted)
                    }
                }
            }
        }
    }

    private var profilePhotoRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Group {
                if let image = pickedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let urlString = prefilledPhotoUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            photoPlaceholder
                        }
                    }
                } else {
                    photoPlaceholder
                }
            }
            .frame(width: 56, height: 56)
            .background(DS.Color.surface2)
            .clipShape(Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(pickedImage == nil ? "No photo selected" : "Photo selected")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text2)

                Button(pickedImage == nil ? "Choose photo" : "Change photo") {
                    showImagePicker = true
                }
                .font(DS.Font.make(15, .semibold))
                .foregroundStyle(DS.Color.primaryText)
                .frame(minHeight: 44, alignment: .leading)
            }

            Spacer()

            if pickedImage != nil {
                Button(role: .destructive) {
                    pickedImage = nil
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(DS.Color.danger)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Remove photo")
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $pickedImage)
        }
    }

    private var photoPlaceholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(DS.Color.muted)
    }

    /// Juengstes erlaubtes Geburtsdatum (18+)
    private static var latestAllowedBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }

    private var dobSection: some View {
        DSSection("Date of birth", ruled: false) {
            DatePicker("Date of birth", selection: $dateOfBirth, in: ...Self.latestAllowedBirthDate, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(DS.Color.primary)
                .frame(maxWidth: .infinity)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(DS.Color.border, lineWidth: 1)
                )
        }
    }

    private var jobInterestsSection: some View {
        DSSection("Job interests", trailing: "Select one or more", ruled: false) {
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
        }
    }

    private var availabilitySection: some View {
        DSSection("Availability", ruled: true) {
            VStack(spacing: 0) {
                ForEach(availability.indices, id: \.self) { i in
                    DSToggleRow(availability[i].name, isOn: $availability[i].available)
                }
            }
        }
    }

    private var bioAndTermsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSTextEditor("Bio (optional)", placeholder: "Tell employers a bit about yourself.", text: $bio, minLines: 4, maxLength: bioLimit)

            Toggle(isOn: $acceptedTerms) {
                Text("I accept the Terms & Conditions and Privacy Policy.")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text)
            }
            .tint(DS.Color.primary)
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            if let localError {
                Text(localError)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let err = userStore.errorMessage {
                Text(err)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var submitButtonSection: some View {
        Button {
            submit()
        } label: {
            Text(isSubmitting ? "Saving..." : "Finish setup")
        }
        .buttonStyle(.ds(.primary))
        .disabled(isSubmitting)
    }

    private var backToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                if hasUnsavedInput {
                    showConfirmBack = true
                } else {
                    changeRoleLocally()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Color.primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
        }
    }

    // MARK: - Helpers

    private var hasUnsavedInput: Bool {
        !firstName.isEmpty ||
        !lastName.isEmpty ||
        !location.isEmpty ||
        pickedImage != nil ||
        !selectedJobInterests.isEmpty ||
        availability.contains(where: { $0.available }) ||
        !bio.isEmpty ||
        acceptedTerms
    }

    private func bindingForInterest(_ option: String) -> Binding<Bool> {
        Binding(
            get: { selectedJobInterests.contains(option) },
            set: { on in
                if on { selectedJobInterests.insert(option) }
                else { selectedJobInterests.remove(option) }
            }
        )
    }

    private func submit() {
        localError = nil
        Task { await submitAsync() }
    }

    @MainActor
    private func submitAsync() async {
        // validation
        guard !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            localError = "Please enter your location."
            return
        }
        guard !selectedJobInterests.isEmpty else {
            localError = "Please select at least one job interest."
            return
        }
        guard availability.contains(where: { $0.available }) else {
            localError = "Please select at least one available day."
            return
        }
        guard acceptedTerms else {
            localError = "Please accept the Terms & Conditions and Privacy Policy."
            return
        }
        
        guard let lat = lat, let lng = lng else {
            localError = "Please select a location from the suggestions."
            return
        }
        
        print("lat: ", lat)
        print("lng: ", lng)

        do {
            var finalProfileUrl: String? = prefilledPhotoUrl
            if let img = pickedImage {
                finalProfileUrl = try await APIClient.shared.uploadProfilePhoto(img)
            }

            isSubmitting = true
            await userStore.completeWorkerOnboarding(
                firstName: firstName.isEmpty ? nil : firstName,
                lastName: lastName.isEmpty ? nil : lastName,
                location: location,
                lat: lat,
                lng: lng,
                dateOfBirthISO: isoDate(dateOfBirth),
                jobInterests: Array(selectedJobInterests),
                availability: availability,
                bio: bio.isEmpty ? nil : bio,
                profilePhotoUrl: finalProfileUrl,
                acceptedTerms: acceptedTerms
            )
            isSubmitting = false
            if userStore.errorMessage == nil { DS.Haptics.success() }
        } catch {
            isSubmitting = false
            localError = error.localizedDescription
        }
    }

    private func prefillFromUserIfNeeded() {
        guard let u = userStore.currentUser else { return }
        if firstName.isEmpty { firstName = u.firstName ?? "" }
        if lastName.isEmpty { lastName = u.lastName ?? "" }
        if location.isEmpty { location = u.location ?? "" }
        if prefilledPhotoUrl == nil { prefilledPhotoUrl = u.profilePhotoUrl }
        
        /*if lat.isEmpty { lat = u.lat ?? nil }
        if lng.isEmpty { lng = u.lng ?? nil }*/
        
        if lat == nil { lat = u.lat }
        if lng == nil { lng = u.lng }
        
        if !location.isEmpty {
            showLocationSuggestions = false
        }
    }

    private func isoDate(_ date: Date) -> String {
        DateOnly.string(from: date)
    }

    private func changeRoleLocally() {
        guard var u = userStore.currentUser else { return }
        u.onboarding = .pendingRole
        u.role = nil
        userStore.currentUser = u
        userStore.errorMessage = nil
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
