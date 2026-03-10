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

    // Employer-only (optional, weil Worker hat sie nicht)
    let companyName: String?
    let companySize: String?
    let industry: String?
    
    let companyLogoUrl: String?
    let websiteOrInstagram: String?
    let companyDescription: String?
    
    let isEmailVerified: Bool
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
