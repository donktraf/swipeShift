//
//  UserRole.swift
//  swipeShift
//
//  Created by DON on 25.12.25.
//

import Foundation

/// Rolle eines Users, kommt 1:1 vom Backend
enum UserRole: String, Codable {
    case worker
    case employer
}
