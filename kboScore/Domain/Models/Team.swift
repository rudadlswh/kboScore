//
//  Team.swift
//  kboScore
//  기능 설명: KBO 팀 식별자, 이름, 약칭 등 팀 도메인 모델을 정의합니다.
//  KBO 경기와 팀 규칙을 화면·저장소와 분리된 값 모델로 표현해 계산과 비교 기준을 일관되게 유지합니다.
//  동명이인, 보류 경기, 취소 경기, 누락 점수처럼 원천 데이터가 불완전한 상황을 고려합니다.
//  TODO : 새 시즌 규칙이나 추가 지표가 생기면 모델 확장 지점을 명확히 분리합니다.
//
//  Created by Codex on 3/25/26.
//

import Foundation

// Team 구조체는 Team 타입의 역할과 값을 정의합니다.
nonisolated struct Team: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let shortName: String
    let englishName: String
    let markText: String
    let previousRegularSeasonRank: Int?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        id: String,
        name: String,
        shortName: String,
        englishName: String,
        markText: String,
        previousRegularSeasonRank: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.englishName = englishName
        self.markText = markText
        self.previousRegularSeasonRank = previousRegularSeasonRank
    }

    nonisolated var displayName: String {
        Self.displayName(forTeamID: id, fallback: shortName)
    }

    // canonicalID 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated static func canonicalID(for value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        let lowered = raw.lowercased()
        if displayNamesByTeamID[lowered] != nil {
            return lowered
        }

        if let canonicalID = canonicalTeamIDsByAlias[lowered] {
            return canonicalID
        }

        return TeamIdentity.catalog.first(where: { _, identity in
            identity.shortLabel.caseInsensitiveCompare(raw) == .orderedSame ||
                identity.monogram.caseInsensitiveCompare(raw) == .orderedSame ||
                identity.displayName == raw
        })?.key
    }

    // displayName 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func displayName(forTeamID teamID: String?, fallback: String) -> String {
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if let canonicalID = canonicalID(for: teamID),
           let displayName = displayNamesByTeamID[canonicalID] {
            return displayName
        }

        if let canonicalFallbackID = canonicalID(for: fallback),
           let displayName = displayNamesByTeamID[canonicalFallbackID] {
            return displayName
        }

        return fallback
    }

    private nonisolated static let displayNamesByTeamID: [String: String] = [
        "lotte": "롯데",
        "kiwoom": "키움",
        "hanwha": "한화",
        "kia": "기아",
        "doosan": "두산",
        "samsung": "삼성",
        "kt": "KT",
        "lg": "LG",
        "nc": "NC",
        "ssg": "SSG"
    ]

    private nonisolated static let canonicalTeamIDsByAlias: [String: String] = [
        "lotte": "lotte",
        "lotte giants": "lotte",
        "롯데": "lotte",
        "롯데 자이언츠": "lotte",
        "kiwoom": "kiwoom",
        "kiwoom heroes": "kiwoom",
        "키움": "kiwoom",
        "키움 히어로즈": "kiwoom",
        "hanwha": "hanwha",
        "hanwha eagles": "hanwha",
        "한화": "hanwha",
        "한화 이글스": "hanwha",
        "kia": "kia",
        "kia tigers": "kia",
        "kia 타이거즈": "kia",
        "기아": "kia",
        "기아 타이거즈": "kia",
        "doosan": "doosan",
        "doosan bears": "doosan",
        "두산": "doosan",
        "두산 베어스": "doosan",
        "samsung": "samsung",
        "samsung lions": "samsung",
        "삼성": "samsung",
        "삼성 라이온즈": "samsung",
        "kt": "kt",
        "kt wiz": "kt",
        "kt 위즈": "kt",
        "lg": "lg",
        "lg twins": "lg",
        "lg 트윈스": "lg",
        "nc": "nc",
        "nc dinos": "nc",
        "nc 다이노스": "nc",
        "ssg": "ssg",
        "ssg landers": "ssg",
        "ssg 랜더스": "ssg"
    ]
}

extension TeamIdentity {
    nonisolated var teamDisplayName: String {
        Team.displayName(forTeamID: id, fallback: shortLabel)
    }
}
