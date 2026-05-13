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
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false else { return nil }
        if let parsed = UUID(uuidString: rawValue) {
            return parsed
        }
        return stableUUID(from: rawValue)
    }

    nonisolated static func canonicalRawValue(id: UUID, providerGameID: String?) -> String {
        trimmedProviderGameID(providerGameID) ?? id.uuidString.lowercased()
    }

    nonisolated static func canonicalKey(id: UUID, providerGameID: String?) -> String {
        if let providerGameID = trimmedProviderGameID(providerGameID) {
            return providerKey(providerGameID)
        }
        return idKey(id)
    }

    nonisolated static func canonicalUUID(id rawID: String?, providerGameID: String?) -> UUID? {
        if let providerGameID = trimmedProviderGameID(providerGameID) {
            return uuid(from: providerGameID)
        }
        return uuid(from: rawID)
    }

    nonisolated static func canonicalUUID(id: UUID, providerGameID: String?) -> UUID {
        if let providerGameID = trimmedProviderGameID(providerGameID),
           let providerUUID = uuid(from: providerGameID) {
            return providerUUID
        }
        return id
    }

    nonisolated static func idKey(_ id: UUID) -> String {
        "id:\(id.uuidString.lowercased())"
    }

    nonisolated static func providerKey(_ providerGameID: String) -> String {
        "provider:\(providerGameID)"
    }

    nonisolated static func lookupKeys(from rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        if trimmed.hasPrefix("provider:") {
            let provider = String(trimmed.dropFirst("provider:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return provider.isEmpty ? [] : [providerKey(provider)]
        }

        if trimmed.hasPrefix("public:") {
            let publicID = String(trimmed.dropFirst("public:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return publicID.isEmpty ? [] : ["public:\(publicID)"]
        }

        if trimmed.hasPrefix("id:") {
            let id = String(trimmed.dropFirst("id:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let uuid = UUID(uuidString: id) {
                return [idKey(uuid)]
            }
            return uuid(from: id).map { [idKey($0)] } ?? []
        }

        if let uuid = UUID(uuidString: trimmed) {
            return [idKey(uuid)]
        }

        return [
            providerKey(trimmed),
            "public:\(trimmed.lowercased())"
        ]
    }

    nonisolated private static func trimmedProviderGameID(_ providerGameID: String?) -> String? {
        guard let providerGameID = providerGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
              providerGameID.isEmpty == false else {
            return nil
        }
        return providerGameID
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
