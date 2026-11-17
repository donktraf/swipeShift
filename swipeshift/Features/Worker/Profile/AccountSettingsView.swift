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
    @EnvironmentObject var userStore: UserStore
    @State private var showChangeEmail    = false
    @State private var showChangePhone    = false
    @State private var showChangePassword = false
    @State private var showSetPassword    = false

    // 2FA: Zustand kommt aus GET /auth/me (twoFactorEnabled)
    @State private var twoFactorChallenge: TwoFactorChallenge? = nil
    @State private var pendingEnable      = false   // Ziel-Zustand der laufenden Aenderung
    @State private var isRequestingCode   = false
    @State private var twoFactorError: String? = nil
    @State private var showDisableConfirm = false

    private var isSocialUser: Bool {
        userStore.currentUser?.hasSocialLogin == true
    }

    private var twoFactorEnabled: Bool {
        userStore.currentUser?.twoFactorEnabled == true
    }

    var body: some View {
        SubScreenShell(title: "Account & Security") {
            VStack(spacing: 16) {
                // Zugangsdaten
                sectionCard("Credentials") {
                    SettingsActionRow(icon: "envelope.fill", label: "Change Email") { showChangeEmail = true }
                    Divider().padding(.leading, 52)
                    SettingsActionRow(icon: "phone.fill", label: "Change Phone") { showChangePhone = true }
                    Divider().padding(.leading, 52)
                    if isSocialUser {
                        SettingsActionRow(icon: "lock.badge.plus", label: "Set Password") { showSetPassword = true }
                    } else {
                        SettingsActionRow(icon: "lock.fill", label: "Change Password") { showChangePassword = true }
                    }
                }

                // Sicherheit
                sectionCard("Security") {
                    HStack(spacing: 14) {
                        Image(systemName: "shield.checkerboard")
                            .font(.system(size: 16))
                            .foregroundColor(SS.primary)
                            .frame(width: 28)
                            .padding(.leading, 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Two-Factor Authentication")
                                .font(.system(size: 15))
                            Text(twoFactorEnabled
                                 ? "On · we email you a code when you sign in"
                                 : "Off · add a code by email when you sign in")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isRequestingCode {
                            ProgressView().padding(.trailing, 14)
                        } else {
                            Toggle("", isOn: Binding(
                                get: { twoFactorEnabled },
                                set: { wantsOn in
                                    if wantsOn { startTwoFactorChange(enable: true) }
                                    else { showDisableConfirm = true }
                                }
                            ))
                            .labelsHidden()
                            .padding(.trailing, 14)
                        }
                    }
                    .padding(.vertical, 14)

                    if let twoFactorError {
                        Text(twoFactorError)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

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
        // refreshMe (nicht ...IfPossible): ein Netzwerkfehler soll hier nicht ausloggen
        .task { await userStore.refreshMe() }
        .sheet(isPresented: $showChangeEmail)    { ChangeEmailSheet() }
        .sheet(isPresented: $showChangePhone)    { ChangePhoneSheet() }
        .sheet(isPresented: $showChangePassword) { ChangePasswordSheet() }
        .sheet(isPresented: $showSetPassword)    { SetPasswordSheet().environmentObject(userStore) }
        .sheet(item: $twoFactorChallenge) { challenge in
            TwoFactorCodeView(
                title: pendingEnable ? "Turn on two-factor" : "Turn off two-factor",
                message: "Enter the 6-digit code we sent to \(challenge.emailHint).",
                confirmLabel: pendingEnable ? "Turn On" : "Turn Off",
                onSubmit: { code in await confirmTwoFactorChange(code: code) },
                onResend: { await resendTwoFactorCode() },
                onCancel: { twoFactorChallenge = nil }
            )
        }
        .alert("Turn off two-factor authentication?", isPresented: $showDisableConfirm) {
            Button("Turn Off", role: .destructive) { startTwoFactorChange(enable: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signing in will only need your password or Google/Apple account. We'll email you a code to confirm.")
        }
    }

    // MARK: 2FA-Ablauf: Code anfordern → Code eingeben → Zustand neu laden

    private func startTwoFactorChange(enable: Bool) {
        pendingEnable = enable
        twoFactorError = nil
        isRequestingCode = true
        Task {
            do {
                twoFactorChallenge = try await APIClient.shared.requestTwoFactorChange(enable: enable)
            } catch {
                twoFactorError = error.localizedDescription
            }
            isRequestingCode = false
        }
    }

    private func resendTwoFactorCode() async -> String? {
        do {
            let fresh = try await APIClient.shared.requestTwoFactorChange(enable: pendingEnable)
            twoFactorChallenge?.challengeId = fresh.challengeId
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func confirmTwoFactorChange(code: String) async -> String? {
        guard let challenge = twoFactorChallenge else { return "Please try again." }
        do {
            _ = try await APIClient.shared.confirmTwoFactorChange(challengeId: challenge.challengeId, code: code)
            await userStore.refreshMe()
            twoFactorChallenge = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - Active Sessions

struct ActiveSessionsView: View {
    @EnvironmentObject var userStore: UserStore

    @State private var sessions: [DeviceSessionDTO] = []
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var actionError: String? = nil
    @State private var sessionToRevoke: DeviceSessionDTO? = nil
    @State private var showSignOutOthersAlert = false
    @State private var busySessionId: String? = nil

    private var otherSessions: [DeviceSessionDTO] { sessions.filter { !$0.isCurrent } }

    var body: some View {
        SubScreenShell(title: "Active Sessions") {
            VStack(spacing: 16) {
                if isLoading && sessions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let loadError, sessions.isEmpty {
                    VStack(spacing: 12) {
                        Text(loadError)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await load() } }
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    Text("These devices are signed in to your account. If you don't recognize one, sign it out and change your password.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(sessions) { session in
                            sessionRow(session)
                            if session.id != sessions.last?.id {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)

                    if let actionError {
                        Text(actionError)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                    }

                    if !otherSessions.isEmpty {
                        Button {
                            showSignOutOthersAlert = true
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
                    } else {
                        Text("No other devices are signed in.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("Sign out of all other devices?", isPresented: $showSignOutOthersAlert) {
            Button("Sign Out", role: .destructive) { Task { await revokeOthers() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stay signed in on this device. Everywhere else you'll need to sign in again.")
        }
        .alert(
            "Sign out this device?",
            isPresented: Binding(get: { sessionToRevoke != nil }, set: { if !$0 { sessionToRevoke = nil } }),
            presenting: sessionToRevoke
        ) { session in
            Button("Sign Out", role: .destructive) { Task { await revoke(session) } }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("\(session.displayName) will need to sign in again.")
        }
    }

    private func sessionRow(_ session: DeviceSessionDTO) -> some View {
        HStack(spacing: 14) {
            Image(systemName: session.iconName)
                .font(.system(size: 22))
                .foregroundColor(session.isCurrent ? SS.primary : .secondary)
                .frame(width: 32)
                .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.displayName)
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
                Text(detailLine(for: session))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Signed in \(session.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !session.isCurrent {
                if busySessionId == session.id {
                    ProgressView().padding(.trailing, 14)
                } else {
                    Button {
                        sessionToRevoke = session
                    } label: {
                        Text("Sign Out")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(Capsule().stroke(Color.red.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                }
            }
        }
        .padding(.vertical, 14)
    }

    // TODO: Standort pro Geraet (Wireframe) braucht IP-Geolocation im Backend — bisher nicht vorhanden
    private func detailLine(for session: DeviceSessionDTO) -> String {
        let activity: String
        if session.isCurrent || Date().timeIntervalSince(session.lastActiveAt) < 120 {
            activity = "Active now"
        } else {
            activity = "Active " + session.lastActiveAt.formatted(.relative(presentation: .named))
        }
        return [session.osVersion, activity].compactMap { $0 }.joined(separator: " · ")
    }

    private func load() async {
        isLoading = true
        do {
            sessions = try await APIClient.shared.fetchSessions()
            loadError = nil
        } catch {
            loadError = "Couldn't load your devices. Check your connection and try again."
        }
        isLoading = false
    }

    private func revoke(_ session: DeviceSessionDTO) async {
        actionError = nil
        busySessionId = session.id
        do {
            try await APIClient.shared.revokeSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
        } catch {
            actionError = "Couldn't sign out \(session.displayName). Please try again."
        }
        busySessionId = nil
    }

    private func revokeOthers() async {
        actionError = nil
        do {
            try await APIClient.shared.revokeOtherSessions()
            sessions.removeAll { !$0.isCurrent }
        } catch {
            actionError = "Couldn't sign out the other devices. Please try again."
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
    @State private var showSavedToast     = false

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
                Button { savePayout() } label: {
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

    private func savePayout() {
        UserDefaults.standard.set(selectedMethod.rawValue,    forKey: "payoutMethod")
        UserDefaults.standard.set(iban,                        forKey: "payoutIBAN")
        UserDefaults.standard.set(paypalEmail,                 forKey: "payoutPayPalEmail")
        UserDefaults.standard.set(selectedFrequency.rawValue,  forKey: "payoutFrequency")
        withAnimation { showSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSavedToast = false }
        }
    }
}

// MARK: - Privacy & Data

struct PrivacyDataView: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.openURL) private var openURL
    @State private var accountPaused    = false
    @State private var showDeleteAlert  = false
    @State private var showPauseConfirm = false
    @State private var isDeletingAccount = false

    var body: some View {
        SubScreenShell(title: "Privacy & Data") {
            VStack(spacing: 16) {
                // Dokumente
                sectionCard("Legal") {
                    SettingsActionRow(icon: "doc.text.fill",    label: "Privacy Policy") {
                        openURL(URL(string: "https://swipeshift.app/privacy")!)
                    }
                    Divider().padding(.leading, 52)
                    SettingsActionRow(icon: "doc.badge.gearshape.fill", label: "Terms of Service") {
                        openURL(URL(string: "https://swipeshift.app/terms")!)
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
                isDeletingAccount = true
                Task {
                    try? await APIClient.shared.deleteAccount()
                    TokenStore.shared.deleteToken()
                    userStore.logout()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All your data will be permanently deleted. This action cannot be undone.")
        }
        .alert("Pause Account?", isPresented: $showPauseConfirm) {
            Button("Pause") {
                UserDefaults.standard.set(true, forKey: "accountPaused")
            }
            Button("Cancel", role: .cancel) { accountPaused = false }
        } message: {
            Text("You will no longer appear in search results and will not be able to submit applications.")
        }
        .onAppear {
            accountPaused = UserDefaults.standard.bool(forKey: "accountPaused")
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
    @State private var isLoading   = false
    @State private var errorMsg: String? = nil
    @State private var success     = false

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
                if let errorMsg {
                    Section { Text(errorMsg).font(.system(size: 13)).foregroundColor(.red) }
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
                    if isLoading { ProgressView() } else {
                        Button("Save") { save() }
                            .disabled(newEmail.isEmpty || password.isEmpty)
                    }
                }
            }
            .alert("Verification Email Sent", isPresented: $success) {
                Button("OK") { dismiss() }
            } message: {
                Text("Please check your new inbox and verify the address to complete the change.")
            }
        }
    }

    private func save() {
        isLoading = true; errorMsg = nil
        Task {
            do {
                try await APIClient.shared.changeEmail(newEmail: newEmail, password: password)
                success = true
            } catch {
                errorMsg = error.localizedDescription
            }
            isLoading = false
        }
    }
}

private struct ChangePhoneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phone     = ""
    @State private var isLoading = false
    @State private var errorMsg: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("New Phone Number") {
                    TextField("+1 555 123 4567", text: $phone)
                        .keyboardType(.phonePad)
                }
                if let errorMsg {
                    Section { Text(errorMsg).font(.system(size: 13)).foregroundColor(.red) }
                }
            }
            .navigationTitle("Change Phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading { ProgressView() } else {
                        Button("Save") { save() }
                            .disabled(phone.isEmpty)
                    }
                }
            }
        }
    }

    private func save() {
        isLoading = true; errorMsg = nil
        Task {
            do {
                try await APIClient.shared.updateProfile(UpdateProfileRequest(phone: phone))
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            isLoading = false
        }
    }
}

private struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current   = ""
    @State private var newPass   = ""
    @State private var confirm   = ""
    @State private var isLoading = false
    @State private var errorMsg: String? = nil
    @State private var success   = false

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
                            .font(.system(size: 13)).foregroundColor(.red)
                    }
                }
                if let errorMsg {
                    Section { Text(errorMsg).font(.system(size: 13)).foregroundColor(.red) }
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading { ProgressView() } else {
                        Button("Save") { save() }.disabled(!isValid)
                    }
                }
            }
            .alert("Password Changed", isPresented: $success) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your password has been updated. For your security, other devices have been signed out.")
            }
        }
    }

    private func save() {
        isLoading = true; errorMsg = nil
        Task {
            do {
                try await APIClient.shared.changePassword(current: current, new: newPass)
                success = true
            } catch {
                errorMsg = error.localizedDescription
            }
            isLoading = false
        }
    }
}

private struct SetPasswordSheet: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.dismiss) private var dismiss

    @State private var newPass  = ""
    @State private var confirm  = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var success = false

    private var isValid: Bool {
        newPass.count >= 8 && newPass == confirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("You signed in with Google or Apple. Set a password to also log in with your email address.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
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
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Set Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(!isValid)
                    }
                }
            }
            .alert("Password Set", isPresented: $success) {
                Button("OK") { dismiss() }
            } message: {
                Text("You can now log in with your email and this password.")
            }
        }
    }

    private func save() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await APIClient.shared.setPassword(newPassword: newPass)
                // hasSocialLogin im lokalen User aktualisieren
                await userStore.refreshMe()
                success = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
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
