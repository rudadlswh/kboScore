//
//  StandingsCalculator.swift
//  kboScore
//
//  Created by Codex on 5/18/26.
//

import Foundation

enum StandingsCalculator {
    static func makeSnapshot(
        for team: Team,
        completedGames: [GameDetail],
        seasonGames: [GameDetail],
        probabilitySignalsByTeamID: [String: LocalStandingsProbabilitySignal] = [:],
        recentResultsLimit: Int = 5
    ) -> TeamStandingsSnapshot {
        let standingsCompletedGames = completedGames
            .filter { $0.isRegularSeason && $0.involves(teamID: team.id) }
            .filter(\.hasCompleteFinalScore)
            .sorted(by: compareCompletedGamesNewestFirst)
        let seasonCompletedGames = seasonGames
            .filter { $0.involves(teamID: team.id) }
            .filter(\.hasCompleteFinalScore)
        let wins = standingsCompletedGames.reduce(into: 0) { partialResult, game in
            if game.finalResult(for: team.id) == .win {
                partialResult += 1
            }
        }
        let losses = standingsCompletedGames.reduce(into: 0) { partialResult, game in
            if game.finalResult(for: team.id) == .loss {
                partialResult += 1
            }
        }
        let ties = standingsCompletedGames.reduce(into: 0) { partialResult, game in
            if game.hasCompleteFinalScore,
               let awayScore = game.awayScore,
               let homeScore = game.homeScore,
               awayScore == homeScore,
               game.involves(teamID: team.id) {
                partialResult += 1
            }
        }
        let runsScored = seasonCompletedGames.reduce(into: 0) { partialResult, game in
            guard let awayScore = game.awayScore,
                  let homeScore = game.homeScore else {
                return
            }

            if game.awayTeam.id == team.id {
                partialResult += awayScore
            } else if game.homeTeam.id == team.id {
                partialResult += homeScore
            }
        }
        let runsAllowed = seasonCompletedGames.reduce(into: 0) { partialResult, game in
            guard let awayScore = game.awayScore,
                  let homeScore = game.homeScore else {
                return
            }

            if game.awayTeam.id == team.id {
                partialResult += homeScore
            } else if game.homeTeam.id == team.id {
                partialResult += awayScore
            }
        }

        let probabilitySignal: LocalStandingsProbabilitySignal? = {
            guard let canonicalID = canonicalTeamIdentifier(team.id) else {
                return nil
            }
            return probabilitySignalsByTeamID[canonicalID]
        }()

        return TeamStandingsSnapshot(
            team: team,
            rank: 0,
            wins: wins,
            losses: losses,
            ties: ties,
            runsScored: runsScored,
            runsAllowed: runsAllowed,
            remainingRegularSeasonGames: max(0, 144 - (wins + losses + ties)),
            recentResults: Array(standingsCompletedGames.compactMap { $0.finalResult(for: team.id) }.prefix(recentResultsLimit)),
            unknownClassificationGames: probabilitySignal?.unknownClassificationGames ?? 0,
            virtualUnscheduledRemainingGames: probabilitySignal?.virtualUnscheduledRemainingGames ?? 0,
            rankingResolution: probabilitySignal?.rankingResolution ?? .resolved,
            rankingResolutionPosition: probabilitySignal?.rankingResolutionPosition,
            postseasonQualificationProbability: probabilitySignal?.postseasonQualificationProbability,
            postseasonQualificationStatus: probabilitySignal?.postseasonQualificationStatus,
            postseasonProbabilityUnavailableReason: probabilitySignal?.postseasonProbabilityUnavailableReason,
            precomputedStreakText: currentStreakText(
                for: team.id,
                completedGames: standingsCompletedGames
            )
        )
    }

    private static func currentStreakText(
        for teamID: String?,
        completedGames: [GameDetail]
    ) -> String? {
        var streakResult: TeamGameResult?
        var streakCount = 0

        for game in completedGames {
            guard let result = game.finalResult(for: teamID) else { continue }
            if result == .tie {
                continue
            }
            if streakResult == nil {
                streakResult = result
                streakCount = 1
                continue
            }
            guard result == streakResult else { break }
            streakCount += 1
        }

        guard let streakResult, streakCount > 0 else { return nil }
        switch streakResult {
        case .win:
            return "\(streakCount)연승"
        case .loss:
            return "\(streakCount)연패"
        case .tie:
            return nil
        }
    }

    private static func compareCompletedGamesNewestFirst(_ lhs: GameDetail, _ rhs: GameDetail) -> Bool {
        let lhsDay = kstCalendar.startOfDay(for: lhs.scheduledStart)
        let rhsDay = kstCalendar.startOfDay(for: rhs.scheduledStart)
        if lhsDay != rhsDay {
            return lhsDay > rhsDay
        }
        if lhs.scheduledStart != rhs.scheduledStart {
            return lhs.scheduledStart > rhs.scheduledStart
        }

        let lhsSourceUpdatedAt = noteTimestamp("source_updated_at", from: lhs.note)
        let rhsSourceUpdatedAt = noteTimestamp("source_updated_at", from: rhs.note)
        if lhsSourceUpdatedAt != rhsSourceUpdatedAt {
            return (lhsSourceUpdatedAt ?? .distantPast) > (rhsSourceUpdatedAt ?? .distantPast)
        }

        let lhsUpdatedAt = noteTimestamp("updated_at", from: lhs.note)
        let rhsUpdatedAt = noteTimestamp("updated_at", from: rhs.note)
        if lhsUpdatedAt != rhsUpdatedAt {
            return (lhsUpdatedAt ?? .distantPast) > (rhsUpdatedAt ?? .distantPast)
        }

        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func noteTimestamp(_ key: String, from note: String?) -> Date? {
        guard let value = noteValue(key, from: note) else { return nil }
        return KBODateParser.parseTimestamp(value)
    }

    private static func noteValue(_ key: String, from note: String?) -> String? {
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

    private static var kstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private static func canonicalTeamIdentifier(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        return Team.canonicalID(for: raw) ?? raw.lowercased()
    }
}
