//
//  JobDTO.swift
//  swipeShift
//
//  Created by DON on 24.12.25.
//

import Foundation

// DTO = so wie es aus dem Backend kommt (Decodable)
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
}

// Mapping: DTO -> Domain Model
extension JobDTO {
    func toDomain() -> Job {
        Job(
            id: id,
            title: title,
            company: company,
            location: location,
            payText: payText,
            distanceText: distanceText,
            shiftText: shiftText,
            shortInfo: shortInfo,
            tags: tags,
            logoEmoji: logoEmoji
        )
    }
}
