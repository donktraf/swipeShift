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

    func apply(jobId: String) async throws {
        let req = try makeRequest(path: "/jobs/\(jobId)/apply", method: "POST")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let body = try? JSONDecoder().decode([String: String].self, from: data),
               let code = body["error"] {
                switch code {
                case "SHIFT_TAKEN":          throw ApplyError.shiftTaken
                case "JOB_UNAVAILABLE":      throw ApplyError.jobUnavailable
                case "SCHEDULING_CONFLICT":  throw ApplyError.schedulingConflict
                default: break
                }
            }
            throw URLError(.badServerResponse)
        }
    }

    func skip(jobId: String) async throws {
        let req = try makeRequest(path: "/jobs/\(jobId)/skip", method: "POST")
        _ = try await URLSession.shared.data(for: req)
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

    
    /// Loggt den User ein und speichert den JWT Token für weitere Requests (Bearer Auth)
    // POST /auth/login
    func login(email: String, password: String) async throws -> UserDTO {
        print("Login aufgerufen")
        
        
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            print("IOS LOGIN status:", http.statusCode)
            print("IOS LOGIN headers:", http.allHeaderFields)
        } else {
            print("IOS LOGIN response is not HTTPURLResponse")
        }
        print("IOS LOGIN raw:", String(data: data, encoding: .utf8) ?? "nil")
        //try validate(response: response, data: data)
        
        try validate(response: response, data: data)
        
        do {
            let decoded = try JSONDecoder().decode(AuthResponseDTO.self, from: data)
            self.token = decoded.token
            return decoded.user //  User zurückgeben
        } catch {
            print("IOS LOGIN decode error:", error)
            throw error
        }
    }

    // POST /auth/register
    func register(requestBody: RegisterRequestDTO) async throws -> UserDTO {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/register"))
        
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        func loginWithApple(idToken: String) async throws -> AuthResponseDTO {
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/apple"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            struct Body: Encodable { let idToken: String }
            request.httpBody = try JSONEncoder().encode(Body(idToken: idToken))

            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)

            let decoded = try JSONDecoder().decode(AuthResponseDTO.self, from: data)
            self.token = decoded.token
            return decoded
        }

        // POST /auth/google
        func loginWithGoogle(idToken: String) async throws -> AuthResponseDTO {
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/google"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            struct Body: Encodable { let idToken: String }
            request.httpBody = try JSONEncoder().encode(Body(idToken: idToken))

            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)

            let decoded = try JSONDecoder().decode(AuthResponseDTO.self, from: data)
            self.token = decoded.token
            return decoded
        }
    
    func resendVerification(email: String) async throws {
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/resend-verification"))
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
            profilePhotoUrl: String?
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
            }

            req.httpBody = try JSONEncoder().encode(
                Body(firstName: firstName, lastName: lastName, location: location, lat: lat, lng: lng,
                     dateOfBirth: dateOfBirthISO, jobInterests: jobInterests,
                     availability: availability, bio: bio, profilePhotoUrl: profilePhotoUrl)
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
            companyDescription: String?
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
                    companyDescription: companyDescription
                )
            )

            let (data, response) = try await URLSession.shared.data(for: req)
            try validate(response: response, data: data)
            return try JSONDecoder().decode(UserDTO.self, from: data)
        }
    
    func fetchNearbyJobs(lat: Double, lng: Double, radius: Double = 100) async throws -> [Job] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("jobs/nearby"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            URLQueryItem(name: "lat",    value: String(lat)),
            URLQueryItem(name: "lng",    value: String(lng)),
            URLQueryItem(name: "radius", value: String(radius)),
        ]

        var request = URLRequest(url: components.url!)
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

    // GET /jobs/mine — eigene Jobs des Arbeitgebers
    func fetchMyJobs() async throws -> [EmployerJob] {
        let req = try makeRequest(path: "/jobs/mine", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        struct Resp: Decodable { let jobs: [EmployerJob] }
        return try JSONDecoder().decode(Resp.self, from: data).jobs
    }

    // PATCH /jobs/:id/status
    func updateJobStatus(jobId: String, status: String) async throws {
        var req = try makeRequest(path: "/jobs/\(jobId)/status", method: "PATCH")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["status": status])
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    // GET /employer/applicants
    func fetchApplicants() async throws -> [Applicant] {
        let req = try makeRequest(path: "/employer/applicants", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        struct Resp: Decodable { let applicants: [Applicant] }
        return try JSONDecoder().decode(Resp.self, from: data).applicants
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
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ConversationDTO].self, from: data)
    }

    func sendMessage(conversationId: String, text: String) async throws -> ChatMessageDTO {
        var req = try makeRequest(path: "/messages/\(conversationId)", method: "POST")
        req.httpBody = try JSONEncoder().encode(["text": text])
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
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
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ChatMessagesResponseDTO.self, from: data)
    }

    // POST /messages/:conversationId/typing — gedrosselter Typing-Ping
    func sendTypingStatus(conversationId: String, isTyping: Bool) async throws {
        var req = try makeRequest(path: "/messages/\(conversationId)/typing", method: "POST")
        req.httpBody = try JSONEncoder().encode(["isTyping": isTyping])
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
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
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(CompanyProfileDTO.self, from: data)
    }

    struct EmployerReviewRequest: Encodable {
        let applyId:                String
        let communication:          Int
        let paymentFairness:        Int
        let workEnvironment:        Int
        let jobDescriptionAccuracy: Int
        let overallExperience:      Int
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
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
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
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(W.self, from: data).saved
    }

    func fetchSavedCompanies() async throws -> [SavedCompanyItem] {
        let req = try makeRequest(path: "/worker/saved-companies", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct W: Decodable { let savedCompanies: [SavedCompanyItem] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
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
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(WorkerReviewsResponse.self, from: data)
    }

    func fetchWorkerFinancials(period: FinancialPeriod = .default) async throws -> WorkerFinancialsDTO {
        let req = try makeRequest(path: Self.path("/worker/financials", query: period.queryItems), method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        return try JSONDecoder().decode(WorkerFinancialsDTO.self, from: data)
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
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(W.self, from: data).pending
    }

    func fetchPastReviews() async throws -> [PastReviewItem] {
        let req = try makeRequest(path: "/employer/reviews", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        struct W: Decodable { let reviews: [PastReviewItem] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(W.self, from: data).reviews
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
        decoder.dateDecodingStrategy = .iso8601
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
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SavedApplicantItem].self, from: data)
    }

    func fetchEmployerCalendar() async throws -> [EmployerCalendarJobDTO] {
        let req = try makeRequest(path: "/employer/calendar", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([EmployerCalendarJobDTO].self, from: data)
    }

    func fetchPendingApplicantsForJob(jobId: String) async throws -> [JobApplicantDTO] {
        let req = try makeRequest(path: "/jobs/\(jobId)/applicants?status=pending", method: "GET")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(response: resp, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wrapper = try decoder.decode(JobApplicantsResponse.self, from: data)
        return wrapper.applicants
    }
}

func validate(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { return }
    guard (200..<300).contains(http.statusCode) else {
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
