//
//  StandingsModels.swift
//  kboScore
//  기능 설명: 순위표 표시와 계산에 사용하는 팀 순위 스냅샷 모델을 정의합니다.
//  KBO 경기와 팀 규칙을 화면·저장소와 분리된 값 모델로 표현해 계산과 비교 기준을 일관되게 유지합니다.
//  동명이인, 보류 경기, 취소 경기, 누락 점수처럼 원천 데이터가 불완전한 상황을 고려합니다.
//  TODO : 새 시즌 규칙이나 추가 지표가 생기면 모델 확장 지점을 명확히 분리합니다.
//
//  Created by Codex on 4/2/26.
//

import Foundation

// TeamRankRow 구조체는 TeamRankRow 타입의 역할과 값을 정의합니다.
nonisolated struct TeamRankRow: Identifiable, Codable, Hashable, Sendable {
    let season: Int
    let teamID: UUID
    let teamCode: String?
    let rank: Int
    let teamName: String
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let draws: Int
    let winningPercentage: Double
    let gamesBehind: Double
    let streakType: String
    let streakCount: Int
    let streakText: String
    let lastGameDate: Date?
    let calculatedAt: Date?
    let updatedAt: Date?
    let createdAt: Date?

    var id: String { "\(season)-\(teamID.uuidString)" }

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case season
        case teamID = "team_id"
        case teamCode = "team_code"
        case rank
        case teamName = "team_name"
        case gamesPlayed = "games_played"
        case wins
        case losses
        case draws
        case winningPercentage = "winning_percentage"
        case gamesBehind = "games_behind"
        case streakType = "streak_type"
        case streakCount = "streak_count"
        case streakText = "streak_text"
        case lastGameDate = "last_game_date"
        case calculatedAt = "calculated_at"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        season: Int,
        teamID: UUID,
        teamCode: String? = nil,
        rank: Int,
        teamName: String,
        gamesPlayed: Int,
        wins: Int,
        losses: Int,
        draws: Int,
        winningPercentage: Double,
        gamesBehind: Double,
        streakType: String,
        streakCount: Int,
        streakText: String,
        lastGameDate: Date? = nil,
        calculatedAt: Date? = nil,
        updatedAt: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.season = season
        self.teamID = teamID
        self.teamCode = teamCode
        self.rank = rank
        self.teamName = teamName
        self.gamesPlayed = gamesPlayed
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.winningPercentage = winningPercentage
        self.gamesBehind = gamesBehind
        self.streakType = streakType
        self.streakCount = streakCount
        self.streakText = streakText
        self.lastGameDate = lastGameDate
        self.calculatedAt = calculatedAt
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        season = try container.decode(Int.self, forKey: .season)
        teamID = try container.decode(UUID.self, forKey: .teamID)
        teamCode = try container.decodeIfPresent(String.self, forKey: .teamCode)
        rank = try container.decode(Int.self, forKey: .rank)
        teamName = try container.decode(String.self, forKey: .teamName)
        gamesPlayed = try container.decode(Int.self, forKey: .gamesPlayed)
        wins = try container.decode(Int.self, forKey: .wins)
        losses = try container.decode(Int.self, forKey: .losses)
        draws = try container.decode(Int.self, forKey: .draws)
        winningPercentage = try container.decodeFlexibleDouble(forKey: .winningPercentage)
        gamesBehind = try container.decodeFlexibleDouble(forKey: .gamesBehind)
        streakType = try container.decode(String.self, forKey: .streakType)
        streakCount = try container.decode(Int.self, forKey: .streakCount)
        streakText = try container.decode(String.self, forKey: .streakText)
        lastGameDate = KBODateParser.parseGameDate(try? container.decodeIfPresent(String.self, forKey: .lastGameDate))
        calculatedAt = (try? container.decodeIfPresent(Date.self, forKey: .calculatedAt)) ??
            KBODateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .calculatedAt))
        updatedAt = (try? container.decodeIfPresent(Date.self, forKey: .updatedAt)) ??
            KBODateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .updatedAt))
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ??
            KBODateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .createdAt))
    }

    // encode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(season, forKey: .season)
        try container.encode(teamID, forKey: .teamID)
        try container.encodeIfPresent(teamCode, forKey: .teamCode)
        try container.encode(rank, forKey: .rank)
        try container.encode(teamName, forKey: .teamName)
        try container.encode(gamesPlayed, forKey: .gamesPlayed)
        try container.encode(wins, forKey: .wins)
        try container.encode(losses, forKey: .losses)
        try container.encode(draws, forKey: .draws)
        try container.encode(winningPercentage, forKey: .winningPercentage)
        try container.encode(gamesBehind, forKey: .gamesBehind)
        try container.encode(streakType, forKey: .streakType)
        try container.encode(streakCount, forKey: .streakCount)
        try container.encode(streakText, forKey: .streakText)
        try container.encodeIfPresent(lastGameDate.map(Self.dateString), forKey: .lastGameDate)
        try container.encodeIfPresent(calculatedAt, forKey: .calculatedAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }

    // dateString 메서드는 이 타입의 주요 동작을 수행합니다.
    private nonisolated static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private extension KeyedDecodingContainer {
    // decodeFlexibleDouble 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func decodeFlexibleDouble(forKey key: Key) throws -> Double {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key),
           let double = Double(value) {
            return double
        }
        return try Double(decode(Int.self, forKey: key))
    }
}

// StandingsRankingResolution 열거형는 StandingsRankingResolution 타입의 역할과 값을 정의합니다.
nonisolated enum StandingsRankingResolution: String, Codable, Hashable, Sendable {
    case resolved
    case tiebreakGameRequired = "tiebreak_game_required"
}

// PostseasonProbabilityUnavailableReason 열거형는 PostseasonProbabilityUnavailableReason 타입의 역할과 값을 정의합니다.
nonisolated enum PostseasonProbabilityUnavailableReason: String, Codable, Hashable, Sendable {
    case unknownClassificationGames = "unknown_classification_games"
    case incompleteRegularSeasonSchedule = "incomplete_regular_season_schedule"
    case insufficientCompletedRegularSeasonGames = "insufficient_completed_regular_season_games"
    case seasonProgressBelowThreshold = "season_progress_below_threshold"

    var displayText: String {
        switch self {
        case .unknownClassificationGames:
            "분류 미확정 경기로 산출 불가"
        case .incompleteRegularSeasonSchedule:
            "남은 일정 데이터가 부족해 산출 불가"
        case .insufficientCompletedRegularSeasonGames:
            "정규시즌 표본 부족"
        case .seasonProgressBelowThreshold:
            "정규시즌 30% 이후 산출"
        }
    }
}

// PostseasonQualificationStatus 열거형는 처리 단계나 경기 상태를 구분합니다.
nonisolated enum PostseasonQualificationStatus: String, Codable, Hashable, Sendable {
    case clinched
    case eliminated
}

// StandingsMetrics 열거형는 StandingsMetrics 타입의 역할과 값을 정의합니다.
nonisolated enum StandingsMetrics {
    nonisolated static let pythagoreanExponent = 1.83
    nonisolated static let postseasonQualifierCount = 5
    nonisolated static let homeFieldAdvantageMultiplier = 1.02
    nonisolated static let awayFieldAdjustmentMultiplier = 0.98
    nonisolated static let postseasonStrengthCredibilityGames = 88.0
    nonisolated static let postseasonStrengthOfScheduleAdjustment = 0.12
    nonisolated static let postseasonStrengthLogitNoiseSigma = 0.20
    nonisolated static let postseasonPriorRankStrengthSpread = 0.028
    nonisolated static let postseasonStrengthFloor = 0.001
    nonisolated static let postseasonStrengthCeiling = 0.999
    nonisolated static let postseasonDisplayFloor = 0.001
    nonisolated static let postseasonDisplayCeiling = 0.999
    nonisolated static let postseasonSimulationPseudoCount = 1.0
    nonisolated static let postseasonHomeFieldLogitAdjustment = log(homeFieldAdvantageMultiplier / awayFieldAdjustmentMultiplier)
    nonisolated static let defaultPostseasonSimulationCount: Int = {
#if DEBUG
        4_000
#else
        10_000
#endif
    }()

    // pythagoreanWinningPercentage 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func pythagoreanWinningPercentage(runsScored: Int, runsAllowed: Int) -> Double {
        let scored = max(0, Double(runsScored))
        let allowed = max(0, Double(runsAllowed))

        guard scored > 0 || allowed > 0 else {
            return 0.5
        }

        let scoredPower = pow(scored, pythagoreanExponent)
        let allowedPower = pow(allowed, pythagoreanExponent)
        let denominator = scoredPower + allowedPower
        guard denominator.isFinite, denominator > 0 else {
            return 0.5
        }

        let winningPercentage = scoredPower / denominator
        guard winningPercentage.isFinite else {
            return 0.5
        }
        return winningPercentage
    }
}

// TeamStandingsSnapshot 구조체는 TeamStandingsSnapshot 타입의 역할과 값을 정의합니다.
nonisolated struct TeamStandingsSnapshot: Identifiable, Hashable, Sendable {
    let team: Team
    let rank: Int
    let wins: Int
    let losses: Int
    let ties: Int
    let runsScored: Int?
    let runsAllowed: Int?
    let remainingRegularSeasonGames: Int
    let recentResults: [TeamGameResult]
    let unknownClassificationGames: Int
    let virtualUnscheduledRemainingGames: Int
    let rankingResolution: StandingsRankingResolution
    let rankingResolutionPosition: Int?
    let postseasonQualificationProbability: Double?
    let postseasonQualificationStatus: PostseasonQualificationStatus?
    let postseasonProbabilityUnavailableReason: PostseasonProbabilityUnavailableReason?
    let precomputedGamesBehind: Double?
    let precomputedStreakText: String?
    let preGameRank: Int?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        team: Team,
        rank: Int,
        wins: Int,
        losses: Int,
        ties: Int,
        runsScored: Int? = nil,
        runsAllowed: Int? = nil,
        remainingRegularSeasonGames: Int,
        recentResults: [TeamGameResult],
        unknownClassificationGames: Int = 0,
        virtualUnscheduledRemainingGames: Int = 0,
        rankingResolution: StandingsRankingResolution = .resolved,
        rankingResolutionPosition: Int? = nil,
        postseasonQualificationProbability: Double? = nil,
        postseasonQualificationStatus: PostseasonQualificationStatus? = nil,
        postseasonProbabilityUnavailableReason: PostseasonProbabilityUnavailableReason? = nil,
        precomputedGamesBehind: Double? = nil,
        precomputedStreakText: String? = nil,
        preGameRank: Int? = nil
    ) {
        self.team = team
        self.rank = rank
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.runsScored = runsScored
        self.runsAllowed = runsAllowed
        self.remainingRegularSeasonGames = remainingRegularSeasonGames
        self.recentResults = recentResults
        self.unknownClassificationGames = unknownClassificationGames
        self.virtualUnscheduledRemainingGames = virtualUnscheduledRemainingGames
        self.rankingResolution = rankingResolution
        self.rankingResolutionPosition = rankingResolutionPosition
        self.postseasonQualificationProbability = postseasonQualificationProbability
        self.postseasonQualificationStatus = postseasonQualificationStatus
        self.postseasonProbabilityUnavailableReason = postseasonProbabilityUnavailableReason
        self.precomputedGamesBehind = precomputedGamesBehind
        self.precomputedStreakText = precomputedStreakText
        self.preGameRank = preGameRank
    }

    // withPreGameRank 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated func withPreGameRank(_ preGameRank: Int?) -> TeamStandingsSnapshot {
        TeamStandingsSnapshot(
            team: team,
            rank: rank,
            wins: wins,
            losses: losses,
            ties: ties,
            runsScored: runsScored,
            runsAllowed: runsAllowed,
            remainingRegularSeasonGames: remainingRegularSeasonGames,
            recentResults: recentResults,
            unknownClassificationGames: unknownClassificationGames,
            virtualUnscheduledRemainingGames: virtualUnscheduledRemainingGames,
            rankingResolution: rankingResolution,
            rankingResolutionPosition: rankingResolutionPosition,
            postseasonQualificationProbability: postseasonQualificationProbability,
            postseasonQualificationStatus: postseasonQualificationStatus,
            postseasonProbabilityUnavailableReason: postseasonProbabilityUnavailableReason,
            precomputedGamesBehind: precomputedGamesBehind,
            precomputedStreakText: precomputedStreakText,
            preGameRank: preGameRank
        )
    }

    var id: String { team.id }

    var rankMovement: RankingMovement {
        StandingsRankMovementResolver.movement(currentRank: rank, preGameRank: preGameRank)
    }

    var gamesPlayed: Int {
        wins + losses + ties
    }

    var winPercentage: Double? {
        let decisions = wins + losses
        guard decisions > 0 else { return nil }
        return Double(wins) / Double(decisions)
    }

    var winPercentageText: String {
        guard let winPercentage else { return "---" }
        return String(format: "%.3f", winPercentage)
    }

    var pythagoreanWinningPercentage: Double? {
        guard let runsScored, let runsAllowed else { return nil }
        return StandingsMetrics.pythagoreanWinningPercentage(
            runsScored: runsScored,
            runsAllowed: runsAllowed
        )
    }

    var pythagoreanWinningPercentageText: String {
        guard let pythagoreanWinningPercentage else { return "---" }
        return String(format: "%.3f", pythagoreanWinningPercentage)
    }

    var recordText: String {
        "\(wins)승 \(losses)패 \(ties)무"
    }

    var recentResultsText: String {
        guard recentResults.isEmpty == false else { return "기록 없음" }
        return recentResults.map(\.shortLabel).joined(separator: " ")
    }

    var recentResultsMetricTitle: String {
        guard recentResults.isEmpty == false else { return "최근" }
        return "최근 \(recentResults.count)"
    }

    var currentStreakText: String {
        if let precomputedStreakText,
           precomputedStreakText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return precomputedStreakText
        }
        guard let firstResult = recentResults.first else { return "-" }

        var count = 0
        for result in recentResults {
            guard result == firstResult else { break }
            count += 1
        }

        return "\(count)\(firstResult.shortLabel)"
    }

    var currentWinningStreakCount: Int {
        var streak = 0
        for result in recentResults {
            guard result == .win else { break }
            streak += 1
        }
        return streak
    }

    var showsWinningStreakFire: Bool {
        currentWinningStreakCount >= 3
    }

    var hasPostseasonProbabilitySignal: Bool {
        postseasonQualificationProbability != nil || postseasonProbabilityUnavailableReason != nil
    }

    var shouldShowPostseasonProbability: Bool {
        postseasonQualificationProbability != nil || postseasonProbabilityUnavailableReason != nil
    }

    var postseasonQualificationText: String? {
        guard shouldShowPostseasonProbability else { return nil }
        if postseasonQualificationStatus == .clinched {
            return "100.0%"
        }
        if postseasonQualificationStatus == .eliminated {
            return "0.0%"
        }
        if let postseasonQualificationProbability {
            let displayProbability: Double
            if remainingRegularSeasonGames == 0 {
                displayProbability = min(max(postseasonQualificationProbability, 0), 1)
            } else {
                displayProbability = min(
                    max(postseasonQualificationProbability, StandingsMetrics.postseasonDisplayFloor),
                    StandingsMetrics.postseasonDisplayCeiling
                )
            }
            return String(format: "%.1f%%", displayProbability * 100)
        }
        if postseasonProbabilityUnavailableReason != nil {
            return "산출 불가"
        }
        return nil
    }

    var visiblePostseasonProbabilityUnavailableReason: PostseasonProbabilityUnavailableReason? {
        guard shouldShowPostseasonProbability else { return nil }
        return postseasonProbabilityUnavailableReason
    }

    var postseasonProbabilityEstimateText: String? {
        guard postseasonQualificationProbability != nil,
              virtualUnscheduledRemainingGames > 0 else {
            return nil
        }
        return "공식 미편성 \(virtualUnscheduledRemainingGames)경기 포함 추정치"
    }
}

// StandingsRowRenderIdentity 구조체는 StandingsRowRenderIdentity 타입의 역할과 값을 정의합니다.
nonisolated struct StandingsRowRenderIdentity: Hashable, Sendable {
    let teamID: String
    let rank: Int
    let preGameRank: Int?
    let movementDisplayText: String

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(snapshot: TeamStandingsSnapshot) {
        self.teamID = snapshot.team.id
        self.rank = snapshot.rank
        self.preGameRank = snapshot.preGameRank
        self.movementDisplayText = snapshot.rankMovement.displayText
    }
}

extension TeamGameResult {
    nonisolated var shortLabel: String {
        switch self {
        case .win:
            "승"
        case .loss:
            "패"
        case .tie:
            "무"
        }
    }
}

// LocalStandingsProbabilitySignal 구조체는 LocalStandingsProbabilitySignal 타입의 역할과 값을 정의합니다.
struct LocalStandingsProbabilitySignal: Hashable, Sendable {
    let unknownClassificationGames: Int
    let virtualUnscheduledRemainingGames: Int
    let rankingResolution: StandingsRankingResolution
    let rankingResolutionPosition: Int?
    let postseasonQualificationProbability: Double?
    let postseasonQualificationStatus: PostseasonQualificationStatus?
    let postseasonProbabilityUnavailableReason: PostseasonProbabilityUnavailableReason?
}

// Uses only local regular-season games. Unknown-classification rows still make
// the result unavailable, but officially unscheduled season deficits are added
// as simulation-only neutral games. These virtual games are never persisted or
// exposed as scheduled games.
// LocalPostseasonQualificationCalculator 구조체는 LocalPostseasonQualificationCalculator 타입의 역할과 값을 정의합니다.
struct LocalPostseasonQualificationCalculator: Sendable {
    nonisolated private static let fallbackPreviousRegularSeasonRankByTeamID: [String: Int] = [
        "lg": 1,
        "hanwha": 2,
        "ssg": 3,
        "samsung": 4,
        "nc": 5,
        "kt": 6,
        "lotte": 7,
        "kia": 8,
        "doosan": 9,
        "kiwoom": 10
    ]

    let regularSeasonLength: Int
    let postseasonQualifierCount: Int
    let simulationCount: Int
    let minimumCompletedGamesPerTeam: Int

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        regularSeasonLength: Int = 144,
        postseasonQualifierCount: Int = StandingsMetrics.postseasonQualifierCount,
        simulationCount: Int = StandingsMetrics.defaultPostseasonSimulationCount,
        minimumCompletedGamesPerTeam: Int? = nil
    ) {
        self.regularSeasonLength = regularSeasonLength
        self.postseasonQualifierCount = postseasonQualifierCount
        self.simulationCount = simulationCount
        self.minimumCompletedGamesPerTeam = minimumCompletedGamesPerTeam ?? Int((Double(regularSeasonLength) * 0.3).rounded(.up))
    }

    // makeSignals 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated func makeSignals(
        teams: [Team],
        games: [GameDetail]
    ) -> [String: LocalStandingsProbabilitySignal] {
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { (Self.canonicalTeamIdentifier($0.id), $0) })
        let completedRegularSeasonGames = games.filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
        let remainingRegularSeasonGames = games
            .filter { $0.isRegularSeason && !$0.hasCompleteFinalScore }
            .map(_SimulationGame.real)
        let virtualRemainingGames = virtualRemainingGames(teams: teams, games: games)
        let simulationRemainingGames = remainingRegularSeasonGames + virtualRemainingGames
        let virtualUnscheduledCounts = remainingRegularSeasonGameCountsByTeamID(
            teams: teams,
            games: virtualRemainingGames
        )
        let unknownClassificationCounts = unknownClassificationCountsByTeamID(teams: teams, games: games)
        let rankingSignals = currentRankingSignals(teams: teams, games: completedRegularSeasonGames)
        if unknownClassificationCounts.values.contains(where: { $0 > 0 }) {
            return makeUnavailableSignals(
                teams: teams,
                rankingSignals: rankingSignals,
                unknownClassificationCounts: unknownClassificationCounts,
                reason: .unknownClassificationGames
            )
        }

        guard completedRegularSeasonGames.isEmpty == false else {
            return makeUnavailableSignals(
                teams: teams,
                rankingSignals: rankingSignals,
                unknownClassificationCounts: unknownClassificationCounts,
                reason: .insufficientCompletedRegularSeasonGames
            )
        }

        let records = currentRecords(teams: teams, games: completedRegularSeasonGames)
        let qualificationStatuses = qualificationStatuses(
            teams: teams,
            currentRecords: records,
            remainingGames: simulationRemainingGames
        )
        let probabilities = qualificationProbabilities(
            teams: teams,
            teamsByID: teamsByID,
            currentRecords: records,
            completedGames: completedRegularSeasonGames,
            remainingGames: simulationRemainingGames,
            qualificationStatuses: qualificationStatuses
        )

        return teams.reduce(into: [:]) { partialResult, team in
            let teamID = Self.canonicalTeamIdentifier(team.id)
            let rankingSignal = rankingSignals[teamID]
            partialResult[teamID] = LocalStandingsProbabilitySignal(
                unknownClassificationGames: unknownClassificationCounts[teamID, default: 0],
                virtualUnscheduledRemainingGames: virtualUnscheduledCounts[teamID, default: 0],
                rankingResolution: rankingSignal?.rankingResolution ?? .resolved,
                rankingResolutionPosition: rankingSignal?.rankingResolutionPosition,
                postseasonQualificationProbability: probabilities[teamID],
                postseasonQualificationStatus: qualificationStatuses[teamID],
                postseasonProbabilityUnavailableReason: nil
            )
        }
    }

    // qualificationProbabilities 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func qualificationProbabilities(
        teams: [Team],
        teamsByID: [String: Team],
        currentRecords: [String: _ProbabilityRecord],
        completedGames: [GameDetail],
        remainingGames: [_SimulationGame],
        qualificationStatuses: [String: PostseasonQualificationStatus]
    ) -> [String: Double] {
        guard remainingGames.isEmpty == false else {
            return qualificationShares(for: Array(currentRecords.values))
        }

        let strengths = strengthByTeamID(
            teams: teams,
            currentRecords: currentRecords,
            completedGames: completedGames
        )
        var qualificationTotals = Dictionary(uniqueKeysWithValues: teams.map { (Self.canonicalTeamIdentifier($0.id), 0.0) })
        var generator = SplitMix64(state: deterministicSeed(teams: teams, completedGames: completedGames, remainingGames: remainingGames))

        for _ in 0..<simulationCount {
            var simulatedRecords = currentRecords
            var simulatedStrengths: [String: Double] = [:]
            for (teamID, strength) in strengths {
                simulatedStrengths[teamID] = simulatedStrength(from: strength, generator: &generator)
            }

            for game in remainingGames {
                let awayID = game.awayTeamID
                let homeID = game.homeTeamID
                guard var awayRecord = simulatedRecords[awayID],
                      var homeRecord = simulatedRecords[homeID],
                      teamsByID[awayID] != nil,
                      teamsByID[homeID] != nil else {
                    continue
                }

                let awayStrength = simulatedStrengths[awayID] ?? 0.5
                let homeStrength = simulatedStrengths[homeID] ?? 0.5
                let awayWinProbability = matchupWinProbability(
                    awayStrength: awayStrength,
                    homeStrength: homeStrength,
                    isNeutralSite: game.isNeutralSite
                )

                if generator.nextUnitInterval() < awayWinProbability {
                    awayRecord.wins += 1
                    homeRecord.losses += 1
                } else {
                    awayRecord.losses += 1
                    homeRecord.wins += 1
                }

                simulatedRecords[awayID] = awayRecord
                simulatedRecords[homeID] = homeRecord
            }

            let shares = qualificationShares(for: Array(simulatedRecords.values))
            for (teamID, share) in shares {
                qualificationTotals[teamID, default: 0] += share
            }
        }

        let posteriorDenominator = Double(simulationCount) + (StandingsMetrics.postseasonSimulationPseudoCount * 2)
        var probabilities = qualificationTotals.mapValues {
            ($0 + StandingsMetrics.postseasonSimulationPseudoCount) / posteriorDenominator
        }
        for (teamID, status) in qualificationStatuses {
            switch status {
            case .clinched:
                probabilities[teamID] = 1
            case .eliminated:
                probabilities[teamID] = 0
            }
        }
        return probabilities
    }

    // makeUnavailableSignals 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated private func makeUnavailableSignals(
        teams: [Team],
        rankingSignals: [String: LocalStandingsProbabilitySignal],
        unknownClassificationCounts: [String: Int],
        reason: PostseasonProbabilityUnavailableReason
    ) -> [String: LocalStandingsProbabilitySignal] {
        teams.reduce(into: [:]) { partialResult, team in
            let teamID = Self.canonicalTeamIdentifier(team.id)
            let rankingSignal = rankingSignals[teamID]
            partialResult[teamID] = LocalStandingsProbabilitySignal(
                unknownClassificationGames: unknownClassificationCounts[teamID, default: 0],
                virtualUnscheduledRemainingGames: 0,
                rankingResolution: rankingSignal?.rankingResolution ?? .resolved,
                rankingResolutionPosition: rankingSignal?.rankingResolutionPosition,
                postseasonQualificationProbability: nil,
                postseasonQualificationStatus: nil,
                postseasonProbabilityUnavailableReason: reason
            )
        }
    }

    // currentRankingSignals 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func currentRankingSignals(
        teams: [Team],
        games: [GameDetail]
    ) -> [String: LocalStandingsProbabilitySignal] {
        let groupedRecords = groupedRecordsByWinPercentage(for: Array(currentRecords(teams: teams, games: games).values))
        var signals: [String: LocalStandingsProbabilitySignal] = [:]
        var currentRank = 1

        for group in groupedRecords {
            let requiresTiebreak = group.count == 2 && (currentRank == 1 || currentRank == postseasonQualifierCount)
            for record in group {
                signals[record.teamID] = LocalStandingsProbabilitySignal(
                    unknownClassificationGames: 0,
                    virtualUnscheduledRemainingGames: 0,
                    rankingResolution: requiresTiebreak ? .tiebreakGameRequired : .resolved,
                    rankingResolutionPosition: requiresTiebreak ? currentRank : nil,
                    postseasonQualificationProbability: nil,
                    postseasonQualificationStatus: nil,
                    postseasonProbabilityUnavailableReason: nil
                )
            }
            currentRank += group.count
        }

        return signals
    }

    // currentRecords 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func currentRecords(
        teams: [Team],
        games: [GameDetail]
    ) -> [String: _ProbabilityRecord] {
        var records = Dictionary(uniqueKeysWithValues: teams.map {
            (Self.canonicalTeamIdentifier($0.id), _ProbabilityRecord(teamID: Self.canonicalTeamIdentifier($0.id)))
        })

        for game in games {
            let awayID = Self.canonicalTeamIdentifier(game.awayTeam.id)
            let homeID = Self.canonicalTeamIdentifier(game.homeTeam.id)
            guard var awayRecord = records[awayID],
                  var homeRecord = records[homeID],
                  let awayScore = game.awayScore,
                  let homeScore = game.homeScore else {
                continue
            }

            if awayScore == homeScore {
                awayRecord.ties += 1
                homeRecord.ties += 1
            } else if awayScore > homeScore {
                awayRecord.wins += 1
                homeRecord.losses += 1
            } else {
                awayRecord.losses += 1
                homeRecord.wins += 1
            }

            records[awayID] = awayRecord
            records[homeID] = homeRecord
        }

        return records
    }

    // groupedRecordsByWinPercentage 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    nonisolated private func groupedRecordsByWinPercentage(
        for records: [_ProbabilityRecord]
    ) -> [[_ProbabilityRecord]] {
        let orderedRecords = records.sorted(by: recordSortComparator)
        var groups: [[_ProbabilityRecord]] = []

        for record in orderedRecords {
            if let last = groups.last?.first, hasSameWinPercentage(record, last) {
                groups[groups.count - 1].append(record)
            } else {
                groups.append([record])
            }
        }

        return groups
    }

    // qualificationShares 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func qualificationShares(for records: [_ProbabilityRecord]) -> [String: Double] {
        let groups = groupedRecordsByWinPercentage(for: records)
        var shares: [String: Double] = [:]
        var currentRank = 1

        for group in groups {
            let groupEndRank = currentRank + group.count - 1
            let share: Double
            if groupEndRank <= postseasonQualifierCount {
                share = 1
            } else if currentRank > postseasonQualifierCount {
                share = 0
            } else if group.count == 2 && currentRank == postseasonQualifierCount {
                // The local model approximates a deciding cutoff-position tiebreak as 50/50.
                share = 0.5
            } else {
                let remainingSpots = max(0, postseasonQualifierCount - (currentRank - 1))
                share = Double(remainingSpots) / Double(group.count)
            }

            for record in group {
                shares[record.teamID] = share
            }
            currentRank += group.count
        }

        return shares
    }

    // completedRegularSeasonGameCountsByTeamID 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func completedRegularSeasonGameCountsByTeamID(
        teams: [Team],
        games: [GameDetail]
    ) -> [String: Int] {
        var counts = Dictionary(uniqueKeysWithValues: teams.map { (Self.canonicalTeamIdentifier($0.id), 0) })
        for game in games {
            counts[Self.canonicalTeamIdentifier(game.awayTeam.id), default: 0] += 1
            counts[Self.canonicalTeamIdentifier(game.homeTeam.id), default: 0] += 1
        }
        return counts
    }

    // virtualRemainingGames 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func virtualRemainingGames(
        teams: [Team],
        games: [GameDetail]
    ) -> [_SimulationGame] {
        let teamIDs = teams
            .map { Self.canonicalTeamIdentifier($0.id) }
            .sorted()
        guard teamIDs.count > 1 else { return [] }

        let targetPairGameCount = regularSeasonLength / max(1, teamIDs.count - 1)
        guard targetPairGameCount > 0 else { return [] }

        var pairCounts: [String: Int] = [:]
        var teamGameCounts = Dictionary(uniqueKeysWithValues: teamIDs.map { ($0, 0) })

        for game in games where game.isRegularSeason {
            let awayID = Self.canonicalTeamIdentifier(game.awayTeam.id)
            let homeID = Self.canonicalTeamIdentifier(game.homeTeam.id)
            guard teamGameCounts[awayID] != nil,
                  teamGameCounts[homeID] != nil,
                  awayID != homeID else {
                continue
            }

            pairCounts[teamPairKey(awayID, homeID), default: 0] += 1
            teamGameCounts[awayID, default: 0] += 1
            teamGameCounts[homeID, default: 0] += 1
        }

        if teamGameCounts.values.allSatisfy({ $0 >= regularSeasonLength }) {
            return []
        }

        var remainingSlotsByTeamID = teamGameCounts.mapValues {
            max(0, regularSeasonLength - $0)
        }
        var virtualGames: [_SimulationGame] = []

        for firstIndex in teamIDs.indices {
            for secondIndex in teamIDs.index(after: firstIndex)..<teamIDs.endIndex {
                let firstTeamID = teamIDs[firstIndex]
                let secondTeamID = teamIDs[secondIndex]
                let pair = teamPairKey(firstTeamID, secondTeamID)
                var deficit = max(0, targetPairGameCount - pairCounts[pair, default: 0])
                var virtualIndex = 0

                while deficit > 0,
                      remainingSlotsByTeamID[firstTeamID, default: 0] > 0,
                      remainingSlotsByTeamID[secondTeamID, default: 0] > 0 {
                    virtualGames.append(
                        _SimulationGame(
                            awayTeamID: firstTeamID,
                            homeTeamID: secondTeamID,
                            isNeutralSite: true,
                            seedKey: "virtual:\(firstTeamID):\(secondTeamID):\(virtualIndex)"
                        )
                    )
                    remainingSlotsByTeamID[firstTeamID, default: 0] -= 1
                    remainingSlotsByTeamID[secondTeamID, default: 0] -= 1
                    deficit -= 1
                    virtualIndex += 1
                }
            }
        }

        return virtualGames
    }

    // unknownClassificationCountsByTeamID 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func unknownClassificationCountsByTeamID(
        teams: [Team],
        games: [GameDetail]
    ) -> [String: Int] {
        var counts = Dictionary(uniqueKeysWithValues: teams.map { (Self.canonicalTeamIdentifier($0.id), 0) })
        for game in games where game.seasonClassification == .unknown {
            counts[Self.canonicalTeamIdentifier(game.awayTeam.id), default: 0] += 1
            counts[Self.canonicalTeamIdentifier(game.homeTeam.id), default: 0] += 1
        }
        return counts
    }

    // qualificationStatuses 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func qualificationStatuses(
        teams: [Team],
        currentRecords: [String: _ProbabilityRecord],
        remainingGames: [_SimulationGame]
    ) -> [String: PostseasonQualificationStatus] {
        let remainingGamesByTeamID = remainingRegularSeasonGameCountsByTeamID(
            teams: teams,
            games: remainingGames
        )
        let teamIDs = teams.map { Self.canonicalTeamIdentifier($0.id) }

        return teamIDs.reduce(into: [:]) { partialResult, teamID in
            guard let teamRecord = currentRecords[teamID] else { return }
            let teamMinimum = minimumPossibleWinPercentage(
                for: teamRecord,
                remainingGames: remainingGamesByTeamID[teamID, default: 0]
            )
            let teamMaximum = maximumPossibleWinPercentage(
                for: teamRecord,
                remainingGames: remainingGamesByTeamID[teamID, default: 0]
            )

            let otherMaximums = teamIDs
                .filter { $0 != teamID }
                .compactMap { otherID -> Double? in
                    guard let otherRecord = currentRecords[otherID] else { return nil }
                    return maximumPossibleWinPercentage(
                        for: otherRecord,
                        remainingGames: remainingGamesByTeamID[otherID, default: 0]
                    )
                }
                .sorted(by: >)

            if otherMaximums.count < postseasonQualifierCount {
                partialResult[teamID] = .clinched
                return
            }

            if teamMinimum > otherMaximums[postseasonQualifierCount - 1] {
                partialResult[teamID] = .clinched
                return
            }

            let otherMinimums = teamIDs
                .filter { $0 != teamID }
                .compactMap { otherID -> Double? in
                    guard let otherRecord = currentRecords[otherID] else { return nil }
                    return minimumPossibleWinPercentage(
                        for: otherRecord,
                        remainingGames: remainingGamesByTeamID[otherID, default: 0]
                    )
                }
                .sorted(by: >)

            guard otherMinimums.count >= postseasonQualifierCount else { return }
            if teamMaximum < otherMinimums[postseasonQualifierCount - 1] {
                partialResult[teamID] = .eliminated
            }
        }
    }

    // strengthByTeamID 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func strengthByTeamID(
        teams: [Team],
        currentRecords: [String: _ProbabilityRecord],
        completedGames: [GameDetail]
    ) -> [String: Double] {
        var aggregateByTeamID = Dictionary(uniqueKeysWithValues: teams.map {
            (Self.canonicalTeamIdentifier($0.id), _ScoringAggregate())
        })

        for game in completedGames {
            let awayID = Self.canonicalTeamIdentifier(game.awayTeam.id)
            let homeID = Self.canonicalTeamIdentifier(game.homeTeam.id)
            guard let awayScore = game.awayScore,
                  let homeScore = game.homeScore else {
                continue
            }

            aggregateByTeamID[awayID, default: _ScoringAggregate()].record(scored: awayScore, allowed: homeScore)
            aggregateByTeamID[homeID, default: _ScoringAggregate()].record(scored: homeScore, allowed: awayScore)
        }

        let priorStrengths: [String: Double] = Dictionary(uniqueKeysWithValues: teams.map { team in
            let teamID = Self.canonicalTeamIdentifier(team.id)
            return (teamID, priorStrength(for: team, teamCount: teams.count))
        })
        let observedStrengths = aggregateByTeamID.mapValues { aggregate in
            StandingsMetrics.pythagoreanWinningPercentage(
                runsScored: aggregate.runsScored,
                runsAllowed: aggregate.runsAllowed
            )
        }
        let blendedStrengths = teams.reduce(into: [String: Double]()) { partialResult, team in
            let teamID = Self.canonicalTeamIdentifier(team.id)
            let priorStrength = priorStrengths[teamID] ?? 0.5
            let observedStrength = observedStrengths[teamID] ?? 0.5
            let gamesPlayed = Double(currentRecords[teamID]?.wins ?? 0)
                + Double(currentRecords[teamID]?.losses ?? 0)
                + Double(currentRecords[teamID]?.ties ?? 0)
            let credibility = credibilityWeight(gamesPlayed: gamesPlayed)
            partialResult[teamID] = boundedStrength(
                ((1 - credibility) * priorStrength) + (credibility * observedStrength)
            )
        }

        let averageOpponentStrengths = averageOpponentStrengthByTeamID(
            teams: teams,
            completedGames: completedGames,
            baselineStrengths: blendedStrengths
        )
        let sosAdjustedStrengths = blendedStrengths.reduce(into: [String: Double]()) { partialResult, item in
            let averageOpponentStrength = averageOpponentStrengths[item.key] ?? 0.5
            partialResult[item.key] = boundedStrength(
                item.value + (StandingsMetrics.postseasonStrengthOfScheduleAdjustment * (averageOpponentStrength - 0.5))
            )
        }

        let leagueAverageStrength = sosAdjustedStrengths.isEmpty
            ? 0.5
            : sosAdjustedStrengths.values.reduce(0, +) / Double(sosAdjustedStrengths.count)
        let calibrationOffset = 0.5 - leagueAverageStrength

        return sosAdjustedStrengths.mapValues { strength in
            boundedStrength(strength + calibrationOffset)
        }
    }

    // averageOpponentStrengthByTeamID 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func averageOpponentStrengthByTeamID(
        teams: [Team],
        completedGames: [GameDetail],
        baselineStrengths: [String: Double]
    ) -> [String: Double] {
        var opponentStrengthTotals = Dictionary(uniqueKeysWithValues: teams.map {
            (Self.canonicalTeamIdentifier($0.id), 0.0)
        })
        var opponentGameCounts = Dictionary(uniqueKeysWithValues: teams.map {
            (Self.canonicalTeamIdentifier($0.id), 0)
        })

        for game in completedGames {
            let awayID = Self.canonicalTeamIdentifier(game.awayTeam.id)
            let homeID = Self.canonicalTeamIdentifier(game.homeTeam.id)
            let awayStrength = baselineStrengths[awayID] ?? 0.5
            let homeStrength = baselineStrengths[homeID] ?? 0.5

            opponentStrengthTotals[awayID, default: 0] += homeStrength
            opponentGameCounts[awayID, default: 0] += 1
            opponentStrengthTotals[homeID, default: 0] += awayStrength
            opponentGameCounts[homeID, default: 0] += 1
        }

        return opponentStrengthTotals.reduce(into: [String: Double]()) { partialResult, item in
            let teamID = item.key
            let gameCount = opponentGameCounts[teamID, default: 0]
            partialResult[teamID] = gameCount > 0 ? (item.value / Double(gameCount)) : 0.5
        }
    }

    // priorStrength 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func priorStrength(for team: Team, teamCount: Int) -> Double {
        let fallbackRank = Self.fallbackPreviousRegularSeasonRankByTeamID[Self.canonicalTeamIdentifier(team.id)]
        guard let rawRank = team.previousRegularSeasonRank ?? fallbackRank,
              teamCount > 1 else {
            return 0.5
        }

        let clampedRank = min(max(rawRank, 1), teamCount)
        let centerRank = Double(teamCount + 1) / 2
        let normalizedRank = (centerRank - Double(clampedRank)) / max(1.0, Double(teamCount - 1) / 2)
        return boundedStrength(
            0.5 + (normalizedRank * StandingsMetrics.postseasonPriorRankStrengthSpread)
        )
    }

    // credibilityWeight 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func credibilityWeight(gamesPlayed: Double) -> Double {
        guard gamesPlayed > 0 else { return 0 }
        return gamesPlayed / (gamesPlayed + StandingsMetrics.postseasonStrengthCredibilityGames)
    }

    // simulatedStrength 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func simulatedStrength(
        from effectiveStrength: Double,
        generator: inout SplitMix64
    ) -> Double {
        let shock = generator.sampleStandardNormal() * StandingsMetrics.postseasonStrengthLogitNoiseSigma
        return boundedStrength(logistic(logit(boundedStrength(effectiveStrength)) + shock))
    }

    // matchupWinProbability 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func matchupWinProbability(
        awayStrength: Double,
        homeStrength: Double,
        isNeutralSite: Bool
    ) -> Double {
        let venueAdjustment = isNeutralSite ? 0 : StandingsMetrics.postseasonHomeFieldLogitAdjustment
        return boundedStrength(
            logistic(
                logit(boundedStrength(awayStrength))
                - logit(boundedStrength(homeStrength))
                - venueAdjustment
            )
        )
    }

    // teamPairKey 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func teamPairKey(_ lhs: String, _ rhs: String) -> String {
        lhs <= rhs ? "\(lhs)|\(rhs)" : "\(rhs)|\(lhs)"
    }

    // minimumPossibleWinPercentage 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func minimumPossibleWinPercentage(
        for record: _ProbabilityRecord,
        remainingGames: Int
    ) -> Double {
        let decisions = record.wins + record.losses + remainingGames
        guard decisions > 0 else { return 0.5 }
        return Double(record.wins) / Double(decisions)
    }

    // maximumPossibleWinPercentage 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func maximumPossibleWinPercentage(
        for record: _ProbabilityRecord,
        remainingGames: Int
    ) -> Double {
        let decisions = record.wins + record.losses + remainingGames
        guard decisions > 0 else { return 0.5 }
        return Double(record.wins + remainingGames) / Double(decisions)
    }

    // remainingRegularSeasonGameCountsByTeamID 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func remainingRegularSeasonGameCountsByTeamID(
        teams: [Team],
        games: [_SimulationGame]
    ) -> [String: Int] {
        var counts = Dictionary(uniqueKeysWithValues: teams.map { (Self.canonicalTeamIdentifier($0.id), 0) })
        for game in games {
            counts[game.awayTeamID, default: 0] += 1
            counts[game.homeTeamID, default: 0] += 1
        }
        return counts
    }

    // boundedStrength 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func boundedStrength(_ value: Double) -> Double {
        min(max(value, StandingsMetrics.postseasonStrengthFloor), StandingsMetrics.postseasonStrengthCeiling)
    }

    // logit 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func logit(_ value: Double) -> Double {
        let bounded = boundedStrength(value)
        return log(bounded / (1 - bounded))
    }

    // logistic 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func logistic(_ value: Double) -> Double {
        1 / (1 + exp(-value))
    }

    // deterministicSeed 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func deterministicSeed(
        teams: [Team],
        completedGames: [GameDetail],
        remainingGames: [_SimulationGame]
    ) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603

        // mix 메서드는 이 타입의 주요 동작을 수행합니다.
        func mix(_ string: String) {
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }

        for team in teams.sorted(by: { $0.id < $1.id }) {
            mix(Self.canonicalTeamIdentifier(team.id))
        }

        for game in completedGames.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            mix(game.id.uuidString)
            mix(Self.canonicalTeamIdentifier(game.awayTeam.id))
            mix(Self.canonicalTeamIdentifier(game.homeTeam.id))
            mix(game.status.rawValue)
            mix(game.seasonClassification.rawValue)
            mix(game.scheduledStart.ISO8601Format())
            if let awayScore = game.awayScore {
                mix(String(awayScore))
            }
            if let homeScore = game.homeScore {
                mix(String(homeScore))
            }
        }

        for game in remainingGames.sorted(by: { $0.seedKey < $1.seedKey }) {
            mix(game.seedKey)
            mix(game.awayTeamID)
            mix(game.homeTeamID)
            mix(game.isNeutralSite ? "neutral" : "scheduled")
        }

        return hash == 0 ? 0x9E37_79B9_7F4A_7C15 : hash
    }

    // recordSortComparator 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated private func recordSortComparator(_ lhs: _ProbabilityRecord, _ rhs: _ProbabilityRecord) -> Bool {
        switch (lhs.winPercentage, rhs.winPercentage) {
        case let (left?, right?) where left != right:
            return left > right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            if lhs.wins != rhs.wins {
                return lhs.wins > rhs.wins
            }
            if lhs.losses != rhs.losses {
                return lhs.losses < rhs.losses
            }
            if lhs.ties != rhs.ties {
                return lhs.ties > rhs.ties
            }
            return lhs.teamID < rhs.teamID
        }
    }

    // hasSameWinPercentage 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated private func hasSameWinPercentage(_ lhs: _ProbabilityRecord, _ rhs: _ProbabilityRecord) -> Bool {
        let lhsDecisions = lhs.wins + lhs.losses
        let rhsDecisions = rhs.wins + rhs.losses
        if lhsDecisions == 0 || rhsDecisions == 0 {
            return lhsDecisions == rhsDecisions
        }
        return lhs.wins * rhsDecisions == rhs.wins * lhsDecisions
    }

    // canonicalTeamIdentifier 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated private static func canonicalTeamIdentifier(_ rawValue: String) -> String {
        Team.canonicalID(for: rawValue) ?? rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// _ProbabilityRecord 구조체는 _ProbabilityRecord 타입의 역할과 값을 정의합니다.
private struct _ProbabilityRecord: Hashable, Sendable {
    let teamID: String
    var wins = 0
    var losses = 0
    var ties = 0

    nonisolated var winPercentage: Double? {
        let decisions = wins + losses
        guard decisions > 0 else { return nil }
        return Double(wins) / Double(decisions)
    }
}

// _ScoringAggregate 구조체는 _ScoringAggregate 타입의 역할과 값을 정의합니다.
private struct _ScoringAggregate: Hashable, Sendable {
    var runsScored = 0
    var runsAllowed = 0
    var gamesPlayed = 0

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(runsScored: Int = 0, runsAllowed: Int = 0, gamesPlayed: Int = 0) {
        self.runsScored = runsScored
        self.runsAllowed = runsAllowed
        self.gamesPlayed = gamesPlayed
    }

    // record 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated mutating func record(scored: Int, allowed: Int) {
        runsScored += scored
        runsAllowed += allowed
        gamesPlayed += 1
    }
}

// _SimulationGame 구조체는 _SimulationGame 타입의 역할과 값을 정의합니다.
private struct _SimulationGame: Hashable, Sendable {
    let awayTeamID: String
    let homeTeamID: String
    let isNeutralSite: Bool
    let seedKey: String

    // real 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func real(_ game: GameDetail) -> _SimulationGame {
        _SimulationGame(
            awayTeamID: game.awayTeam.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            homeTeamID: game.homeTeam.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            isNeutralSite: false,
            seedKey: "real:\(game.id.uuidString)"
        )
    }
}

// _ScoringRate 구조체는 _ScoringRate 타입의 역할과 값을 정의합니다.
private struct _ScoringRate: Hashable, Sendable {
    let offense: Double
    let defense: Double
}

// SplitMix64 구조체는 SplitMix64 타입의 역할과 값을 정의합니다.
private struct SplitMix64: Sendable {
    var state: UInt64

    // next 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    // nextUnitInterval 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated mutating func nextUnitInterval() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    // sampleStandardNormal 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated mutating func sampleStandardNormal() -> Double {
        let u1 = max(nextUnitInterval(), Double.leastNonzeroMagnitude)
        let u2 = nextUnitInterval()
        return sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2)
    }

    // samplePoisson 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated mutating func samplePoisson(lambda: Double) -> Int {
        guard lambda > 0 else { return 0 }
        let threshold = exp(-lambda)
        var product = 1.0
        var count = 0

        repeat {
            count += 1
            product *= nextUnitInterval()
        } while product > threshold

        return count - 1
    }
}

private extension Dictionary where Key == String, Value == _ScoringRate {
    nonisolated var leagueAverageRuns: Double {
        get { self["__league_average__", default: _ScoringRate(offense: 4.5, defense: 4.5)].offense }
        set { self["__league_average__"] = _ScoringRate(offense: newValue, defense: newValue) }
    }
}
