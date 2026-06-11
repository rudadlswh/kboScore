//
//  HomeGameSummaryBuilder.swift
//  kboScore
//
//  Created by Codex on 5/18/26.
//

import Foundation

enum HomeGameSummaryBuilder {
    static func makeSummary(
        game: GameDetail,
        teams: [Team],
        favoriteTeamID: String?
    ) -> GameSummary {
        let providerIDs = homeCardProviderTeamIDs(from: game.note)
        let awayTeam = resolveHomeCardTeam(game.awayTeam, fallbackID: providerIDs?.awayID, teams: teams)
        let homeTeam = resolveHomeCardTeam(game.homeTeam, fallbackID: providerIDs?.homeID, teams: teams)
        let recentEvent = sanitizeHomeCardRecentEvent(
            game.highlightText ?? game.note,
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            status: game.status
        )

        return GameSummary(
            id: game.id,
            scheduledStart: game.scheduledStart,
            venue: game.venue,
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: game.awayScore,
            homeScore: game.homeScore,
            status: game.status,
            inningText: game.inningText,
            recentEvent: recentEvent,
            isMyTeamGame: game.involves(teamID: favoriteTeamID),
            awayStartingPitcherName: game.awayStartingPitcherName,
            homeStartingPitcherName: game.homeStartingPitcherName,
            currentPitcherName: game.currentPitcherName,
            currentBatterName: game.currentBatterName,
            bases: game.bases,
            baseRunners: game.baseRunners,
            balls: game.balls,
            strikes: game.strikes,
            outs: game.outs
        )
    }

    private static func resolveHomeCardTeam(_ team: Team, fallbackID: String? = nil, teams: [Team]) -> Team {
        let canonicalID = canonicalTeamIdentifier(team.id) ?? team.id
        let resolvedID: String
        if canonicalID.hasPrefix("unknown"),
           let fallbackID = canonicalTeamIdentifier(fallbackID) {
            resolvedID = fallbackID
        } else {
            resolvedID = canonicalID
        }

        if let resolved = teams.first(where: { canonicalTeamIdentifier($0.id) == resolvedID }) {
            return resolved
        }

        if let identity = TeamIdentity.catalog[resolvedID] {
            return Team(
                id: resolvedID,
                name: identity.displayName,
                shortName: identity.shortLabel,
                englishName: team.englishName,
                markText: identity.monogram
            )
        }

        return Team(
            id: resolvedID,
            name: team.name,
            shortName: team.shortName,
            englishName: team.englishName,
            markText: team.markText
        )
    }

    private static func homeCardProviderTeamIDs(from note: String?) -> (awayID: String, homeID: String)? {
        guard let note else { return nil }
        guard let providerRange = note.range(of: "provider_game_id=") else { return nil }

        let suffix = note[providerRange.upperBound...]
        let rawValue = suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first ?? ""
        let components = rawValue.split(separator: "_").map(String.init)
        guard components.count >= 2 else { return nil }

        let awayRaw = components[components.count - 2]
        let homeRaw = components[components.count - 1]
        guard let awayID = canonicalTeamIdentifier(awayRaw),
              let homeID = canonicalTeamIdentifier(homeRaw) else {
            return nil
        }

        return (awayID: awayID, homeID: homeID)
    }

    private static func sanitizeHomeCardRecentEvent(
        _ text: String?,
        awayTeam: Team,
        homeTeam: Team,
        status: GameStatus
    ) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let lowered = trimmed.lowercased()
        if lowered.contains("provider_game_id=") || lowered.hasPrefix("db_export") {
            return "\(awayTeam.displayName) vs \(homeTeam.displayName) · \(status.title)"
        }
        return trimmed
    }

    private static func canonicalTeamIdentifier(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        return Team.canonicalID(for: raw) ?? raw.lowercased()
    }
}
