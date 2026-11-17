//
//  TotpSetupView.swift
//  swipeShift
//
//  Einrichtung der Authenticator-App (TOTP) als 2FA: Mail-Code (Re-Auth) → QR-Code / Secret →
//  Code bestaetigen → Backup-Codes (werden nur einmal angezeigt).
//  Dazu: "Regenerate backup codes" (mit gueltigem Authenticator-Code).
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

/// QR-Code aus Text (CoreImage, kein externes Paket)
enum QRCodeImage {
    static func make(from text: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        let context = CIContext()
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Kopiert Geheimnisse nur kurz in die Zwischenablage (laeuft nach 2 Minuten ab, nicht auf andere Geraete)
func copySecret(_ text: String) {
    UIPasteboard.general.setItems(
        [[UTType.plainText.identifier: text]],
        options: [.expirationDate: Date().addingTimeInterval(120), .localOnly: true]
    )
}

struct TotpSetupView: View {
    /// Wird nach erfolgreicher Aktivierung (beim Schliessen) aufgerufen, z.B. um das Profil neu zu laden
    let onFinished: () -> Void
    let onCancel: () -> Void

    private enum Step {
        case loading
        case failed(String)
        case verifyEmail(TwoFactorChallenge)
        case scan(TotpSetupDTO)
        case backupCodes([String])
    }

    @State private var step: Step = .loading
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var isSubmitting = false
    @State private var copiedSecret = false
    @State private var isResending = false
    @FocusState private var fieldFocused: Bool

    private var digitsOnly: String { code.filter(\.isNumber) }
    private var canSubmit: Bool { digitsOnly.count == 6 && !isSubmitting }

    private var showsBackupCodes: Bool {
        if case .backupCodes = step { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SS.background().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        switch step {
                        case .loading:
                            ProgressView().padding(.top, 80)
                        case .failed(let message):
                            failedView(message)
                        case .verifyEmail(let challenge):
                            verifyEmailView(challenge)
                        case .scan(let setup):
                            scanView(setup)
                        case .backupCodes(let codes):
                            BackupCodesView(codes: codes, title: "Two-factor is on", onDone: onFinished)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Authenticator App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showsBackupCodes {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
            }
        }
        // Nach der Aktivierung nur ueber "Done" schliessen (Backup-Codes sind sonst weg)
        .interactiveDismissDisabled(showsBackupCodes || isSubmitting)
        .task { await requestEmailCode() }
    }

    // MARK: Schritt 1: Scannen + Code bestaetigen

    private func scanView(_ setup: TotpSetupDTO) -> some View {
        VStack(spacing: 18) {
            Text("Scan this QR code with your authenticator app (for example Google Authenticator, 1Password or Authy).")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let image = QRCodeImage.make(from: setup.otpauthUri) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                    .accessibilityLabel("QR code for your authenticator app")
            }

            Button {
                if let url = URL(string: setup.otpauthUri) {
                    UIApplication.shared.open(url) { opened in
                        if !opened {
                            infoMessage = "No authenticator app found on this device. Scan the QR code or enter the key manually."
                        }
                    }
                }
            } label: {
                Label("Open in authenticator app", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(SS.primary)
            }
            .buttonStyle(.plain)

            VStack(spacing: 6) {
                Text("Can't scan? Enter this key manually:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Text(groupedSecret(setup.secret))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        copySecret(setup.secret)
                        copiedSecret = true
                    } label: {
                        Image(systemName: copiedSecret ? "checkmark" : "doc.on.doc")
                            .foregroundColor(SS.primary)
                    }
                    .accessibilityLabel("Copy key")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            }

            Divider().padding(.vertical, 4)

            Text("Then enter the 6-digit code from the app to turn it on.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            OneTimeCodeField(code: $code, errorMessage: $errorMessage, focused: $fieldFocused)

            statusText

            Button {
                confirm()
            } label: {
                if isSubmitting { ProgressView().tint(.white) } else { Text("Turn On") }
            }
            .buttonStyle(SSPrimaryButtonStyle(isEnabled: canSubmit))
            .disabled(!canSubmit)
        }
    }

    // MARK: Schritt 0: Mail-Code (Re-Auth, bevor es ein Secret gibt)

    private func verifyEmailView(_ challenge: TwoFactorChallenge) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 44))
                .foregroundColor(SS.primary)

            Text("Confirm it's you")
                .font(.system(size: 22, weight: .bold))

            Text("We sent a 6-digit code to \(challenge.emailHint). Enter it to continue setting up your authenticator app.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            OneTimeCodeField(code: $code, errorMessage: $errorMessage, focused: $fieldFocused)

            statusText

            Button {
                submitEmailCode(challenge)
            } label: {
                if isSubmitting { ProgressView().tint(.white) } else { Text("Continue") }
            }
            .buttonStyle(SSPrimaryButtonStyle(isEnabled: canSubmit))
            .disabled(!canSubmit)

            Button {
                resend()
            } label: {
                Text(isResending ? "Sending…" : "Send a new code")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SS.primary)
            }
            .buttonStyle(.plain)
            .disabled(isResending)
        }
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder
    private var statusText: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13))
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
        } else if let infoMessage {
            Text(infoMessage)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
            Button("Try again") {
                step = .loading
                Task { await requestEmailCode() }
            }
            .buttonStyle(SSPrimaryButtonStyle(isEnabled: true))
        }
        .padding(.top, 40)
    }

    // MARK: Aktionen

    private func groupedSecret(_ secret: String) -> String {
        stride(from: 0, to: secret.count, by: 4).map { start in
            let s = secret.index(secret.startIndex, offsetBy: start)
            let e = secret.index(s, offsetBy: 4, limitedBy: secret.endIndex) ?? secret.endIndex
            return String(secret[s..<e])
        }.joined(separator: " ")
    }

    private func requestEmailCode() async {
        do {
            let challenge = try await APIClient.shared.requestTwoFactorChange(enable: true, method: .totp)
            step = .verifyEmail(challenge)
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func submitEmailCode(_ challenge: TwoFactorChallenge) {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                let setup = try await APIClient.shared.startTotpSetup(challengeId: challenge.challengeId, code: digitsOnly)
                code = ""
                infoMessage = nil
                step = .scan(setup)
            } catch {
                errorMessage = error.localizedDescription
                code = ""
            }
            isSubmitting = false
        }
    }

    private func resend() {
        isResending = true
        errorMessage = nil
        Task {
            do {
                let fresh = try await APIClient.shared.requestTwoFactorChange(enable: true, method: .totp)
                step = .verifyEmail(fresh)
                code = ""
                infoMessage = "We sent you a new code."
            } catch {
                errorMessage = error.localizedDescription
            }
            isResending = false
        }
    }

    private func confirm() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                let codes = try await APIClient.shared.confirmTotpSetup(code: digitsOnly)
                step = .backupCodes(codes)
            } catch {
                errorMessage = error.localizedDescription
                code = ""
            }
            isSubmitting = false
        }
    }
}


/// 6-stelliges Code-Feld (Zahlenblock, One-Time-Code)
struct OneTimeCodeField: View {
    @Binding var code: String
    @Binding var errorMessage: String?
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextField("000000", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .font(.system(size: 28, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.center)
            .padding(.vertical, 14)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 24)
            .focused(focused)
            .onChange(of: code) { _, newValue in
                let cleaned = String(newValue.filter(\.isNumber).prefix(6))
                if cleaned != newValue { code = cleaned }
                errorMessage = nil
            }
            .accessibilityLabel("6-digit code")
    }
}

/// Backup-Codes (einmalig sichtbar) mit Kopieren-Button
struct BackupCodesView: View {
    let codes: [String]
    let title: String
    let onDone: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)

            Text(title)
                .font(.system(size: 22, weight: .bold))

            Text("Save these codes. If you lose access to your authenticator app, each code lets you sign in once. They are shown only now.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(codes, id: \.self) { backup in
                    Text(backup)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .textSelection(.enabled)
                }
            }

            Button {
                copySecret(codes.joined(separator: "\n"))
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy all codes", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(SS.primary)
            }
            .buttonStyle(.plain)

            Button("Done", action: onDone)
                .buttonStyle(SSPrimaryButtonStyle(isEnabled: true))
        }
    }
}

/// "Regenerate backup codes": aktueller Authenticator-Code → neue Codes (die alten werden ungueltig)
struct RegenerateBackupCodesView: View {
    let onFinished: () -> Void
    let onCancel: () -> Void

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var newCodes: [String]?
    @FocusState private var fieldFocused: Bool

    private var digitsOnly: String { code.filter(\.isNumber) }
    private var canSubmit: Bool { digitsOnly.count == 6 && !isSubmitting }

    var body: some View {
        NavigationStack {
            ZStack {
                SS.background().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        if let newCodes {
                            BackupCodesView(codes: newCodes, title: "New backup codes", onDone: onFinished)
                        } else {
                            Text("Enter the current code from your authenticator app. Your old backup codes will stop working.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            OneTimeCodeField(code: $code, errorMessage: $errorMessage, focused: $fieldFocused)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 13))
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }

                            Button {
                                submit()
                            } label: {
                                if isSubmitting { ProgressView().tint(.white) } else { Text("Generate New Codes") }
                            }
                            .buttonStyle(SSPrimaryButtonStyle(isEnabled: canSubmit))
                            .disabled(!canSubmit)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Backup Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if newCodes == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                }
            }
            .onAppear { fieldFocused = true }
        }
        .interactiveDismissDisabled(newCodes != nil || isSubmitting)
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                newCodes = try await APIClient.shared.regenerateBackupCodes(code: digitsOnly)
            } catch {
                errorMessage = error.localizedDescription
                code = ""
            }
            isSubmitting = false
        }
    }
}
