//
//  GameIdentifier.swift
//  kboScore
//  기능 설명: 여러 데이터 소스의 경기 식별자를 하나의 비교 가능한 키로 정규화합니다.
//  KBO 경기와 팀 규칙을 화면·저장소와 분리된 값 모델로 표현해 계산과 비교 기준을 일관되게 유지합니다.
//  동명이인, 보류 경기, 취소 경기, 누락 점수처럼 원천 데이터가 불완전한 상황을 고려합니다.
//  TODO : 새 시즌 규칙이나 추가 지표가 생기면 모델 확장 지점을 명확히 분리합니다.
//
//  Created by Codex on 3/26/26.
//

import CryptoKit
import Foundation

// GameIdentifier 열거형는 GameIdentifier 타입의 역할과 값을 정의합니다.
enum GameIdentifier {
// IdentityMatchToken 구조체는 IdentityMatchToken 타입의 역할과 값을 정의합니다.
    struct IdentityMatchToken: Hashable, Sendable {
        let value: String
        let priority: Int
        let reason: String
    }

// IdentityMatch 구조체는 IdentityMatch 타입의 역할과 값을 정의합니다.
    struct IdentityMatch: Sendable {
        let priority: Int
        let token: String
        let reason: String
    }

    // uuid 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func uuid(from rawValue: String?) -> UUID? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false else { return nil }
        if let parsed = UUID(uuidString: rawValue) {
            return parsed
        }
        return stableUUID(from: rawValue)
    }

    // canonicalRawValue 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated static func canonicalRawValue(id: UUID, providerGameID: String?) -> String {
        trimmedProviderGameID(providerGameID) ?? id.uuidString.lowercased()
    }

    // canonicalKey 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated static func canonicalKey(id: UUID, providerGameID: String?) -> String {
        if let providerGameID = trimmedProviderGameID(providerGameID) {
            return providerKey(providerGameID)
        }
        return idKey(id)
    }

    // canonicalUUID 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated static func canonicalUUID(id rawID: String?, providerGameID: String?) -> UUID? {
        if let providerGameID = trimmedProviderGameID(providerGameID) {
            return uuid(from: providerGameID)
        }
        return uuid(from: rawID)
    }

    // canonicalUUID 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated static func canonicalUUID(id: UUID, providerGameID: String?) -> UUID {
        if let providerGameID = trimmedProviderGameID(providerGameID),
           let providerUUID = uuid(from: providerGameID) {
            return providerUUID
        }
        return id
    }

    // idKey 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func idKey(_ id: UUID) -> String {
        "id:\(id.uuidString.lowercased())"
    }

    nonisolated static func attendanceCanonicalKey(_ id: UUID) -> String {
        idKey(id)
    }

    nonisolated static func attendanceCanonicalKey(from rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false else {
            return nil
        }
        if rawValue.hasPrefix("id:") {
            let rawID = String(rawValue.dropFirst("id:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return UUID(uuidString: rawID).map(attendanceCanonicalKey)
        }
        if let uuid = UUID(uuidString: rawValue) {
            return attendanceCanonicalKey(uuid)
        }
        return rawValue.lowercased()
    }

    nonisolated static func attendanceUUID(fromCanonicalKey key: String) -> UUID? {
        guard let canonicalKey = attendanceCanonicalKey(from: key),
              canonicalKey.hasPrefix("id:") else {
            return nil
        }
        return UUID(uuidString: String(canonicalKey.dropFirst("id:".count)))
    }

    // providerKey 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func providerKey(_ providerGameID: String) -> String {
        "provider:\(providerGameID)"
    }

    // lookupKeys 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // rawIdentifier 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func rawIdentifier(from identity: String) -> String {
        let trimmed = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["public:", "provider:"] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    // requestedIdentityTokens 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // bestMatch 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // trimmedProviderGameID 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func trimmedProviderGameID(_ providerGameID: String?) -> String? {
        guard let providerGameID = providerGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
              providerGameID.isEmpty == false else {
            return nil
        }
        return providerGameID
    }

    // stableUUID 메서드는 이 타입의 주요 동작을 수행합니다.
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
