//
//  MultipartFormDataBuilder.swift
//  swipeShift
//
//  Created by DON on 13.01.26.
//

import Foundation

struct MultipartFormDataBuilder {
    private let boundary: String
    private var body = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func addFile(
        fieldName: String,
        fileName: String,
        mimeType: String,
        data: Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    func build() -> Data {
        var finalBody = body
        finalBody.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return finalBody
    }
}
