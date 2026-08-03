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
    
    let isEmailVerified: Bool
    let hasSocialLogin: Bool?
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

    init(
        firstName: String? = nil, lastName: String? = nil,
        location: String? = nil, bio: String? = nil,
        dateOfBirth: String? = nil, availability: [AvailabilityDTO]? = nil,
        jobInterests: [String]? = nil, phone: String? = nil,
        willingToRelocate: Bool? = nil, maxTravelDistance: Int? = nil,
        transport: String? = nil, availableForSameDay: Bool? = nil,
        preferredCategories: [String]? = nil, payRangeMin: Double? = nil,
        payRangeMax: Double? = nil, skills: WorkerSkillsDTO? = nil,
        workAuthorization: Bool? = nil, profilePhotoUrl: String? = nil
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
}
