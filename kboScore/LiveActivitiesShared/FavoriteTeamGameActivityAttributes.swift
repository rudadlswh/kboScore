//
//  FavoriteTeamGameActivityAttributes.swift
//  kboScore
//  기능 설명: 앱과 확장 사이에서 공유하는 마이팀 경기 Live Activity 속성을 정의합니다.
//  앱과 확장 사이에서 공유하는 마이팀 경기 Live Activity 속성을 정의합니다.을 명확히 분리해 변경 범위와 책임을 예측 가능하게 유지합니다.
//  입력 데이터 누락, 비동기 실행 순서, 플랫폼별 동작 차이를 고려해 방어적으로 처리합니다.
//  TODO : 반복되는 정책이나 화면 상태가 늘어나면 전용 모델과 테스트로 분리합니다.
//
//  Created by Codex on 3/26/26.
//

import Foundation

// KBOCountDisplay 열거형는 KBOCountDisplay 타입의 역할과 값을 정의합니다.
nonisolated public enum KBOCountDisplay {
    // balls 메서드는 이 타입의 주요 동작을 수행합니다.
    public static func balls(_ value: Int?) -> Int? {
        normalized(value, upperBound: 3)
    }

    // strikes 메서드는 이 타입의 주요 동작을 수행합니다.
    public static func strikes(_ value: Int?) -> Int? {
        normalized(value, upperBound: 2)
    }

    // outs 메서드는 이 타입의 주요 동작을 수행합니다.
    public static func outs(_ value: Int?) -> Int? {
        normalized(value, upperBound: 2)
    }

    // normalized 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    private static func normalized(_ value: Int?, upperBound: Int) -> Int? {
        guard let value else { return nil }
        return min(max(value, 0), upperBound)
    }
}

// KBOInningFormatter 열거형는 도메인 값을 화면 표시용 문자열로 변환합니다.
nonisolated public enum KBOInningFormatter {
    // korean 메서드는 이 타입의 주요 동작을 수행합니다.
    public static func korean(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let lowercased = trimmed.lowercased()
        let half: String?
        if trimmed.contains("초") || lowercased.contains("top") {
            half = "초"
        } else if trimmed.contains("말") || lowercased.contains("bottom") || lowercased.contains("bot") {
            half = "말"
        } else {
            half = nil
        }

        guard let inning = firstInteger(in: trimmed) else {
            return trimmed
        }
        guard let half else {
            return "\(inning)회"
        }
        return "\(inning)회 \(half)"
    }

    // firstInteger 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func firstInteger(in value: String) -> Int? {
        var digits = ""
        for character in value {
            if character.isNumber {
                digits.append(character)
            } else if digits.isEmpty == false {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits)
    }
}

// KBOLiveActivityOffenseSide 열거형는 Live Activity에서 현재 공격 중인 팀 방향을 표현합니다.
nonisolated enum KBOLiveActivityOffenseSide: String, Codable, Hashable, Sendable {
    case away
    case home
}

// KBOLiveActivityOffenseResolver 열거형는 Live Activity 표시용 공격 팀 방향을 판별합니다.
nonisolated enum KBOLiveActivityOffenseResolver {
    // offenseSide 메서드는 Live Activity에서 공격 indicator를 보여줄 팀을 결정합니다.
    static func offenseSide(isPreGame: Bool, summaryText: String, inningText: String) -> KBOLiveActivityOffenseSide? {
        guard isPreGame == false, isLiveStatus(summaryText) else {
            return nil
        }

        let lowercased = inningText.lowercased()
        if inningText.contains("초") || lowercased.contains("top") {
            return .away
        }
        if inningText.contains("말") || lowercased.contains("bottom") || lowercased.contains("bot") {
            return .home
        }
        return nil
    }

    private static func isLiveStatus(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "live" || normalized == "경기중"
    }
}

#if canImport(ActivityKit)
import ActivityKit

// FavoriteTeamGameActivityAttributes 구조체는 FavoriteTeamGameActivityAttributes 타입의 역할과 값을 정의합니다.
struct FavoriteTeamGameActivityAttributes: ActivityAttributes {
// ContentState 구조체는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
    public struct ContentState: Codable, Hashable {
        let isPreGame: Bool
        let favoriteScoreText: String
        let opponentScoreText: String
        let inningText: String
        let summaryText: String
        let favoriteStartingPitcherName: String?
        let opponentStartingPitcherName: String?
        let balls: Int?
        let strikes: Int?
        let outs: Int?
        let runnerOnFirst: Bool?
        let runnerOnSecond: Bool?
        let runnerOnThird: Bool?
        let currentBatterName: String?
        let currentPitcherName: String?
    }

    let gameID: String
    let favoriteTeamID: String
    let favoriteTeamName: String
    let favoriteTeamShortName: String
    let opponentTeamID: String
    let opponentTeamName: String
    let opponentTeamShortName: String
    let venue: String
    let isHomeGame: Bool
}
#endif
