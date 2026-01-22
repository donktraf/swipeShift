//
//  FormValidator.swift
//  swipeShift
//
//  Created by DON on 28.12.25.
//

import Foundation

enum FormValidator {

    // MARK: - Public API

    static func validateWorker(
        firstName: String,
        lastName: String,
        email: String,
        dateOfBirth: Date,
        password: String,
        confirmPassword: String,
        locationText: String,
        jobInterests: Set<String>,
        availability: [DayAvailability],
        acceptedTerms: Bool
    ) -> [FieldKey: String] {

        var errors: [FieldKey: String] = [:]

        // First Name
        if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.firstName] = "Please enter your first name."
        }

        // Last Name
        if lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.lastName] = "Please enter your last name."
        }

        // Email
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.email] = "Please enter your email address."
        } else if !isValidEmail(email) {
            errors[.email] = "Please enter a valid email address."
        }
        
        // Age validation
        let calendar = Calendar.current
        
        if let minDate = calendar.date(byAdding: .year, value: 18, to: dateOfBirth),
           minDate > Date() {
            errors[.dateOfBirth] = "You must be at least 18 years old."
        }

        // Password
        if password.isEmpty {
            errors[.password] = "Please enter a password."
        } else if password.count < 6 {
            errors[.password] = "Password must be at least 6 characters long."
        }

        // Confirm Password
        if confirmPassword.isEmpty {
            errors[.confirmPassword] = "Please confirm your password."
        } else if confirmPassword != password {
            errors[.confirmPassword] = "Passwords do not match."
        }

        // Location
        if locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.locationText] = "Please enter your city or ZIP code."
        }
        
        // Job Interests
        if jobInterests.isEmpty {
            errors[.jobInterests] = "Please select at least one job interest."
        }
        
        // Availability (mind. 1 Tag true)
        let hasAnyAvailableDay = availability.contains { $0.available }
        if !hasAnyAvailableDay {
            errors[.availability] = "Please select at least one available day."
        }

        // Terms
        if acceptedTerms == false {
            errors[.terms] = "Please accept the Terms & Privacy Policy."
        }

        return errors
    }

    static func validateEmployer(
        companyName: String,
        contactFirstName: String,
        contactLastName: String,
        email: String,
        employerPassword: String,
        confirmPassword: String,
        location: String,
        industry: String,
        companySizeRaw: CompanySize,
        acceptedTerms: Bool
    ) -> [FieldKey: String] {

        var errors: [FieldKey: String] = [:]

        // Company name
        if companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.companyName] = "Please enter the company name."
        }

        // Contact First/Last Name (NOT optional)
        if contactFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.firstName] = "Please enter the contact person's first name."
        }
        if contactLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.lastName] = "Please enter the contact person's last name."
        }

        // Email
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.employerEmail] = "Please enter an email address."
        } else if !isValidEmail(email) {
            errors[.employerEmail] = "Please enter a valid email address."
        }

        // Password
        if employerPassword.isEmpty {
            errors[.employerPassword] = "Please enter a password."
        } else if employerPassword.count < 6 {
            errors[.employerPassword] = "Password must be at least 6 characters long."
        }

        // Confirm Password
        if confirmPassword.isEmpty {
            errors[.employerConfirmPassword] = "Please confirm your password."
        } else if confirmPassword != employerPassword {
            errors[.employerConfirmPassword] = "Passwords do not match."
        }

        // Location
        if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.employerLocation] = "Please enter the company location."
        }

        // Industry
        if industry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.employerIndustry] = "Please select an industry or category."
        }

        // Company Size (comes in as rawValue)
        if companySizeRaw == .none {
            errors[.companySize] = "Please select a company size."
        }

        // Terms
        if acceptedTerms == false {
            errors[.employerTerms] = "Please accept the Terms & Privacy Policy."
        }

        return errors
    }

    // MARK: - Helpers

    private static func isValidEmail(_ email: String) -> Bool {
        // Simple, MVP-ready
        let pattern = #"^\S+@\S+\.\S+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}
