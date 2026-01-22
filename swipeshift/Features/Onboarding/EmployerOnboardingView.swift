import SwiftUI

struct EmployerOnboardingView: View {
    @EnvironmentObject var userStore: UserStore

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var location = ""
    // Suggestions (wie RegisterView)
    @StateObject private var locationGeocoder = LocationGeocoder()

    @State private var showLocationSuggestions = false
    @State private var locationSearchTask: Task<Void, Never>? = nil

    // Coordinates (must be non-nil before submit)
    @State private var lat: Double? = nil
    @State private var lng: Double? = nil

    @State private var acceptedTerms = false

    @State private var companyName = ""
    @State private var companySize = "1-10"
    @State private var industry = "Hospitality"

    @State private var websiteOrInstagram = ""
    @State private var companyDescription = ""
    private let descLimit = 300

    // Logo
    @State private var companyLogoUIImage: UIImage? = nil
    @State private var showCompanyLogoPicker: Bool = false
    @State private var prefilledCompanyLogoUrl: String? = nil

    // UI state
    @State private var isSubmitting = false
    @State private var localError: String?

    // Back confirm
    @State private var showConfirmBack = false

    private let industries = ["Hospitality", "Events", "Retail", "Office", "Logistics", "Warehouse", "Customer Service"]
    private let sizes = ["1-10", "11-50", "50+"]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerSection
                contactSection
                logoSection
                companySection
                websiteSection
                descriptionAndTermsSection
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
            Text("Complete your employer profile")
                .font(.title2).bold()
            Text("We need company info before you can use employer features.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
        .padding(.horizontal, 24)
    }

    private var contactSection: some View {
        VStack(spacing: 12) {
            TextField("Contact first name", text: $firstName)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            TextField("Contact last name", text: $lastName)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            // ✅ Location mit Suggestions + lat/lng
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

    private var logoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Company logo (optional)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Group {
                    if let image = companyLogoUIImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if let urlString = prefilledCompanyLogoUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                Image(systemName: "building.2.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.secondary)
                                    .padding(10)
                            }
                        }
                    } else {
                        Image(systemName: "building.2.crop.circle.fill")
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
                    Text(companyLogoUIImage == nil ? "No logo selected" : "Logo selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button { showCompanyLogoPicker = true } label: {
                        Text(companyLogoUIImage == nil ? "Choose logo" : "Change logo")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }

                Spacer()

                if companyLogoUIImage != nil {
                    Button(role: .destructive) {
                        companyLogoUIImage = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .sheet(isPresented: $showCompanyLogoPicker) {
                ImagePicker(image: $companyLogoUIImage)
            }
        }
        .padding(.horizontal, 24)
    }

    private var companySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Company").font(.headline)

            Text("Company name").font(.subheadline)
            TextField("Company name", text: $companyName)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            Text("Company size").font(.subheadline)
            Picker("", selection: $companySize) {
                ForEach(sizes, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)

            Text("Industry").font(.subheadline)
            Picker("", selection: $industry) {
                ForEach(industries, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .padding(.horizontal, 24)
    }

    private var websiteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Website / Instagram (optional)").font(.headline)
            TextField("https:// or @instagram", text: $websiteOrInstagram)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
        }
        .padding(.horizontal, 24)
    }

    private var descriptionAndTermsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description (optional)").font(.headline)

            TextEditor(text: $companyDescription)
                .frame(minHeight: 100)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .onChange(of: companyDescription) { _, newValue in
                    if newValue.count > descLimit {
                        companyDescription = String(newValue.prefix(descLimit))
                    }
                }

            HStack {
                Spacer()
                Text("\(companyDescription.count)/\(descLimit)")
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
        Button { submit() } label: {
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
        !companyName.isEmpty ||
        companyLogoUIImage != nil ||
        websiteOrInstagram.isEmpty == false ||
        companyDescription.isEmpty == false ||
        acceptedTerms
    }

    private func submit() {
        localError = nil
        Task { await submitAsync() }
    }

    @MainActor
    private func submitAsync() async {
        guard !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            localError = "Please enter your location."
            return
        }
        guard !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            localError = "Please enter your company name."
            return
        }
        guard acceptedTerms else {
            localError = "Please accept the Terms & Conditions and Privacy Policy."
            return
        }
        guard let lat, let lng else {
            localError = "Please select a location from suggestions so we can save coordinates."
            return
        }

        do {
            var finalCompanyLogoUrl: String? = prefilledCompanyLogoUrl
            if let img = companyLogoUIImage {
                finalCompanyLogoUrl = try await APIClient.shared.uploadCompanyLogo(img)
            }

            isSubmitting = true
            await userStore.completeEmployerOnboarding(
                firstName: firstName.isEmpty ? nil : firstName,
                lastName: lastName.isEmpty ? nil : lastName,
                location: location,
                lat: lat,
                lng: lng,
                companyName: companyName,
                companySize: companySize,
                industry: industry,
                companyLogoUrl: finalCompanyLogoUrl,
                websiteOrInstagram: websiteOrInstagram.isEmpty ? nil : websiteOrInstagram,
                companyDescription: companyDescription.isEmpty ? nil : companyDescription
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
        
        if !location.isEmpty {
            showLocationSuggestions = false
        }

        // wenn du es im UserDTO hast:
        // if prefilledCompanyLogoUrl == nil { prefilledCompanyLogoUrl = u.companyLogoUrl }
        // lat/lng ggf. auch vorbefüllen:
        // if lat == nil { lat = u.lat }
        // if lng == nil { lng = u.lng }
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
