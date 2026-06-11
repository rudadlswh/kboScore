//
//  GameMergeResolver.swift
//  kboScore
//
//  Created by Codex on 6/10/26.
//

import Foundation

nonisolated enum GameMergeResolver {
    static func equivalentGame(to game: GameDetail, in candidates: [GameDetail]) -> GameDetail? {
        let lookupAliases = identityAliases(for: game)
        return candidates.reduce(nil) { preferred, candidate in
            guard identityAliases(for: candidate).isDisjoint(with: lookupAliases) == false else {
                return preferred
            }
            return preferredGame(existing: preferred, candidate: candidate)
        }
    }

    static func equivalentGames(to game: GameDetail, in candidates: [GameDetail]) -> [GameDetail] {
        var equivalentAliases = identityAliases(for: game)
        var didExpand = true

        while didExpand {
            didExpand = false
            for candidate in candidates {
                let candidateAliases = identityAliases(for: candidate)
                guard equivalentAliases.isDisjoint(with: candidateAliases) == false else { continue }
                let previousCount = equivalentAliases.count
                equivalentAliases.formUnion(candidateAliases)
                didExpand = equivalentAliases.count != previousCount
            }
        }

        return candidates.filter { candidate in
            identityAliases(for: candidate).isDisjoint(with: equivalentAliases) == false
        }
    }

    static func mergeEquivalentGames(_ sourceGames: [GameDetail]) -> [GameDetail] {
        var gamesByMergeKey: [String: GameDetail] = [:]
        var mergeKeyByAlias: [String: String] = [:]

        for candidate in sourceGames {
            let candidateAliases = identityAliases(for: candidate)
            let linkedMergeKeys = Set(candidateAliases.compactMap { mergeKeyByAlias[$0] })
            let mergeKey = linkedMergeKeys.sorted().first ?? candidate.canonicalGameIdentityKey
            var aliasesToRelink = candidateAliases
            var selected = gamesByMergeKey[mergeKey].map {
                preferredGame(existing: $0, candidate: candidate)
            } ?? candidate

            for linkedKey in linkedMergeKeys.sorted() where linkedKey != mergeKey {
                guard let linkedGame = gamesByMergeKey[linkedKey] else { continue }
                aliasesToRelink.formUnion(identityAliases(for: linkedGame))
                selected = preferredGame(existing: selected, candidate: linkedGame)
                gamesByMergeKey[linkedKey] = nil
            }

            gamesByMergeKey[mergeKey] = selected

            let selectedAliases = identityAliases(for: selected)
            for alias in aliasesToRelink.union(selectedAliases) {
                mergeKeyByAlias[alias] = mergeKey
            }
        }

        return Array(gamesByMergeKey.values)
    }

    static func upsert(
        incomingGames: [GameDetail],
        into existingGames: [GameDetail]
    ) -> (games: [GameDetail], inserted: Int, updated: Int, skippedExisting: Int) {
        var updatedGames = existingGames
        var inserted = 0
        var updated = 0
        var skippedExisting = 0

        for candidate in incomingGames {
            let candidateAliases = identityAliases(for: candidate)
            if let existingIndex = updatedGames.firstIndex(where: { existing in
                identityAliases(for: existing).isDisjoint(with: candidateAliases) == false
            }) {
                let existing = updatedGames[existingIndex]
                let selected = preferredGame(existing: existing, candidate: candidate)
                if selected != existing {
                    updatedGames[existingIndex] = selected
                    updated += 1
                } else {
                    skippedExisting += 1
                }
            } else {
                updatedGames.append(candidate)
                inserted += 1
            }
        }

        return (updatedGames, inserted, updated, skippedExisting)
    }

    static func preferredGame(existing: GameDetail?, candidate: GameDetail) -> GameDetail {
        guard let existing else { return candidate }
        let stateSource = preferredGameStateSource(existing: existing, candidate: candidate)
        let supplementalSource = stateSource == candidate ? existing : candidate
        return GameDetail(
            id: existing.id,
            scheduledStart: stateSource.scheduledStart,
            venue: nonBlank(candidate.venue) ?? existing.venue,
            awayTeam: preferredTeam(candidate.awayTeam, fallback: existing.awayTeam),
            homeTeam: preferredTeam(candidate.homeTeam, fallback: existing.homeTeam),
            awayScore: stateSource.awayScore ?? supplementalSource.awayScore,
            homeScore: stateSource.homeScore ?? supplementalSource.homeScore,
            status: stateSource.status,
            seasonClassification: stateSource.seasonClassification == .unknown ? existing.seasonClassification : stateSource.seasonClassification,
            inningText: nonBlank(stateSource.inningText) ?? supplementalSource.inningText,
            bases: stateSource.bases,
            baseRunners: mergedBaseRunners(
                primary: stateSource.baseRunners,
                supplemental: supplementalSource.baseRunners,
                bases: stateSource.bases
            ),
            balls: stateSource.balls,
            strikes: stateSource.strikes,
            outs: stateSource.outs,
            highlightText: nonBlank(candidate.highlightText) ?? existing.highlightText,
            events: candidate.events.isEmpty ? existing.events : candidate.events,
            note: mergedGameNote(existing: existing.note, candidate: candidate.note),
            providerGameID: nonBlank(candidate.providerGameID) ?? existing.providerGameID,
            awayStartingPitcherName: nonBlank(candidate.awayStartingPitcherName) ?? existing.awayStartingPitcherName,
            homeStartingPitcherName: nonBlank(candidate.homeStartingPitcherName) ?? existing.homeStartingPitcherName,
            currentPitcherName: nonBlank(stateSource.currentPitcherName),
            currentBatterName: nonBlank(stateSource.currentBatterName)
        )
    }

    static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func identityAliases(for game: GameDetail) -> Set<String> {
        game.gameIdentityAliases
    }

    private static func mergedBaseRunners(
        primary: GameBaseRunners?,
        supplemental: GameBaseRunners?,
        bases: RunnerState?
    ) -> GameBaseRunners? {
        guard let bases else {
            return primary ?? supplemental
        }
        let first = bases.first ? (nonBlank(primary?.first) ?? nonBlank(supplemental?.first)) : nil
        let second = bases.second ? (nonBlank(primary?.second) ?? nonBlank(supplemental?.second)) : nil
        let third = bases.third ? (nonBlank(primary?.third) ?? nonBlank(supplemental?.third)) : nil
        guard first != nil || second != nil || third != nil else {
            return nil
        }
        return GameBaseRunners(first: first, second: second, third: third)
    }

    private static func preferredGameStateSource(existing: GameDetail, candidate: GameDetail) -> GameDetail {
        if shouldRecoverUnconfirmedFinal(existing: existing, candidate: candidate) {
            return candidate
        }
        let candidatePriority = gameStateMergePriority(candidate)
        let existingPriority = gameStateMergePriority(existing)
        if candidatePriority != existingPriority {
            return candidatePriority > existingPriority ? candidate : existing
        }
        let candidateFreshness = freshnessDate(for: candidate)
        let existingFreshness = freshnessDate(for: existing)
        if let candidateFreshness, let existingFreshness, candidateFreshness != existingFreshness {
            return candidateFreshness > existingFreshness ? candidate : existing
        }
        if candidateFreshness != nil, existingFreshness == nil {
            return candidate
        }
        if candidate.hasCompleteFinalScore != existing.hasCompleteFinalScore {
            return candidate.hasCompleteFinalScore ? candidate : existing
        }
        let candidateHasProvider = candidate.officialGameCenterID != nil
        let existingHasProvider = existing.officialGameCenterID != nil
        if candidateHasProvider != existingHasProvider {
            return candidateHasProvider ? candidate : existing
        }
        return candidate
    }

    private static func shouldRecoverUnconfirmedFinal(existing: GameDetail, candidate: GameDetail) -> Bool {
        guard existing.status == .final,
              hasConfirmedFinalStatus(existing) == false,
              isLiveLike(candidate) else {
            return false
        }
        let candidateFreshness = freshnessDate(for: candidate)
        let existingFreshness = freshnessDate(for: existing)
        if let candidateFreshness, let existingFreshness {
            return candidateFreshness >= existingFreshness
        }
        if candidateFreshness != nil, existingFreshness == nil {
            return true
        }
        return hasLiveProgress(candidate)
    }

    private static func hasConfirmedFinalStatus(_ game: GameDetail) -> Bool {
        game.status == .final && gameNoteValue("final_confirmed_at", in: game.note) != nil
    }

    private static func isLiveLike(_ game: GameDetail) -> Bool {
        game.status.isLiveLike || hasLiveProgress(game)
    }

    private static func hasLiveProgress(_ game: GameDetail) -> Bool {
        nonBlank(game.currentPitcherName) != nil
            || nonBlank(game.currentBatterName) != nil
            || game.balls != nil
            || game.strikes != nil
            || game.outs != nil
    }

    private static func preferredTeam(_ candidate: Team, fallback: Team) -> Team {
        candidate.id.hasPrefix("unknown-") ? fallback : candidate
    }

    private static func mergedGameNote(existing: String?, candidate: String?) -> String? {
        let components = [candidate, existing].compactMap(nonBlank)
        guard components.isEmpty == false else { return nil }

        var seen: Set<String> = []
        let merged = components
            .flatMap { $0.split(separator: " ").map(String.init) }
            .filter { seen.insert($0).inserted }
            .joined(separator: " ")
        return nonBlank(merged)
    }

    private static func freshnessDate(for game: GameDetail) -> Date? {
        [
            gameNoteValue("live_last_checked_at", in: game.note),
            gameNoteValue("updated_at", in: game.note),
            gameNoteValue("source_updated_at", in: game.note)
        ]
        .compactMap(KBODateParser.parseTimestamp)
        .max()
    }

    private static func gameNoteValue(_ key: String, in note: String?) -> String? {
        guard let note,
              let range = note.range(of: "\(key)=") else {
            return nil
        }
        let suffix = note[range.upperBound...]
        return suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init)
    }

    private static func gameStateMergePriority(_ game: GameDetail) -> Int {
        switch game.status {
        case .final, .cancelled:
            return 3
        case .live, .rainDelay:
            return 2
        case .upcoming:
            return 1
        }
    }
}
