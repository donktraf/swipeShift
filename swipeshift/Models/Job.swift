//
//  Job.swift
//  swipeShift
//
//  Created by DON on 15.12.25.
//

// Job.swift

import Foundation

// Einfaches Job-Modell für das Swipe-UI
struct Job: Identifiable, Equatable {
    let id: String              // kommt als UUID-String vom Backend
    let title: String           // Job Title
    let company: String         // Company Name
    let location: String        // z.B. "Berlin"
    let payText: String         // z.B. "€15 / hour"
    let distanceText: String    // z.B. "1.8 miles away"
    let shiftText: String       // z.B. "Today, 18:00–22:00"
    let shortInfo: String       // Short Shift Info
    let tags: [String]          // z.B. ["Flexible", "Same-day Pay"]
    let logoEmoji: String       // Einfaches Placeholder-"Logo" (Emoji)
}
