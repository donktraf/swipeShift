//
//  MainView.swift
//  swipeShift
//

import SwiftUI
import AuthenticationServices

struct MainView: View {
    var body: some View {
        LandingView()
    }
}

struct LandingView: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showLogin = false
    @State private var showRegister = false
    @State private var socialLoginError: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                Spacer(minLength: DS.Spacing.xl)

                // Marke + Value-Proposition
                VStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(DS.Color.primaryText)
                        .frame(width: 72, height: 72)
                        .background(DS.Color.primarySoft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                        .accessibilityHidden(true)

                    Text("SwipeShift")
                        .dsFont(.display)
                        .foregroundStyle(DS.Color.text)

                    Text("Find short-term shifts that match you, or hire the right people fast.")
                        .dsFont(.body)
                        .foregroundStyle(DS.Color.text2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.md)
                }
                .padding(.top, DS.Spacing.xl)

                VStack(spacing: DS.Spacing.sm) {
                    // Register per fullScreenCover statt NavigationLink
                    Button("Create account") { showRegister = true }
                        .buttonStyle(.ds(.primary))

                    // Login per fullScreenCover statt NavigationLink
                    Button("Log in") { showLogin = true }
                        .buttonStyle(.ds(.secondary))
                    LastLoginHint(method: .email)

                    orDivider

                    // Apple (Apple-Richtlinie: schwarzer bzw. weisser Standard-Button)
                    SignInWithAppleButton(.continue) { request in
                        userStore.prepareAppleRequest(request)
                    } onCompletion: { result in
                        Task { await userStore.handleAppleCompletion(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                    LastLoginHint(method: .apple)

                    // Google
                    Button {
                        socialLoginError = nil
                        Task {
                            do {
                                try await userStore.loginWithGoogle()
                            } catch {
                                socialLoginError = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image("googleIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                            Text("Continue with Google")
                        }
                    }
                    .buttonStyle(.ds(.secondary))
                    LastLoginHint(method: .google)

                    if let socialLoginError {
                        Text(socialLoginError)
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.danger)
                            .multilineTextAlignment(.center)
                    }

                    Text("By continuing, you agree to our Terms & Privacy Policy")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, DS.Spacing.xs)
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.bottom, DS.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .dsBackground()
        #if DEBUG
        .onAppear {
            // SS_DEBUG_SCREEN=auth.login|auth.register → vorhandene fullScreenCover oeffnen
            switch DebugLaunch.screen {
            case "auth.login":    showLogin = true
            case "auth.register": showRegister = true
            default: break
            }
        }
        #endif
        // ✅ Login als fullScreenCover
        .fullScreenCover(isPresented: $showLogin) {
            NavigationStack {
                LoginView()
                    .environmentObject(userStore)
            }
        }
        // ✅ Register als fullScreenCover
        .fullScreenCover(isPresented: $showRegister) {
            RegisterView()
                .environmentObject(userStore)
        }
        // 2FA-Code nach Google/Apple-Login (der Login-Screen hat sein eigenes Sheet)
        .twoFactorLoginSheet(isActive: !showLogin && !showRegister && !userStore.showLogin)
        // Hinweis, wenn die Sitzung serverseitig beendet wurde
        .alert("Signed out", isPresented: Binding(
            get: { userStore.signedOutNotice != nil && !showLogin && !userStore.showLogin },
            set: { if !$0 { userStore.signedOutNotice = nil } }
        )) {
            Button("OK", role: .cancel) { userStore.signedOutNotice = nil }
        } message: {
            Text(userStore.signedOutNotice ?? "")
        }
    }

    private var orDivider: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSDivider()
            Text("or").dsFont(.caption).foregroundStyle(DS.Color.muted)
            DSDivider()
        }
        .padding(.vertical, DS.Spacing.xxs)
    }
}
#Preview {
    LandingView()
        .environmentObject(UserStore())
}
