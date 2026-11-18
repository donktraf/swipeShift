//
//  SwitchToEmailView.swift
//  swipeShift
//
//  Wechsel 2FA von Authenticator-App zu E-Mail-Codes, ohne 2FA vorher auszuschalten:
//  1) aktueller Authenticator-/Backup-Code → 2) Code aus der Mail (beweist, dass das Postfach funktioniert).
//

import SwiftUI

struct SwitchToEmailView: View {
    let onFinished: () -> Void
    let onCancel: () -> Void

    private enum Step {
        case authenticator
        case email(TwoFactorChallenge)
    }

    @State private var step: Step = .authenticator

    var body: some View {
        switch step {
        case .authenticator:
            TwoFactorCodeView(
                title: "Switch to email codes",
                message: "Enter the code from your authenticator app. Then we'll email you a code to confirm.",
                confirmLabel: "Send Email Code",
                onSubmit: { code in
                    do {
                        let challenge = try await APIClient.shared.startSwitchToEmail(code: code)
                        step = .email(challenge)
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                },
                onResend: { nil },
                onCancel: onCancel,
                method: .totp
            )
        case .email(let challenge):
            TwoFactorCodeView(
                title: "Confirm your email",
                message: "Enter the 6-digit code we sent to \(challenge.emailHint). Your authenticator app and backup codes will stop working.",
                confirmLabel: "Switch to Email Codes",
                onSubmit: { code in
                    do {
                        try await APIClient.shared.confirmSwitchToEmail(challengeId: challenge.challengeId, code: code)
                        onFinished()
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                },
                // Ein neuer Mail-Code braucht erneut den Authenticator-Code (Bindung an den ersten Schritt)
                onResend: { "To get a new code, go back and start the switch again." },
                onCancel: onCancel,
                method: .email
            )
        }
    }
}
