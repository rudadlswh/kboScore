//
//  StandingsRowBuilder.swift
//  kboScore
//  기능 설명: 원격 순위 행 데이터를 앱 순위 스냅샷으로 변환합니다.
//  KBO 순위 산정 규칙과 홈 화면 대체 요약에 필요한 계산을 화면 코드에서 분리합니다.
//  완료되지 않은 경기, 취소 경기, 동률, 원정/홈 득실 계산이 순위에 잘못 반영되지 않도록 제한합니다.
//  TODO : 실제 KBO 동률 규정 변경이나 포스트시즌 확률 로직 개선 시 계산 기준을 갱신합니다.
//
//  Created by Codex on 5/18/26.
//

import Foundation

// StandingsRowBuilder 열거형는 화면이나 도메인 모델에 필요한 값을 조립합니다.
enum StandingsRowBuilder {
    // makeSnapshots 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // team 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // recentResults 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // canonicalTeamIdentifier 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private static func canonicalTeamIdentifier(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        return Team.canonicalID(for: raw) ?? raw.lowercased()
    }
}
