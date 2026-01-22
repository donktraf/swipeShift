//
//  AppConfig.swift
//  swipeShift
//
//  Created by DON on 30.12.25.
//

import Foundation

enum AppConfig {

    static var baseURL: URL {
        #if DEBUG
        // Simulator + lokales Backend
        return URL(string: "http://localhost:3000")! //192.168.0.144
        #else
        // Production / später echte API
        return URL(string: "https://api.swipeshift.com")!
        #endif
    }
    
    // ✅ aus Google Cloud Console / GoogleService-Info.plist
     static let googleClientID = "426389454990-f15heflrjh0bv6iuvs65jbh44chau2ca.apps.googleusercontent.com"
}
