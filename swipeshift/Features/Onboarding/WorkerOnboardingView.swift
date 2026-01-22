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
            VStack(spacing: 18) {
                headerSection
                profileInfoSection
                dobSection
                jobInterestsSection
                availabilitySection
                bioAndTermsSection
                errorSection
                submitButtonSection
                Spacer(minLength: 20)
            }
        }
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
        VStack(spacing: 8) {
            Text("Complete your worker profile")
                .font(.title2).bold()
            Text("We need a few details to match you with jobs.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
        .padding(.horizontal, 24)
    }

    private var profileInfoSection: some View {
        VStack(spacing: 12) {
            Text("Profile Information")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            profilePhotoRow

            TextField("First name", text: $firstName)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            TextField("Last name", text: $lastName)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Location")
                    .font(.headline)

                Text("Start typing a city or ZIP. Pick a suggestion so we can save coordinates.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("City / ZIP code", text: $location)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textContentType(.addressCity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
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
                                    Text(s.title)
                                        .foregroundColor(.primary)
                                    if !s.subtitle.isEmpty {
                                        Text(s.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Divider()
                        }
                    }
                    .background(Color.gray.opacity(0.06))
                    .cornerRadius(12)
                }

                if let lat, let lng {
                    Text("Saved coordinates: \(lat), \(lng)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var profilePhotoRow: some View {
        HStack(spacing: 12) {
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
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.secondary)
                                .padding(10)
                        }
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.secondary)
                        .padding(10)
                }
            }
            .frame(width: 56, height: 56)
            .background(Color.gray.opacity(0.08))
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(pickedImage == nil ? "No photo selected" : "Photo selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button {
                    showImagePicker = true
                } label: {
                    Text(pickedImage == nil ? "Choose photo" : "Change photo")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }

            Spacer()

            if pickedImage != nil {
                Button(role: .destructive) {
                    pickedImage = nil
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $pickedImage)
        }
    }

    private var dobSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date of birth")
                .font(.headline)

            DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
        }
        .padding(.horizontal, 24)
    }

    private var jobInterestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job interests")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(jobInterestOptions, id: \.self) { option in
                    Toggle(isOn: bindingForInterest(option)) {
                        Text(option).font(.subheadline)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .padding()
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Availability")
                .font(.headline)

            VStack(spacing: 12) {
                ForEach(availability.indices, id: \.self) { i in
                    HStack {
                        Text(availability[i].name)
                        Spacer()
                        Toggle("", isOn: $availability[i].available)
                            .labelsHidden()
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .padding(.horizontal, 24)
    }

    private var bioAndTermsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bio (optional)")
                .font(.headline)

            TextEditor(text: $bio)
                .frame(minHeight: 100)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .onChange(of: bio) { _, newValue in
                    if newValue.count > bioLimit {
                        bio = String(newValue.prefix(bioLimit))
                    }
                }

            HStack {
                Spacer()
                Text("\(bio.count)/\(bioLimit)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Toggle(isOn: $acceptedTerms) {
                Text("I accept the Terms & Conditions and Privacy Policy.")
                    .font(.footnote)
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))
        }
        .padding(.horizontal, 24)
    }

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let localError {
                Text(localError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let err = userStore.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
    }

    private var submitButtonSection: some View {
        Button {
            submit()
        } label: {
            Text(isSubmitting ? "Saving..." : "Finish setup")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .fontWeight(.semibold)
                .cornerRadius(14)
        }
        .padding(.horizontal, 24)
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
            }
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
                profilePhotoUrl: finalProfileUrl
            )
            isSubmitting = false
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
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
