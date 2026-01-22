//
//  UploadTarget.swift
//  swipeShift
//
//  Created by DON on 13.01.26.
//

import Foundation

enum UploadTarget {
    case profilePhoto
    case companyLogo

    /// Backend-Pfad
    var path: String {
        switch self {
        case .profilePhoto:
            return "uploads/profile-photo"
        case .companyLogo:
            return "uploads/company-logo"
        }
    }

    /// Dateiname im Multipart-Upload
    var fileName: String {
        switch self {
        case .profilePhoto:
            return "profile.jpg"
        case .companyLogo:
            return "logo.jpg"
        }
    }
}
