//
//  AccountSettingsView.swift
//  swipeShift
//

import SwiftUI

// MARK: - AccountSettingsView (Hauptmenü)

struct AccountSettingsView: View {
    @EnvironmentObject var userStore: UserStore

    var body: some View {
        SubScreenShell(title: "Account Settings", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                DSSection("Settings") {
                    ProfileNavRow(icon: "person.badge.shield.checkmark.fill", label: "Account & Security") { AccountSecurityView() }
                    ProfileNavRow(icon: "bell.badge.fill",                    label: "Notifications") { NotificationSettingsView() }
                    ProfileNavRow(icon: "creditcard.fill",                    label: "Payments & Payouts") { PaymentsPayoutsView() }
                    ProfileNavRow(icon: "hand.raised.fill",                   label: "Privacy & Data") { PrivacyDataView() }
                    ProfileNavRow(icon: "slider.horizontal.3",                label: "App Preferences") { AppPreferencesView() }
                }

                // Nur fuer Admin-Konten (Flag kommt aus GET /auth/me; das Backend prueft jeden Request erneut)
                if userStore.currentUser?.isAdmin == true {
                    DSSection("Admin") {
                        ProfileNavRow(icon: "shield.lefthalf.filled", label: "Admin: Reports") { AdminReportsView() }
                    }
                }
            }
        }
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
        SubScreenShell(title: "Account & Security", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Zugangsdaten
                sectionCard("Credentials") {
                    SettingsActionRow(icon: "envelope.fill", label: "Change Email") { showChangeEmail = true }
                    SettingsActionRow(icon: "phone.fill", label: "Change Phone") { showChangePhone = true }
                    if isSocialUser {
                        SettingsActionRow(icon: "lock.badge.plus", label: "Set Password") { showSetPassword = true }
                    } else {
                        SettingsActionRow(icon: "lock.fill", label: "Change Password") { showChangePassword = true }
                    }
                }

                // Sicherheit
                sectionCard("Security") {
                    DSRow(
                        "Two-Factor Authentication",
                        subtitle: twoFactorEnabled
                            ? (twoFactorMethod == .totp
                               ? "On · authenticator app code when you sign in"
                               : "On · we email you a code when you sign in")
                            : "Off · add a code by email when you sign in",
                        systemIcon: "shield.checkerboard"
                    ) {
                        if isRequestingCode {
                            ProgressView()
                        } else {
                            Toggle("Two-Factor Authentication", isOn: Binding(
                                get: { twoFactorEnabled },
                                set: { wantsOn in
                                    DS.Haptics.selection()
                                    if wantsOn { showMethodChoice = true }
                                    else { showDisableConfirm = true }
                                }
                            ))
                            .labelsHidden()
                            .tint(DS.Color.primary)
                        }
                    }

                    if let twoFactorError {
                        Text(twoFactorError)
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.danger)
                            .padding(.vertical, DS.Spacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if twoFactorEnabled {
                        if twoFactorMethod == .totp {
                            SettingsActionRow(icon: "envelope.badge.fill", label: "Switch to email codes") { showSwitchToEmail = true }
                        } else {
                            SettingsActionRow(icon: "lock.shield.fill", label: "Switch to authenticator app") { showTotpSetup = true }
                        }
                    }

                    if twoFactorEnabled && twoFactorMethod == .totp {
                        DSRow(
                            "Backup Codes",
                            subtitle: backupRemaining.map { "\($0) of 8 left" } ?? "Loading…",
                            systemIcon: "key.fill",
                            iconTone: (backupRemaining ?? 8) <= 2 ? .danger : .primary
                        ) {
                            Button("Regenerate") { showRegenerate = true }
                                .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                                .foregroundStyle(DS.Color.primaryText)
                                .frame(minHeight: 44)
                        }
                    }

                    ProfileNavRow(icon: "iphone.and.arrow.forward", label: "Active Sessions") { ActiveSessionsView() }
                }
            }
        }
        // refreshMe (nicht ...IfPossible): ein Netzwerkfehler soll hier nicht ausloggen
        .task {
            await userStore.refreshMe()
            await loadBackupRemaining()
        }
        .sheet(isPresented: $showChangeEmail)    { ChangeEmailSheet().environmentObject(userStore) }
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
        SubScreenShell(title: "Active Sessions", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if isLoading && sessions.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        DSSkeletonBlock(height: 70, radius: DS.Radius.card)
                        DSSkeletonBlock(height: 70, radius: DS.Radius.card)
                    }
                    .accessibilityLabel("Loading devices")
                } else if let loadError, sessions.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        Text(loadError)
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.muted)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.xxl)
                } else {
                    Text("These devices are signed in to your account. If you don't recognize one, sign it out and change your password.")
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.muted)

                    DSSection("Devices") {
                        ForEach(sessions) { session in
                            sessionRow(session)
                        }
                    }

                    if let actionError {
                        Text(actionError)
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.danger)
                    }

                    if !otherSessions.isEmpty {
                        Button {
                            showSignOutOthersAlert = true
                        } label: {
                            Text("Sign out of all other devices")
                        }
                        .buttonStyle(.ds(.destructiveSoft))
                    } else {
                        Text("No other devices are signed in.")
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
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
        DSRow(
            session.displayName,
            subtitle: detailLine(for: session) + "\nSigned in \(session.createdAt.formatted(date: .abbreviated, time: .omitted))",
            systemIcon: session.iconName,
            iconTone: session.isCurrent ? .primary : .neutral
        ) {
            if session.isCurrent {
                DSBadge("This Device", .today)
            } else if busySessionId == session.id {
                ProgressView()
            } else {
                Button {
                    sessionToRevoke = session
                } label: {
                    Text("Sign Out")
                        .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(DS.Color.danger)
                        .padding(.horizontal, DS.Spacing.sm)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.dsPressable)
            }
        }
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
        let tone: DS.Tone
        let label: String
    }

    private let rows: [CategoryRow] = [
        .init(id: \.jobActivity, icon: "briefcase.fill",         tone: .primary, label: "Job Activity"),
        .init(id: \.payments,    icon: "dollarsign.circle.fill",  tone: .success, label: "Payments"),
        .init(id: \.messages,    icon: "bubble.left.fill",        tone: .primary, label: "Messages"),
        .init(id: \.account,     icon: "person.fill",             tone: .warning, label: "Account"),
    ]

    @State private var settings: AccountSettingsDTO?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isSaving = false
    @ObservedObject private var push = PushNotificationManager.shared

    var body: some View {
        SubScreenShell(title: "Notifications", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                if let settings {
                    content(settings)
                } else if let loadError {
                    VStack(spacing: DS.Spacing.sm) {
                        Text(loadError).dsFont(.callout).foregroundStyle(DS.Color.muted)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.xxl)
                } else {
                    VStack(spacing: DS.Spacing.sm) {
                        DSSkeletonBlock(height: 56, radius: DS.Radius.card)
                        DSSkeletonBlock(height: 56, radius: DS.Radius.card)
                        DSSkeletonBlock(height: 56, radius: DS.Radius.card)
                    }
                    .accessibilityLabel("Loading notification settings")
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
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Label("Push notifications are turned off for SwipeShift in iOS Settings, so you won't receive any push messages.",
                      systemImage: "bell.slash.fill")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Spacing.inset)
            .background(DS.Color.warningSoft, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        } else if push.authorizationStatus == .notDetermined {
            Button("Allow Push Notifications") { Task { await push.requestPermission() } }
                .buttonStyle(.ds(.soft, size: .medium))
        }
    }

    @ViewBuilder
    private func content(_ current: AccountSettingsDTO) -> some View {
        systemPermissionHint

        // Kategorien (Push + E-Mail je Kategorie)
        DSSection("Categories") {
            HStack {
                Spacer()
                Text("Push")
                    .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(DS.Color.muted)
                    .frame(width: 51)
                Text("E-Mail")
                    .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(DS.Color.muted)
                    .frame(width: 51)
            }
            .padding(.bottom, DS.Spacing.xxs)

            ForEach(rows) { row in
                DSRow(row.label, systemIcon: row.icon, iconTone: row.tone) {
                    Toggle("\(row.label) push", isOn: channelBinding(row.id, \.push))
                        .labelsHidden()
                        .tint(DS.Color.primary)
                        .frame(width: 51)
                    Toggle("\(row.label) email", isOn: channelBinding(row.id, \.email))
                        .labelsHidden()
                        .tint(DS.Color.primary)
                        .frame(width: 51)
                }
            }
        }

        // Ruhige Stunden
        DSSection("Quiet Hours") {
            DSToggleRow("Quiet Hours", systemIcon: "moon.fill", isOn: quietBinding(\.enabled))

            if current.quietHours.enabled {
                DSRow("From", systemIcon: "clock.fill", iconTone: .neutral) {
                    DatePicker("From", selection: timeBinding(\.from), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("to").dsFont(.body).foregroundStyle(DS.Color.muted)
                    DatePicker("To", selection: timeBinding(\.to), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
        }
        .dsAnimation(.standard, value: current.quietHours.enabled)

        if let saveError {
            Text(saveError)
                .dsFont(.caption)
                .foregroundStyle(DS.Color.danger)
        }

        Text("Quiet Hours mute push notifications only. Emails are still sent, and security emails (sign-in codes, password changes) are always delivered.")
            .dsFont(.caption)
            .foregroundStyle(DS.Color.muted)
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
                DS.Haptics.selection()
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
        SubScreenShell(title: "Payments & Payouts", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                if isLoading {
                    VStack(spacing: DS.Spacing.sm) {
                        DSSkeletonBlock(height: 56, radius: DS.Radius.control)
                        DSSkeletonBlock(height: 56, radius: DS.Radius.control)
                        DSSkeletonBlock(height: 56, radius: DS.Radius.control)
                    }
                    .accessibilityLabel("Loading payout settings")
                } else {
                    form
                }
            }
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
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.xxs) {
                    ForEach(PayoutMethod.allCases, id: \.self) { method in
                        Button {
                            DS.Haptics.selection()
                            selectedMethod = method
                        } label: {
                            Text(method.label)
                                .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                                .foregroundStyle(selectedMethod == method ? DS.Color.onPrimary : DS.Color.text2)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(selectedMethod == method ? DS.Color.primary : Color.clear, in: Capsule())
                                .frame(minHeight: 44)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.dsPressable)
                        .accessibilityAddTraits(selectedMethod == method ? .isSelected : [])
                    }
                }
                .padding(DS.Spacing.xxs)
                .background(DS.Color.surface2, in: Capsule())
                .dsAnimation(.snappy, value: selectedMethod)

                if selectedMethod == .bank {
                    bankForm
                } else {
                    DSTextField("PayPal E-Mail", placeholder: "name@example.com", text: $paypalEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .padding(.vertical, DS.Spacing.sm)
        }

        // Auszahlungsrhythmus
        sectionCard("Payout Frequency") {
            ForEach(PayoutFrequency.allCases, id: \.self) { freq in
                DSRow(
                    freq.label,
                    systemIcon: selectedFrequency == freq ? "checkmark.circle.fill" : "circle",
                    iconTone: selectedFrequency == freq ? .primary : .neutral,
                    action: { selectedFrequency = freq }
                ) {
                    Text(freq == .instant ? "\(PlatformFees.percentLabel(feeConfig.instantPayoutFeePercent)) fee" : "Free")
                        .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(freq == .instant ? DS.Color.warning : DS.Color.success)
                }
                .accessibilityAddTraits(selectedFrequency == freq ? .isSelected : [])
            }
            Text("Standard payouts (weekly or monthly) are free. Instant payouts will cost \(PlatformFees.percentLabel(feeConfig.instantPayoutFeePercent)) once in-app payouts launch. You always earn the full hourly wage; there are no platform fees for workers.")
                .dsFont(.caption)
                .foregroundStyle(DS.Color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Spacing.sm)
        }

        if let errorMessage {
            Text(errorMessage)
                .dsFont(.callout)
                .foregroundStyle(DS.Color.danger)
        } else if showSavedToast {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(DS.Color.success)
        }

        // Speichern
        Button { Task { await savePayout() } } label: {
            if isSaving {
                ProgressView().tint(DS.Color.onPrimary)
            } else {
                Text("Save")
            }
        }
        .buttonStyle(.ds(.primary))
        .disabled(isSaving || !canSave)

        // TODO: Echte Auszahlungen (Zahlungsdienstleister) gibt es noch nicht — Daten werden nur hinterlegt
        Text("Payouts aren't active yet. Your details are stored encrypted and will be used once payouts launch.")
            .dsFont(.caption)
            .foregroundStyle(DS.Color.muted)
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
        DSTextField("Account holder name", placeholder: "Name on the account", text: $holderName)
            .textContentType(.name)
            .autocorrectionDisabled()

        DSTextField("Routing number (9 digits)", placeholder: "123456789", text: $routingNumber, error: routingError)
            .keyboardType(.numberPad)
            .autocorrectionDisabled()

        if let savedBank, !isChangingAccount {
            DSRow("•••• \(savedBank.accountLast4) saved", systemIcon: "number", showsDivider: false) {
                Button("Change") { isChangingAccount = true }
                    .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                    .foregroundStyle(DS.Color.primaryText)
                    .frame(minHeight: 44)
            }
        } else {
            DSTextField("Account number", placeholder: "Account number", text: $accountNumber, error: accountError, isSecure: true)
                .keyboardType(.numberPad)
                .textContentType(.none)
                .autocorrectionDisabled()
            DSTextField("Confirm account number", placeholder: "Confirm account number", text: $confirmAccount, error: confirmError, isSecure: true)
                .keyboardType(.numberPad)
                .textContentType(.none)
                .autocorrectionDisabled()
            if savedBank != nil {
                Button("Keep saved account number") {
                    isChangingAccount = false
                    accountNumber = ""
                    confirmAccount = ""
                }
                .dsFont(.callout)
                .foregroundStyle(DS.Color.muted)
                .frame(minHeight: 44)
            }
        }

        Picker("Account type", selection: $accountType) {
            ForEach(BankAccountType.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
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
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text("Confirm it's you")
                        .dsFont(.title)
                        .foregroundStyle(DS.Color.text)
                    Text("For your security, please confirm your identity before changing payout details.")
                        .dsFont(.body)
                        .foregroundStyle(DS.Color.text2)

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
                            .dsFont(.callout).foregroundStyle(DS.Color.muted)
                        DSTextField("Code", placeholder: "Code", text: $secret)
                            .textContentType(.oneTimeCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    case "password":
                        DSTextField("Password", placeholder: "Password", text: $secret, isSecure: true)
                            .textContentType(.password)
                    default:
                        if codeSent {
                            Text("We sent a 6-digit code to \(emailHint).")
                                .dsFont(.callout).foregroundStyle(DS.Color.muted)
                            DSTextField("6-digit code", placeholder: "123456", text: $secret)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                        }
                        Button(codeSent ? "Send a new code" : "Send code to \(emailHint)") {
                            Task { await sendCode() }
                        }
                        .buttonStyle(.ds(.soft, size: .medium))
                        .disabled(isBusy)
                    }

                    if let errorMessage {
                        Text(errorMessage).dsFont(.callout).foregroundStyle(DS.Color.danger)
                    }

                    Button { Task { await submit() } } label: {
                        if isBusy { ProgressView().tint(DS.Color.onPrimary) }
                        else { Text("Confirm") }
                    }
                    .buttonStyle(.ds(.primary))
                    .disabled(!canSubmit)
                }
                .padding(DS.Spacing.screenEdge)
            }
            .dsBackground()
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
        SubScreenShell(title: "Privacy & Data", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Dokumente
                sectionCard("Legal") {
                    SettingsActionRow(icon: "doc.text.fill",    label: "Privacy Policy") {
                        openURL(AppConfig.websiteURL.appendingPathComponent("privacy"))
                    }
                    SettingsActionRow(icon: "doc.badge.gearshape.fill", label: "Terms of Service") {
                        openURL(AppConfig.websiteURL.appendingPathComponent("terms"))
                    }
                }

                // Blockierte Nutzer
                sectionCard("Safety") {
                    ProfileNavRow(icon: "hand.raised.slash.fill", label: "Blocked users") { BlockedUsersView() }
                }

                // Konto-Status
                sectionCard("Account Status") {
                    DSRow("Pause Account", subtitle: pauseSubtitle, systemIcon: "pause.circle.fill", iconTone: .warning) {
                        if isUpdatingPause {
                            ProgressView()
                        } else {
                            Toggle("Pause Account", isOn: Binding(
                                get: { accountPaused },
                                set: { wantsPause in
                                    DS.Haptics.selection()
                                    if wantsPause { showPauseConfirm = true } else { Task { await setPaused(false) } }
                                }
                            ))
                            .labelsHidden()
                            .tint(DS.Color.primary)
                        }
                    }

                    if let pauseError {
                        Text(pauseError)
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.danger)
                            .padding(.vertical, DS.Spacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Konto löschen
                Button {
                    DS.Haptics.warning()
                    showDeleteAlert = true
                } label: {
                    Label("Delete Account", systemImage: "trash.fill")
                }
                .buttonStyle(.ds(.destructiveSoft))
            }
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
                        if let api = error as? APIError, api.code == "UNPAID_WORKERS" {
                            // Beendete Schichten sind noch nicht bezahlt: Meldung + betroffene Jobs
                            // TODO: Direkt-Navigation zur Zahlungsuebersicht (Settings liegt tief im Profil-Stack)
                            let jobs = api.unpaidJobs ?? []
                            let more = jobs.count > 5 ? ["and \(jobs.count - 5) more"] : []
                            let list = (jobs.prefix(5).map { "• \($0.title) (\($0.unpaidWorkers) unpaid)" } + more).joined(separator: "\n")
                            deleteError = api.message + (list.isEmpty ? "" : "\n\n" + list)
                                + "\n\nOpen Jobs > Payments to pay them."
                            return
                        }
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
        SubScreenShell(title: "App Preferences", padded: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Erscheinungsbild
                sectionCard("Appearance") {
                    ForEach(AppColorSchemePreference.allCases, id: \.self) { scheme in
                        DSRow(scheme.label, systemIcon: schemeIcon(scheme), action: {
                            DS.Haptics.selection()
                            colorSchemeRaw = scheme.rawValue
                        }) {
                            if colorScheme == scheme {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(DS.Color.primary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityAddTraits(colorScheme == scheme ? .isSelected : [])
                    }
                }

                // Sprache — die App ist bisher nur auf Englisch; keine Auswahl ohne Wirkung anbieten.
                // TODO: Mit Lokalisierung (Localizable.xcstrings) hier auf die iOS-App-Spracheinstellung verlinken
                sectionCard("Language") {
                    DSRow("English", subtitle: "More languages are coming soon.", systemIcon: "globe")
                }
            }
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
    @EnvironmentObject var userStore: UserStore
    @State private var mailFailed  = false
    @State private var newEmail    = ""
    @State private var password    = ""
    @State private var isLoading   = false
    @State private var errorMsg: String? = nil
    @State private var success     = false

    var body: some View {
        NavigationStack {
            sheetScroll {
                DSTextField("New Email Address", placeholder: "name@example.com", text: $newEmail)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                DSTextField("Confirm Current Password", placeholder: "Password", text: $password, isSecure: true)
                if let errorMsg {
                    Text(errorMsg).dsFont(.callout).foregroundStyle(DS.Color.danger)
                }
                Text("After saving, you will receive a verification email at the new address.")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.muted)
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
            .alert(mailFailed ? "Email Changed" : "Verification Email Sent", isPresented: $success) {
                Button("OK") {
                    dismiss()
                    // Erst jetzt neu laden: ContentView wechselt dann auf VerifyEmailView
                    Task { await userStore.refreshMe() }
                }
            } message: {
                Text(mailFailed
                     ? "Your email was changed, but we couldn't send the confirmation email. Tap Resend to try again."
                     : "Please check your new inbox and verify the address to complete the change.")
            }
        }
    }

    private func save() {
        isLoading = true; errorMsg = nil
        Task {
            do {
                let sent = try await APIClient.shared.changeEmail(newEmail: newEmail, password: password)
                userStore.verificationMailFailed = !sent
                mailFailed = !sent
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
            sheetScroll {
                DSTextField("New Phone Number", placeholder: "+1 555 123 4567", text: $phone)
                    .keyboardType(.phonePad)
                if let errorMsg {
                    Text(errorMsg).dsFont(.callout).foregroundStyle(DS.Color.danger)
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
            sheetScroll {
                DSTextField("Current Password", placeholder: "••••••••", text: $current, isSecure: true)
                DSTextField("New Password (min. 8 characters)", placeholder: "New password", text: $newPass, isSecure: true)
                DSTextField("Repeat password", placeholder: "Repeat password", text: $confirm, isSecure: true)
                if !newPass.isEmpty && newPass != confirm {
                    Text("Passwords do not match.")
                        .dsFont(.callout).foregroundStyle(DS.Color.danger)
                }
                if let errorMsg {
                    Text(errorMsg).dsFont(.callout).foregroundStyle(DS.Color.danger)
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
            sheetScroll {
                Text("You signed in with Google or Apple. Set a password to also log in with your email address.")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.muted)
                DSTextField("New Password (min. 8 characters)", placeholder: "New password", text: $newPass, isSecure: true)
                DSTextField("Repeat password", placeholder: "Repeat password", text: $confirm, isSecure: true)
                if !newPass.isEmpty && newPass != confirm {
                    Text("Passwords do not match.")
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.danger)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.danger)
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

/// Flache Gruppe mit Sektionslabel (Zeilen zeichnen ihre Trennlinien selbst).
private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    DSSection(title) { content() }
}

/// Scrollbarer, flacher Formularinhalt fuer die Aenderungs-Sheets (16er Innenabstand in den Feldern, 20 Rand).
private func sheetScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: DS.Spacing.md) { content() }
            .padding(DS.Spacing.screenEdge)
    }
    .scrollDismissesKeyboard(.interactively)
    .dsBackground()
}

/// Aktionszeile (Button) mit Icon-Kachel und Chevron.
private struct SettingsActionRow: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        DSRow(label, systemIcon: icon, showsChevron: true, action: action)
    }
}
