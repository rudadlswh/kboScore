//
//  GameMergeResolver.swift
//  kboScore
//  기능 설명: 로컬 경기와 새로 받은 경기 데이터를 병합할 때 보존할 값을 결정합니다.
//  KBO 경기와 팀 규칙을 화면·저장소와 분리된 값 모델로 표현해 계산과 비교 기준을 일관되게 유지합니다.
//  동명이인, 보류 경기, 취소 경기, 누락 점수처럼 원천 데이터가 불완전한 상황을 고려합니다.
//  TODO : 새 시즌 규칙이나 추가 지표가 생기면 모델 확장 지점을 명확히 분리합니다.
//
//  Created by Codex on 6/10/26.
//

import Foundation

// GameMergeResolver 열거형는 입력 상태를 해석해 필요한 결과 값을 결정합니다.
nonisolated enum GameMergeResolver {
    // equivalentGame 메서드는 이 타입의 주요 동작을 수행합니다.
    static func equivalentGame(to game: GameDetail, in candidates: [GameDetail]) -> GameDetail? {
        let lookupAliases = identityAliases(for: game)
        return candidates.reduce(nil) { preferred, candidate in
            guard identityAliases(for: candidate).isDisjoint(with: lookupAliases) == false else {
                return preferred
            }
            return preferredGame(existing: preferred, candidate: candidate)
        }
    }

    // equivalentGames 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // mergeEquivalentGames 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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

    // upsert 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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

    // preferredGame 메서드는 이 타입의 주요 동작을 수행합니다.
    static func preferredGame(existing: GameDetail?, candidate: GameDetail) -> GameDetail {
        guard let existing else { return candidate }
        let stateSource = preferredGameStateSource(existing: existing, candidate: candidate)
        let supplementalSource = stateSource == candidate ? existing : candidate
        let candidateSnapshotBasesAreAuthoritative = stateSource == candidate && candidate.bases != nil
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
                supplemental: candidateSnapshotBasesAreAuthoritative ? nil : supplementalSource.baseRunners,
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

    // nonBlank 메서드는 이 타입의 주요 동작을 수행합니다.
    static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // identityAliases 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func identityAliases(for game: GameDetail) -> Set<String> {
        game.gameIdentityAliases
    }

    // mergedBaseRunners 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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

    // preferredGameStateSource 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func preferredGameStateSource(existing: GameDetail, candidate: GameDetail) -> GameDetail {
        if shouldRecoverUnconfirmedFinal(existing: existing, candidate: candidate) {
            return candidate
        }
        if shouldPreferCancellation(existing: existing, candidate: candidate) {
            return candidate
        }
        if shouldKeepExistingCancellation(existing: existing, candidate: candidate) {
            return existing
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

    // shouldPreferCancellation 메서드는 remote 취소/순연 상태가 오래된 예정/라이브 캐시를 덮도록 합니다.
    private static func shouldPreferCancellation(existing: GameDetail, candidate: GameDetail) -> Bool {
        candidate.status == .cancelled && existing.status != .final
    }

    // shouldKeepExistingCancellation 메서드는 이후 예정 응답이 이미 반영된 취소 상태를 되돌리지 못하게 합니다.
    private static func shouldKeepExistingCancellation(existing: GameDetail, candidate: GameDetail) -> Bool {
        existing.status == .cancelled && candidate.status != .final
    }

    // shouldRecoverUnconfirmedFinal 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
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

    // hasConfirmedFinalStatus 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private static func hasConfirmedFinalStatus(_ game: GameDetail) -> Bool {
        game.status == .final && gameNoteValue("final_confirmed_at", in: game.note) != nil
    }

    // isLiveLike 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private static func isLiveLike(_ game: GameDetail) -> Bool {
        game.status.isLiveLike || hasLiveProgress(game)
    }

    // hasLiveProgress 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private static func hasLiveProgress(_ game: GameDetail) -> Bool {
        nonBlank(game.currentPitcherName) != nil
            || nonBlank(game.currentBatterName) != nil
            || game.balls != nil
            || game.strikes != nil
            || game.outs != nil
    }

    // preferredTeam 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func preferredTeam(_ candidate: Team, fallback: Team) -> Team {
        candidate.id.hasPrefix("unknown-") ? fallback : candidate
    }

    // mergedGameNote 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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

    // freshnessDate 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func freshnessDate(for game: GameDetail) -> Date? {
        [
            gameNoteValue("live_last_checked_at", in: game.note),
            gameNoteValue("updated_at", in: game.note),
            gameNoteValue("source_updated_at", in: game.note)
        ]
        .compactMap(KBODateParser.parseTimestamp)
        .max()
    }

    // gameNoteValue 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func gameNoteValue(_ key: String, in note: String?) -> String? {
        guard let note,
              let range = note.range(of: "\(key)=") else {
            return nil
        }
        let suffix = note[range.upperBound...]
        return suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init)
    }

    // gameStateMergePriority 메서드는 이 타입의 주요 동작을 수행합니다.
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
