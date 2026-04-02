import Foundation
import Combine
import UIKit
import SwiftUI
import MapKit

/// `UserStore` ist der zentrale Auth- und User-State-Container der App.
///
/// Aufgaben:
/// - hält den aktuell eingeloggten User (`currentUser`)
/// - führt Login & Registrierung über das Backend aus
/// - kapselt Upload-Logik (z. B. Profilfoto)
/// - stellt einen sauberen Zugang für Views bereit (EnvironmentObject)
///
/// Views (LoginView, RegisterView, ContentView) sprechen **nur** mit UserStore,
/// niemals direkt mit APIClient.
final class UserStore: ObservableObject {

    /// Der aktuell eingeloggte User, wie er vom Backend zurückkommt.
    /// Wenn `nil` → User ist nicht eingeloggt.
    @Published var currentUser: UserDTO? = nil

    /// Optionaler Fehlertext für UI (z. B. Toast, Inline-Error).
    @Published var errorMessage: String? = nil
    
    // ✅ Neu: App soll Login anzeigen (z.B. nach Reset)
    @Published var showLogin: Bool = false
    
    @Published var loginPrefillEmail: String = ""
    
    @Published var showSocialSuccess: Bool = false

    // Token + Email die via Deep Link ankommen — warten auf "I have a token" Tap
    @Published var pendingResetToken: String? = nil
    @Published var pendingResetEmail: String? = nil
    
    @MainActor
    func presentLoginAfterReset() {
        // Sicherheitsmäßig: nicht automatisch einloggen
        // (du hast ja nur Reset gemacht, nicht "auth")
        self.showLogin = true
    }

    // MARK: - Authentication

    /// Loggt einen User über das Backend ein.
    ///
    /// - Wichtig: Läuft auf dem MainActor, da `@Published` Properties geändert werden.
    /// - Setzt bei Erfolg `currentUser`
    /// - Setzt bei Fehler `errorMessage`
    @MainActor
    func loginRemote(email: String, password: String) async {
        errorMessage = nil
        
        //Email normalisieren
          let emailNorm = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        do {
            let user = try await APIClient.shared.login(
                email: emailNorm,
                password: password
            )

            self.currentUser = user
            
            self.showLogin = false
            print("Login success:", user.email)

        } catch {
            self.errorMessage = error.localizedDescription
            print("Login error:", error.localizedDescription)
            print("Login error:", error)
        }
    }

    /// Registriert einen neuen User (Worker oder Employer) über das Backend.
    ///
    /// Besonderheit:
    /// - Falls ein Profilbild vorhanden ist, wird es **zuerst hochgeladen**
    /// - Das Backend bekommt **nur die Bild-URL**, niemals das Bild selbst
    ///
    /// Ablauf:
    /// 1) optionaler Upload → URL
    /// 2) Register-Request mit vollständigem Body
    /// 3) currentUser setzen
    @MainActor
    func registerRemote(request: RegisterRequestDTO, pickedImage: UIImage?) async {
        errorMessage = nil
        print("Vor aufruf Backend. Daten aus Front: ", request);
        do {
            var finalRequest = request

            // optional Upload je nach Rolle
            if let image = pickedImage {
                if request.role == "worker" {
                    let url = try await APIClient.shared.uploadProfilePhoto(image)

                    finalRequest = RegisterRequestDTO(
                        firstName: request.firstName,
                        lastName: request.lastName,
                        email: request.email,
                        password: request.password,
                        role: request.role,
                        location: request.location,
                        lat: request.lat,
                        lng: request.lng,

                        dateOfBirth: request.dateOfBirth,
                        jobInterests: request.jobInterests,
                        availability: request.availability,
                        bio: request.bio,
                        profilePhotoUrl: url,

                        companyName: request.companyName,
                        companySize: request.companySize,
                        industry: request.industry,

                        companyLogoUrl: request.companyLogoUrl,
                        websiteOrInstagram: request.websiteOrInstagram,
                        companyDescription: request.companyDescription
                    )
                } else {
                    let url = try await APIClient.shared.uploadCompanyLogo(image)

                    finalRequest = RegisterRequestDTO(
                        firstName: request.firstName,
                        lastName: request.lastName,
                        email: request.email,
                        password: request.password,
                        role: request.role,
                        location: request.location,
                        lat: request.lat,
                        lng: request.lng,

                        dateOfBirth: request.dateOfBirth,
                        jobInterests: request.jobInterests,
                        availability: request.availability,
                        bio: request.bio,
                        profilePhotoUrl: request.profilePhotoUrl,

                        companyName: request.companyName,
                        companySize: request.companySize,
                        industry: request.industry,
                        companyLogoUrl: url,
                        websiteOrInstagram: request.websiteOrInstagram,
                        companyDescription: request.companyDescription
                    )
                }
            }
            // Registrierung durchführen
            let user = try await APIClient.shared.register(requestBody: finalRequest)
            
            // App-State aktualisieren
            self.currentUser = user
            print("Register success:", user.firstName)
            print("User:", user)
        } catch {
            self.errorMessage = error.localizedDescription
            print("Register error:", error.localizedDescription)
        }
    }
    
    @MainActor
    func forgotPasswordRemote(email: String) async {
        errorMessage = nil
        do {
            try await APIClient.shared.forgotPassword(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func resetPasswordRemote(email: String, token: String, newPassword: String) async {
        errorMessage = nil
        do {
            try await APIClient.shared.resetPassword(email: email, token: token, newPassword: newPassword)
            
            // ✅ sinnvoll: User ist danach nicht automatisch eingeloggt
            self.currentUser = nil
            self.showLogin = true
            self.loginPrefillEmail = email
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
        // MARK: - Apple Sign In
        func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
            request.requestedScopes = [.email, .fullName]
            // Optional: nonce (sauberer). Kann später ergänzt werden.
        }

    @MainActor
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil

        switch result {
        case .failure(let err):
            errorMessage = err.localizedDescription

        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let identityTokenData = credential.identityToken,
                let identityToken = String(data: identityTokenData, encoding: .utf8)
            else {
                errorMessage = "Apple Sign-In failed: missing token."
                return
            }

            do {
                let response = try await APIClient.shared.loginWithApple(idToken: identityToken)
                self.currentUser = response.user

                // ✅ Nur neuer User bekommt den Success Screen
                if response.isNewUser == true {
                    self.showSocialSuccess = true
                }
                // Bestehender User → direkt Home
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Google Sign In

    @MainActor
    func loginWithGoogle() async throws {
        errorMessage = nil

        guard let rootVC = UIApplication.shared.firstKeyWindowRootViewController else {
            throw NSError(domain: "GoogleSignIn", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Missing root view controller."])
        }

        let config = GIDConfiguration(clientID: AppConfig.googleClientID)
        GIDSignIn.sharedInstance.configuration = config

        let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)

        guard let idToken = signInResult.user.idToken?.tokenString else {
            throw NSError(domain: "GoogleSignIn", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token."])
        }

        let response = try await APIClient.shared.loginWithGoogle(idToken: idToken)
        self.currentUser = response.user

        // ✅ Nur neuer User bekommt den Success Screen
        if response.isNewUser == true {
            self.showSocialSuccess = true
        }
        // Bestehender User → currentUser ist gesetzt → ContentView zeigt direkt Home
    }
    
    @MainActor
    func refreshMe() async {
        errorMessage = nil
        do {
            let me = try await APIClient.shared.fetchMe()
            self.currentUser = me
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func resendVerification() async {
        guard let email = currentUser?.email else { return }
        errorMessage = nil
        do {
            try await APIClient.shared.resendVerification(email: email)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    @MainActor
    func bootstrapSession() async {
        // 1) Token aus Keychain laden (wenn du das implementiert hast)
        if let saved = TokenStore.shared.getToken() {
            APIClient.shared.token = saved
            await refreshMeIfPossible()
        }
    }

    @MainActor
    func refreshMeIfPossible() async {
        guard APIClient.shared.token != nil else { return }
        do {
            let me = try await APIClient.shared.fetchMe()
            self.currentUser = me
        } catch {
            // Token evtl. abgelaufen → logout
            APIClient.shared.token = nil
            self.currentUser = nil
        }
    }
    
    @MainActor
    func setRole(role: String) async {
        errorMessage = nil
        do {
            let user = try await APIClient.shared.setRole(role: role)
            self.currentUser = user
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func completeWorkerOnboarding(
        firstName: String?,
        lastName: String?,
        location: String,
        lat: Double,
        lng: Double,
        dateOfBirthISO: String,
        jobInterests: [String],
        availability: [AvailabilityDTO],
        bio: String?,
        profilePhotoUrl: String?
    ) async {
        errorMessage = nil
        do {
            let user = try await APIClient.shared.completeWorkerOnboarding(
                firstName: firstName,
                lastName: lastName,
                location: location,
                lat: lat,
                lng: lng,
                dateOfBirthISO: dateOfBirthISO,
                jobInterests: jobInterests,
                availability: availability,
                bio: bio,
                profilePhotoUrl: profilePhotoUrl
            )
            self.currentUser = user
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func completeEmployerOnboarding(
        firstName: String?,
        lastName: String?,
        location: String,
        lat: Double,
        lng: Double,
        companyName: String,
        companySize: String,
        industry: String,
        companyLogoUrl: String?,
        websiteOrInstagram: String?,
        companyDescription: String?
    ) async {
        errorMessage = nil
        do {
            let user = try await APIClient.shared.completeEmployerOnboarding(
                firstName: firstName,
                lastName: lastName,
                location: location,
                lat: lat,
                lng: lng,
                companyName: companyName,
                companySize: companySize,
                industry: industry,
                companyLogoUrl: companyLogoUrl,
                websiteOrInstagram: websiteOrInstagram,
                companyDescription: companyDescription
            )
            self.currentUser = user
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// Loggt den User lokal aus:
    /// - JWT Token wird entfernt
    /// - currentUser zurückgesetzt
    /// - UI springt automatisch in den Logged-Out State
    @MainActor
    func logout() {
        APIClient.shared.token = nil
        currentUser = nil
        errorMessage = nil
    }
}

import AuthenticationServices
import GoogleSignIn
import UIKit


// MARK: - UIKit helper
private extension UIApplication {
    var firstKeyWindowRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    }
}
