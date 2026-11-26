import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(prefilledEmail: String = "") {
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Welcome Back").dsFont(.display).foregroundStyle(DS.Color.text)
                    Text("Login to your account").dsFont(.body).foregroundStyle(DS.Color.text2)
                    LastLoginHint(method: .email)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    DSTextField("Email", placeholder: "you@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    DSTextField("Password", placeholder: "••••••••", text: $password, error: errorMessage, isSecure: true)
                        .textContentType(.oneTimeCode)
                }

                NavigationLink {
                    ForgotPasswordView(prefilledEmail: email)
                } label: {
                    Text("Forgot password?")
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.primaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }

                Button(action: handleLogin) {
                    Text(isSubmitting ? "Logging in..." : "Login")
                }
                .buttonStyle(.ds(.primary))
                .disabled(email.isEmpty || password.isEmpty || isSubmitting)
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.xs)
            .padding(.bottom, DS.Spacing.lg)
        }
        .dsBackground()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // Schliessen-Button oben links
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Color.text2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .twoFactorLoginSheet()
        // Login per 2FA-Code abgeschlossen → Login-Screen schliessen
        .onChange(of: userStore.currentUser?.id) { _, newValue in
            if newValue != nil {
                userStore.showLogin = false
                dismiss()
            }
        }
    }

    private func handleLogin() {
        errorMessage = nil
        isSubmitting = true

        Task {
            await userStore.loginRemote(email: email, password: password)
            isSubmitting = false

            if let msg = userStore.errorMessage {
                errorMessage = msg
            } else if userStore.currentUser != nil {
                userStore.showLogin = false
                dismiss()
            } else if userStore.pendingTwoFactor != nil {
                // 2FA: Code-Sheet ist offen, Login wird dort abgeschlossen (siehe onChange unten)
            } else {
                errorMessage = "Invalid email or password. Please try again."
            }
        }
    }
}
