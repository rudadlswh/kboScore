//
//  StandingsRowBuilder.swift
//  kboScore
//
//  Created by Codex on 5/18/26.
//

import Foundation

enum StandingsRowBuilder {
    static func makeSnapshots(
        from rows: [TeamRankRow],
        teams: [Team]
    ) -> [TeamStandingsSnapshot] {
        rows.sorted { $0.rank < $1.rank }.map { row in
            TeamStandingsSnapshot(
                team: team(for: row, teams: teams),
                rank: row.rank,
                wins: row.wins,
                losses: row.losses,
                ties: row.draws,
                remainingRegularSeasonGames: max(0, 144 - row.gamesPlayed),
                recentResults: recentResults(for: row),
                precomputedGamesBehind: row.gamesBehind,
                precomputedStreakText: row.streakText
            )
        }
    }

    private static func team(for row: TeamRankRow, teams: [Team]) -> Team {
        if let canonicalID = canonicalTeamIdentifier(row.teamCode),
           let team = teams.first(where: { canonicalTeamIdentifier($0.id) == canonicalID }) {
            return team
        }
        if let canonicalID = canonicalTeamIdentifier(row.teamName),
           let team = teams.first(where: { canonicalTeamIdentifier($0.id) == canonicalID }) {
            return team
        }
        let fallbackID = canonicalTeamIdentifier(row.teamCode) ?? canonicalTeamIdentifier(row.teamName) ?? row.teamID.uuidString
        if let identity = TeamIdentity.catalog[fallbackID] {
            return Team(
                id: fallbackID,
                name: row.teamName,
                shortName: identity.shortLabel,
                englishName: identity.displayName,
                markText: identity.monogram
            )
        }
        return Team(
            id: fallbackID,
            name: row.teamName,
            shortName: Team.displayName(forTeamID: fallbackID, fallback: row.teamName),
            englishName: row.teamName,
            markText: String(row.teamName.prefix(2))
        )
    }

    private static func recentResults(for row: TeamRankRow) -> [TeamGameResult] {
        let result: TeamGameResult?
        switch row.streakType.uppercased() {
        case "WIN":
            result = .win
        case "LOSS":
            result = .loss
        case "DRAW":
            result = .tie
        default:
            result = nil
        }
        guard let result else { return [] }
        return Array(repeating: result, count: max(0, min(row.streakCount, 5)))
    }

    private static func canonicalTeamIdentifier(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        let lowered = raw.lowercased()
        if TeamIdentity.catalog[lowered] != nil {
            return lowered
        }

        if let matched = TeamIdentity.catalog.first(where: { _, identity in
            identity.shortLabel.caseInsensitiveCompare(raw) == .orderedSame ||
            identity.monogram.caseInsensitiveCompare(raw) == .orderedSame ||
            identity.displayName == raw
        })?.key {
            return matched
        }

        return lowered
    }
}
