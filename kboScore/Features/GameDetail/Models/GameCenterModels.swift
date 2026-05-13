//
//  GameCenterModels.swift
//  kboScore
//
//  Created by Codex on 5/13/26.
//

import Foundation

struct GameCenterDetailPayload: Sendable {
    let summary: GameCenterSummary
    let lineScore: GameCenterLineScore?
    let review: GameCenterReview?
    let preview: GameCenterPreview?
}

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

struct GameCenterBaseRunners: Hashable, Sendable {
    let first: String?
    let second: String?
    let third: String?
}

struct GameCenterProbableStarters: Sendable {
    let away: String?
    let home: String?
}

struct GameCenterLineScore: Sendable {
    let inningLabels: [String]
    let awayInnings: [String]
    let homeInnings: [String]
    let awayTotals: GameCenterTeamLineTotals
    let homeTotals: GameCenterTeamLineTotals
}

struct GameCenterTeamLineTotals: Sendable {
    let runs: String?
    let hits: String?
    let errors: String?
    let walks: String?
}

struct GameCenterReview: Sendable {
    let summaryItems: [GameCenterSummaryItem]
    let awayBatting: GameCenterBattingSection
    let homeBatting: GameCenterBattingSection
    let awayPitching: GameCenterPitchingSection
    let homePitching: GameCenterPitchingSection

    var hasDisplayableRecords: Bool {
        awayBatting.lines.isEmpty == false ||
            homeBatting.lines.isEmpty == false ||
            awayPitching.lines.isEmpty == false ||
            homePitching.lines.isEmpty == false ||
            summaryItems.isEmpty == false
    }
}

struct GameCenterKeyStatsComparison: Sendable, Equatable {
    let away: GameCenterTeamKeyStats
    let home: GameCenterTeamKeyStats
}

struct GameCenterTeamKeyStats: Sendable, Equatable {
    let hits: Int
    let homeRuns: Int
    let stolenBases: Int
    let strikeouts: Int
    let doublePlays: Int
    let errors: Int
}

struct GameCenterSummaryItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let value: String
    let values: [String]

    init(title: String, value: String, values: [String]? = nil) {
        self.title = title
        self.value = value
        self.values = values ?? [value]
    }
}

struct GameCenterBattingSection: Sendable {
    let lines: [GameCenterBattingLine]
    let totals: GameCenterBattingTotals?
}

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
    let average: String?
    let plateAppearanceHomeRuns: String?
    let plateAppearanceWalks: String?
    let plateAppearanceStrikeouts: String?

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
        self.average = average
        self.plateAppearanceHomeRuns = plateAppearanceHomeRuns
        self.plateAppearanceWalks = plateAppearanceWalks
        self.plateAppearanceStrikeouts = plateAppearanceStrikeouts
    }

    var battingOrderNumber: String? {
        battingOrder.battingOrderNumber
    }
}

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

struct GameCenterPitchingSection: Sendable {
    let lines: [GameCenterPitchingLine]
}

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

struct GameCenterPreview: Sendable {
    let probableStarters: GameCenterProbableStarters?
    let awayMatchup: GameCenterMatchupSnapshot?
    let homeMatchup: GameCenterMatchupSnapshot?
}

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
