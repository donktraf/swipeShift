//
//  AccountSettingsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - AccountSettingsView (Hauptmenü)

struct AccountSettingsView: View {
    @EnvironmentObject var userStore: UserStore

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

                // Nur fuer Admin-Konten (Flag kommt aus GET /auth/me; das Backend prueft jeden Request erneut)
                if userStore.currentUser?.isAdmin == true {
                    settingsGroup([
                        AnyView(NavigationLink { AdminReportsView() } label: { SettingsNavRow(icon: "shield.lefthalf.filled", label: "Admin: Reports") }),
                    ])
                }
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
    @State private var showMethodChoice   = false
    @State private var showTotpSetup      = false
    @State private var showRegenerate     = false
    @State private var showSwitchToEmail  = false
    @State private var backupRemaining: Int? = nil

    private var isSocialUser: Bool {
        userStore.currentUser?.hasSocialLogin == true
    }

    private var twoFactorEnabled: Bool {
        userStore.currentUser?.twoFactorEnabled == true
    }

    private var twoFactorMethod: TwoFactorMethod {
        TwoFactorMethod(rawValue: userStore.currentUser?.twoFactorMethod ?? "email") ?? .email
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
                                 ? (twoFactorMethod == .totp
                                    ? "On · authenticator app code when you sign in"
                                    : "On · we email you a code when you sign in")
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
                                    if wantsOn { showMethodChoice = true }
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

                    if twoFactorEnabled {
                        Divider().padding(.leading, 52)
                        if twoFactorMethod == .totp {
                            SettingsActionRow(icon: "envelope.badge.fill", label: "Switch to email codes") { showSwitchToEmail = true }
                        } else {
                            SettingsActionRow(icon: "lock.shield.fill", label: "Switch to authenticator app") { showTotpSetup = true }
                        }
                    }

                    if twoFactorEnabled && twoFactorMethod == .totp {
                        Divider().padding(.leading, 52)
                        HStack(spacing: 14) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 16))
                                .foregroundColor(SS.primary)
                                .frame(width: 28)
                                .padding(.leading, 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Backup Codes")
                                    .font(.system(size: 15))
                                Text(backupRemaining.map { "\($0) of 8 left" } ?? "Loading…")
                                    .font(.system(size: 12))
                                    .foregroundColor((backupRemaining ?? 8) <= 2 ? .red : .secondary)
                            }
                            Spacer()
                            Button("Regenerate") { showRegenerate = true }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(SS.primary)
                                .padding(.trailing, 14)
                        }
                        .padding(.vertical, 14)
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
        .task {
            await userStore.refreshMe()
            await loadBackupRemaining()
        }
        .sheet(isPresented: $showChangeEmail)    { ChangeEmailSheet() }
        .sheet(isPresented: $showChangePhone)    { ChangePhoneSheet() }
        .sheet(isPresented: $showChangePassword) { ChangePasswordSheet() }
        .sheet(isPresented: $showSetPassword)    { SetPasswordSheet().environmentObject(userStore) }
        .sheet(item: $twoFactorChallenge) { challenge in
            TwoFactorCodeView(
                title: pendingEnable ? "Turn on two-factor" : "Turn off two-factor",
                message: challenge.method == .totp
                    ? "Enter the code from your authenticator app to turn off two-factor."
                    : "Enter the 6-digit code we sent to \(challenge.emailHint).",
                confirmLabel: pendingEnable ? "Turn On" : "Turn Off",
                onSubmit: { code in await confirmTwoFactorChange(code: code) },
                onResend: { await resendTwoFactorCode() },
                onCancel: { twoFactorChallenge = nil },
                method: challenge.method
            )
        }
        .sheet(isPresented: $showTotpSetup) {
            TotpSetupView(
                onFinished: {
                    showTotpSetup = false
                    Task {
                        await userStore.refreshMe()
                        await loadBackupRemaining()
                    }
                },
                onCancel: { showTotpSetup = false }
            )
        }
        .sheet(isPresented: $showSwitchToEmail) {
            SwitchToEmailView(
                onFinished: {
                    showSwitchToEmail = false
                    Task {
                        await userStore.refreshMe()
                        await loadBackupRemaining()
                    }
                },
                onCancel: { showSwitchToEmail = false }
            )
        }
        .sheet(isPresented: $showRegenerate) {
            RegenerateBackupCodesView(
                onFinished: {
                    showRegenerate = false
                    Task { await loadBackupRemaining() }
                },
                onCancel: { showRegenerate = false }
            )
        }
        .confirmationDialog("Choose how to get your codes", isPresented: $showMethodChoice, titleVisibility: .visible) {
            Button("Email code") { startTwoFactorChange(enable: true) }
            Button("Authenticator app") { showTotpSetup = true }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Turn off two-factor authentication?", isPresented: $showDisableConfirm) {
            Button("Turn Off", role: .destructive) { startTwoFactorChange(enable: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(twoFactorMethod == .totp
                 ? "Signing in will only need your password or Google/Apple account. Confirm with a code from your authenticator app."
                 : "Signing in will only need your password or Google/Apple account. We'll email you a code to confirm.")
        }
    }

    private func loadBackupRemaining() async {
        backupRemaining = (try? await APIClient.shared.fetchTwoFactorStatus())?.backupCodesRemaining
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

    // Ort kommt vom Geraet selbst (grober App-Standort, "City, ST") — keine IP-Ortung
    private func detailLine(for session: DeviceSessionDTO) -> String {
        let activity: String
        if session.isCurrent || Date().timeIntervalSince(session.lastActiveAt) < 120 {
            activity = "Active now"
        } else {
            activity = "Active " + session.lastActiveAt.formatted(.relative(presentation: .named))
        }
        return [session.osVersion, session.city.map { "\($0) (approx.)" }, activity].compactMap { $0 }.joined(separator: " · ")
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
    private struct CategoryRow: Identifiable {
        let id: WritableKeyPath<NotificationSettingsDTO, NotificationChannelDTO>
        let icon: String
        let color: Color
        let label: String
    }

    private let rows: [CategoryRow] = [
        .init(id: \.jobActivity, icon: "briefcase.fill",      color: SS.primary, label: "Job Activity"),
        .init(id: \.payments,    icon: "dollarsign.circle.fill", color: .green,     label: "Payments"),
        .init(id: \.messages,    icon: "bubble.left.fill",     color: .blue,      label: "Messages"),
        .init(id: \.account,     icon: "person.fill",          color: .orange,    label: "Account"),
    ]

    @State private var settings: AccountSettingsDTO?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isSaving = false
    @ObservedObject private var push = PushNotificationManager.shared

    var body: some View {
        SubScreenShell(title: "Notifications") {
            VStack(spacing: 16) {
                if let settings {
                    content(settings)
                } else if let loadError {
                    VStack(spacing: 12) {
                        Text(loadError).font(.system(size: 14)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await load() } }
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
        }
        .task { await load() }
        .task { await push.refreshAuthorizationStatus() }
        // Nach Rueckkehr aus den iOS-Einstellungen den Status neu lesen
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await push.refreshAuthorizationStatus() }
        }
    }

    /// Hinweis, wenn Push auf Systemebene nicht erlaubt ist (die App-Schalter allein reichen dann nicht)
    @ViewBuilder
    private var systemPermissionHint: some View {
        if push.authorizationStatus == .denied {
            VStack(alignment: .leading, spacing: 10) {
                Label("Push notifications are turned off for SwipeShift in iOS Settings, so you won't receive any push messages.",
                      systemImage: "bell.slash.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        } else if push.authorizationStatus == .notDetermined {
            Button("Allow Push Notifications") { Task { await push.requestPermission() } }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func content(_ current: AccountSettingsDTO) -> some View {
        systemPermissionHint

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
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(row.color.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: row.icon)
                            .font(.system(size: 14))
                            .foregroundColor(row.color)
                    }
                    .padding(.leading, 14)

                    Text(row.label)
                        .font(.system(size: 15))

                    Spacer()

                    Toggle("", isOn: channelBinding(row.id, \.push))
                        .labelsHidden()
                        .frame(width: 50)

                    Toggle("", isOn: channelBinding(row.id, \.email))
                        .labelsHidden()
                        .frame(width: 50)
                        .padding(.trailing, 14)
                }
                .padding(.vertical, 12)

                if index < rows.count - 1 {
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
                Toggle("", isOn: quietBinding(\.enabled))
                    .labelsHidden()
                    .padding(.trailing, 14)
            }
            .padding(.vertical, 14)

            if current.quietHours.enabled {
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
                    DatePicker("", selection: timeBinding(\.from), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("to")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                    DatePicker("", selection: timeBinding(\.to), displayedComponents: .hourAndMinute)
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
        .animation(.easeInOut(duration: 0.2), value: current.quietHours.enabled)

        if let saveError {
            Text(saveError)
                .font(.system(size: 12))
                .foregroundColor(.red)
                .padding(.horizontal, 20)
        }

        Text("Quiet Hours mute push notifications only. Emails are still sent, and security emails (sign-in codes, password changes) are always delivered.")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
    }

    // MARK: Bindings (jede Aenderung wird sofort gespeichert)

    private func channelBinding(
        _ category: WritableKeyPath<NotificationSettingsDTO, NotificationChannelDTO>,
        _ channel: WritableKeyPath<NotificationChannelDTO, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { settings?.notifications[keyPath: category][keyPath: channel] ?? false },
            set: { newValue in
                guard var updated = settings else { return }
                updated.notifications[keyPath: category][keyPath: channel] = newValue
                save(updated, patch: AccountSettingsPatch(notifications: updated.notifications))
            }
        )
    }

    private func quietBinding(_ key: WritableKeyPath<QuietHoursDTO, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings?.quietHours[keyPath: key] ?? false },
            set: { newValue in
                guard var updated = settings else { return }
                updated.quietHours[keyPath: key] = newValue
                save(updated, patch: AccountSettingsPatch(quietHours: updated.quietHours))
            }
        )
    }

    private func timeBinding(_ key: WritableKeyPath<QuietHoursDTO, String>) -> Binding<Date> {
        Binding(
            get: { Self.date(from: settings?.quietHours[keyPath: key] ?? "00:00") },
            set: { newValue in
                guard var updated = settings else { return }
                updated.quietHours[keyPath: key] = Self.hhmm(from: newValue)
                save(updated, patch: AccountSettingsPatch(quietHours: updated.quietHours))
            }
        )
    }

    private static func date(from hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        let hour = parts.first ?? 0, minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private static func hhmm(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: Laden / Speichern

    private func load() async {
        loadError = nil
        do {
            settings = try await APIClient.shared.fetchAccountSettings().settings
        } catch {
            loadError = "Couldn't load your notification settings. Check your connection and try again."
        }
    }

    /// Optimistisch anzeigen, im Fehlerfall auf den vorherigen Stand zurueck
    private func save(_ updated: AccountSettingsDTO, patch: AccountSettingsPatch) {
        let previous = settings
        settings = updated
        saveError = nil
        Task {
            do {
                settings = try await APIClient.shared.updateAccountSettings(patch)
            } catch {
                settings = previous
                saveError = "Couldn't save. Please try again."
            }
        }
    }
}

// MARK: - Payments & Payouts

struct PaymentsPayoutsView: View {
    enum PayoutMethod: String, CaseIterable {
        case bank, paypal
        var label: String { self == .bank ? "Bank Account" : "PayPal" }
    }
    enum BankAccountType: String, CaseIterable {
        case checking, savings
        var label: String { self == .checking ? "Checking" : "Savings" }
    }
    enum PayoutFrequency: String, CaseIterable {
        case instant, weekly, monthly
        var label: String {
            switch self {
            case .instant: return "Immediately"
            case .weekly:  return "Weekly"
            case .monthly: return "Monthly"
            }
        }
    }

    @State private var selectedMethod:    PayoutMethod    = .bank
    @State private var holderName:        String          = ""
    @State private var routingNumber:     String          = ""
    @State private var accountNumber:     String          = ""
    @State private var confirmAccount:    String          = ""
    @State private var accountType:       BankAccountType = .checking
    @State private var isChangingAccount  = false
    @State private var paypalEmail:       String          = ""
    @State private var selectedFrequency: PayoutFrequency = .weekly
    @ObservedObject private var feeConfig = FeeConfig.shared
    @State private var savedBank:         BankDetailsDTO?
    @State private var isLoading          = true
    @State private var isSaving           = false
    @State private var errorMessage:      String?
    @State private var showSavedToast     = false
    @State private var reauthMethods:     [String]?       // gesetzt = Re-Auth-Sheet sichtbar

    var body: some View {
        SubScreenShell(title: "Payments & Payouts") {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    form
                }
            }
            .padding(.horizontal, 16)
        }
        .task { await load() }
        .task { await feeConfig.refresh() }
        .onDisappear {
            accountNumber = ""
            confirmAccount = ""
        }
        .sheet(isPresented: Binding(get: { reauthMethods != nil }, set: { if !$0 { reauthMethods = nil } })) {
            ReauthSheet(methods: reauthMethods ?? []) {
                reauthMethods = nil
                Task { await savePayout() }   // Formularwerte bleiben erhalten, Speichern automatisch wiederholen
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        // Methode wählen
        sectionCard("Payout Method") {
            HStack(spacing: 0) {
                ForEach(PayoutMethod.allCases, id: \.self) { method in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedMethod = method }
                    } label: {
                        Text(method.label)
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

            if selectedMethod == .bank {
                bankForm
            } else {
                inputRow(icon: "p.circle.fill", placeholder: "PayPal E-Mail", text: $paypalEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
                            Text(freq.label)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                            Spacer()
                            Text(freq == .instant ? "\(PlatformFees.percentLabel(feeConfig.instantPayoutFeePercent)) fee" : "Free")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(freq == .instant ? .orange : .green)
                                .padding(.trailing, 14)
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if freq != PayoutFrequency.allCases.last {
                        Divider().padding(.leading, 52)
                    }
                }
                Divider().padding(.horizontal, 14)
                Text("Standard payouts (weekly or monthly) are free. Instant payouts will cost \(PlatformFees.percentLabel(feeConfig.instantPayoutFeePercent)) once in-app payouts launch. You always earn the full hourly wage; there are no platform fees for workers.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }

        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13))
                .foregroundColor(.red)
                .padding(.horizontal, 4)
        } else if showSavedToast {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)
        }

        // Speichern
        Button { Task { await savePayout() } } label: {
            if isSaving {
                ProgressView().tint(.white).frame(maxWidth: .infinity)
            } else {
                Text("Save").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(SSPrimaryButtonStyle())
        .disabled(isSaving || !canSave)
        .opacity(canSave ? 1 : 0.5)

        // TODO: Echte Auszahlungen (Zahlungsdienstleister) gibt es noch nicht — Daten werden nur hinterlegt
        Text("Payouts aren't active yet. Your details are stored encrypted and will be used once payouts launch.")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
    }

    // MARK: Bank form (US)

    private var routingDigits: String {
        routingNumber.filter { !$0.isWhitespace && $0 != "-" }
    }
    private var routingError: String? {
        if routingDigits.isEmpty { return nil }
        guard routingDigits.allSatisfy { $0.isASCII && $0.isNumber }, routingDigits.count == 9 else {
            return "Routing number must be 9 digits"
        }
        return Self.isValidRouting(routingDigits) && !routingDigits.allSatisfy({ $0 == "0" }) ? nil : "Check the routing number"
    }
    private var accountDigits: String {
        accountNumber.filter { !$0.isWhitespace && $0 != "-" }
    }
    private var needsAccountEntry: Bool { savedBank == nil || isChangingAccount }
    private var accountError: String? {
        if accountDigits.isEmpty { return nil }
        if !accountDigits.allSatisfy { $0.isASCII && $0.isNumber } || accountDigits.count < 4 || accountDigits.count > 17 {
            return "Account number must be 4 to 17 digits"
        }
        return nil
    }
    private var confirmError: String? {
        if confirmAccount.isEmpty || accountError != nil { return nil }
        let c = confirmAccount.filter { !$0.isWhitespace && $0 != "-" }
        return c == accountDigits ? nil : "Account numbers don't match"
    }

    private var isBankValid: Bool {
        let name = holderName.trimmingCharacters(in: .whitespaces)
        guard name.count >= 2, name.count <= 100 else { return false }
        guard routingDigits.count == 9, routingError == nil else { return false }
        if needsAccountEntry {
            let c = confirmAccount.filter { !$0.isWhitespace && $0 != "-" }
            guard (4...17).contains(accountDigits.count), accountError == nil, c == accountDigits else { return false }
        }
        return true
    }
    private var canSave: Bool {
        switch selectedMethod {
        case .bank:   return isBankValid
        case .paypal:
            let e = paypalEmail.trimmingCharacters(in: .whitespaces)
            return e.contains("@") && e.contains(".")
        }
    }

    /// ABA-Pruefsumme: 3(d1+d4+d7) + 7(d2+d5+d8) + (d3+d6+d9) teilbar durch 10
    private static func isValidRouting(_ digits: String) -> Bool {
        let d = digits.compactMap { $0.wholeNumberValue }
        guard d.count == 9 else { return false }
        let sum = 3 * (d[0] + d[3] + d[6]) + 7 * (d[1] + d[4] + d[7]) + (d[2] + d[5] + d[8])
        return sum % 10 == 0
    }

    @ViewBuilder
    private var bankForm: some View {
        inputRow(icon: "person.fill", placeholder: "Account holder name", text: $holderName)
            .textContentType(.name)
            .autocorrectionDisabled()
        Divider().padding(.horizontal, 14)

        inputRow(icon: "building.columns.fill", placeholder: "Routing number (9 digits)", text: $routingNumber)
            .keyboardType(.numberPad)
            .autocorrectionDisabled()
        fieldError(routingError)
        Divider().padding(.horizontal, 14)

        if let savedBank, !isChangingAccount {
            HStack(spacing: 12) {
                Image(systemName: "number")
                    .font(.system(size: 16))
                    .foregroundColor(SS.primary)
                    .frame(width: 28)
                    .padding(.leading, 14)
                Text("•••• \(savedBank.accountLast4) saved")
                    .font(.system(size: 15))
                Spacer()
                Button("Change") { isChangingAccount = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SS.primary)
                    .padding(.trailing, 14)
            }
            .padding(.vertical, 14)
        } else {
            secureInputRow(icon: "number", placeholder: "Account number", text: $accountNumber)
            fieldError(accountError)
            Divider().padding(.horizontal, 14)
            secureInputRow(icon: "number", placeholder: "Confirm account number", text: $confirmAccount)
            fieldError(confirmError)
            if savedBank != nil {
                Button("Keep saved account number") {
                    isChangingAccount = false
                    accountNumber = ""
                    confirmAccount = ""
                }
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
        Divider().padding(.horizontal, 14)

        Picker("Account type", selection: $accountType) {
            ForEach(BankAccountType.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func fieldError(_ message: String?) -> some View {
        if let message {
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }

    private func secureInputRow(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(SS.primary)
                .frame(width: 28)
                .padding(.leading, 14)
            SecureField(placeholder, text: text)
                .font(.system(size: 15))
                .keyboardType(.numberPad)
                .textContentType(.none)
                .autocorrectionDisabled()
                .padding(.trailing, 14)
        }
        .padding(.vertical, 14)
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

    private func apply(_ payout: PayoutSettingsDTO) {
        selectedMethod    = PayoutMethod(rawValue: payout.method) ?? .bank
        selectedFrequency = PayoutFrequency(rawValue: payout.frequency) ?? .weekly
        paypalEmail       = payout.paypalEmail ?? ""
        savedBank         = payout.bank
        holderName        = payout.bank?.accountHolderName ?? holderName
        routingNumber     = payout.bank?.routingNumber ?? routingNumber
        accountType       = BankAccountType(rawValue: payout.bank?.accountType ?? "") ?? accountType
        // Eingegebene Kontonummer wird nie zurueck angezeigt
        accountNumber     = ""
        confirmAccount    = ""
        isChangingAccount = false
    }

    private func load() async {
        isLoading = true
        do {
            apply(try await APIClient.shared.fetchAccountSettings().settings.payout)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your payout settings."
        }
        isLoading = false
    }

    private func savePayout() async {
        isSaving = true
        errorMessage = nil
        showSavedToast = false
        // Bankdaten nur senden, wenn die Bank-Methode aktiv ist; Kontonummer nur wenn neu eingegeben
        let bankPatch: AccountSettingsPatch.BankPatch? = selectedMethod == .bank
            ? .init(accountHolderName: holderName.trimmingCharacters(in: .whitespaces),
                    routingNumber: routingDigits,
                    accountNumber: needsAccountEntry ? accountDigits : nil,
                    accountType: accountType.rawValue)
            : nil
        let patch = AccountSettingsPatch(payout: .init(
            method: selectedMethod.rawValue,
            bank: bankPatch,
            paypalEmail: selectedMethod == .paypal ? paypalEmail.trimmingCharacters(in: .whitespaces) : nil,
            frequency: selectedFrequency.rawValue
        ))
        do {
            apply(try await APIClient.shared.updateAccountSettings(patch).payout)
            withAnimation { showSavedToast = true }
        } catch {
            let message = (error as? APIError)?.message ?? ""
            if let api = error as? APIError, api.code == "REAUTH_REQUIRED" {
                reauthMethods = api.methods?.isEmpty == false ? api.methods : ["email"]
                isSaving = false
                return
            }
            if message.contains("routingNumber") {
                errorMessage = "Check the routing number"
            } else if message.contains("accountNumber") {
                errorMessage = "That account number doesn't look right. Please check it."
            } else if message.contains("payout.bank") {
                errorMessage = "Please check your bank details."
            } else if message.contains("paypalEmail") {
                errorMessage = "Please enter a valid PayPal email."
            } else {
                errorMessage = "Couldn't save. Please try again."
            }
        }
        isSaving = false
    }
}

// MARK: - Re-Auth Sheet (Step-up vor dem Aendern von Auszahlungsdaten)

struct ReauthSheet: View {
    let methods: [String]
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var method: String
    @State private var secret = ""
    @State private var emailHint = "your email"
    @State private var codeSent = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    init(methods: [String], onSuccess: @escaping () -> Void) {
        self.methods = methods
        self.onSuccess = onSuccess
        _method = State(initialValue: methods.first ?? "email")
    }

    private func title(_ m: String) -> String {
        switch m {
        case "totp":     return "Authenticator"
        case "password": return "Password"
        default:         return "Email code"
        }
    }

    private var canSubmit: Bool {
        !(method == "password" ? secret : secret.trimmingCharacters(in: .whitespaces)).isEmpty && !isBusy && (method != "email" || codeSent)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Confirm it's you")
                    .font(.system(size: 22, weight: .bold))
                Text("For your security, please confirm your identity before changing payout details.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                if methods.count > 1 {
                    Picker("Method", selection: $method) {
                        ForEach(methods, id: \.self) { Text(title($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: method) { _, _ in secret = ""; errorMessage = nil }
                }

                switch method {
                case "totp":
                    Text("Enter the 6-digit code from your authenticator app, or one of your backup codes.")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                    TextField("Code", text: $secret)
                        .textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .textFieldStyle(.roundedBorder)
                case "password":
                    SecureField("Password", text: $secret)
                        .textContentType(.password)
                        .focused($focused)
                        .textFieldStyle(.roundedBorder)
                default:
                    if codeSent {
                        Text("We sent a 6-digit code to \(emailHint).")
                            .font(.system(size: 13)).foregroundColor(.secondary)
                        TextField("6-digit code", text: $secret)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focused)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(codeSent ? "Send a new code" : "Send code to \(emailHint)") {
                        Task { await sendCode() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SS.primary)
                    .disabled(isBusy)
                }

                if let errorMessage {
                    Text(errorMessage).font(.system(size: 13)).foregroundColor(.red)
                }

                Button { Task { await submit() } } label: {
                    if isBusy { ProgressView().tint(.white).frame(maxWidth: .infinity) }
                    else { Text("Confirm").fontWeight(.semibold).frame(maxWidth: .infinity) }
                }
                .buttonStyle(SSPrimaryButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)

                Spacer()
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
            .task {
                if let info = try? await APIClient.shared.fetchReauthMethods(), let hint = info.emailHint, !hint.isEmpty {
                    emailHint = hint
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isBusy)
    }

    private func message(for error: Error) -> String {
        guard let api = error as? APIError else { return "Something went wrong. Please try again." }
        if api.code == "TOO_MANY_ATTEMPTS", let m = api.retryAfterMinutes {
            return "Too many wrong attempts. Try again in \(m) minute\(m == 1 ? "" : "s")."
        }
        if api.code == "CODE_ATTEMPTS_EXCEEDED" { return "Too many attempts — request a new code." }
        return api.message
    }

    private func sendCode() async {
        isBusy = true; errorMessage = nil
        do {
            try await APIClient.shared.sendReauthEmailCode()
            codeSent = true
            secret = ""
        } catch {
            errorMessage = message(for: error)
        }
        isBusy = false
    }

    private func submit() async {
        isBusy = true; errorMessage = nil
        do {
            // Passwort unveraendert senden (Leerzeichen koennen Teil des Passworts sein), Codes trimmen
            try await APIClient.shared.reauthenticate(method: method, secret: method == "password" ? secret : secret.trimmingCharacters(in: .whitespaces))
            isBusy = false
            onSuccess()
            return
        } catch {
            errorMessage = message(for: error)
        }
        isBusy = false
    }
}

// MARK: - Privacy & Data

struct PrivacyDataView: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.openURL) private var openURL
    @State private var accountPaused    = false
    @State private var showDeleteAlert  = false
    @State private var showPauseConfirm = false
    @State private var isUpdatingPause  = false
    @State private var pauseError: String?
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

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

                // Blockierte Nutzer
                sectionCard("Safety") {
                    NavigationLink {
                        BlockedUsersView()
                    } label: {
                        SettingsNavRow(icon: "hand.raised.slash.fill", label: "Blocked users")
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
                            Text(pauseSubtitle)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isUpdatingPause {
                            ProgressView().padding(.trailing, 14)
                        } else {
                            Toggle("", isOn: Binding(
                                get: { accountPaused },
                                set: { wantsPause in
                                    if wantsPause { showPauseConfirm = true } else { Task { await setPaused(false) } }
                                }
                            ))
                            .labelsHidden()
                            .padding(.trailing, 14)
                        }
                    }
                    .padding(.vertical, 14)

                    if let pauseError {
                        Text(pauseError)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
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
                    do {
                        try await APIClient.shared.deleteAccount()
                    } catch {
                        // Konto existiert noch → nicht ausloggen, Fehler anzeigen
                        isDeletingAccount = false
                        deleteError = "Your account could not be deleted. Please try again."
                        return
                    }
                    // Hinweis "Last signed in with ..." entfernen
                    LastLoginMethod.clear()
                    TokenStore.shared.deleteToken()
                    userStore.logout()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All your data will be permanently deleted. This action cannot be undone.")
        }
        .alert("Couldn't Delete Account", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Pause Account?", isPresented: $showPauseConfirm) {
            Button("Pause") { Task { await setPaused(true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isEmployer
                 ? "Your job posts will be hidden from workers and nobody can apply until you resume."
                 : "You won't be able to apply for jobs until you resume your account.")
        }
        .task {
            accountPaused = userStore.currentUser?.isPaused == true
            if let fresh = try? await APIClient.shared.fetchAccountSettings().paused {
                accountPaused = fresh
            }
        }
    }

    private var isEmployer: Bool { userStore.currentUser?.role == .employer }

    private var pauseSubtitle: String {
        if accountPaused {
            return isEmployer ? "Paused · your jobs are hidden from workers" : "Paused · you can't apply for jobs"
        }
        return isEmployer ? "Hide your jobs and stop new applications" : "Stop applying for jobs for a while"
    }

    private func setPaused(_ paused: Bool) async {
        isUpdatingPause = true
        pauseError = nil
        do {
            accountPaused = try await APIClient.shared.setAccountPaused(paused)
            await userStore.refreshMe()
        } catch {
            pauseError = "Couldn't update your account status. Please try again."
        }
        isUpdatingPause = false
    }
}

// MARK: - App Preferences

struct AppPreferencesView: View {
    // Pro Geraet gespeichert, wirkt sofort (swipeShiftApp liest denselben Key)
    @AppStorage(AppColorSchemePreference.storageKey) private var colorSchemeRaw = AppColorSchemePreference.system.rawValue

    private var colorScheme: AppColorSchemePreference {
        AppColorSchemePreference(rawValue: colorSchemeRaw) ?? .system
    }

    var body: some View {
        SubScreenShell(title: "App Preferences") {
            VStack(spacing: 16) {
                // Erscheinungsbild
                sectionCard("Appearance") {
                    VStack(spacing: 0) {
                        ForEach(AppColorSchemePreference.allCases, id: \.self) { scheme in
                            Button {
                                colorSchemeRaw = scheme.rawValue
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: schemeIcon(scheme))
                                        .font(.system(size: 16))
                                        .foregroundColor(SS.primary)
                                        .frame(width: 28)
                                        .padding(.leading, 14)
                                    Text(scheme.label)
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
                            if scheme != AppColorSchemePreference.allCases.last {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }

                // Sprache — die App ist bisher nur auf Englisch; keine Auswahl ohne Wirkung anbieten.
                // TODO: Mit Lokalisierung (Localizable.xcstrings) hier auf die iOS-App-Spracheinstellung verlinken
                sectionCard("Language") {
                    HStack(spacing: 14) {
                        Image(systemName: "globe")
                            .font(.system(size: 16))
                            .foregroundColor(SS.primary)
                            .frame(width: 28)
                            .padding(.leading, 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("English")
                                .font(.system(size: 15))
                            Text("More languages are coming soon.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func schemeIcon(_ scheme: AppColorSchemePreference) -> String {
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
