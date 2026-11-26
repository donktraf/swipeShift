//
//  TwoFactorCodeView.swift
//  swipeShift
//
//  Eingabe des 6-stelligen E-Mail-Codes — fuer den Login mit 2FA und zum
//  Ein-/Ausschalten von 2FA in den Account-Settings.
//

import SwiftUI

struct TwoFactorCodeView: View {
    let title: String
    let message: String
    let confirmLabel: String
    /// Prueft den Code. Rueckgabe: Fehlermeldung oder nil bei Erfolg.
    let onSubmit: (String) async -> String?
    /// Fordert einen neuen Code an. Rueckgabe: Fehlermeldung oder nil.
    let onResend: () async -> String?
    let onCancel: () -> Void
    /// Bei `.totp`: kein "Send a new code", dafuer "Use a backup code"
    var method: TwoFactorMethod = .email

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var isSubmitting = false
    @State private var isResending = false
    @State private var useBackupCode = false
    @FocusState private var fieldFocused: Bool

    private var digitsOnly: String { code.filter(\.isNumber) }
    /// Backup-Code ohne Bindestrich/Leerzeichen, gross
    private var backupNormalized: String { code.uppercased().filter { $0.isLetter || $0.isNumber } }
    private var enteredCode: String { useBackupCode ? backupNormalized : digitsOnly }
    private var canSubmit: Bool {
        !isSubmitting && (useBackupCode ? backupNormalized.count == 10 : digitsOnly.count == 6)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.lg) {
                    Image(systemName: method == .totp ? "lock.shield.fill" : "envelope.badge.shield.half.filled")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(DS.Color.primaryText)
                        .frame(width: 72, height: 72)
                        .background(DS.Color.primarySoft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                        .padding(.top, DS.Spacing.lg)
                        .accessibilityHidden(true)

                    VStack(spacing: DS.Spacing.xs) {
                        Text(title).dsFont(.title).foregroundStyle(DS.Color.text)
                            .multilineTextAlignment(.center)
                        Text(useBackupCode ? "Enter one of the backup codes you saved when you set up two-factor. Each code works once." : message)
                            .dsFont(.body)
                            .foregroundStyle(DS.Color.text2)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: DS.Spacing.xs) {
                        TextField(
                            useBackupCode ? "XXXXX-XXXXX" : "000000",
                            text: $code,
                            prompt: Text(useBackupCode ? "XXXXX-XXXXX" : "000000").foregroundStyle(DS.Color.muted)
                        )
                        .keyboardType(useBackupCode ? .asciiCapable : .numberPad)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(useBackupCode ? nil : .oneTimeCode)
                        .font(.system(size: useBackupCode ? 22 : 28, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.Color.text)
                        .tint(DS.Color.primary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, DS.Spacing.sm)
                        .frame(minHeight: 56)
                        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .strokeBorder(
                                    errorMessage != nil ? DS.Color.danger : (fieldFocused ? DS.Color.primary : DS.Color.border),
                                    lineWidth: fieldFocused || errorMessage != nil ? 1.5 : 1
                                )
                        )
                        .focused($fieldFocused)
                        .onChange(of: code) { _, newValue in
                            let cleaned = useBackupCode
                                ? String(newValue.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(11))
                                : String(newValue.filter(\.isNumber).prefix(6))
                            if cleaned != newValue { code = cleaned }
                            errorMessage = nil
                        }
                        .accessibilityLabel(useBackupCode ? "Backup code" : "6-digit code")

                        if let errorMessage {
                            Text(errorMessage)
                                .dsFont(.caption)
                                .foregroundStyle(DS.Color.danger)
                                .multilineTextAlignment(.center)
                        } else if let infoMessage {
                            Text(infoMessage)
                                .dsFont(.caption)
                                .foregroundStyle(DS.Color.text2)
                        }
                    }

                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView().tint(DS.Color.onPrimary)
                        } else {
                            Text(confirmLabel)
                        }
                    }
                    .buttonStyle(.ds(.primary))
                    .disabled(!canSubmit)

                    if method == .totp {
                        Button(useBackupCode ? "Use the authenticator code instead" : "Use a backup code") {
                            useBackupCode.toggle()
                            code = ""
                            errorMessage = nil
                        }
                        .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                    } else {
                        Button(isResending ? "Sending…" : "Send a new code", action: resend)
                            .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
                            .disabled(isResending)
                    }
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.bottom, DS.Spacing.lg)
            }
            .dsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(DS.Color.primaryText)
                }
            }
            .onAppear { fieldFocused = true }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        infoMessage = nil
        Task {
            let error = await onSubmit(enteredCode)
            isSubmitting = false
            if let error {
                errorMessage = error
                code = ""
            }
        }
    }

    private func resend() {
        isResending = true
        errorMessage = nil
        Task {
            let error = await onResend()
            isResending = false
            if let error {
                errorMessage = error
            } else {
                code = ""
                infoMessage = "We sent you a new code."
            }
        }
    }
}

/// Login-Variante: haengt das Code-Sheet an einen Login-Screen und spricht mit dem UserStore.
struct TwoFactorLoginSheetModifier: ViewModifier {
    @EnvironmentObject var userStore: UserStore
    /// false, solange dieser Screen selbst etwas anderes praesentiert (verhindert Doppel-Praesentation)
    var isActive: Bool = true

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { isActive ? userStore.pendingTwoFactor : nil },
            set: { if $0 == nil, isActive { userStore.cancelTwoFactorLogin() } }
        )) { challenge in
            TwoFactorCodeView(
                title: "Enter your code",
                message: challenge.method == .totp
                    ? "Enter the code from your authenticator app."
                    : "We sent a 6-digit sign-in code to \(challenge.emailHint).",
                confirmLabel: "Verify & Sign In",
                onSubmit: { await userStore.verifyTwoFactorLogin(code: $0) },
                onResend: { await userStore.resendTwoFactorLoginCode() },
                onCancel: { userStore.cancelTwoFactorLogin() },
                method: challenge.method
            )
        }
    }
}

extension View {
    func twoFactorLoginSheet(isActive: Bool = true) -> some View {
        modifier(TwoFactorLoginSheetModifier(isActive: isActive))
    }
}
