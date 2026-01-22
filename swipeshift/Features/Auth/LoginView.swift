//
//  LoginView.swift
//  L1 Demo
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    // Zugriff auf unser Fake-Backend
    @EnvironmentObject var userStore: UserStore
    
    @Environment(\.dismiss) private var dismiss

    // Eingaben des Users
    @State private var email: String = ""
    @State private var password: String = ""
    
    @State private var isSubmitting = false

    // Fehlermeldung, falls Login scheitert
    @State private var errorMessage: String?
    
    @State private var socialLoginError: String? = nil
    
    init(prefilledEmail: String = "") {
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        VStack(spacing: 24) {
            // MARK: - Header
            VStack(spacing: 8) {
                Text("Login")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Welcome back. Log in to continue.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            // MARK: - Eingabefelder
            VStack(spacing: 16) {

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .onChange(of: email) { _, _ in
                        errorMessage = nil   // Fehler löschen sobald User tippt
                    }

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .onChange(of: password) { _, _ in
                        errorMessage = nil
                    }

                // Fehlermeldung
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 24)

            // MARK: - Login Button
            Button(action: handleLogin) {
                Text("Login")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(email.isEmpty || password.isEmpty ? Color.gray.opacity(0.5) : Color.blue)
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .disabled(email.isEmpty || password.isEmpty)

            // Optional: Anzeige, wenn jemand eingeloggt ist
            if let current = userStore.currentUser {
                Text("Logged in as \(current.email)")
                    .font(.footnote)
                    .foregroundColor(.green)
                    .padding(.top, 8)
            }
            
            NavigationLink {
                ForgotPasswordView(prefilledEmail: email)
            } label: {
                Text("Forgot password?")
                    .font(.footnote)
                    .foregroundColor(.blue)
            }
            .padding(.top, 6)
            
            // ==========================
            // ✅ OR Divider + Social Login
            // ==========================
            VStack(spacing: 14) {
                orDivider

                // Google
                Button {
                    Task { await signInWithGoogle() }
                } label: {
                    HStack {
                        // Google Icon
                        Image("googleIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .padding(.leading, 16)

                        Spacer()

                        Text("Continue with Google")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)

                        Spacer()

                        // Unsichtbarer Spacer für perfekte Zentrierung
                        Color.clear
                            .frame(width: 18, height: 18)
                            .padding(.trailing, 16)
                    }
                    .frame(height: 52)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                    )
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

                // Apple (native UI von Apple empfohlen)
                SignInWithAppleButton(.continue) { request in
                    print("🍎 Apple button tapped – request builder called")
                    userStore.prepareAppleRequest(request)
                } onCompletion: { result in
                    print("🍎 Apple completion called:", result)
                    Task { await userStore.handleAppleCompletion(result) }
                }
                .signInWithAppleButtonStyle(.white) // or .black (je nach UI)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                        .allowsHitTesting(false)   // ✅ wichtig
                )
                .cornerRadius(14)
                
                if let socialLoginError {
                    Text(socialLoginError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                // Join link
                NavigationLink {
                    RegisterView()
                        .environmentObject(userStore)
                } label: {
                    HStack(spacing: 6) {
                        Text("New to SwipeShift?")
                            .foregroundColor(.secondary)
                        Text("Create an account")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    .font(.footnote)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
   

            Spacer()
        }
        .navigationTitle("Login")
        .navigationBarTitleDisplayMode(.inline)

    }
    
    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.25))
            Text("or")
                .font(.footnote)
                .foregroundColor(.secondary)
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.25))
        }
    }

    // MARK: - Aktionen

    private func handleLogin() {
        errorMessage = nil
        isSubmitting = true
        
        
        Task {
            
            await userStore.loginRemote(email: email, password: password)
            
            isSubmitting = false

            // Falls du UI-Fehler lokal anzeigen willst:
            if let msg = userStore.errorMessage {
                errorMessage = msg
            }
            
            if userStore.currentUser != nil {
                   userStore.showLogin = false     // <— WICHTIG
                
                   dismiss()                       // optional, aber hilft zuverlässig
               } else {
                   errorMessage = "Invalid email or password. Please try again."
               }
        }
    }
    
    private func signInWithGoogle() async {
        socialLoginError = nil

        do {
            try await userStore.loginWithGoogle()

            if userStore.currentUser != nil {
                userStore.showLogin = false
                dismiss()
            } else {
                socialLoginError = "Google login failed: user not returned."
            }

        } catch {
            socialLoginError = error.localizedDescription
        }
    }
}

/// Simple label for a “Continue with …” pill button
private struct SocialButtonLabel: View {
    let iconSystemName: String?
    let iconImage: Image?
    let fallbackSystemIcon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let iconImage {
                    iconImage.resizable().scaledToFit()
                } else if let iconSystemName {
                    Image(systemName: iconSystemName)
                        .resizable().scaledToFit()
                } else {
                    Image(systemName: fallbackSystemIcon)
                        .resizable().scaledToFit()
                }
            }
            .frame(width: 20, height: 20)

            Text(title)
                .fontWeight(.semibold)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.gray.opacity(0.12))
        .foregroundColor(.primary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        LoginView()
            .environmentObject(UserStore())
    }
}

