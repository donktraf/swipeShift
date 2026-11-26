//
//  EditEmployerProfileView.swift
//  swipeShift
//

import SwiftUI

struct EditEmployerProfileView: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: ProfileTab = .company

    enum ProfileTab: String, CaseIterable {
        case company = "Company"
        case personal = "Your Profile"
    }

    var body: some View {
        SubScreenShell(title: "Edit Profile") {
            VStack(spacing: 0) {
                // Tab Switcher (segmentierte Pills)
                HStack(spacing: DS.Spacing.xxs) {
                    ForEach(ProfileTab.allCases, id: \.self) { tab in
                        Button {
                            DS.Haptics.selection()
                            selectedTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                                .foregroundStyle(selectedTab == tab ? DS.Color.onPrimary : DS.Color.text2)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(selectedTab == tab ? DS.Color.primary : Color.clear, in: Capsule())
                                .frame(minHeight: 44)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.dsPressable)
                        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                }
                .padding(DS.Spacing.xxs)
                .background(DS.Color.surface2, in: Capsule())
                .dsAnimation(.snappy, value: selectedTab)
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.bottom, DS.Spacing.lg)

                switch selectedTab {
                case .company:  CompanyInfoTab()
                case .personal: PersonalProfileTab()
                }
            }
        }
    }
}

// MARK: - Company Information Tab

private struct CompanyInfoTab: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.dismiss) private var dismiss

    @State private var companyName: String = ""
    @State private var businessAreas: Set<String> = []
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var companySize: String = "1–10"
    @State private var companyBio: String = ""
    @State private var website: String = ""
    @State private var primaryLocation: String = ""
    @State private var locations: [String] = []
    @State private var newLocationText: String = ""
    @State private var showAddLocation = false
    @State private var publicForm = EmployerPublicProfileForm()
    /// Prefill nur einmal, damit erneutes onAppear ungespeicherte Eingaben nicht ueberschreibt
    @State private var didPrefill = false
    @State private var showLogoPicker = false
    @State private var selectedLogo: UIImage? = nil

    @State private var termsAccepted = false
    @State private var ratingSystemAccepted = false
    @State private var paymentResponsibility = false
    @State private var accurateJobInfo = false
    @State private var legalHiring = false
    /// AGB sind Kontovoraussetzung: einmal zugestimmt, nicht mehr abwaehlbar
    @State private var termsLocked = false
    @State private var isSaving = false
    @State private var saveError: String? = nil

    private let allAreas = ["Hospitality", "Events", "Logistics", "Retail",
                            "Customer Service", "Warehouse", "Office", "Cleaning"]
    private let sizeOptions = ["1–10", "11–50", "51–200", "201–500", "500+"]

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            // Logo
            VStack(spacing: DS.Spacing.sm) {
                if let img = selectedLogo {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                } else {
                    DSAvatar(text: "🏢", size: 80, shape: .circle)
                }
                Button("Change Logo") { showLogoPicker = true }
                    .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
            }
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $showLogoPicker) {
                ImagePicker(image: $selectedLogo)
            }

            // Basic Info
            empSection(title: "Company Details") {
                DSTextField("Company Name", placeholder: "Acme Corp", text: $companyName)
                DSTextField("Work Email", placeholder: "hello@company.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                DSTextField("Phone", placeholder: "+49 711 000 0000", text: $phone)
                    .keyboardType(.phonePad)
                DSTextField("Website", placeholder: "https://company.com", text: $website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                empRow(label: "Company Size") {
                    Picker("Company Size", selection: $companySize) {
                        ForEach(sizeOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(DS.Color.primaryText)
                }
            }

            // Business Areas
            empSection(title: "Business Areas") {
                Text("Select all that apply")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.muted)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Spacing.xs), GridItem(.flexible())], spacing: DS.Spacing.xs) {
                    ForEach(allAreas, id: \.self) { area in
                        let on = businessAreas.contains(area)
                        DSChip(area, isSelected: on) {
                            if on { businessAreas.remove(area) }
                            else  { businessAreas.insert(area) }
                        }
                    }
                }
            }

            // Locations
            empSection(title: "Locations") {
                DSTextField("Primary Location", placeholder: "Stuttgart, Germany", text: $primaryLocation)
                    .textContentType(.addressCity)

                ForEach(locations, id: \.self) { loc in
                    locationRow(loc) { locations.removeAll { $0 == loc } }
                }

                // Add location row
                addLocationRow(text: $newLocationText) {
                    let t = newLocationText.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { locations.append(t); newLocationText = "" }
                }
            }

            // Oeffentliche Infos (Slogan, Social, Adresse, Ansprechpartner)
            EmployerPublicProfileSection(form: $publicForm)

            // Bio
            empSection(title: "Company Bio") {
                DSTextEditor("Company Bio", placeholder: "Tell workers about your company", text: $companyBio, minLines: 3, maxLines: 8, maxLength: 500)
            }

            // Legal
            empSection(title: "Legal Agreements") {
                legalToggle("I agree to the Terms of Service", isOn: $termsAccepted, locked: termsLocked)
                legalToggle("I accept the Rating System guidelines", isOn: $ratingSystemAccepted)
                legalToggle("I take payment responsibility for hired workers", isOn: $paymentResponsibility)
                legalToggle("I will provide accurate job descriptions", isOn: $accurateJobInfo)
                legalToggle("I confirm legal right to hire in this region", isOn: $legalHiring)
            }

            // Save
            Button { Task { await save() } } label: {
                if isSaving { ProgressView().tint(DS.Color.onPrimary) }
                else { Text("Save Changes") }
            }
            .buttonStyle(.ds(.primary))
            .padding(.horizontal, DS.Spacing.screenEdge)
            .disabled(isSaving)
            .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        guard !didPrefill, let u = userStore.currentUser else { return }
        didPrefill = true
        companyName     = u.companyName      ?? ""
        email           = u.companyEmail     ?? u.email
        phone           = u.companyPhone     ?? ""
        companyBio      = u.companyDescription ?? ""
        website         = u.websiteOrInstagram ?? ""
        primaryLocation = u.primaryHiringLocation ?? u.location ?? ""
        companySize     = u.companySize      ?? "1–10"
        publicForm      = EmployerPublicProfileForm(user: u)

        if let areas = u.businessAreas, !areas.isEmpty {
            businessAreas = Set(areas)
        } else if let ind = u.industry, !ind.isEmpty {
            businessAreas = Set(ind.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }

        if let locs = u.companyLocations, !locs.isEmpty {
            locations = locs
        }

        let consents = u.legalConsents ?? [:]
        termsAccepted        = consents["terms"] ?? false
        termsLocked          = termsAccepted
        ratingSystemAccepted = consents["ratingSystem"] ?? false
        paymentResponsibility = consents["paymentResponsibility"] ?? false
        accurateJobInfo      = consents["accurateJobInfo"] ?? false
        legalHiring          = consents["legalHiring"] ?? false
    }

    private func save() async {
        isSaving = true
        do {
            var uploadedPhotoUrl: String? = nil
            if let img = selectedLogo {
                uploadedPhotoUrl = try await APIClient.shared.uploadProfilePhoto(img)
            }
            var request = UpdateEmployerProfileRequest(
                companyName:           companyName.isEmpty ? nil : companyName,
                companySize:           companySize,
                companyPhone:          phone.isEmpty   ? nil : phone,
                companyEmail:          email.isEmpty   ? nil : email,
                businessAreas:         Array(businessAreas),
                locations:             locations,
                primaryHiringLocation: primaryLocation.isEmpty ? nil : primaryLocation,
                companyBio:            companyBio.isEmpty ? nil : companyBio,
                website:               website.isEmpty ? nil : website,
                teamMembers:           nil,
                profilePhotoUrl:       uploadedPhotoUrl,
                firstName:             nil,
                lastName:              nil,
                jobTitle:              nil,
                managerRole:           nil,
                legalConsents: [
                    "terms":                 termsAccepted,
                    "ratingSystem":          ratingSystemAccepted,
                    "paymentResponsibility": paymentResponsibility,
                    "accurateJobInfo":       accurateJobInfo,
                    "legalHiring":           legalHiring,
                ]
            )
            publicForm.apply(to: &request)
            try await APIClient.shared.updateEmployerProfile(request)
            await userStore.refreshMe()
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Your Profile Tab

private struct PersonalProfileTab: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var workEmail: String = ""
    @State private var jobTitle: String = ""
    @State private var role: ManagerRole = .hiringManager
    @State private var managedLocations: [String] = ["Stuttgart HQ"]
    @State private var newManagedLocation: String = ""

    @State private var teamMembers: [TeamMember] = []
    @State private var inviteEmail: String = ""
    @State private var inviteRole: ManagerRole = .hiringManager
    @State private var showInviteSheet = false
    @State private var memberToRemove: TeamMember? = nil
    @State private var didPrefill = false
    @State private var isSaving = false
    @State private var saveError: String? = nil

    enum ManagerRole: String, CaseIterable {
        case admin         = "Admin"
        case hiringManager = "Hiring Manager"
    }

    struct TeamMember: Identifiable {
        let id = UUID()
        let name: String
        let email: String
        let role: ManagerRole
        var avatarLetter: String { String(name.prefix(1)) }

        static let mock: [TeamMember] = [
            TeamMember(name: "Sarah Klein",  email: "sarah@company.com",  role: .admin),
            TeamMember(name: "Tom Fischer",  email: "tom@company.com",    role: .hiringManager),
        ]
    }

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            // Personal Details
            empSection(title: "Personal Details") {
                DSTextField("First Name", placeholder: "John", text: $firstName).textContentType(.givenName)
                DSTextField("Last Name", placeholder: "Smith", text: $lastName).textContentType(.familyName)
                DSTextField("Work Email", placeholder: "john@company.com", text: $workEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                DSTextField("Job Title", placeholder: "Head of Recruitment", text: $jobTitle)
                empRow(label: "Role") {
                    Picker("Role", selection: $role) {
                        ForEach(ManagerRole.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(DS.Color.primaryText)
                }
            }

            // Managed Locations
            empSection(title: "Managed Locations") {
                ForEach(managedLocations, id: \.self) { loc in
                    locationRow(loc) { managedLocations.removeAll { $0 == loc } }
                }
                addLocationRow(text: $newManagedLocation) {
                    let t = newManagedLocation.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { managedLocations.append(t); newManagedLocation = "" }
                }
            }

            // Team Members
            empSection(title: "Team Members") {
                ForEach(teamMembers) { member in
                    HStack(spacing: DS.Spacing.sm) {
                        DSAvatar(text: member.avatarLetter, size: 40, shape: .circle)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .dsFont(.callout)
                                .foregroundStyle(DS.Color.text)
                            Text(member.email)
                                .dsFont(.caption)
                                .foregroundStyle(DS.Color.muted)
                        }

                        Spacer(minLength: DS.Spacing.xs)

                        DSBadge(member.role.rawValue, member.role == .admin ? .tone(.primary) : .tone(.neutral))

                        Button {
                            DS.Haptics.warning()
                            memberToRemove = member
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(DS.Color.danger)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.dsPressable)
                        .accessibilityLabel("Remove \(member.name)")
                    }
                }

                // Invite Button
                Button { showInviteSheet = true } label: {
                    Label("Invite Team Member", systemImage: "person.badge.plus")
                }
                .buttonStyle(.ds(.soft, size: .medium))
            }

            // Save
            Button { Task { await save() } } label: {
                if isSaving { ProgressView().tint(DS.Color.onPrimary) }
                else { Text("Save Changes") }
            }
            .buttonStyle(.ds(.primary))
            .padding(.horizontal, DS.Spacing.screenEdge)
            .disabled(isSaving)
            .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
        .onAppear { prefill() }
        .sheet(isPresented: $showInviteSheet) {
            inviteSheet
        }
        .alert("Remove \(memberToRemove?.name ?? "member")?", isPresented: .constant(memberToRemove != nil)) {
            Button("Remove", role: .destructive) {
                if let m = memberToRemove {
                    teamMembers.removeAll { $0.id == m.id }
                }
                memberToRemove = nil
            }
            Button("Cancel", role: .cancel) { memberToRemove = nil }
        } message: {
            Text("They will lose access to the company account.")
        }
    }

    private var inviteSheet: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.lg) {
                empSection(title: "Invite Details") {
                    DSTextField("Email", placeholder: "colleague@company.com", text: $inviteEmail)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    empRow(label: "Role") {
                        Picker("Role", selection: $inviteRole) {
                            ForEach(PersonalProfileTab.ManagerRole.allCases, id: \.self) { r in
                                Text(r.rawValue).tag(r)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(DS.Color.primaryText)
                    }
                }
                .padding(.top, DS.Spacing.lg)

                Button {
                    let t = inviteEmail.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty {
                        teamMembers.append(PersonalProfileTab.TeamMember(
                            name: t.components(separatedBy: "@").first?.capitalized ?? t,
                            email: t, role: inviteRole
                        ))
                        inviteEmail = ""
                    }
                    showInviteSheet = false
                } label: {
                    Text("Send Invite")
                }
                .buttonStyle(.ds(.primary))
                .padding(.horizontal, DS.Spacing.screenEdge)
                .disabled(inviteEmail.isEmpty)

                Spacer()
            }
            .dsBackground()
            .navigationTitle("Invite Team Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showInviteSheet = false }
                }
            }
        }
    }

    private func prefill() {
        guard !didPrefill, let u = userStore.currentUser else { return }
        didPrefill = true
        firstName = u.firstName ?? ""
        lastName  = u.lastName  ?? ""
        workEmail = u.email
        jobTitle  = u.jobTitle  ?? ""
        if let r = u.managerRole, let parsed = ManagerRole(rawValue: r) {
            role = parsed
        }
        if let members = u.teamMembers {
            teamMembers = members.map { TeamMember(name: $0.name, email: $0.email, role: ManagerRole(rawValue: $0.role) ?? .hiringManager) }
        }
    }

    private func save() async {
        isSaving = true
        let memberDTOs = teamMembers.map { TeamMemberDTO(name: $0.name, email: $0.email, role: $0.role.rawValue) }
        do {
            try await APIClient.shared.updateEmployerProfile(UpdateEmployerProfileRequest(
                companyName:           nil,
                companySize:           nil,
                companyPhone:          nil,
                companyEmail:          nil,
                businessAreas:         nil,
                locations:             nil,
                primaryHiringLocation: nil,
                companyBio:            nil,
                website:               nil,
                teamMembers:           memberDTOs,
                profilePhotoUrl:       nil,
                firstName:             firstName.isEmpty ? nil : firstName,
                lastName:              lastName.isEmpty  ? nil : lastName,
                jobTitle:              jobTitle.isEmpty  ? nil : jobTitle,
                managerRole:           role.rawValue
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

// MARK: - Shared Helpers (file-private)

/// Flache Gruppe: Sektionslabel + Felder mit 16er Abstand, Trennlinie unten (keine Box), 20 Seitenrand.
private func empSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    DSSection(title) {
        VStack(alignment: .leading, spacing: DS.Spacing.md) { content() }
            .padding(.vertical, DS.Spacing.sm)
    }
    .padding(.horizontal, DS.Spacing.screenEdge)
}

/// Zeile mit Label links und Bedienelement rechts (Menues).
private func empRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(spacing: DS.Spacing.sm) {
        Text(label)
            .dsFont(.body)
            .foregroundStyle(DS.Color.text)
        Spacer(minLength: DS.Spacing.xs)
        content()
            .font(DS.Font.make(15, .medium))
    }
    .frame(minHeight: 44)
}

/// Eingetragener Standort mit Entfernen-Button.
private func locationRow(_ location: String, onRemove: @escaping () -> Void) -> some View {
    HStack {
        Text(location)
            .dsFont(.body)
            .foregroundStyle(DS.Color.text)
        Spacer(minLength: DS.Spacing.xs)
        Button {
            DS.Haptics.light()
            onRemove()
        } label: {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(DS.Color.danger)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPressable)
        .accessibilityLabel("Remove \(location)")
    }
    .frame(minHeight: 44)
}

/// Feld + Plus-Button zum Hinzufuegen eines Standorts.
private func addLocationRow(text: Binding<String>, onAdd: @escaping () -> Void) -> some View {
    HStack(alignment: .bottom, spacing: DS.Spacing.xs) {
        DSTextField("Add location", placeholder: "Add location...", text: text)
        Button {
            DS.Haptics.light()
            onAdd()
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(DS.Color.primary)
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPressable)
        .accessibilityLabel("Add location")
    }
}

private func legalToggle(_ label: String, isOn: Binding<Bool>, locked: Bool = false) -> some View {
    Button {
        DS.Haptics.selection()
        isOn.wrappedValue.toggle()
    } label: {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                .font(.system(size: 22))
                .foregroundStyle(isOn.wrappedValue ? DS.Color.primary : DS.Color.muted)
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
    .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
}
