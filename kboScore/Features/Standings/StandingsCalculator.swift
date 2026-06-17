//
//  StandingsCalculator.swift
//  kboScore
//  기능 설명: 완료 경기 목록으로 팀별 승패, 득실, 최근 흐름, 순위 계산용 스냅샷을 생성합니다.
//  KBO 순위 산정 규칙과 홈 화면 대체 요약에 필요한 계산을 화면 코드에서 분리합니다.
//  완료되지 않은 경기, 취소 경기, 동률, 원정/홈 득실 계산이 순위에 잘못 반영되지 않도록 제한합니다.
//  TODO : 실제 KBO 동률 규정 변경이나 포스트시즌 확률 로직 개선 시 계산 기준을 갱신합니다.
//
//  Created by Codex on 5/18/26.
//

import Foundation

// StandingsCalculator 열거형는 StandingsCalculator 타입의 역할과 값을 정의합니다.
enum StandingsCalculator {
    // makeSnapshot 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated static func makeSnapshot(
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

    // currentStreakText 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func currentStreakText(
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

    // compareCompletedGamesNewestFirst 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    nonisolated private static func compareCompletedGamesNewestFirst(_ lhs: GameDetail, _ rhs: GameDetail) -> Bool {
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

    // noteTimestamp 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func noteTimestamp(_ key: String, from note: String?) -> Date? {
        guard let value = noteValue(key, from: note) else { return nil }
        return KBODateParser.parseTimestamp(value)
    }

    // noteValue 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func noteValue(_ key: String, from note: String?) -> String? {
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

    nonisolated private static var kstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    // canonicalTeamIdentifier 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated private static func canonicalTeamIdentifier(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        return Team.canonicalID(for: raw) ?? raw.lowercased()
    }
}
