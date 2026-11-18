//
//  APIClient.swift
//  swipeShift
//
//  Created by DON on 24.12.25.
//

import Foundation
import UIKit
import Combine

enum ApplyError: Error {
    case shiftTaken
    case jobUnavailable
    case schedulingConflict
    case accountPaused
    case blocked
    case tryAgain   // Backend: TRY_AGAIN (viele parallele Bewerbungen) → wie Verbindungsfehler behandeln
}

// Einfacher API-Client fürs MVP (später: Error-Typen, Refresh-Token, etc.)
final class APIClient {
    static let shared = APIClient()
    
    private let baseURL = AppConfig.baseURL
    
    // Token persistiert in Keychain
    var token: String? = TokenStore.shared.getToken() {
        didSet {
            if let token {
                TokenStore.shared.saveToken(token)
            } else {
                TokenStore.shared.deleteToken()
            }
        }
    }

    private init() {}

    // MARK: - Helpers
    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        
        req.httpMethod = method
        
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Grober Geraete-Ort ("Austin, TX"), falls bekannt — haelt "Active Sessions" aktuell
        DeviceInfo.applyCity(to: &req)
        DeviceInfo.applyTimeZone(to: &req)
        DeviceInfo.applyPushToken(to: &req) // auch 2FA-Abschluss (createSession) laeuft ueber makeRequest
        return req
    }

    // MARK: - Calls
    func fetchJob(jobId: String) async throws -> Job {
        let req = try makeRequest(path: "/jobs/\(jobId)", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct R: Decodable { let job: JobDTO }
        return try JSONDecoder().decode(R.self, from: data).job.toDomain()
    }

    /// Liefert `true`, wenn die Bewerbung per Instant Match sofort angenommen wurde.
    @discardableResult
    func apply(jobId: String) async throws -> Bool {
        let req = try makeRequest(path: "/jobs/\(jobId)/apply", method: "POST")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let body = try? JSONDecoder().decode([String: String].self, from: data),
               let code = body["error"] {
                if body["code"] == "BLOCKED" { throw ApplyError.blocked }
                if body["code"] == "TRY_AGAIN" { throw ApplyError.tryAgain }
                switch code {
                case "SHIFT_TAKEN":          throw ApplyError.shiftTaken
                case "JOB_UNAVAILABLE":      throw ApplyError.jobUnavailable
                case "SCHEDULING_CONFLICT":  throw ApplyError.schedulingConflict
                case "ACCOUNT_PAUSED":       throw ApplyError.accountPaused
                default: break
                }
            }
            throw URLError(.badServerResponse)
        }
        struct ApplyResponse: Decodable { let autoAccepted: Bool? }
        return (try? JSONDecoder().decode(ApplyResponse.self, from: data))?.autoAccepted ?? false
    }

    func skip(jobId: String) async throws {
        let req = try makeRequest(path: "/jobs/\(jobId)/skip", method: "POST")
        _ = try await URLSession.shared.data(for: req)
    }

    /// "Not interested" (Gespeichert): entfernt den Save und blendet den Job in allen Feeds aus
    /// Rueckgabe: true, wenn es vorher schon einen normalen Swipe-Skip gab (Undo soll ihn behalten)
    @discardableResult
    func markNotInterested(jobId: String) async throws -> Bool {
        var req = try makeRequest(path: "/jobs/\(jobId)/skip", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["notInterested": true])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct R: Decodable { let hadSkip: Bool? }
        return (try? JSONDecoder().decode(R.self, from: data))?.hadSkip ?? false
    }

    /// Markiert die Bewerberliste eines Jobs als gesehen ("New Matches" zuruecksetzen); nur Owner
    func markApplicantsSeen(jobId: String) async throws {
        let req = try makeRequest(path: "/jobs/\(jobId)/applicants/seen", method: "POST")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    /// Skip zuruecknehmen (Undo von "Not interested")
    /// `restoreSkip`: vorheriger normaler Skip bleibt bestehen (nur "Not interested" wird zurueckgenommen)
    func unskip(jobId: String, restoreSkip: Bool = false) async throws {
        let req = try makeRequest(path: "/jobs/\(jobId)/skip\(restoreSkip ? "?restoreSkip=1" : "")", method: "DELETE")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func fetchJobs(location: String? = nil, type: String? = nil, category: String? = nil) async throws -> [Job] {

        // 1) URL: /jobs
        var components = URLComponents(
            url: baseURL.appendingPathComponent("jobs"),
            resolvingAgainstBaseURL: false
        )!

        // 2) Optionale Query-Parameter
        var queryItems: [URLQueryItem] = []
        if let location, !location.isEmpty {
            queryItems.append(URLQueryItem(name: "location", value: location.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if let type, !type.isEmpty {
            queryItems.append(URLQueryItem(name: "type", value: type))
        }
        if let category, !category.isEmpty {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        // 3) HTTP Request bauen
        var request = URLRequest(url: components.url!)
        DeviceInfo.applyTimeZone(to: &request)
        request.httpMethod = "GET"

        // 4) Auth Token setzen
        if let token {
            request.setValue(
                "Bearer \(token)",
                forHTTPHeaderField: "Authorization"
            )
        }
        print("Requesting:", request.url?.absoluteString ?? "nil")
        // Debug
        //print("Requesting:", request.url?.absoluteString ?? "nil")
        // print("Auth header:", request.value(forHTTPHeaderField: "Authorization") ?? "NONE")

        // 5) Netzwerk-Call zum Backend
        let (data, response) = try await URLSession.shared.data(for: request)

        // 6) HTTP Response prüfen
        /*let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            print("❌ HTTP \(http.statusCode) BODY:", body)
            throw NSError(domain: "APIError", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"
            ])
        }*/
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "APIError",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                    "HTTP \(http.statusCode): \(body)"
                ]
            )
        }

        // Debug
        print("HTTP:", http.statusCode)
        print("Body:", String(data: data, encoding: .utf8) ?? "no body")

        // 7) JSON → DTO
        struct JobsResponse: Decodable {
            let jobs: [JobDTO]
        }

        let decoded = try JSONDecoder().decode(JobsResponse.self, from: data)

        // 8) DTO → App Model
        return decoded.jobs.map { $0.toDomain() }
    }
    
    struct UploadResponseDTO: Decodable {
           let url: String
       }

    
    /// Loggt den User ein. Bei aktivierter 2FA kommt statt Token eine Code-Challenge zurueck.
    // POST /auth/login
    func login(email: String, password: String) async throws -> LoginOutcome {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        DeviceInfo.apply(to: &request)
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try handleLoginResponse(data)
    }

    /// Gemeinsame Auswertung aller Login-Antworten (E-Mail, Google, Apple, 2FA-Verify)
    private func handleLoginResponse(_ data: Data) throws -> LoginOutcome {
        let decoded = try JSONDecoder().decode(LoginResponseDTO.self, from: data)
        if decoded.twoFactorRequired == true, let challengeId = decoded.challengeId {
            return .twoFactorRequired(TwoFactorChallenge(
                challengeId: challengeId,
                emailHint: decoded.emailHint ?? "your email",
                method: TwoFactorMethod(rawValue: decoded.method ?? "email") ?? .email
            ))
        }
        guard let token = decoded.token, let user = decoded.user else {
            throw URLError(.cannotParseResponse)
        }
        self.token = token
        return .signedIn(user: user, isNewUser: decoded.isNewUser ?? false)
    }

    // POST /auth/register
    func register(requestBody: RegisterRequestDTO) async throws -> UserDTO {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/register"))
        
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        DeviceInfo.apply(to: &request)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data) // nutzt deine validate()-Funktion
        
        // Nur zum testen
        let body = String(data: data, encoding: .utf8) ?? "no body"
        print("RESPONSE BODY:", response)

        let decoded = try JSONDecoder().decode(AuthResponseDTO.self, from: data)
        
        // Set decoded Token
        self.token = decoded.token
        
        return decoded.user
    }
    
    struct ForgotPasswordResult: Decodable {
        let ok: Bool
        let devToken: String?
        let devEmail: String?
        enum CodingKeys: String, CodingKey {
            case ok
            case devToken = "_devToken"
            case devEmail = "_devEmail"
        }
    }

    func forgotPassword(email: String) async throws -> ForgotPasswordResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/forgot-password"))
        DeviceInfo.applyTimeZone(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return (try? JSONDecoder().decode(ForgotPasswordResult.self, from: data))
            ?? ForgotPasswordResult(ok: true, devToken: nil, devEmail: nil)
    }

    func resetPassword(email: String, token: String, newPassword: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/reset-password"))
        DeviceInfo.applyTimeZone(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "email": email,
            "token": token,
            "newPassword": newPassword
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func setPassword(newPassword: String) async throws {
        var req = try makeRequest(path: "/auth/set-password", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["newPassword": newPassword])
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    func changePassword(current: String, new: String) async throws {
        var req = try makeRequest(path: "/auth/change-password", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["currentPassword": current, "newPassword": new])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func changeEmail(newEmail: String, password: String) async throws {
        var req = try makeRequest(path: "/auth/me/email", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["newEmail": newEmail, "password": password])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func deleteAccount() async throws {
        let req = try makeRequest(path: "/auth/me", method: "DELETE")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }


        /// Zentrale Upload-Funktion für alle Bilder
        func uploadImage(_ image: UIImage, target: UploadTarget) async throws -> String {

            guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
                throw NSError(
                    domain: "Upload",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Could not convert image to JPEG."]
                )
            }

            let url = baseURL.appendingPathComponent(target.path)
            var request = URLRequest(url: url)
            DeviceInfo.applyTimeZone(to: &request)
            request.httpMethod = "POST"

            let boundary = UUID().uuidString
            request.setValue(
                "multipart/form-data; boundary=\(boundary)",
                forHTTPHeaderField: "Content-Type"
            )

            // 🔐 Auth Header (falls Upload geschützt)
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            var builder = MultipartFormDataBuilder(boundary: boundary)
            builder.addFile(
                fieldName: "file",
                fileName: target.fileName,
                mimeType: "image/jpeg",
                data: jpegData
            )

            request.httpBody = builder.build()

            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)

            struct UploadResponse: Decodable {
                let url: String
            }

            return try JSONDecoder().decode(UploadResponse.self, from: data).url
        }
    
    func uploadProfilePhoto(_ image: UIImage) async throws -> String {
        try await uploadImage(image, target: .profilePhoto)
    }

    func uploadCompanyLogo(_ image: UIImage) async throws -> String {
        try await uploadImage(image, target: .companyLogo)
    }
    
        // POST /auth/apple
        func loginWithApple(idToken: String) async throws -> LoginOutcome {
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/apple"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            DeviceInfo.apply(to: &request)

            struct Body: Encodable { let idToken: String }
            request.httpBody = try JSONEncoder().encode(Body(idToken: idToken))

            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
            return try handleLoginResponse(data)
        }

        // POST /auth/google
        func loginWithGoogle(idToken: String) async throws -> LoginOutcome {
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/google"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            DeviceInfo.apply(to: &request)

            struct Body: Encodable { let idToken: String }
            request.httpBody = try JSONEncoder().encode(Body(idToken: idToken))

            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
            return try handleLoginResponse(data)
        }
    
    func resendVerification(email: String) async throws {
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/resend-verification"))
            DeviceInfo.applyTimeZone(to: &request)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            struct Body: Encodable { let email: String }
            request.httpBody = try JSONEncoder().encode(Body(email: email))

            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
        }

    
        func fetchMe() async throws -> UserDTO {
            let req = try makeRequest(path: "/auth/me", method: "GET")
            let (data, response) = try await URLSession.shared.data(for: req)
            try validate(response: response, data: data)
            return try JSONDecoder().decode(UserDTO.self, from: data)
        }
    
    // GET /employer/stats
    func fetchEmployerStats() async throws -> EmployerStatsDTO {
        let req = try makeRequest(path: "/employer/stats", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(EmployerStatsDTO.self, from: data)
    }

    // PATCH /auth/me/role
    func setRole(role: String) async throws -> UserDTO {
        var req = try makeRequest(path: "/auth/me/role", method: "PATCH")

        struct Body: Encodable {
            let role: String
        }

        req.httpBody = try JSONEncoder().encode(Body(role: role))

        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(UserDTO.self, from: data)
    }
    
    // PATCH /onboarding/worker
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
            profilePhotoUrl: String?,
            acceptedTerms: Bool
        ) async throws -> UserDTO {

            var req = try makeRequest(path: "/onboarding/worker", method: "PATCH")

            struct Body: Encodable {
                let firstName: String?
                let lastName: String?
                let location: String
                let lat: Double
                let lng: Double
                let dateOfBirth: String
                let jobInterests: [String]
                let availability: [AvailabilityDTO]
                let bio: String?
                let profilePhotoUrl: String?
                let acceptedTerms: Bool
            }

            req.httpBody = try JSONEncoder().encode(
                Body(firstName: firstName, lastName: lastName, location: location, lat: lat, lng: lng,
                     dateOfBirth: dateOfBirthISO, jobInterests: jobInterests,
                     availability: availability, bio: bio, profilePhotoUrl: profilePhotoUrl,
                     acceptedTerms: acceptedTerms)
            )

            let (data, response) = try await URLSession.shared.data(for: req)
            try validate(response: response, data: data)
            return try JSONDecoder().decode(UserDTO.self, from: data)
        }

        // PATCH /onboarding/employer
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
            companyDescription: String?,
            acceptedTerms: Bool
        ) async throws -> UserDTO {

            var req = try makeRequest(path: "/onboarding/employer", method: "PATCH")

            struct Body: Encodable {
                let firstName: String?
                let lastName: String?
                let location: String
                let lat: Double
                let lng: Double
                let companyName: String
                let companySize: String
                let industry: String
                let companyLogoUrl: String?
                let websiteOrInstagram: String?
                let companyDescription: String?
                let acceptedTerms: Bool
            }

            req.httpBody = try JSONEncoder().encode(
                Body(
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
                    companyDescription: companyDescription,
                    acceptedTerms: acceptedTerms
                )
            )

            let (data, response) = try await URLSession.shared.data(for: req)
            try validate(response: response, data: data)
            return try JSONDecoder().decode(UserDTO.self, from: data)
        }
    
    /// Radius in Meilen; das Backend rechnet bei unit=mi selbst in km um
    func fetchNearbyJobs(lat: Double, lng: Double, radiusMiles: Double = 100) async throws -> [Job] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("jobs/nearby"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            URLQueryItem(name: "lat",    value: String(lat)),
            URLQueryItem(name: "lng",    value: String(lng)),
            URLQueryItem(name: "radius", value: String(radiusMiles)),
            URLQueryItem(name: "unit",   value: "mi"),
        ]

        var request = URLRequest(url: components.url!)
        DeviceInfo.applyTimeZone(to: &request)
        request.httpMethod = "GET"

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        print("Requesting nearby jobs:", request.url?.absoluteString ?? "nil")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "APIError",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"]
            )
        }

        struct JobsResponse: Decodable { let jobs: [JobDTO] }
        let decoded = try JSONDecoder().decode(JobsResponse.self, from: data)
        return decoded.jobs.map { $0.toDomain() }
    }

    // POST /jobs — Job erstellen (Arbeitgeber)
    func postJob(_ request: PostJobRequest) async throws {
        var req = try makeRequest(path: "/jobs", method: "POST")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // PUT /jobs/:id — Draft bearbeiten (request.status "published" veroeffentlicht direkt)
    func updateJob(id: String, request: PostJobRequest) async throws {
        var req = try makeRequest(path: "/jobs/\(id)", method: "PUT")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // DELETE /jobs/:id — Draft loeschen
    func deleteJob(id: String) async throws {
        let req = try makeRequest(path: "/jobs/\(id)", method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // GET /jobs/:id — voller Job fuer PostJobView im Bearbeiten-Modus
    func fetchJobForEditing(id: String) async throws -> EditableJob {
        let req = try makeRequest(path: "/jobs/\(id)", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        struct Resp: Decodable { let job: EditableJob }
        return try JSONDecoder().decode(Resp.self, from: data).job
    }

    // GET /jobs/mine — eigene Jobs des Arbeitgebers
    func fetchMyJobs() async throws -> [EmployerJob] {
        let req = try makeRequest(path: "/jobs/mine", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        struct Resp: Decodable { let jobs: [EmployerJob] }
        return try JSONDecoder().decode(Resp.self, from: data).jobs
    }

    // PATCH /jobs/:id/status
    /// `reason` nur beim Stornieren relevant (optional, wird Workern im Kalender angezeigt)
    /// `termsAccepted` ist beim Veroeffentlichen eines Entwurfs Pflicht (Backend: TERMS_REQUIRED)
    func updateJobStatus(jobId: String, status: String, reason: String? = nil, termsAccepted: Bool = false) async throws {
        var req = try makeRequest(path: "/jobs/\(jobId)/status", method: "PATCH")
        var body: [String: Any] = ["status": status]
        if termsAccepted { body["termsAccepted"] = true }
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["reason"] = reason }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // GET /employer/applicants
    /// Mit `jobId`: nur dieser Job; das Backend setzt dann "New Matches" fuer den Job zurueck
    func fetchApplicants(jobId: String? = nil) async throws -> [Applicant] {
        let path = jobId.map { "/employer/applicants?jobId=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)" } ?? "/employer/applicants"
        let req = try makeRequest(path: path, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        struct Resp: Decodable { let applicants: [Applicant] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return try decoder.decode(Resp.self, from: data).applicants
    }

    // GET /employer/workers/:userId — echtes Worker-Profil fuer DetailedWorkerView
    /// `jobId` (optional): Job-Kontext fuer den Match-Hinweis (Backend prueft, dass der Job dem Employer gehoert)
    func fetchWorkerProfile(userId: String, jobId: String? = nil) async throws -> WorkerProfileDTO {
        let query = jobId.map { "?jobId=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)" } ?? ""
        let req = try makeRequest(path: "/employer/workers/\(userId)\(query)", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .flexibleISO8601
        return try dec.decode(WorkerProfileDTO.self, from: data)
    }

    // POST /employer/applicants/:applyId/accept
    func acceptApplicant(applyId: String) async throws {
        let req = try makeRequest(path: "/employer/applicants/\(applyId)/accept", method: "POST")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // POST /employer/applicants/:applyId/decline
    func declineApplicant(applyId: String) async throws {
        let req = try makeRequest(path: "/employer/applicants/\(applyId)/decline", method: "POST")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // POST /employer/applicants/:applyId/unassign
    func unassignWorker(applyId: String) async throws {
        let req = try makeRequest(path: "/employer/applicants/\(applyId)/unassign", method: "POST")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // GET /employer/assigned-workers
    func fetchAssignedWorkers() async throws -> [AssignableJobDTO] {
        let req = try makeRequest(path: "/employer/assigned-workers", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        struct Resp: Decodable { let jobs: [AssignableJobDTO] }
        return try JSONDecoder().decode(Resp.self, from: data).jobs
    }

    // MARK: - Messages

    func fetchConversations() async throws -> [ConversationDTO] {
        let req = try makeRequest(path: "/messages", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return try decoder.decode([ConversationDTO].self, from: data)
    }

    func sendMessage(conversationId: String, text: String) async throws -> ChatMessageDTO {
        var req = try makeRequest(path: "/messages/\(conversationId)", method: "POST")
        req.httpBody = try JSONEncoder().encode(["text": text])
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return try decoder.decode(ChatMessageDTO.self, from: data)
    }

    func fetchMessages(conversationId: String, since: Date? = nil) async throws -> ChatMessagesResponseDTO {
        var path = "/messages/\(conversationId)"
        if let since {
            let iso = ISO8601DateFormatter().string(from: since)
            let encoded = iso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? iso
            path += "?since=\(encoded)"
        }
        let req = try makeRequest(path: path, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return try decoder.decode(ChatMessagesResponseDTO.self, from: data)
    }

    // POST /messages/:conversationId/typing — gedrosselter Typing-Ping
    func sendTypingStatus(conversationId: String, isTyping: Bool) async throws {
        var req = try makeRequest(path: "/messages/\(conversationId)/typing", method: "POST")
        req.httpBody = try JSONEncoder().encode(["isTyping": isTyping])
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // MARK: - Safety (Melden / Blockieren)

    func reportUser(userId: String, conversationId: String?, reason: String, details: String?) async throws {
        var req = try makeRequest(path: "/safety/reports", method: "POST")
        struct Body: Encodable {
            let reportedUserId: String
            let conversationId: String?
            let reason: String
            let details: String?
        }
        req.httpBody = try JSONEncoder().encode(
            Body(reportedUserId: userId, conversationId: conversationId, reason: reason, details: details)
        )
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    func blockUser(userId: String) async throws {
        var req = try makeRequest(path: "/safety/blocks", method: "POST")
        req.httpBody = try JSONEncoder().encode(["userId": userId])
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    func unblockUser(userId: String) async throws {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        let req = try makeRequest(path: "/safety/blocks/\(encoded)", method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    func fetchBlockedUsers() async throws -> [BlockedUser] {
        let req = try makeRequest(path: "/safety/blocks", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        struct W: Decodable { let blocks: [BlockedUser] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .flexibleISO8601
        return try dec.decode(W.self, from: data).blocks
    }

    func markConversationRead(conversationId: String) async throws {
        let req = try makeRequest(path: "/messages/\(conversationId)/read", method: "PATCH")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // MARK: - Companies

    func fetchCompany(name: String) async throws -> CompanyProfileDTO {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let req = try makeRequest(path: "/companies/\(encoded)", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .flexibleISO8601
        return try dec.decode(CompanyProfileDTO.self, from: data)
    }

    struct EmployerReviewRequest: Encodable {
        let applyId:                String
        let communication:          Int
        let paymentFairness:        Int
        let workEnvironment:        Int
        let jobDescriptionAccuracy: Int
        let overallExperience:      Int
        let wouldWorkAgain:         Bool
        let publishConsent:         Bool
        let comment:                String?
    }

    func submitEmployerReview(_ request: EmployerReviewRequest) async throws {
        var req = try makeRequest(path: "/worker/reviews", method: "POST")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    // MARK: - Employer Financials

    /// Haengt Query-Parameter korrekt kodiert an einen relativen Pfad an
    private static func path(_ base: String, query: [URLQueryItem]) -> String {
        var comps = URLComponents()
        comps.path = base
        comps.queryItems = query.isEmpty ? nil : query
        return comps.string ?? base
    }

    func fetchEmployerFinancials(period: FinancialPeriod = .default) async throws -> EmployerFinancialsDTO {
        let req = try makeRequest(path: Self.path("/employer/financials", query: period.queryItems), method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(EmployerFinancialsDTO.self, from: data)
    }

    // MARK: - Update Profile

    func updateProfile(_ request: UpdateProfileRequest) async throws {
        var req = try makeRequest(path: "/auth/me", method: "PATCH")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func updateEmployerProfile(_ request: UpdateEmployerProfileRequest) async throws {
        var req = try makeRequest(path: "/employer/profile", method: "PATCH")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    // MARK: - Worker Profile Data

    func fetchWorkerApplications() async throws -> [WorkerApplicationItem] {
        let req = try makeRequest(path: "/worker/applications", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct W: Decodable { let applications: [WorkerApplicationItem] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .flexibleISO8601
        return try dec.decode(W.self, from: data).applications
    }

    func withdrawApplication(applyId: String) async throws {
        let req = try makeRequest(path: "/worker/applications/\(applyId)", method: "DELETE")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func fetchWorkerSaved() async throws -> [WorkerSavedJob] {
        let req = try makeRequest(path: "/worker/saved", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct W: Decodable { let saved: [WorkerSavedJob] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .flexibleISO8601
        return try dec.decode(W.self, from: data).saved
    }

    func fetchSavedCompanies() async throws -> [SavedCompanyItem] {
        let req = try makeRequest(path: "/worker/saved-companies", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct W: Decodable { let savedCompanies: [SavedCompanyItem] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .flexibleISO8601
        return try dec.decode(W.self, from: data).savedCompanies
    }

    func saveCompany(name: String) async throws {
        var req = try makeRequest(path: "/worker/saved-companies", method: "POST")
        struct Body: Encodable { let companyName: String }
        req.httpBody = try JSONEncoder().encode(Body(companyName: name))
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func unsaveCompany(name: String) async throws {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let req = try makeRequest(path: "/worker/saved-companies/\(encoded)", method: "DELETE")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func fetchWorkerReviews() async throws -> WorkerReviewsResponse {
        let req = try makeRequest(path: "/worker/reviews", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .flexibleISO8601
        return try dec.decode(WorkerReviewsResponse.self, from: data)
    }

    func fetchWorkerFinancials(period: FinancialPeriod = .default) async throws -> WorkerFinancialsDTO {
        let req = try makeRequest(path: Self.path("/worker/financials", query: period.queryItems), method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .flexibleISO8601
        return try dec.decode(WorkerFinancialsDTO.self, from: data)
    }

    func saveJob(jobId: String) async throws {
        let req = try makeRequest(path: "/jobs/\(jobId)/save", method: "POST")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func unsaveJob(jobId: String) async throws {
        let req = try makeRequest(path: "/jobs/\(jobId)/save", method: "DELETE")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    // MARK: - Job Payments

    func fetchJobPayments(jobId: String) async throws -> [PayableWorker] {
        let req = try makeRequest(path: "/employer/jobs/\(jobId)/payments", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct W: Decodable { let workers: [PayableWorker] }
        return try JSONDecoder().decode(W.self, from: data).workers
    }

    func payWorker(jobId: String, applyId: String) async throws {
        let req = try makeRequest(path: "/employer/jobs/\(jobId)/workers/\(applyId)/pay", method: "POST")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func payAllWorkers(jobId: String) async throws {
        let req = try makeRequest(path: "/employer/jobs/\(jobId)/pay-all", method: "POST")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    // MARK: - Employer Reviews

    func fetchPendingReviews() async throws -> [PendingReviewItem] {
        let req = try makeRequest(path: "/employer/reviews/pending", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct W: Decodable { let pending: [PendingReviewItem] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return try decoder.decode(W.self, from: data).pending
    }

    func fetchPastReviews() async throws -> [PastReviewItem] {
        let req = try makeRequest(path: "/employer/reviews", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct W: Decodable { let reviews: [PastReviewItem] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return try decoder.decode(W.self, from: data).reviews
    }

    func fetchReviewDrafts() async throws -> [ReviewDraftItem] {
        let req = try makeRequest(path: "/employer/reviews/drafts", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct W: Decodable { let drafts: [ReviewDraftItem] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return try decoder.decode(W.self, from: data).drafts
    }

    func saveReviewDraft(applyId: String, values: ReviewDraftValues) async throws {
        var req = try makeRequest(path: "/employer/reviews/drafts/\(applyId)", method: "PUT")
        req.httpBody = try JSONEncoder().encode(values)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func deleteReviewDraft(applyId: String) async throws {
        let req = try makeRequest(path: "/employer/reviews/drafts/\(applyId)", method: "DELETE")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func submitReview(_ request: SubmitReviewRequest) async throws {
        var req = try makeRequest(path: "/employer/reviews", method: "POST")
        req.httpBody = try JSONEncoder().encode(request)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func fetchNotifications() async throws -> [NotificationDTO] {
        let req = try makeRequest(path: "/notifications", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return try decoder.decode([NotificationDTO].self, from: data)
    }

    func saveApplicant(applyId: String) async throws {
        let req = try makeRequest(path: "/employer/applicants/\(applyId)/save", method: "POST")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func unsaveApplicant(applyId: String) async throws {
        let req = try makeRequest(path: "/employer/applicants/\(applyId)/save", method: "DELETE")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    func fetchSavedApplicants() async throws -> [SavedApplicantItem] {
        let req = try makeRequest(path: "/employer/saved-applicants", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return try decoder.decode([SavedApplicantItem].self, from: data)
    }

    func fetchEmployerCalendar() async throws -> [EmployerCalendarJobDTO] {
        let req = try makeRequest(path: "/employer/calendar", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return try decoder.decode([EmployerCalendarJobDTO].self, from: data)
    }

    func fetchPendingApplicantsForJob(jobId: String) async throws -> [JobApplicantDTO] {
        let req = try makeRequest(path: "/jobs/\(jobId)/applicants?status=pending", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        let wrapper = try decoder.decode(JobApplicantsResponse.self, from: data)
        return wrapper.applicants
    }
}

// MARK: - Sessions & 2FA

extension APIClient {
    // `private`-Member von APIClient sind hier sichtbar (gleiche Datei)
    private func securityRequest(_ path: String, method: String = "POST", body: [String: String]? = nil) throws -> URLRequest {
        var req = try makeRequest(path: path, method: method)
        if let body { req.httpBody = try JSONEncoder().encode(body) }
        return req
    }

    // GET /auth/sessions
    func fetchSessions() async throws -> [DeviceSessionDTO] {
        let req = try securityRequest("/auth/sessions", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .flexibleISO8601
        return try dec.decode(DeviceSessionsResponseDTO.self, from: data).sessions
    }

    // POST /auth/sessions/:id/revoke
    func revokeSession(id: String) async throws {
        let req = try securityRequest("/auth/sessions/\(id)/revoke")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    // POST /auth/sessions/revoke-others
    func revokeOtherSessions() async throws {
        let req = try securityRequest("/auth/sessions/revoke-others")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    /// POST /auth/me/push-devices — APNs-Geraetetoken der aktuellen Sitzung registrieren (Upsert)
    func registerPushDevice(token: String, environment: String) async throws {
        var req = try makeRequest(path: "/auth/me/push-devices", method: "POST")
        req.httpBody = try JSONEncoder().encode(["token": token, "environment": environment])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    /// DELETE /auth/me/push-devices/:token — mit explizitem Auth-Token, weil beim Logout der gespeicherte schon geloescht wird
    /// Wirft nur bei Netzwerk-/Serverfehlern (→ spaeter erneut versuchen). 401/403/404 gelten als erledigt:
    /// die Sitzung ist beendet (Backend hat die Geraete dabei schon geloescht) bzw. das Token ist unbekannt.
    func unregisterPushDevice(token: String, authToken: String) async throws {
        var req = try makeRequest(path: "/auth/me/push-devices/\(token)", method: "DELETE")
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if (200..<300).contains(http.statusCode) || [401, 403, 404].contains(http.statusCode) { return }
        throw URLError(.badServerResponse)
    }

    /// POST /auth/logout — beendet die Sitzung serverseitig. Fehler sind egal (lokal wird trotzdem ausgeloggt).
    func logoutRemote(token: String) async {
        guard var req = try? securityRequest("/auth/logout") else { return }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }

    /// POST /auth/2fa/request — schickt einen Code, um 2FA ein- (`enable`) oder auszuschalten (`disable`).
    /// `method: .totp` beim Einschalten = Mail-Code als Bestaetigung vor der Authenticator-Einrichtung.
    func requestTwoFactorChange(enable: Bool, method: TwoFactorMethod = .email) async throws -> TwoFactorChallenge {
        var body = ["action": enable ? "enable" : "disable"]
        if enable { body["method"] = method.rawValue }
        let req = try securityRequest("/auth/2fa/request", body: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try JSONDecoder().decode(TwoFactorCodeSentDTO.self, from: data).asChallenge
    }

    /// GET /auth/2fa — Methode + verbleibende Backup-Codes
    func fetchTwoFactorStatus() async throws -> TwoFactorStatusDTO {
        let req = try securityRequest("/auth/2fa", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try JSONDecoder().decode(TwoFactorStatusDTO.self, from: data)
    }

    /// POST /auth/2fa/confirm — liefert den neuen Zustand (an/aus)
    func confirmTwoFactorChange(challengeId: String, code: String) async throws -> Bool {
        let req = try securityRequest("/auth/2fa/confirm", body: ["challengeId": challengeId, "code": code])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct R: Decodable { let enabled: Bool }
        return try JSONDecoder().decode(R.self, from: data).enabled
    }

    /// POST /auth/2fa/verify-login — schliesst einen Login mit 2FA ab
    func verifyTwoFactorLogin(challengeId: String, code: String) async throws -> LoginOutcome {
        var req = try securityRequest("/auth/2fa/verify-login", body: ["challengeId": challengeId, "code": code])
        req.setValue(nil, forHTTPHeaderField: "Authorization")
        DeviceInfo.apply(to: &req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try handleLoginResponse(data)
    }

    /// POST /auth/2fa/totp/setup — Pending-Secret + otpauth-URI, erst nach gueltigem Mail-Code
    func startTotpSetup(challengeId: String, code: String) async throws -> TotpSetupDTO {
        let req = try securityRequest("/auth/2fa/totp/setup", body: ["challengeId": challengeId, "code": code])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try JSONDecoder().decode(TotpSetupDTO.self, from: data)
    }

    /// POST /auth/2fa/totp/backup-codes — neue Backup-Codes (mit aktuellem Authenticator-Code)
    func regenerateBackupCodes(code: String) async throws -> [String] {
        let req = try securityRequest("/auth/2fa/totp/backup-codes", body: ["code": code])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try JSONDecoder().decode(BackupCodesDTO.self, from: data).backupCodes
    }

    /// POST /auth/2fa/totp/confirm — aktiviert TOTP, liefert die Backup-Codes (einmalig)
    func confirmTotpSetup(code: String) async throws -> [String] {
        let req = try securityRequest("/auth/2fa/totp/confirm", body: ["code": code])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try JSONDecoder().decode(TotpConfirmDTO.self, from: data).backupCodes
    }

    /// POST /auth/2fa/switch-to-email/start — Authenticator-/Backup-Code → Mail-Code (an diese Sitzung gebunden)
    func startSwitchToEmail(code: String) async throws -> TwoFactorChallenge {
        let req = try securityRequest("/auth/2fa/switch-to-email/start", body: ["code": code])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try JSONDecoder().decode(TwoFactorCodeSentDTO.self, from: data).asChallenge
    }

    /// POST /auth/2fa/switch-to-email/confirm — Mail-Code → Methode email
    func confirmSwitchToEmail(challengeId: String, code: String) async throws {
        let req = try securityRequest("/auth/2fa/switch-to-email/confirm", body: ["challengeId": challengeId, "code": code])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    /// POST /auth/2fa/resend — neuer Login-Code (neue challengeId)
    func resendTwoFactorLoginCode(challengeId: String) async throws -> TwoFactorChallenge {
        var req = try securityRequest("/auth/2fa/resend", body: ["challengeId": challengeId])
        req.setValue(nil, forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try JSONDecoder().decode(TwoFactorCodeSentDTO.self, from: data).asChallenge
    }
}

// MARK: - Account Settings

extension APIClient {
    // GET /auth/me/settings
    func fetchAccountSettings() async throws -> AccountSettingsResponseDTO {
        let req = try makeRequest(path: "/auth/me/settings", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try JSONDecoder().decode(AccountSettingsResponseDTO.self, from: data)
    }

    // PATCH /auth/me/settings
    func updateAccountSettings(_ patch: AccountSettingsPatch) async throws -> AccountSettingsDTO {
        var req = try makeRequest(path: "/auth/me/settings", method: "PATCH")
        req.httpBody = try JSONEncoder().encode(patch)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try JSONDecoder().decode(AccountSettingsResponseDTO.self, from: data).settings
    }

    // GET /auth/me/reauth/methods — Methoden fuer die Re-Auth (Reihenfolge = Praeferenz)
    func fetchReauthMethods() async throws -> ReauthMethodsDTO {
        let req = try makeRequest(path: "/auth/me/reauth/methods", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try JSONDecoder().decode(ReauthMethodsDTO.self, from: data)
    }

    // POST /auth/me/reauth/email-code — Code an die Konto-E-Mail senden
    func sendReauthEmailCode() async throws {
        let req = try makeRequest(path: "/auth/me/reauth/email-code", method: "POST")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    // POST /auth/me/reauth — method: "totp" | "password" | "email"; secret = Code bzw. Passwort
    func reauthenticate(method: String, secret: String) async throws {
        var req = try makeRequest(path: "/auth/me/reauth", method: "POST")
        let key = method == "password" ? "password" : "code"
        req.httpBody = try JSONEncoder().encode(["method": method, key: secret])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
    }

    // POST /auth/me/pause
    func setAccountPaused(_ paused: Bool) async throws -> Bool {
        var req = try makeRequest(path: "/auth/me/pause", method: "POST")
        req.httpBody = try JSONEncoder().encode(["paused": paused])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct R: Decodable { let paused: Bool }
        return try JSONDecoder().decode(R.self, from: data).paused
    }
}

/// Fehler mit der lesbaren Backend-Meldung ({ error }) als localizedDescription.
struct APIError: LocalizedError {
    let status: Int
    let message: String
    let code: String?
    var missing: [String]? = nil
    var methods: [String]? = nil
    var retryAfterMinutes: Int? = nil
    var errorDescription: String? { message }
}

func validate(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { return }
    guard (200..<300).contains(http.statusCode) else {
        let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)

        // Sitzung serverseitig beendet → App loggt sich lokal aus (UserStore hoert darauf)
        if http.statusCode == 401, body?.code == "SESSION_REVOKED" {
            NotificationCenter.default.post(name: .sessionRevoked, object: nil)
        }

        // Lesbare Backend-Meldung ({ error }, optional mit code) durchreichen statt rohem JSON
        if let message = body?.error, !message.isEmpty {
            throw APIError(status: http.statusCode, message: message, code: body?.code, missing: body?.missing,
                           methods: body?.methods, retryAfterMinutes: body?.retryAfterMinutes)
        }

        let raw = String(data: data, encoding: .utf8) ?? "<no body>"
        throw NSError(
            domain: "HTTP",
            code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(raw)"]
        )
    }
}

// MARK: - DTOs (Backend-Format)

/*struct JobsResponse: Decodable {
    let jobs: [JobDTO]
}

struct JobDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let company: String
    let location: String
    let payText: String
    let distanceText: String
    let shiftText: String
    let shortInfo: String
    let tags: [String]
    let logoEmoji: String
}*/

// MARK: - Shared date decoding

extension JSONDecoder.DateDecodingStrategy {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    /// ISO-8601 mit oder ohne Millisekunden (Prisma/Express liefert "2026-11-17T10:00:00.000Z").
    static let flexibleISO8601: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let date = withFraction.date(from: raw) ?? plain.date(from: raw) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(raw)"))
    }
}
