//
//  GameModels.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import Foundation

enum GameSeasonClassification: String, CaseIterable, Codable, Hashable, Sendable {
    case unknown
    case regularSeason = "regular_season"
    case exhibitionPreseason = "exhibition_preseason"
    case postseason

    nonisolated var isRegularSeason: Bool {
        self == .regularSeason
    }

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

enum GameStatus: String, CaseIterable, Codable, Hashable, Sendable {
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

struct RunnerState: Hashable, Codable, Sendable {
    var first: Bool
    var second: Bool
    var third: Bool

    nonisolated static let empty = RunnerState(first: false, second: false, third: false)
}

enum GameEventType: String, Codable, Hashable, Sendable {
    case score
    case pitching
    case keyPlay
    case weather
    case note
}

struct GameEvent: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let type: GameEventType
    let headline: String
    let inningText: String
    let timestamp: Date
}

enum TeamGameResult: Hashable, Sendable {
    case win
    case loss
    case tie
}

struct GameDetail: Identifiable, Hashable, Codable, Sendable {
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

    nonisolated func involves(teamID: String?) -> Bool {
        guard let teamID else { return false }
        return awayTeam.id == teamID || homeTeam.id == teamID
    }

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
            currentPitcherName: currentPitcherName,
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
        return "KBO LIVE\n\(scoreText)\n\(stateText)\n\(venue)"
    }

    nonisolated var hasCompleteFinalScore: Bool {
        status == .final && awayScore != nil && homeScore != nil
    }

    nonisolated var officialGameCenterID: String? {
        providerGameID ?? Self.providerGameID(from: note)
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
        if let officialGameCenterID = Self.providerGameID(from: note) {
            aliases.insert(GameIdentifier.providerKey(officialGameCenterID))
        }
        if let publicGameID = Self.noteValue("public_game_id", from: note) {
            aliases.insert("public:\(publicGameID.lowercased())")
        }
        return aliases
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

    nonisolated private static func providerGameID(from note: String?) -> String? {
        noteValue("provider_game_id", from: note)
    }

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

    nonisolated private static func kstDayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct GameBaseRunners: Hashable, Codable, Sendable {
    let first: String?
    let second: String?
    let third: String?
}

struct GameSummary: Identifiable, Hashable, Sendable {
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
