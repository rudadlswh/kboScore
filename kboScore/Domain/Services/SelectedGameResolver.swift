//
//  SelectedGameResolver.swift
//  kboScore
//  기능 설명: 사용자가 선택한 경기 식별자를 현재 데이터에서 실제 경기로 해석합니다.
//  KBO 경기와 팀 규칙을 화면·저장소와 분리된 값 모델로 표현해 계산과 비교 기준을 일관되게 유지합니다.
//  동명이인, 보류 경기, 취소 경기, 누락 점수처럼 원천 데이터가 불완전한 상황을 고려합니다.
//  TODO : 새 시즌 규칙이나 추가 지표가 생기면 모델 확장 지점을 명확히 분리합니다.
//
//  Created by Codex on 6/10/26.
//

import Foundation

// SelectedGameResolution 구조체는 SelectedGameResolution 타입의 역할과 값을 정의합니다.
nonisolated struct SelectedGameResolution: Sendable {
    let game: GameDetail
    let priority: Int
    let token: String
    let reason: String
}

// SelectedGameResolver 열거형는 입력 상태를 해석해 필요한 결과 값을 결정합니다.
nonisolated enum SelectedGameResolver {
    // match 메서드는 이 타입의 주요 동작을 수행합니다.
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
