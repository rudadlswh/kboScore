//
//  GameModels.swift
//  kboScore
//  기능 설명: 경기, 요약, 이닝, 주자 등 핵심 경기 도메인 모델을 정의합니다.
//  KBO 경기와 팀 규칙을 화면·저장소와 분리된 값 모델로 표현해 계산과 비교 기준을 일관되게 유지합니다.
//  동명이인, 보류 경기, 취소 경기, 누락 점수처럼 원천 데이터가 불완전한 상황을 고려합니다.
//  TODO : 새 시즌 규칙이나 추가 지표가 생기면 모델 확장 지점을 명확히 분리합니다.
//
//  Created by Codex on 3/25/26.
//

import Foundation

// GameSeasonClassification 열거형는 GameSeasonClassification 타입의 역할과 값을 정의합니다.
nonisolated enum GameSeasonClassification: String, CaseIterable, Codable, Hashable, Sendable {
    case unknown
    case regularSeason = "regular_season"
    case exhibitionPreseason = "exhibition_preseason"
    case postseason

    nonisolated var isRegularSeason: Bool {
        self == .regularSeason
    }

    // inferred 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func inferred(from note: String?) -> GameSeasonClassification {
        guard let normalizedNote = note?.lowercased() else { return .unknown }
        if normalizedNote.contains("provider_game_id=kbo_pre_") ||
            normalizedNote.contains("시범경기") ||
            normalizedNote.contains("preseason") ||
            normalizedNote.contains("exhibition") {
            return .exhibitionPreseason
        }
        return .unknown
    }
}

// GameStatus 열거형는 처리 단계나 경기 상태를 구분합니다.
nonisolated enum GameStatus: String, CaseIterable, Codable, Hashable, Sendable {
    case upcoming
    case live
    case final
    case rainDelay
    case cancelled

    nonisolated var title: String {
        switch self {
        case .upcoming:
            "예정"
        case .live:
            "LIVE"
        case .final:
            "종료"
        case .rainDelay:
            "우천 중단"
        case .cancelled:
            "취소"
        }
    }

    nonisolated var isLiveLike: Bool {
        switch self {
        case .live, .rainDelay:
            true
        case .upcoming, .final, .cancelled:
            false
        }
    }

    nonisolated var isFinishedLike: Bool {
        switch self {
        case .final, .cancelled:
            true
        case .upcoming, .live, .rainDelay:
            false
        }
    }
}

// RunnerState 구조체는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
nonisolated struct RunnerState: Hashable, Codable, Sendable {
    var first: Bool
    var second: Bool
    var third: Bool

    nonisolated static let empty = RunnerState(first: false, second: false, third: false)
}

// GameEventType 열거형는 도메인 값을 종류별로 구분합니다.
nonisolated enum GameEventType: String, Codable, Hashable, Sendable {
    case score
    case pitching
    case keyPlay
    case weather
    case note
}

// GameEvent 구조체는 GameEvent 타입의 역할과 값을 정의합니다.
nonisolated struct GameEvent: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let type: GameEventType
    let headline: String
    let inningText: String
    let timestamp: Date
}

// TeamGameResult 열거형는 TeamGameResult 타입의 역할과 값을 정의합니다.
nonisolated enum TeamGameResult: Hashable, Sendable {
    case win
    case loss
    case tie
}

// GameDetail 구조체는 GameDetail 타입의 역할과 값을 정의합니다.
nonisolated struct GameDetail: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let scheduledStart: Date
    let venue: String
    let awayTeam: Team
    let homeTeam: Team
    let awayScore: Int?
    let homeScore: Int?
    let status: GameStatus
    let seasonClassification: GameSeasonClassification
    let inningText: String?
    let bases: RunnerState?
    var baseRunners: GameBaseRunners? = nil
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let highlightText: String?
    let events: [GameEvent]
    let note: String?
    let providerGameID: String?
    let awayStartingPitcherName: String?
    let homeStartingPitcherName: String?
    var currentPitcherName: String? = nil
    var currentBatterName: String? = nil

    nonisolated var isRegularSeason: Bool {
        seasonClassification.isRegularSeason
    }

    // involves 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated func involves(teamID: String?) -> Bool {
        guard let teamID else { return false }
        return awayTeam.id == teamID || homeTeam.id == teamID
    }

    // summary 메서드는 이 타입의 주요 동작을 수행합니다.
    func summary(isMyTeamGame: Bool) -> GameSummary {
        GameSummary(
            id: id,
            scheduledStart: scheduledStart,
            venue: venue,
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: awayScore,
            homeScore: homeScore,
            status: status,
            inningText: inningText,
            recentEvent: highlightText ?? note,
            isMyTeamGame: isMyTeamGame,
            awayStartingPitcherName: awayStartingPitcherName,
            homeStartingPitcherName: homeStartingPitcherName,
            currentPitcherName: currentPitcherName ?? (status.isLiveLike ? (awayStartingPitcherName ?? homeStartingPitcherName) : nil),
            currentBatterName: currentBatterName,
            bases: bases,
            baseRunners: baseRunners,
            balls: balls,
            strikes: strikes,
            outs: outs
        )
    }

    var shareText: String {
        let scoreText: String
        if let awayScore, let homeScore {
            scoreText = "\(awayTeam.displayName) \(awayScore) : \(homeScore) \(homeTeam.displayName)"
        } else {
            scoreText = "\(awayTeam.displayName) vs \(homeTeam.displayName)"
        }

        let stateText = inningText ?? status.title
        return "\(scoreText)\n\(stateText)\n\(venue)"
    }

    nonisolated var hasCompleteFinalScore: Bool {
        status == .final && awayScore != nil && homeScore != nil
    }

    nonisolated var officialGameCenterID: String? {
        officialProviderGameID ?? providerGameID ?? Self.providerGameID(from: note)
    }

    nonisolated var officialProviderGameID: String? {
        Self.noteValue("official_provider_game_id", from: note) ??
            Self.officialProviderFallback(from: providerGameID) ??
            Self.officialProviderFallback(from: Self.providerGameID(from: note))
    }

    nonisolated var publicGameID: String? {
        Self.noteValue("public_game_id", from: note)
    }

    nonisolated var canonicalGameIdentityValue: String {
        GameIdentifier.canonicalRawValue(id: id, providerGameID: officialGameCenterID)
    }

    nonisolated var stableDetailIdentity: String {
        if let providerGameID = officialGameCenterID?.trimmingCharacters(in: .whitespacesAndNewlines),
           providerGameID.isEmpty == false {
            return "provider:\(providerGameID)"
        }
        if let publicGameID = publicGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           publicGameID.isEmpty == false {
            return "public:\(publicGameID.lowercased())"
        }
        let day = Self.kstDayKey(for: scheduledStart)
        return "dateTeams:\(day):\(awayTeam.id):\(homeTeam.id)"
    }

    nonisolated var canonicalGameIdentityKey: String {
        GameIdentifier.canonicalKey(id: id, providerGameID: officialGameCenterID)
    }

    nonisolated var gameIdentityAliases: Set<String> {
        var aliases: Set<String> = [
            GameIdentifier.idKey(id),
            matchupIdentityKey,
            dateTeamIdentityKey,
            dateTeamVenueIdentityKey
        ]
        if let providerGameID = providerGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           providerGameID.isEmpty == false {
            aliases.insert(GameIdentifier.providerKey(providerGameID))
        }
        if let officialProviderGameID {
            aliases.insert(GameIdentifier.providerKey(officialProviderGameID))
        }
        if let publicGameID = Self.noteValue("public_game_id", from: note) {
            aliases.insert("public:\(publicGameID.lowercased())")
        }
        return aliases
    }

    nonisolated var gameIdentityMatchTokens: [GameIdentifier.IdentityMatchToken] {
        var tokens: [GameIdentifier.IdentityMatchToken] = []
        var seen: Set<String> = []

        // append 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
        func append(_ value: String?, priority: Int, reason: String) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  value.isEmpty == false,
                  seen.insert("\(priority)::\(value)").inserted else { return }
            tokens.append(GameIdentifier.IdentityMatchToken(value: value, priority: priority, reason: reason))
        }

        if let publicGameID {
            append(publicGameID, priority: 1, reason: "publicGameID")
            append("public:\(publicGameID)", priority: 2, reason: "publicStableIdentity")
            append("public:\(publicGameID.lowercased())", priority: 7, reason: "stableIdentityAlias")
        }
        if let officialProviderGameID {
            append(officialProviderGameID, priority: 3, reason: "officialProviderGameID")
            append(GameIdentifier.providerKey(officialProviderGameID), priority: 4, reason: "officialProviderStableIdentity")
        }
        if let providerGameID {
            append(providerGameID, priority: 5, reason: "providerGameID")
            append(GameIdentifier.providerKey(providerGameID), priority: 6, reason: "providerStableIdentity")
        }
        append(stableDetailIdentity, priority: 7, reason: "stableDetailIdentity")
        append(canonicalGameIdentityKey, priority: 7, reason: "canonicalGameIdentityKey")
        append(GameIdentifier.idKey(id), priority: 7, reason: "databaseID")
        return tokens
    }

    nonisolated var attendanceStorageKey: String {
        if let providerGameID = providerGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           providerGameID.isEmpty == false {
            return GameIdentifier.providerKey(providerGameID)
        }
        if let officialGameCenterID = Self.providerGameID(from: note) {
            return GameIdentifier.providerKey(officialGameCenterID)
        }
        return GameIdentifier.idKey(id)
    }

    nonisolated var attendanceStorageAliases: Set<String> {
        var aliases: Set<String> = [GameIdentifier.idKey(id)]
        if let providerGameID = providerGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           providerGameID.isEmpty == false {
            aliases.insert(GameIdentifier.providerKey(providerGameID))
        }
        if let officialGameCenterID = Self.providerGameID(from: note) {
            aliases.insert(GameIdentifier.providerKey(officialGameCenterID))
        }
        return aliases
    }

    var finalWinningTeam: Team? {
        guard hasCompleteFinalScore, let awayScore, let homeScore, awayScore != homeScore else {
            return nil
        }
        return awayScore > homeScore ? awayTeam : homeTeam
    }

    var finalScoreLine: String? {
        guard hasCompleteFinalScore, let awayScore, let homeScore else { return nil }
        return "\(awayTeam.displayName) \(awayScore) : \(homeScore) \(homeTeam.displayName)"
    }

    // finalResult 메서드는 이 타입의 주요 동작을 수행합니다.
    func finalResult(for teamID: String?) -> TeamGameResult? {
        guard hasCompleteFinalScore,
              let teamID,
              involves(teamID: teamID),
              let awayScore,
              let homeScore else {
            return nil
        }
        if awayScore == homeScore {
            return .tie
        }
        guard let winningTeam = finalWinningTeam else { return nil }
        return winningTeam.id == teamID ? .win : .loss
    }

    // providerGameID 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func providerGameID(from note: String?) -> String? {
        noteValue("provider_game_id", from: note)
    }

    // officialProviderFallback 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func officialProviderFallback(from value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.count >= 9,
              value.hasPrefix("sched-") == false,
              value.prefix(8).allSatisfy(\.isNumber) else {
            return nil
        }
        return value
    }

    // noteValue 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func noteValue(_ key: String, from note: String?) -> String? {
        guard let note,
              let range = note.range(of: "\(key)=") else {
            return nil
        }

        let suffix = note[range.upperBound...]
        let token = suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first
        guard let token, token.isEmpty == false else {
            return nil
        }
        return String(token)
    }

    nonisolated private var matchupIdentityKey: String {
        let startSecond = Int(scheduledStart.timeIntervalSince1970.rounded())
        return [
            "match",
            String(startSecond),
            awayTeam.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            homeTeam.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ].joined(separator: ":")
    }

    nonisolated private var dateTeamIdentityKey: String {
        [
            "date-team",
            Self.kstDayKey(for: scheduledStart),
            awayTeam.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            homeTeam.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ].joined(separator: ":")
    }

    nonisolated private var dateTeamVenueIdentityKey: String {
        [
            "date-team-venue",
            Self.kstDayKey(for: scheduledStart),
            awayTeam.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            homeTeam.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            venue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ].joined(separator: ":")
    }

    // kstDayKey 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func kstDayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// GameBaseRunners 구조체는 GameBaseRunners 타입의 역할과 값을 정의합니다.
nonisolated struct GameBaseRunners: Hashable, Codable, Sendable {
    let first: String?
    let second: String?
    let third: String?
}

// GameSummary 구조체는 GameSummary 타입의 역할과 값을 정의합니다.
nonisolated struct GameSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let scheduledStart: Date
    let venue: String
    let awayTeam: Team
    let homeTeam: Team
    let awayScore: Int?
    let homeScore: Int?
    let status: GameStatus
    let inningText: String?
    let recentEvent: String?
    let isMyTeamGame: Bool
    let awayStartingPitcherName: String?
    let homeStartingPitcherName: String?
    let currentPitcherName: String?
    let currentBatterName: String?
    let bases: RunnerState?
    let baseRunners: GameBaseRunners?
    let balls: Int?
    let strikes: Int?
    let outs: Int?

    var displayScore: String {
        guard let awayScore, let homeScore, showsLiveOrFinalScore else {
            return "VS"
        }
        return "\(awayScore) : \(homeScore)"
    }

    var secondaryText: String {
        switch status {
        case .upcoming:
            scheduledStart.formatted(date: .omitted, time: .shortened)
        case .live, .rainDelay:
            KBOInningFormatter.korean(inningText) ?? status.title
        case .final, .cancelled:
            status.title
        }
    }

    var showsLiveOrFinalScore: Bool {
        guard status != .upcoming else { return false }
        guard status.isFinishedLike || status.isLiveLike else { return false }
        return true
    }
}
