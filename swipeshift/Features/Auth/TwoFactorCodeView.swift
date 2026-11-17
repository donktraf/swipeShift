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

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var isSubmitting = false
    @State private var isResending = false
    @FocusState private var fieldFocused: Bool

    private var digitsOnly: String { code.filter(\.isNumber) }
    private var canSubmit: Bool { digitsOnly.count == 6 && !isSubmitting }

    var body: some View {
        NavigationStack {
            ZStack {
                SS.background().ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 44))
                        .foregroundColor(SS.primary)
                        .padding(.top, 24)

                    VStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    TextField("000000", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                        .padding(.horizontal, 48)
                        .focused($fieldFocused)
                        .onChange(of: code) { _, newValue in
                            let cleaned = String(newValue.filter(\.isNumber).prefix(6))
                            if cleaned != newValue { code = cleaned }
                            errorMessage = nil
                        }
                        .accessibilityLabel("6-digit code")

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    } else if let infoMessage {
                        Text(infoMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(confirmLabel)
                        }
                    }
                    .buttonStyle(SSPrimaryButtonStyle(isEnabled: canSubmit))
                    .disabled(!canSubmit)
                    .padding(.horizontal, 24)

                    Button(action: resend) {
                        Text(isResending ? "Sending…" : "Send a new code")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SS.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isResending)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
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
            let error = await onSubmit(digitsOnly)
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
                message: "We sent a 6-digit sign-in code to \(challenge.emailHint).",
                confirmLabel: "Verify & Sign In",
                onSubmit: { await userStore.verifyTwoFactorLogin(code: $0) },
                onResend: { await userStore.resendTwoFactorLoginCode() },
                onCancel: { userStore.cancelTwoFactorLogin() }
            )
        }
    }
}

extension View {
    func twoFactorLoginSheet(isActive: Bool = true) -> some View {
        modifier(TwoFactorLoginSheetModifier(isActive: isActive))
    }
}
