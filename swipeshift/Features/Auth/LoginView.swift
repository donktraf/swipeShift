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
        ZStack {
            SS.background().ignoresSafeArea()

            VStack {
                Spacer()

                SSCard {
                    VStack(spacing: 18) {

                        // ✅ Schließen-Button oben links
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(10)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                        Text("Welcome Back")
                            .font(.system(size: 34, weight: .bold))

                        Text("Login to your account")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Email")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 10) {
                                Image(systemName: "envelope")
                                    .foregroundColor(.secondary)
                                TextField("you@example.com", text: $email)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            .ssTextField()

                            Text("Password")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.top, 6)

                            HStack(spacing: 10) {
                                Image(systemName: "lock")
                                    .foregroundColor(.secondary)
                                SecureField("••••••••", text: $password)
                                    .textContentType(.oneTimeCode)
                            }
                            .ssTextField()
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        NavigationLink {
                            ForgotPasswordView(prefilledEmail: email)
                        } label: {
                            HStack {
                                Spacer()
                                Text("Forgot password?")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(SS.primary)
                            }
                        }

                        Button(action: handleLogin) {
                            Text(isSubmitting ? "Logging in..." : "Login")
                        }
                        .buttonStyle(SSPrimaryButtonStyle(isEnabled: !(email.isEmpty || password.isEmpty) && !isSubmitting))
                        .disabled(email.isEmpty || password.isEmpty || isSubmitting)
                    }
                }

                Spacer()
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
            } else {
                errorMessage = "Invalid email or password. Please try again."
            }
        }
    }
}
