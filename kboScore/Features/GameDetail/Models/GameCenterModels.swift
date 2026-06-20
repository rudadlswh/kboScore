//
//  GameCenterModels.swift
//  kboScore
//  기능 설명: 게임센터 상세 화면에서 사용하는 기록, 라인스코어, 리뷰 모델을 정의합니다.
//  KBO 경기와 팀 규칙을 화면·저장소와 분리된 값 모델로 표현해 계산과 비교 기준을 일관되게 유지합니다.
//  동명이인, 보류 경기, 취소 경기, 누락 점수처럼 원천 데이터가 불완전한 상황을 고려합니다.
//  TODO : 새 시즌 규칙이나 추가 지표가 생기면 모델 확장 지점을 명확히 분리합니다.
//
//  Created by Codex on 5/13/26.
//

import Foundation

// GameCenterDetailPayload 구조체는 GameCenterDetailPayload 타입의 역할과 값을 정의합니다.
struct GameCenterDetailPayload: Sendable {
    let summary: GameCenterSummary
    let lineScore: GameCenterLineScore?
    let review: GameCenterReview?
    let preview: GameCenterPreview?
}

// GameCenterSummary 구조체는 GameCenterSummary 타입의 역할과 값을 정의합니다.
struct GameCenterSummary: Sendable {
    let officialGameID: String
    let dateText: String
    let stadium: String?
    let startTime: String?
    let endTime: String?
    let durationText: String?
    let crowdText: String?
    let status: GameStatus
    let inningText: String?
    let awayScore: Int?
    let homeScore: Int?
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let bases: RunnerState?
    let baseRunners: GameCenterBaseRunners?
    let probableStarters: GameCenterProbableStarters?
    let winningPitcher: String?
    let losingPitcher: String?
    let savePitcher: String?
}

// GameCenterBaseRunners 구조체는 GameCenterBaseRunners 타입의 역할과 값을 정의합니다.
struct GameCenterBaseRunners: Hashable, Sendable {
    let first: String?
    let second: String?
    let third: String?
}

// GameCenterProbableStarters 구조체는 GameCenterProbableStarters 타입의 역할과 값을 정의합니다.
struct GameCenterProbableStarters: Sendable {
    let away: String?
    let home: String?
}

// GameCenterLineScore 구조체는 GameCenterLineScore 타입의 역할과 값을 정의합니다.
struct GameCenterLineScore: Sendable {
    let inningLabels: [String]
    let awayInnings: [String]
    let homeInnings: [String]
    let awayTotals: GameCenterTeamLineTotals
    let homeTotals: GameCenterTeamLineTotals
}

// GameCenterTeamLineTotals 구조체는 GameCenterTeamLineTotals 타입의 역할과 값을 정의합니다.
struct GameCenterTeamLineTotals: Sendable {
    let runs: String?
    let hits: String?
    let errors: String?
    let walks: String?
}

// GameCenterRecordSource 열거형는 GameCenterRecordSource 타입의 역할과 값을 정의합니다.
enum GameCenterRecordSource: String, Sendable {
    case unknown
    case dbLiveTextRecords
    case fullBoxscore
    case scoreboardHTMLBoxscore
    case keyplayerPartialLimited
    case lineupLimited

    var isLimited: Bool {
        self == .keyplayerPartialLimited || self == .lineupLimited
    }
}

// GameCenterReview 구조체는 GameCenterReview 타입의 역할과 값을 정의합니다.
struct GameCenterReview: Sendable {
    let summaryItems: [GameCenterSummaryItem]
    let awayBatting: GameCenterBattingSection
    let homeBatting: GameCenterBattingSection
    let awayPitching: GameCenterPitchingSection
    let homePitching: GameCenterPitchingSection
    let recordSource: GameCenterRecordSource

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        summaryItems: [GameCenterSummaryItem],
        awayBatting: GameCenterBattingSection,
        homeBatting: GameCenterBattingSection,
        awayPitching: GameCenterPitchingSection,
        homePitching: GameCenterPitchingSection,
        recordSource: GameCenterRecordSource = .unknown
    ) {
        self.summaryItems = summaryItems
        self.awayBatting = awayBatting
        self.homeBatting = homeBatting
        self.awayPitching = awayPitching
        self.homePitching = homePitching
        self.recordSource = recordSource
    }

    var hasDisplayableRecords: Bool {
        awayBatting.lines.isEmpty == false ||
            homeBatting.lines.isEmpty == false ||
            awayPitching.lines.isEmpty == false ||
            homePitching.lines.isEmpty == false ||
            summaryItems.isEmpty == false
    }
}

// GameCenterKeyStatsComparison 구조체는 GameCenterKeyStatsComparison 타입의 역할과 값을 정의합니다.
struct GameCenterKeyStatsComparison: Sendable, Equatable {
    let away: GameCenterTeamKeyStats
    let home: GameCenterTeamKeyStats
}

// GameCenterTeamKeyStats 구조체는 GameCenterTeamKeyStats 타입의 역할과 값을 정의합니다.
struct GameCenterTeamKeyStats: Sendable, Equatable {
    let hits: Int
    let homeRuns: Int
    let stolenBases: Int
    let strikeouts: Int
    let doublePlays: Int
    let errors: Int
}

// GameCenterSummaryItem 구조체는 GameCenterSummaryItem 타입의 역할과 값을 정의합니다.
struct GameCenterSummaryItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let value: String
    let values: [String]

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(title: String, value: String, values: [String]? = nil) {
        self.title = title
        self.value = value
        self.values = values ?? [value]
    }
}

// GameCenterBattingSection 구조체는 GameCenterBattingSection 타입의 역할과 값을 정의합니다.
struct GameCenterBattingSection: Sendable {
    let lines: [GameCenterBattingLine]
    let totals: GameCenterBattingTotals?
}

// GameCenterBattingLine 구조체는 GameCenterBattingLine 타입의 역할과 값을 정의합니다.
struct GameCenterBattingLine: Identifiable, Hashable, Sendable {
    let id = UUID()
    let battingOrder: String
    let position: String
    let name: String
    let atBats: String?
    let runs: String?
    let hits: String?
    let runsBattedIn: String?
    let homeRuns: String?
    let walks: String?
    let strikeouts: String?
    let stolenBases: String?
    let groundedIntoDoublePlay: String?
    let errors: String?
    let average: String?
    let plateAppearanceHomeRuns: String?
    let plateAppearanceWalks: String?
    let plateAppearanceStrikeouts: String?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        battingOrder: String,
        position: String,
        name: String,
        atBats: String?,
        runs: String?,
        hits: String?,
        runsBattedIn: String?,
        homeRuns: String?,
        walks: String?,
        strikeouts: String?,
        stolenBases: String? = nil,
        groundedIntoDoublePlay: String? = nil,
        errors: String? = nil,
        average: String?,
        plateAppearanceHomeRuns: String? = nil,
        plateAppearanceWalks: String? = nil,
        plateAppearanceStrikeouts: String? = nil
    ) {
        self.battingOrder = battingOrder
        self.position = position
        self.name = name
        self.atBats = atBats
        self.runs = runs
        self.hits = hits
        self.runsBattedIn = runsBattedIn
        self.homeRuns = homeRuns
        self.walks = walks
        self.strikeouts = strikeouts
        self.stolenBases = stolenBases
        self.groundedIntoDoublePlay = groundedIntoDoublePlay
        self.errors = errors
        self.average = average
        self.plateAppearanceHomeRuns = plateAppearanceHomeRuns
        self.plateAppearanceWalks = plateAppearanceWalks
        self.plateAppearanceStrikeouts = plateAppearanceStrikeouts
    }

    var battingOrderNumber: String? {
        battingOrder.battingOrderNumber
    }
}

// GameCenterBattingTotals 구조체는 GameCenterBattingTotals 타입의 역할과 값을 정의합니다.
struct GameCenterBattingTotals: Sendable {
    let atBats: String?
    let runs: String?
    let hits: String?
    let runsBattedIn: String?
    let homeRuns: String?
    let walks: String?
    let strikeouts: String?
    let stolenBases: String?
    let average: String?
    let plateAppearanceHomeRuns: String?
    let plateAppearanceWalks: String?
    let plateAppearanceStrikeouts: String?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        atBats: String?,
        runs: String?,
        hits: String?,
        runsBattedIn: String?,
        homeRuns: String?,
        walks: String?,
        strikeouts: String?,
        stolenBases: String? = nil,
        average: String?,
        plateAppearanceHomeRuns: String? = nil,
        plateAppearanceWalks: String? = nil,
        plateAppearanceStrikeouts: String? = nil
    ) {
        self.atBats = atBats
        self.runs = runs
        self.hits = hits
        self.runsBattedIn = runsBattedIn
        self.homeRuns = homeRuns
        self.walks = walks
        self.strikeouts = strikeouts
        self.stolenBases = stolenBases
        self.average = average
        self.plateAppearanceHomeRuns = plateAppearanceHomeRuns
        self.plateAppearanceWalks = plateAppearanceWalks
        self.plateAppearanceStrikeouts = plateAppearanceStrikeouts
    }
}

// GameCenterPitchingSection 구조체는 GameCenterPitchingSection 타입의 역할과 값을 정의합니다.
struct GameCenterPitchingSection: Sendable {
    let lines: [GameCenterPitchingLine]
}

// GameCenterPitchingLine 구조체는 GameCenterPitchingLine 타입의 역할과 값을 정의합니다.
struct GameCenterPitchingLine: Identifiable, Hashable, Sendable {
    let id = UUID()
    let pitchingOrder: String?
    let name: String
    let role: String?
    let result: String?
    let innings: String?
    let battersFaced: String?
    let pitches: String?
    let atBats: String?
    let hitsAllowed: String?
    let walksAllowed: String?
    let hitBatters: String?
    let walksOrHitByPitch: String?
    let strikeouts: String?
    let homeRunsAllowed: String?
    let runsAllowed: String?
    let earnedRuns: String?
    let earnedRunAverage: String?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        pitchingOrder: String? = nil,
        name: String,
        role: String?,
        result: String?,
        innings: String?,
        battersFaced: String? = nil,
        pitches: String?,
        atBats: String? = nil,
        hitsAllowed: String?,
        walksAllowed: String?,
        hitBatters: String?,
        walksOrHitByPitch: String? = nil,
        strikeouts: String?,
        homeRunsAllowed: String?,
        runsAllowed: String?,
        earnedRuns: String?,
        earnedRunAverage: String?
    ) {
        self.pitchingOrder = pitchingOrder
        self.name = name
        self.role = role
        self.result = result
        self.innings = innings
        self.battersFaced = battersFaced
        self.pitches = pitches
        self.atBats = atBats
        self.hitsAllowed = hitsAllowed
        self.walksAllowed = walksAllowed
        self.hitBatters = hitBatters
        self.walksOrHitByPitch = walksOrHitByPitch
        self.strikeouts = strikeouts
        self.homeRunsAllowed = homeRunsAllowed
        self.runsAllowed = runsAllowed
        self.earnedRuns = earnedRuns
        self.earnedRunAverage = earnedRunAverage
    }
}

// GameCenterPreview 구조체는 GameCenterPreview 타입의 역할과 값을 정의합니다.
struct GameCenterPreview: Sendable {
    let probableStarters: GameCenterProbableStarters?
    let awayMatchup: GameCenterMatchupSnapshot?
    let homeMatchup: GameCenterMatchupSnapshot?
}

// GameCenterMatchupSnapshot 구조체는 GameCenterMatchupSnapshot 타입의 역할과 값을 정의합니다.
struct GameCenterMatchupSnapshot: Sendable {
    let teamName: String
    let seasonRecord: String?
    let recentFive: String?
    let teamERA: String?
    let battingAverage: String?
    let runsScored: String?
    let runsAllowed: String?
}

private extension String {
    var battingOrderNumber: String? {
        let digits = trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }
}
