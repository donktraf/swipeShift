//
//  MainView.swift
//  L1 Demo
//
//  Created by DON on 07.12.25.
//

import SwiftUI

// MainView ist der Einstieg in die "eigentliche" App
// Hier sitzt der NavigationStack, der die Navigation zwischen Screens regelt
struct MainView: View {
    var body: some View {
        // NavigationStack ermöglicht Navigation mit NavigationLink
        NavigationStack {
            // Erste Seite im Stack ist unsere LandingView
            LandingView()
        }
    }
}

// LandingView ist die erste sichtbare Seite nach dem Onboarding
// Hier kann der Nutzer sich für Login oder Registrierung entscheiden
struct LandingView: View {
    @EnvironmentObject var userStore: UserStore
    
    var body: some View {
        VStack(spacing: 32) {
            
            // MARK: - Überschrift + Subheadline
            VStack(spacing: 8) {
                Text("SwipeShift") // Platzhalter-Titel (kann später App-Name sein)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                //Text("Connect with employers who value your skills.")
                Text("Flexible work, on your terms.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center) // Text zentrieren
            }
            .padding(.top, 60)
            .padding(.horizontal, 24)
            
            Spacer() // Schiebt den Content darunter nach unten
            
            // MARK: - Buttons für Login & Account-Erstellung
            VStack(spacing: 16) {
                
                // NavigationLink: Beim Tippen → zur LoginView navigieren
                NavigationLink {
                    LoginView()
                } label: {
                    Text("Login")
                        .frame(maxWidth: .infinity) // Button wird so breit wie möglich
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                        .cornerRadius(14)
                }
                
                // NavigationLink: Beim Tippen → zur RegisterView navigieren
                NavigationLink {
                    RegisterView()
                } label: {
                    Text("Create Account")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer() // Schiebt den Footer nach unten
            
            // Anzeige wer grade eingeloggt ist
            if let current = userStore.currentUser {
                Text("You are logged in as \(current.email)")
                    .font(.footnote)
                    .foregroundColor(.green)
            }
            
            // Kleiner Info-Text im Footer
            Text("By continuing you agree to our terms.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 24)
            
            //Test Button um zu reseten
            /*Button("Reset Onboarding") {
                UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
            }*/

        }
        // MARK: - Hintergrund mit leichtem Verlauf
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.05),
                    Color.purple.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea() // Hintergrund geht über den ganzen Screen
        )
    }
}

#Preview {
    NavigationStack {
        LandingView()
            .environmentObject(UserStore())
    }
}

