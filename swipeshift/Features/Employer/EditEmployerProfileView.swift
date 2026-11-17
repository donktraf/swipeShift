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
                // Tab Switcher
                HStack(spacing: 0) {
                    ForEach(ProfileTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    selectedTab == tab
                                        ? SS.primary
                                        : Color.white.opacity(0.08)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 20)

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
        VStack(spacing: 20) {
            // Logo
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 80, height: 80)
                    if let img = selectedLogo {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } else {
                        Text("🏢")
                            .font(.system(size: 36))
                    }
                }
                Button("Change Logo") { showLogoPicker = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
            .sheet(isPresented: $showLogoPicker) {
                ImagePicker(image: $selectedLogo)
            }

            // Basic Info
            empSection(title: "Company Details") {
                empRow(label: "Company Name") {
                    TextField("Acme Corp", text: $companyName)
                }
                empRow(label: "Work Email") {
                    TextField("hello@company.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                }
                empRow(label: "Phone") {
                    TextField("+49 711 000 0000", text: $phone)
                        .keyboardType(.phonePad)
                }
                empRow(label: "Website") {
                    TextField("https://company.com", text: $website)
                        .keyboardType(.URL)
                }
                empRow(label: "Company Size") {
                    Picker("", selection: $companySize) {
                        ForEach(sizeOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            // Business Areas
            empSection(title: "Business Areas") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select all that apply")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(allAreas, id: \.self) { area in
                            let on = businessAreas.contains(area)
                            Button {
                                if on { businessAreas.remove(area) }
                                else  { businessAreas.insert(area) }
                            } label: {
                                Text(area)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(on ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(on ? SS.primary : Color.gray.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }

            // Locations
            empSection(title: "Locations") {
                empRow(label: "Primary Location") {
                    TextField("Stuttgart, Germany", text: $primaryLocation)
                        .textContentType(.addressCity)
                }

                if !locations.isEmpty {
                    ForEach(locations, id: \.self) { loc in
                        HStack {
                            Text(loc)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .padding(.leading, 14)
                            Spacer()
                            Button {
                                locations.removeAll { $0 == loc }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                                    .padding(.trailing, 14)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 12)
                        Divider().padding(.leading, 14)
                    }
                }

                // Add location row
                HStack {
                    TextField("Add location...", text: $newLocationText)
                        .font(.system(size: 14))
                        .padding(.leading, 14)
                    Button {
                        let t = newLocationText.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { locations.append(t); newLocationText = "" }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(SS.primary)
                            .padding(.trailing, 14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
            }

            // Bio
            empSection(title: "Company Bio") {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $companyBio)
                        .frame(minHeight: 80)
                        .font(.system(size: 14))
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                        .onChange(of: companyBio) { _, new in
                            if new.count > 500 { companyBio = String(new.prefix(500)) }
                        }
                    Text("\(companyBio.count)/500")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
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
                Group {
                    if isSaving { ProgressView().tint(.white) }
                    else { Text("Save Changes") }
                }
            }
            .buttonStyle(SSPrimaryButtonStyle(isEnabled: !isSaving))
            .padding(.horizontal, 16)
            .disabled(isSaving)
            .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }

            Spacer().frame(height: 20)
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let u = userStore.currentUser else { return }
        companyName     = u.companyName      ?? ""
        email           = u.companyEmail     ?? u.email
        phone           = u.companyPhone     ?? ""
        companyBio      = u.companyDescription ?? ""
        website         = u.websiteOrInstagram ?? ""
        primaryLocation = u.primaryHiringLocation ?? u.location ?? ""
        companySize     = u.companySize      ?? "1–10"

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
            try await APIClient.shared.updateEmployerProfile(UpdateEmployerProfileRequest(
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
        VStack(spacing: 20) {
            // Personal Details
            empSection(title: "Personal Details") {
                empRow(label: "First Name") {
                    TextField("John", text: $firstName).textContentType(.givenName)
                }
                empRow(label: "Last Name") {
                    TextField("Smith", text: $lastName).textContentType(.familyName)
                }
                empRow(label: "Work Email") {
                    TextField("john@company.com", text: $workEmail)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                }
                empRow(label: "Job Title") {
                    TextField("Head of Recruitment", text: $jobTitle)
                }
                empRow(label: "Role") {
                    Picker("", selection: $role) {
                        ForEach(ManagerRole.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            // Managed Locations
            empSection(title: "Managed Locations") {
                ForEach(managedLocations, id: \.self) { loc in
                    HStack {
                        Text(loc)
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .padding(.leading, 14)
                        Spacer()
                        Button {
                            managedLocations.removeAll { $0 == loc }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red.opacity(0.7))
                                .padding(.trailing, 14)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 12)
                    Divider().padding(.leading, 14)
                }
                HStack {
                    TextField("Add location...", text: $newManagedLocation)
                        .font(.system(size: 14))
                        .padding(.leading, 14)
                    Button {
                        let t = newManagedLocation.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { managedLocations.append(t); newManagedLocation = "" }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(SS.primary)
                            .padding(.trailing, 14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
            }

            // Team Members
            empSection(title: "Team Members") {
                ForEach(teamMembers) { member in
                    HStack(spacing: 12) {
                        // Avatar
                        ZStack {
                            Circle().fill(SS.primary.opacity(0.15)).frame(width: 38, height: 38)
                            Text(member.avatarLetter)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(SS.primary)
                        }
                        .padding(.leading, 14)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                            Text(member.email)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(member.role.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(member.role == .admin ? SS.primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((member.role == .admin ? SS.primary : Color.gray).opacity(0.1))
                            .clipShape(Capsule())

                        Button {
                            memberToRemove = member
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.red.opacity(0.6))
                                .padding(.trailing, 14)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                    if member.id != teamMembers.last?.id {
                        Divider().padding(.leading, 64)
                    }
                }

                // Invite Button
                Button { showInviteSheet = true } label: {
                    Label("Invite Team Member", systemImage: "person.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SS.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(SS.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            // Save
            Button { Task { await save() } } label: {
                Group {
                    if isSaving { ProgressView().tint(.white) }
                    else { Text("Save Changes") }
                }
            }
            .buttonStyle(SSPrimaryButtonStyle(isEnabled: !isSaving))
            .padding(.horizontal, 16)
            .disabled(isSaving)
            .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }

            Spacer().frame(height: 20)
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
            VStack(spacing: 20) {
                empSection(title: "Invite Details") {
                    empRow(label: "Email") {
                        TextField("colleague@company.com", text: $inviteEmail)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                    }
                    empRow(label: "Role") {
                        Picker("", selection: $inviteRole) {
                            ForEach(PersonalProfileTab.ManagerRole.allCases, id: \.self) { r in
                                Text(r.rawValue).tag(r)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.top, 20)

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
                .buttonStyle(SSPrimaryButtonStyle(isEnabled: !inviteEmail.isEmpty))
                .padding(.horizontal, 16)
                .disabled(inviteEmail.isEmpty)

                Spacer()
            }
            .background(SS.background().ignoresSafeArea())
            .navigationTitle("Invite Team Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showInviteSheet = false }
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func prefill() {
        guard let u = userStore.currentUser else { return }
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

private func empSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
        content()
    }
    .background(Color(uiColor: .systemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .padding(.horizontal, 16)
    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
}

private func empRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
                .padding(.leading, 14)
            content()
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 12)
        Divider().padding(.leading, 14)
    }
}

private func legalToggle(_ label: String, isOn: Binding<Bool>, locked: Bool = false) -> some View {
    VStack(spacing: 0) {
        HStack(spacing: 12) {
            Button { isOn.wrappedValue.toggle() } label: {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(isOn.wrappedValue ? SS.primary : .gray.opacity(0.4))
                    .padding(.leading, 14)
            }
            .buttonStyle(.plain)
            .disabled(locked)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .padding(.trailing, 14)
            Spacer()
        }
        .padding(.vertical, 10)
        .opacity(locked ? 0.6 : 1)
        Divider().padding(.leading, 14)
    }
}
