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
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                headerSection
                contactSection
                logoSection
                companySection
                websiteSection
                descriptionAndTermsSection
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
            Text("Complete your employer profile")
                .dsFont(.display)
                .foregroundStyle(DS.Color.text)
            Text("We need company info before you can use employer features.")
                .dsFont(.body)
                .foregroundStyle(DS.Color.text2)
        }
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            DSSection("Contact person", ruled: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    DSTextField("Contact first name", text: $firstName)
                        .textInputAutocapitalization(.words)
                    DSTextField("Contact last name", text: $lastName)
                        .textInputAutocapitalization(.words)
                }
            }

            // Location mit Suggestions + lat/lng
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

    private var logoSection: some View {
        DSSection("Company logo (optional)", ruled: false) {
            HStack(spacing: DS.Spacing.sm) {
                Group {
                    if let image = companyLogoUIImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if let urlString = prefilledCompanyLogoUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                logoPlaceholder
                            }
                        }
                    } else {
                        logoPlaceholder
                    }
                }
                .frame(width: 56, height: 56)
                .background(DS.Color.surface2)
                .clipShape(Circle())
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(companyLogoUIImage == nil ? "No logo selected" : "Logo selected")
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.text2)

                    Button(companyLogoUIImage == nil ? "Choose logo" : "Change logo") {
                        showCompanyLogoPicker = true
                    }
                    .font(DS.Font.make(15, .semibold))
                    .foregroundStyle(DS.Color.primaryText)
                    .frame(minHeight: 44, alignment: .leading)
                }

                Spacer()

                if companyLogoUIImage != nil {
                    Button(role: .destructive) {
                        companyLogoUIImage = nil
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(DS.Color.danger)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Remove logo")
                }
            }
            .sheet(isPresented: $showCompanyLogoPicker) {
                ImagePicker(image: $companyLogoUIImage)
            }
        }
    }

    private var logoPlaceholder: some View {
        Image(systemName: "building.2.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(DS.Color.muted)
    }

    private var companySection: some View {
        DSSection("Company", ruled: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                DSTextField("Company name", text: $companyName)
                    .textInputAutocapitalization(.words)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Company size")
                        .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(DS.Color.text2)
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(sizes, id: \.self) { size in
                            DSChip(size, isSelected: companySize == size) { companySize = size }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Industry")
                        .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(DS.Color.text2)
                    HStack {
                        Picker("Industry", selection: $industry) {
                            ForEach(industries, id: \.self) { Text($0).tag($0) }
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
                }
            }
        }
    }

    private var websiteSection: some View {
        DSTextField("Website / Instagram (optional)", placeholder: "https:// or @instagram", text: $websiteOrInstagram)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    private var descriptionAndTermsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSTextEditor("Description (optional)", placeholder: "What does your company do?", text: $companyDescription, minLines: 4, maxLength: descLimit)

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
        Button { submit() } label: {
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
                companyDescription: companyDescription.isEmpty ? nil : companyDescription,
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
