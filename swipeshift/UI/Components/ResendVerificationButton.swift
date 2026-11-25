import SwiftUI

/// "Erneut senden"-Button mit gemeinsamem 60-s-Cooldown (State liegt im UserStore).
/// Zeigt "Resend in 42s" waehrend der Sperre und kurz "Mail sent" nach Erfolg.
struct ResendVerificationButton: View {
    @EnvironmentObject var userStore: UserStore
    var title: String = "Resend verification email"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let remaining = max(0, Int(ceil((userStore.resendCooldownEnd ?? .distantPast).timeIntervalSince(now))))
            let justSent = userStore.resendSentAt.map { now.timeIntervalSince($0) < 4 } ?? false
            let label: String = {
                if userStore.isResendingVerification { return "Sending..." }
                if justSent && remaining > 0 { return "Mail sent" }
                if remaining > 0 { return "Resend in \(remaining)s" }
                return title
            }()
            Button {
                Task { await userStore.resendVerification() }
            } label: {
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(remaining > 0 || userStore.isResendingVerification ? .secondary : SS.primary)
            }
            .buttonStyle(.plain)
            .disabled(remaining > 0 || userStore.isResendingVerification)
        }
    }
}
