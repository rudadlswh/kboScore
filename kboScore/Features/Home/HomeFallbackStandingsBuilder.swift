//
//  HomeFallbackStandingsBuilder.swift
//  kboScore
//  기능 설명: 경기 없는 날 홈 화면에 표시할 주간 순위 스냅샷을 생성합니다.
//  오늘 경기와 경기 없는 날의 대체 정보를 홈에서 바로 판단할 수 있도록 표시용 요약을 별도로 구성합니다.
//  월요일 직전 주 요약, 마이팀 경기 우선순위, 빈 일정 상태가 겹칠 수 있어 선택 순서를 명확히 유지합니다.
//  TODO : 홈 요약 정책이 바뀌면 날짜별 스냅샷 테스트를 추가합니다.
//
//  Created by Codex on 5/18/26.
//

import Foundation

// HomeFallbackStandingsBuilder 열거형는 화면이나 도메인 모델에 필요한 값을 조립합니다.
enum HomeFallbackStandingsBuilder {
    // makeSnapshots 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    static func makeSnapshots(
        teams: [Team],
        referenceCompletedGames: [GameDetail],
        seasonGames: [GameDetail],
        probabilitySignalsByTeamID: [String: LocalStandingsProbabilitySignal] = [:],
        previousRankProvider: (Team) -> Int?
    ) -> [TeamStandingsSnapshot] {
        guard referenceCompletedGames.isEmpty == false else { return [] }

        let rankedSnapshots = teams
            .map { team in
                let completedGames = referenceCompletedGames
                    .filter { $0.involves(teamID: team.id) }
                    .sorted { $0.scheduledStart > $1.scheduledStart }
                return StandingsCalculator.makeSnapshot(
                    for: team,
                    completedGames: completedGames,
                    seasonGames: seasonGames,
                    probabilitySignalsByTeamID: probabilitySignalsByTeamID,
                    recentResultsLimit: completedGames.count
                )
            }
            .sorted {
                StandingsSorter.compare($0, $1, previousRankProvider: previousRankProvider)
            }

        return rankedSnapshots.enumerated().map { index, snapshot in
            TeamStandingsSnapshot(
                team: snapshot.team,
                rank: index + 1,
                wins: snapshot.wins,
                losses: snapshot.losses,
                ties: snapshot.ties,
                runsScored: snapshot.runsScored,
                runsAllowed: snapshot.runsAllowed,
                remainingRegularSeasonGames: snapshot.remainingRegularSeasonGames,
                recentResults: snapshot.recentResults,
                unknownClassificationGames: snapshot.unknownClassificationGames,
                virtualUnscheduledRemainingGames: snapshot.virtualUnscheduledRemainingGames,
                rankingResolution: snapshot.rankingResolution,
                rankingResolutionPosition: snapshot.rankingResolutionPosition,
                postseasonQualificationProbability: snapshot.postseasonQualificationProbability,
                postseasonQualificationStatus: snapshot.postseasonQualificationStatus,
                postseasonProbabilityUnavailableReason: snapshot.postseasonProbabilityUnavailableReason,
                precomputedStreakText: snapshot.precomputedStreakText
            )
        }
    }
}
