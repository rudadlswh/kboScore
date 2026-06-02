//
//  GameIdentifier.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import CryptoKit
import Foundation

enum GameIdentifier {
    struct IdentityMatchToken: Hashable, Sendable {
        let value: String
        let priority: Int
        let reason: String
    }

    struct IdentityMatch: Sendable {
        let priority: Int
        let token: String
        let reason: String
    }

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

    nonisolated static func rawIdentifier(from identity: String) -> String {
        let trimmed = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["public:", "provider:"] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    nonisolated static func requestedIdentityTokens(from identity: String) -> Set<String> {
        let trimmed = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        if trimmed.hasPrefix("public:") || trimmed.hasPrefix("provider:") {
            return [trimmed]
        }

        if trimmed.hasPrefix("id:") {
            let rawID = rawIdentifier(from: trimmed)
            if let uuid = UUID(uuidString: rawID) {
                return [idKey(uuid)]
            }
            return [trimmed]
        }

        if let uuid = UUID(uuidString: trimmed) {
            return [trimmed, idKey(uuid)]
        }

        return [trimmed]
    }

    nonisolated static func bestMatch(
        requestTokens: Set<String>,
        candidateTokens: [IdentityMatchToken]
    ) -> IdentityMatch? {
        candidateTokens
            .filter { requestTokens.contains($0.value) }
            .sorted {
                if $0.priority == $1.priority {
                    return $0.value < $1.value
                }
                return $0.priority < $1.priority
            }
            .first
            .map {
                IdentityMatch(priority: $0.priority, token: $0.value, reason: $0.reason)
            }
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
