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

    @State private var showLogin = false
    @State private var showRegister = false
    @State private var socialLoginError: String? = nil

    var body: some View {
        ZStack {
            SS.background().ignoresSafeArea()

            VStack {
                Spacer()

                SSCard {
                    VStack(spacing: 18) {

                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(SS.primary.opacity(0.18))
                            .frame(width: 86, height: 86)
                            .overlay(
                                Image(systemName: "briefcase")
                                    .font(.system(size: 34, weight: .semibold))
                                    .foregroundColor(SS.primary)
                            )
                            .padding(.top, 4)

                        Text("SwipeShift")
                            .font(.system(size: 36, weight: .bold))

                        Text("Find jobs that match you")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)

                        VStack(spacing: 12) {

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
                                SSOAuthPillButton(
                                    title: "Continue with Google",
                                    icon: Image("googleIcon"),
                                    background: .black,
                                    foreground: .white,
                                    //border: Color.gray.opacity(0.20)
                                    border: Color.clear
                                )
                            }
                            .buttonStyle(.plain)

                            // Apple
                            SignInWithAppleButton(.continue) { request in
                                userStore.prepareAppleRequest(request)
                            } onCompletion: { result in
                                Task { await userStore.handleAppleCompletion(result) }
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                            // Divider
                            HStack(spacing: 12) {
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.gray.opacity(0.20))
                                Text("or")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.gray.opacity(0.20))
                            }
                            .padding(.vertical, 2)

                            // ✅ Login per fullScreenCover statt NavigationLink
                            Button {
                                showLogin = true
                            } label: {
                                Text("Log in")
                            }
                            .buttonStyle(SSPrimaryButtonStyle())

                            // ✅ Register per fullScreenCover statt NavigationLink
                            Button {
                                showRegister = true
                            } label: {
                                Text("Create account")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(SS.primary)
                            }
                            .buttonStyle(.plain)

                            if let socialLoginError {
                                Text(socialLoginError)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }

                            Text("By continuing, you agree to our Terms & Privacy Policy")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 14)
            }
        }
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
    }
}

#Preview {
    LandingView()
        .environmentObject(UserStore())
}
