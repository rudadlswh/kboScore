//
//  GameIdentifier.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import CryptoKit
import Foundation

enum GameIdentifier {
    nonisolated static func uuid(from rawValue: String?) -> UUID? {
        guard let rawValue, rawValue.isEmpty == false else { return nil }
        if let parsed = UUID(uuidString: rawValue) {
            return parsed
        }
        return stableUUID(from: rawValue)
    }

    nonisolated private static func stableUUID(from value: String) -> UUID {
        let digest = SHA256.hash(data: Data(value.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let part1 = String(hex.prefix(8))
        let part2 = String(hex.dropFirst(8).prefix(4))
        let part3 = String(hex.dropFirst(12).prefix(4))
        let part4 = String(hex.dropFirst(16).prefix(4))
        let part5 = String(hex.dropFirst(20).prefix(12))
        let uuidString = "\(part1)-\(part2)-\(part3)-\(part4)-\(part5)"

        return UUID(uuidString: uuidString) ?? UUID()
    }
}
