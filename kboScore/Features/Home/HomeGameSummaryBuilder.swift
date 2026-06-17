//
//  HomeGameSummaryBuilder.swift
//  kboScore
//  기능 설명: 홈 화면에 표시할 경기 요약 데이터를 생성합니다.
//  오늘 경기와 경기 없는 날의 대체 정보를 홈에서 바로 판단할 수 있도록 표시용 요약을 별도로 구성합니다.
//  월요일 직전 주 요약, 마이팀 경기 우선순위, 빈 일정 상태가 겹칠 수 있어 선택 순서를 명확히 유지합니다.
//  TODO : 홈 요약 정책이 바뀌면 날짜별 스냅샷 테스트를 추가합니다.
//
//  Created by Codex on 5/18/26.
//

import Foundation

// HomeGameSummaryBuilder 열거형는 화면이나 도메인 모델에 필요한 값을 조립합니다.
enum HomeGameSummaryBuilder {
    // makeSummary 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // resolveHomeCardTeam 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
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

    // homeCardProviderTeamIDs 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // sanitizeHomeCardRecentEvent 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // canonicalTeamIdentifier 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private static func canonicalTeamIdentifier(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        return Team.canonicalID(for: raw) ?? raw.lowercased()
    }
}
