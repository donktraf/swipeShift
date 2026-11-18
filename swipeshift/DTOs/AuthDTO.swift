//
//  AuthDTO.swift
//  swipeShift
//
//  Created by DON on 25.12.25.
//

import Foundation
enum OnboardingStatus: String, Decodable {
    case pendingRole
    case pendingProfile
    case complete
}

// Backend-User wie er zurückkommt
struct UserDTO: Decodable {
    let id: String
    //let fullName: String
    let firstName: String?
    let lastName: String?
    let email: String
    var role: UserRole?
    var onboarding: OnboardingStatus
    let location: String?
    let lat: Double?
    let lng: Double?
    
    // Worker-only (optional, weil Employer hat sie nicht)
    let dateOfBirth: String?
    let jobInterests: [String]?
    let availability: [AvailabilityDTO]?
    let bio: String?
    let profilePhotoUrl: String?
    let phone: String?
    let willingToRelocate: Bool?
    let maxTravelDistance: Int?
    let transport: String?
    let availableForSameDay: Bool?
    let preferredCategories: [String]?
    let payRangeMin: Double?
    let payRangeMax: Double?
    let skills: WorkerSkillsDTO?
    let workAuthorization: Bool?
    let availableTimes: [String]?
    let shiftTypes: [String]?
    let experience: [WorkerExperienceEntry]?

    // Employer-only (optional, weil Worker hat sie nicht)
    let companyName: String?
    let companySize: String?
    let industry: String?
    let companyLogoUrl: String?
    let websiteOrInstagram: String?
    let companyDescription: String?
    let companyPhone: String?
    let companyEmail: String?
    let businessAreas: [String]?
    let companyLocations: [String]?
    let primaryHiringLocation: String?
    let teamMembers: [TeamMemberDTO]?
    let jobTitle: String?
    let managerRole: String?
    // Oeffentliches Firmenprofil
    let yearFounded: Int?
    let tagline: String?
    let socialLinks: SocialLinksDTO?
    let streetAddress: String?
    let zipCode: String?
    let addressLat: Double?
    let addressLng: Double?
    let publicContactName: String?
    let publicContactRole: String?
    let postsInMultipleStates: Bool?
    let remoteFriendly: Bool?

    let isEmailVerified: Bool
    let hasSocialLogin: Bool?
    /// 2FA per E-Mail-Code aktiv (nur in GET /auth/me enthalten)
    let twoFactorEnabled: Bool?
    /// "email" | "totp" (nur in GET /auth/me, nil wenn 2FA aus)
    let twoFactorMethod: String?
    /// Konto pausiert (nur in GET /auth/me enthalten)
    let isPaused: Bool?
    /// Admin-Konto (Moderation); nur in GET /auth/me
    let isAdmin: Bool?
    /// Rechtliche Zustimmungen: Key -> zugestimmt (terms, ratingSystem, paymentResponsibility, accurateJobInfo, legalHiring); nur in GET /auth/me
    let legalConsents: [String: Bool]?
}

// Login/Register Response
struct AuthResponseDTO: Decodable {
    let token: String
    let user: UserDTO
    let isNewUser: Bool?
}

// Login Request Body
struct LoginRequestDTO: Encodable {
    let email: String
    let password: String
}


struct AvailabilityDTO: Codable {
    let name: String
    var available: Bool
}

struct WorkerSkillsDTO: Codable {
    let communication: Int
    let teamwork: Int
    let reliability: Int
    let underPressure: Int
}

struct UpdateProfileRequest: Encodable {
    let firstName: String?
    let lastName: String?
    let location: String?
    let bio: String?
    let dateOfBirth: String?
    let availability: [AvailabilityDTO]?
    let jobInterests: [String]?
    let phone: String?
    let willingToRelocate: Bool?
    let maxTravelDistance: Int?
    let transport: String?
    let availableForSameDay: Bool?
    let preferredCategories: [String]?
    let payRangeMin: Double?
    let payRangeMax: Double?
    let skills: WorkerSkillsDTO?
    let workAuthorization: Bool?
    let profilePhotoUrl: String?
    let legalConsents: [String: Bool]?
    let availableTimes: [String]?
    let shiftTypes: [String]?
    let experience: [WorkerExperienceEntry]?

    init(
        firstName: String? = nil, lastName: String? = nil,
        location: String? = nil, bio: String? = nil,
        dateOfBirth: String? = nil, availability: [AvailabilityDTO]? = nil,
        jobInterests: [String]? = nil, phone: String? = nil,
        willingToRelocate: Bool? = nil, maxTravelDistance: Int? = nil,
        transport: String? = nil, availableForSameDay: Bool? = nil,
        preferredCategories: [String]? = nil, payRangeMin: Double? = nil,
        payRangeMax: Double? = nil, skills: WorkerSkillsDTO? = nil,
        workAuthorization: Bool? = nil, profilePhotoUrl: String? = nil,
        legalConsents: [String: Bool]? = nil,
        availableTimes: [String]? = nil, shiftTypes: [String]? = nil,
        experience: [WorkerExperienceEntry]? = nil
    ) {
        self.firstName = firstName; self.lastName = lastName
        self.location = location; self.bio = bio
        self.dateOfBirth = dateOfBirth; self.availability = availability
        self.jobInterests = jobInterests; self.phone = phone
        self.willingToRelocate = willingToRelocate; self.maxTravelDistance = maxTravelDistance
        self.transport = transport; self.availableForSameDay = availableForSameDay
        self.preferredCategories = preferredCategories; self.payRangeMin = payRangeMin
        self.payRangeMax = payRangeMax; self.skills = skills
        self.workAuthorization = workAuthorization; self.profilePhotoUrl = profilePhotoUrl
        self.legalConsents = legalConsents
        self.availableTimes = availableTimes; self.shiftTypes = shiftTypes
        self.experience = experience
    }
}

struct TeamMemberDTO: Codable, Identifiable {
    let name: String
    let email: String
    let role: String
    var id: String { email }
}

struct UpdateEmployerProfileRequest: Encodable {
    // Company Info Tab
    let companyName: String?
    let companySize: String?
    let companyPhone: String?
    let companyEmail: String?
    let businessAreas: [String]?
    let locations: [String]?
    let primaryHiringLocation: String?
    let companyBio: String?
    let website: String?
    let teamMembers: [TeamMemberDTO]?
    let profilePhotoUrl: String?
    // Your Profile Tab
    let firstName: String?
    let lastName: String?
    let jobTitle: String?
    let managerRole: String?
    // Legal Agreements (Key -> zugestimmt)
    var legalConsents: [String: Bool]? = nil
    // Oeffentliche Firmeninfos. Leerer String loescht das Feld (nil wird nicht gesendet).
    var yearFounded: String? = nil
    var tagline: String? = nil
    var socialLinks: SocialLinksDTO? = nil
    var streetAddress: String? = nil
    var zipCode: String? = nil
    var addressLat: NullableDouble? = nil
    var addressLng: NullableDouble? = nil
    var publicContactName: String? = nil
    var publicContactRole: String? = nil
    var postsInMultipleStates: Bool? = nil
    var remoteFriendly: Bool? = nil
}

struct RegisterRequestDTO: Encodable {
    let firstName: String
    let lastName: String
    let email: String
    let password: String
    let role: String
    let location: String
    let lat: Double      
    let lng: Double

    // Worker-only
    let dateOfBirth: String?
    let jobInterests: [String]?
    let availability: [AvailabilityDTO]?
    let bio: String?
    let profilePhotoUrl: String?

    // Employer-only
    let companyName: String?
    let companySize: String?
    let industry: String?
    let companyLogoUrl: String?
    let websiteOrInstagram: String?
    let companyDescription: String?

    /// AGB-Zustimmung bei der Registrierung (Backend speichert sie nur, wenn true)
    var acceptedTerms: Bool? = nil
}
