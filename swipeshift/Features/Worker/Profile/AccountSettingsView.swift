//
//  AccountSettingsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - AccountSettingsView (Hauptmenü)

struct AccountSettingsView: View {
    var body: some View {
        SubScreenShell(title: "Account Settings") {
            VStack(spacing: 16) {
                settingsGroup([
                    AnyView(NavigationLink { AccountSecurityView()       } label: { SettingsNavRow(icon: "person.badge.shield.checkmark.fill", label: "Account & Security") }),
                    AnyView(NavigationLink { NotificationSettingsView()  } label: { SettingsNavRow(icon: "bell.badge.fill",                    label: "Notifications") }),
                    AnyView(NavigationLink { PaymentsPayoutsView()       } label: { SettingsNavRow(icon: "creditcard.fill",                    label: "Payments & Payouts") }),
                    AnyView(NavigationLink { PrivacyDataView()           } label: { SettingsNavRow(icon: "hand.raised.fill",                   label: "Privacy & Data") }),
                    AnyView(NavigationLink { AppPreferencesView()        } label: { SettingsNavRow(icon: "slider.horizontal.3",                label: "App Preferences") }),
                ])
            }
            .padding(.horizontal, 16)
        }
    }

    private func settingsGroup(_ rows: [AnyView]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                rows[i]
                if i < rows.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Account & Security

struct AccountSecurityView: View {
    @State private var showChangeEmail    = false
    @State private var showChangePhone    = false
    @State private var showChangePassword = false
    @State private var twoFAEnabled       = false

    var body: some View {
        SubScreenShell(title: "Account & Security") {
            VStack(spacing: 16) {
                // Zugangsdaten
                sectionCard("Credentials") {
                    SettingsActionRow(icon: "envelope.fill",    label: "Change Email")    { showChangeEmail = true }
                    Divider().padding(.leading, 52)
                    SettingsActionRow(icon: "phone.fill",        label: "Change Phone")   { showChangePhone = true }
                    Divider().padding(.leading, 52)
                    SettingsActionRow(icon: "lock.fill",         label: "Change Password")  { showChangePassword = true }
                }

                // Sicherheit
                sectionCard("Security") {
                    HStack(spacing: 14) {
                        Image(systemName: "shield.checkerboard")
                            .font(.system(size: 16))
                            .foregroundColor(SS.primary)
                            .frame(width: 28)
                            .padding(.leading, 14)
                        Text("Two-Factor Authentication")
                            .font(.system(size: 15))
                        Spacer()
                        Toggle("", isOn: $twoFAEnabled)
                            .labelsHidden()
                            .padding(.trailing, 14)
                    }
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 52)

                    NavigationLink {
                        ActiveSessionsView()
                    } label: {
                        SettingsNavRow(icon: "iphone.and.arrow.forward", label: "Active Sessions")
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showChangeEmail)    { ChangeEmailSheet() }
        .sheet(isPresented: $showChangePhone)    { ChangePhoneSheet() }
        .sheet(isPresented: $showChangePassword) { ChangePasswordSheet() }
    }
}

// MARK: - Active Sessions

struct ActiveSessionsView: View {
    private struct DeviceSession: Identifiable {
        let id = UUID()
        let deviceName: String
        let location: String
        let lastActive: String
        let isCurrent: Bool
    }

    private let sessions: [DeviceSession] = [
        .init(deviceName: "iPhone 15 Pro",   location: "Berlin, DE",   lastActive: "Active now",   isCurrent: true),
        .init(deviceName: "iPad Air (5th Gen)", location: "Hamburg, DE", lastActive: "2 days ago",   isCurrent: false),
        .init(deviceName: "iPhone 13",       location: "Munich, DE",  lastActive: "1 week ago",    isCurrent: false),
    ]

    @State private var showSignOutAlert = false

    var body: some View {
        SubScreenShell(title: "Active Sessions") {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        HStack(spacing: 14) {
                            Image(systemName: session.deviceName.contains("iPad") ? "ipad" : "iphone")
                                .font(.system(size: 22))
                                .foregroundColor(session.isCurrent ? SS.primary : .secondary)
                                .frame(width: 32)
                                .padding(.leading, 14)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(session.deviceName)
                                        .font(.system(size: 14, weight: .semibold))
                                    if session.isCurrent {
                                        Text("This Device")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(SS.primary)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text("\(session.location) · \(session.lastActive)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if !session.isCurrent {
                                Button {
                                    // TODO: POST /auth/sessions/:id/revoke
                                } label: {
                                    Text("Sign Out")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .overlay(
                                            Capsule().stroke(Color.red.opacity(0.5), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 14)
                            }
                        }
                        .padding(.vertical, 14)

                        if session.id != sessions.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)

                Button {
                    showSignOutAlert = true
                } label: {
                    Text("Sign out of all other devices")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 0)
            }
            .padding(.horizontal, 16)
        }
        .alert("Sign out of all other devices?", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) { /* TODO: POST /auth/sessions/revoke-all */ }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be automatically signed out on all other devices.")
        }
    }
}

// MARK: - Notification Settings

struct NotificationSettingsView: View {
    private struct NotifCategory: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let label: String
        var push: Bool
        var email: Bool
    }

    @State private var categories: [NotifCategory] = [
        .init(icon: "briefcase.fill",       color: SS.primary, label: "Job Activity", push: true,  email: true),
        .init(icon: "eurosign.circle.fill",  color: .green,     label: "Payments",    push: true,  email: false),
        .init(icon: "bubble.left.fill",      color: .blue,      label: "Messages",    push: true,  email: false),
        .init(icon: "person.fill",           color: .orange,    label: "Account",     push: false, email: true),
    ]
    @State private var quietHoursEnabled = false
    @State private var quietFrom         = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var quietTo           = Calendar.current.date(bySettingHour: 7,  minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        SubScreenShell(title: "Notifications") {
            VStack(spacing: 16) {
                // Kanal-Header
                HStack {
                    Spacer()
                    Text("Push")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 50)
                    Text("E-Mail")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 50)
                        .padding(.trailing, 14)
                }
                .padding(.horizontal, 16)

                // Kategorien
                VStack(spacing: 0) {
                    ForEach(categories.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(categories[i].color.opacity(0.12))
                                    .frame(width: 34, height: 34)
                                Image(systemName: categories[i].icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(categories[i].color)
                            }
                            .padding(.leading, 14)

                            Text(categories[i].label)
                                .font(.system(size: 15))

                            Spacer()

                            Toggle("", isOn: $categories[i].push)
                                .labelsHidden()
                                .frame(width: 50)

                            Toggle("", isOn: $categories[i].email)
                                .labelsHidden()
                                .frame(width: 50)
                                .padding(.trailing, 14)
                        }
                        .padding(.vertical, 12)

                        if i < categories.count - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 16)

                // Ruhige Stunden
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 16))
                            .foregroundColor(SS.primary)
                            .frame(width: 28)
                            .padding(.leading, 14)
                        Text("Quiet Hours")
                            .font(.system(size: 15))
                        Spacer()
                        Toggle("", isOn: $quietHoursEnabled)
                            .labelsHidden()
                            .padding(.trailing, 14)
                    }
                    .padding(.vertical, 14)

                    if quietHoursEnabled {
                        Divider().padding(.leading, 52)
                        HStack(spacing: 14) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .frame(width: 28)
                                .padding(.leading, 14)
                            Text("From")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                            DatePicker("", selection: $quietFrom, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("to")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                            DatePicker("", selection: $quietTo, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .padding(.trailing, 14)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 16)
                .animation(.easeInOut(duration: 0.2), value: quietHoursEnabled)
            }
        }
    }
}

// MARK: - Payments & Payouts

struct PaymentsPayoutsView: View {
    enum PayoutMethod: String, CaseIterable {
        case bankAccount = "Bank Account"
        case paypal      = "PayPal"
    }
    enum PayoutFrequency: String, CaseIterable {
        case instant  = "Immediately"
        case weekly   = "Weekly"
        case monthly  = "Monthly"
    }

    @State private var selectedMethod:    PayoutMethod    = .bankAccount
    @State private var iban:              String          = ""
    @State private var paypalEmail:       String          = ""
    @State private var selectedFrequency: PayoutFrequency = .weekly

    var body: some View {
        SubScreenShell(title: "Payments & Payouts") {
            VStack(spacing: 16) {
                // Methode wählen
                sectionCard("Payout Method") {
                    HStack(spacing: 0) {
                        ForEach(PayoutMethod.allCases, id: \.self) { method in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { selectedMethod = method }
                            } label: {
                                Text(method.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(selectedMethod == method ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(selectedMethod == method ? SS.primary : Color.clear)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    Divider().padding(.horizontal, 14)

                    if selectedMethod == .bankAccount {
                        inputRow(icon: "building.columns.fill", placeholder: "IBAN (e.g. DE89 3704 0044 ...)", text: $iban)
                    } else {
                        inputRow(icon: "p.circle.fill", placeholder: "PayPal E-Mail", text: $paypalEmail)
                    }
                }

                // Auszahlungsrhythmus
                sectionCard("Payout Frequency") {
                    VStack(spacing: 0) {
                        ForEach(PayoutFrequency.allCases, id: \.self) { freq in
                            Button {
                                selectedFrequency = freq
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: selectedFrequency == freq ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18))
                                        .foregroundColor(selectedFrequency == freq ? SS.primary : .secondary)
                                        .frame(width: 28)
                                        .padding(.leading, 14)
                                    Text(freq.rawValue)
                                        .font(.system(size: 15))
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if freq != PayoutFrequency.allCases.last {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }

                // Speichern
                Button {
                    // TODO: PATCH /users/:id/payout-settings
                } label: {
                    Text("Save")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SSPrimaryButtonStyle())
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, 16)
        }
    }

    private func inputRow(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(SS.primary)
                .frame(width: 28)
                .padding(.leading, 14)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .padding(.trailing, 14)
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Privacy & Data

struct PrivacyDataView: View {
    @State private var accountPaused    = false
    @State private var showDeleteAlert  = false
    @State private var showPauseConfirm = false

    var body: some View {
        SubScreenShell(title: "Privacy & Data") {
            VStack(spacing: 16) {
                // Dokumente
                sectionCard("Legal") {
                    SettingsActionRow(icon: "doc.text.fill",    label: "Privacy Policy") {
                        // TODO: URL öffnen
                    }
                    Divider().padding(.leading, 52)
                    SettingsActionRow(icon: "doc.badge.gearshape.fill", label: "Terms of Service") {
                        // TODO: URL öffnen
                    }
                }

                // Konto-Status
                sectionCard("Account Status") {
                    HStack(spacing: 14) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                            .frame(width: 28)
                            .padding(.leading, 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pause Account")
                                .font(.system(size: 15))
                            Text("Applications & visibility will be disabled")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $accountPaused)
                            .labelsHidden()
                            .onChange(of: accountPaused) { _, newValue in
                                if newValue { showPauseConfirm = true }
                            }
                            .padding(.trailing, 14)
                    }
                    .padding(.vertical, 14)
                }

                // Konto löschen
                Button {
                    showDeleteAlert = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14))
                        Text("Delete Account")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 0)
            }
            .padding(.horizontal, 16)
        }
        .alert("Delete Account?", isPresented: $showDeleteAlert) {
            Button("Delete Permanently", role: .destructive) {
                // TODO: DELETE /users/:id
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All your data will be permanently deleted. This action cannot be undone.")
        }
        .alert("Pause Account?", isPresented: $showPauseConfirm) {
            Button("Pause") { /* TODO: PATCH /users/:id { paused: true } */ }
            Button("Cancel", role: .cancel) { accountPaused = false }
        } message: {
            Text("You will no longer appear in search results and will not be able to submit applications.")
        }
    }
}

// MARK: - App Preferences

struct AppPreferencesView: View {
    enum AppColorScheme: String, CaseIterable {
        case system = "System"
        case light  = "Light"
        case dark   = "Dark"
    }
    enum AppLanguage: String, CaseIterable {
        case german  = "German"
        case english = "English"
    }

    @State private var colorScheme: AppColorScheme = .system
    @State private var language:    AppLanguage     = .german

    var body: some View {
        SubScreenShell(title: "App Preferences") {
            VStack(spacing: 16) {
                // Erscheinungsbild
                sectionCard("Appearance") {
                    VStack(spacing: 0) {
                        ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                            Button {
                                colorScheme = scheme
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: schemeIcon(scheme))
                                        .font(.system(size: 16))
                                        .foregroundColor(SS.primary)
                                        .frame(width: 28)
                                        .padding(.leading, 14)
                                    Text(scheme.rawValue)
                                        .font(.system(size: 15))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if colorScheme == scheme {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(SS.primary)
                                            .padding(.trailing, 14)
                                    }
                                }
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if scheme != AppColorScheme.allCases.last {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }

                // Sprache
                sectionCard("Language") {
                    VStack(spacing: 0) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Button {
                                language = lang
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 16))
                                        .foregroundColor(SS.primary)
                                        .frame(width: 28)
                                        .padding(.leading, 14)
                                    Text(lang.rawValue)
                                        .font(.system(size: 15))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if language == lang {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(SS.primary)
                                            .padding(.trailing, 14)
                                    }
                                }
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if lang != AppLanguage.allCases.last {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func schemeIcon(_ scheme: AppColorScheme) -> String {
        switch scheme {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }
}

// MARK: - Change Sheets

private struct ChangeEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var newEmail    = ""
    @State private var password    = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("New Email Address") {
                    TextField("name@example.com", text: $newEmail)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Confirm Current Password") {
                    SecureField("Password", text: $password)
                }
                Section {
                    Text("After saving, you will receive a verification email at the new address.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Change Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // TODO: PATCH /users/:id/email
                        dismiss()
                    }
                    .disabled(newEmail.isEmpty || password.isEmpty)
                }
            }
        }
    }
}

private struct ChangePhoneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("New Phone Number") {
                    TextField("+1 555 123 4567", text: $phone)
                        .keyboardType(.phonePad)
                }
            }
            .navigationTitle("Change Phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // TODO: PATCH /users/:id/phone
                        dismiss()
                    }
                    .disabled(phone.isEmpty)
                }
            }
        }
    }
}

private struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current  = ""
    @State private var newPass  = ""
    @State private var confirm  = ""

    private var isValid: Bool {
        !current.isEmpty && newPass.count >= 8 && newPass == confirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Password") {
                    SecureField("••••••••", text: $current)
                }
                Section("New Password (min. 8 characters)") {
                    SecureField("New password", text: $newPass)
                    SecureField("Repeat password", text: $confirm)
                }
                if !newPass.isEmpty && newPass != confirm {
                    Section {
                        Text("Passwords do not match.")
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // TODO: POST /auth/change-password
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

// MARK: - Shared Helpers

private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)

        VStack(spacing: 0) {
            content()
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

private struct SettingsNavRow: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(SS.primary)
                .frame(width: 28)
                .padding(.leading, 14)
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.4))
                .padding(.trailing, 14)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct SettingsActionRow: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(SS.primary)
                    .frame(width: 28)
                    .padding(.leading, 14)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
                    .padding(.trailing, 14)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
