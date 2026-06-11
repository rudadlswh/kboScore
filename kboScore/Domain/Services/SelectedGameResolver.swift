//
//  SelectedGameResolver.swift
//  kboScore
//
//  Created by Codex on 6/10/26.
//

import Foundation

nonisolated struct SelectedGameResolution: Sendable {
    let game: GameDetail
    let priority: Int
    let token: String
    let reason: String
}

nonisolated enum SelectedGameResolver {
    static func match(for gameIdentity: String, in candidates: [GameDetail]) -> SelectedGameResolution? {
        let requestTokens = GameIdentifier.requestedIdentityTokens(from: gameIdentity)
        guard requestTokens.isEmpty == false else { return nil }

        let matches = candidates.compactMap { game -> SelectedGameResolution? in
            guard let match = GameIdentifier.bestMatch(
                requestTokens: requestTokens,
                candidateTokens: game.gameIdentityMatchTokens
            ) else {
                return nil
            }
            return SelectedGameResolution(game: game, priority: match.priority, token: match.token, reason: match.reason)
        }

        guard let bestPriority = matches.map(\.priority).min() else { return nil }
        let bestMatches = matches.filter { $0.priority == bestPriority }
        let publicIDs = Set(bestMatches.compactMap { GameMergeResolver.nonBlank($0.game.publicGameID) })
        if bestMatches.count > 1, publicIDs.count > 1 {
            return nil
        }

        let equivalentCandidates = bestMatches.flatMap {
            GameMergeResolver.equivalentGames(to: $0.game, in: candidates)
        }
        let equivalentPublicIDs = Set(equivalentCandidates.compactMap { GameMergeResolver.nonBlank($0.publicGameID) })
        if equivalentPublicIDs.count > 1 {
            return nil
        }

        let candidatePool = equivalentCandidates.isEmpty ? bestMatches.map(\.game) : equivalentCandidates
        let selected = candidatePool.reduce(nil as GameDetail?) { preferred, game in
            GameMergeResolver.preferredGame(existing: preferred, candidate: game)
        }
        guard let selected else { return nil }
        let reason = bestMatches.first?.reason ?? "unknown"
        let token = bestMatches.first?.token ?? ""
        return SelectedGameResolution(game: selected, priority: bestPriority, token: token, reason: reason)
    }
}
