//
//  StandingsModels.swift
//  kboScore
//
//  Created by Codex on 4/2/26.
//

import Foundation

enum StandingsRankingResolution: String, Codable, Hashable, Sendable {
    case resolved
    case tiebreakGameRequired = "tiebreak_game_required"
}

enum PostseasonProbabilityUnavailableReason: String, Codable, Hashable, Sendable {
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

struct TeamStandingsSnapshot: Identifiable, Hashable, Sendable {
    let team: Team
    let rank: Int
    let wins: Int
    let losses: Int
    let ties: Int
    let remainingRegularSeasonGames: Int
    let recentResults: [TeamGameResult]
    let unknownClassificationGames: Int
    let rankingResolution: StandingsRankingResolution
    let rankingResolutionPosition: Int?
    let postseasonQualificationProbability: Double?
    let postseasonProbabilityUnavailableReason: PostseasonProbabilityUnavailableReason?

    nonisolated init(
        team: Team,
        rank: Int,
        wins: Int,
        losses: Int,
        ties: Int,
        remainingRegularSeasonGames: Int,
        recentResults: [TeamGameResult],
        unknownClassificationGames: Int = 0,
        rankingResolution: StandingsRankingResolution = .resolved,
        rankingResolutionPosition: Int? = nil,
        postseasonQualificationProbability: Double? = nil,
        postseasonProbabilityUnavailableReason: PostseasonProbabilityUnavailableReason? = nil
    ) {
        self.team = team
        self.rank = rank
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.remainingRegularSeasonGames = remainingRegularSeasonGames
        self.recentResults = recentResults
        self.unknownClassificationGames = unknownClassificationGames
        self.rankingResolution = rankingResolution
        self.rankingResolutionPosition = rankingResolutionPosition
        self.postseasonQualificationProbability = postseasonQualificationProbability
        self.postseasonProbabilityUnavailableReason = postseasonProbabilityUnavailableReason
    }

    var id: String { team.id }

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

    var recordText: String {
        "\(wins)승 \(losses)패 \(ties)무"
    }

    var recentResultsText: String {
        guard recentResults.isEmpty == false else { return "기록 없음" }
        return recentResults.map(\.shortLabel).joined(separator: " ")
    }

    var hasPostseasonProbabilitySignal: Bool {
        postseasonQualificationProbability != nil || postseasonProbabilityUnavailableReason != nil
    }

    var shouldShowPostseasonProbability: Bool {
        if postseasonQualificationProbability != nil {
            return true
        }
        guard let postseasonProbabilityUnavailableReason else { return false }
        return postseasonProbabilityUnavailableReason != .seasonProgressBelowThreshold
    }

    var postseasonQualificationText: String? {
        guard shouldShowPostseasonProbability else { return nil }
        if let postseasonQualificationProbability {
            return "\(Int((postseasonQualificationProbability * 100).rounded()))%"
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
}

extension TeamGameResult {
    var shortLabel: String {
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

struct LocalStandingsProbabilitySignal: Hashable, Sendable {
    let unknownClassificationGames: Int
    let rankingResolution: StandingsRankingResolution
    let rankingResolutionPosition: Int?
    let postseasonQualificationProbability: Double?
    let postseasonProbabilityUnavailableReason: PostseasonProbabilityUnavailableReason?
}

// Uses only local regular-season games. Unknown-classification rows or an
// incomplete 144-game schedule make the result unavailable. When the schedule
// is complete, remaining games are simulated with a deterministic seed from the
// current snapshot, and top-5 qualification is evaluated by win-percentage
// groups with equal sharing at the cutoff.
struct LocalPostseasonQualificationCalculator: Sendable {
    let regularSeasonLength: Int
    let simulationCount: Int
    let minimumCompletedGamesPerTeam: Int
    private let shrinkageGames = 6.0

    nonisolated init(
        regularSeasonLength: Int = 144,
        simulationCount: Int = 2_000,
        minimumCompletedGamesPerTeam: Int? = nil
    ) {
        self.regularSeasonLength = regularSeasonLength
        self.simulationCount = simulationCount
        self.minimumCompletedGamesPerTeam = minimumCompletedGamesPerTeam ?? Int((Double(regularSeasonLength) * 0.3).rounded(.up))
    }

    nonisolated func makeSignals(
        teams: [Team],
        games: [GameDetail]
    ) -> [String: LocalStandingsProbabilitySignal] {
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { (Self.canonicalTeamIdentifier($0.id), $0) })
        let completedRegularSeasonGames = games.filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
        let remainingRegularSeasonGames = games.filter { $0.isRegularSeason && !$0.hasCompleteFinalScore }
        let unknownClassificationCounts = unknownClassificationCountsByTeamID(teams: teams, games: games)
        let rankingSignals = currentRankingSignals(teams: teams, games: completedRegularSeasonGames)
        let completedGameCounts = completedRegularSeasonGameCountsByTeamID(teams: teams, games: completedRegularSeasonGames)

        if unknownClassificationCounts.values.contains(where: { $0 > 0 }) {
            return makeUnavailableSignals(
                teams: teams,
                rankingSignals: rankingSignals,
                unknownClassificationCounts: unknownClassificationCounts,
                reason: .unknownClassificationGames
            )
        }

        let scheduledGamesByTeamID = scheduledRegularSeasonGameCountsByTeamID(teams: teams, games: games)
        if scheduledGamesByTeamID.values.contains(where: { $0 != regularSeasonLength }) {
            return makeUnavailableSignals(
                teams: teams,
                rankingSignals: rankingSignals,
                unknownClassificationCounts: unknownClassificationCounts,
                reason: .incompleteRegularSeasonSchedule
            )
        }

        if completedGameCounts.values.min() ?? 0 < minimumCompletedGamesPerTeam {
            return makeUnavailableSignals(
                teams: teams,
                rankingSignals: rankingSignals,
                unknownClassificationCounts: unknownClassificationCounts,
                reason: .seasonProgressBelowThreshold
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
        let probabilities = qualificationProbabilities(
            teams: teams,
            teamsByID: teamsByID,
            currentRecords: records,
            completedGames: completedRegularSeasonGames,
            remainingGames: remainingRegularSeasonGames
        )

        return teams.reduce(into: [:]) { partialResult, team in
            let teamID = Self.canonicalTeamIdentifier(team.id)
            let rankingSignal = rankingSignals[teamID]
            partialResult[teamID] = LocalStandingsProbabilitySignal(
                unknownClassificationGames: unknownClassificationCounts[teamID, default: 0],
                rankingResolution: rankingSignal?.rankingResolution ?? .resolved,
                rankingResolutionPosition: rankingSignal?.rankingResolutionPosition,
                postseasonQualificationProbability: probabilities[teamID],
                postseasonProbabilityUnavailableReason: nil
            )
        }
    }

    private func qualificationProbabilities(
        teams: [Team],
        teamsByID: [String: Team],
        currentRecords: [String: _ProbabilityRecord],
        completedGames: [GameDetail],
        remainingGames: [GameDetail]
    ) -> [String: Double] {
        guard remainingGames.isEmpty == false else {
            return qualificationShares(for: Array(currentRecords.values))
        }

        let scoringRates = scoringRatesByTeamID(teams: teams, completedGames: completedGames)
        var qualificationTotals = Dictionary(uniqueKeysWithValues: teams.map { (Self.canonicalTeamIdentifier($0.id), 0.0) })
        var generator = SplitMix64(state: deterministicSeed(teams: teams, games: completedGames + remainingGames))

        for _ in 0..<simulationCount {
            var simulatedRecords = currentRecords

            for game in remainingGames {
                let awayID = Self.canonicalTeamIdentifier(game.awayTeam.id)
                let homeID = Self.canonicalTeamIdentifier(game.homeTeam.id)
                guard var awayRecord = simulatedRecords[awayID],
                      var homeRecord = simulatedRecords[homeID],
                      teamsByID[awayID] != nil,
                      teamsByID[homeID] != nil else {
                    continue
                }

                let awayRuns = generator.samplePoisson(
                    lambda: matchupRunExpectation(
                        offense: scoringRates[awayID]?.offense ?? scoringRates.leagueAverageRuns,
                        defense: scoringRates[homeID]?.defense ?? scoringRates.leagueAverageRuns,
                        homeFieldMultiplier: 0.98
                    )
                )
                let homeRuns = generator.samplePoisson(
                    lambda: matchupRunExpectation(
                        offense: scoringRates[homeID]?.offense ?? scoringRates.leagueAverageRuns,
                        defense: scoringRates[awayID]?.defense ?? scoringRates.leagueAverageRuns,
                        homeFieldMultiplier: 1.02
                    )
                )

                if awayRuns == homeRuns {
                    awayRecord.ties += 1
                    homeRecord.ties += 1
                } else if awayRuns > homeRuns {
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

        return qualificationTotals.mapValues { $0 / Double(simulationCount) }
    }

    private func makeUnavailableSignals(
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
                rankingResolution: rankingSignal?.rankingResolution ?? .resolved,
                rankingResolutionPosition: rankingSignal?.rankingResolutionPosition,
                postseasonQualificationProbability: nil,
                postseasonProbabilityUnavailableReason: reason
            )
        }
    }

    private func currentRankingSignals(
        teams: [Team],
        games: [GameDetail]
    ) -> [String: LocalStandingsProbabilitySignal] {
        let groupedRecords = groupedRecordsByWinPercentage(for: Array(currentRecords(teams: teams, games: games).values))
        var signals: [String: LocalStandingsProbabilitySignal] = [:]
        var currentRank = 1

        for group in groupedRecords {
            let requiresTiebreak = group.count == 2 && (currentRank == 1 || currentRank == 5)
            for record in group {
                signals[record.teamID] = LocalStandingsProbabilitySignal(
                    unknownClassificationGames: 0,
                    rankingResolution: requiresTiebreak ? .tiebreakGameRequired : .resolved,
                    rankingResolutionPosition: requiresTiebreak ? currentRank : nil,
                    postseasonQualificationProbability: nil,
                    postseasonProbabilityUnavailableReason: nil
                )
            }
            currentRank += group.count
        }

        return signals
    }

    private func currentRecords(
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

    private func groupedRecordsByWinPercentage(
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

    private func qualificationShares(for records: [_ProbabilityRecord]) -> [String: Double] {
        let groups = groupedRecordsByWinPercentage(for: records)
        var shares: [String: Double] = [:]
        var currentRank = 1

        for group in groups {
            let groupEndRank = currentRank + group.count - 1
            let share: Double
            if groupEndRank <= 5 {
                share = 1
            } else if currentRank > 5 {
                share = 0
            } else if group.count == 2 && currentRank == 5 {
                // The local model approximates a deciding 5th-place tiebreak as 50/50.
                share = 0.5
            } else {
                let remainingSpots = max(0, 5 - (currentRank - 1))
                share = Double(remainingSpots) / Double(group.count)
            }

            for record in group {
                shares[record.teamID] = share
            }
            currentRank += group.count
        }

        return shares
    }

    private func scheduledRegularSeasonGameCountsByTeamID(
        teams: [Team],
        games: [GameDetail]
    ) -> [String: Int] {
        var counts = Dictionary(uniqueKeysWithValues: teams.map { (Self.canonicalTeamIdentifier($0.id), 0) })
        for game in games where game.isRegularSeason {
            counts[Self.canonicalTeamIdentifier(game.awayTeam.id), default: 0] += 1
            counts[Self.canonicalTeamIdentifier(game.homeTeam.id), default: 0] += 1
        }
        return counts
    }

    private func completedRegularSeasonGameCountsByTeamID(
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

    private func unknownClassificationCountsByTeamID(
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

    private func scoringRatesByTeamID(
        teams: [Team],
        completedGames: [GameDetail]
    ) -> [String: _ScoringRate] {
        var aggregateByTeamID = Dictionary(uniqueKeysWithValues: teams.map {
            (Self.canonicalTeamIdentifier($0.id), _ScoringAggregate())
        })
        var totalRuns = 0.0
        var totalTeamGames = 0.0

        for game in completedGames {
            let awayID = Self.canonicalTeamIdentifier(game.awayTeam.id)
            let homeID = Self.canonicalTeamIdentifier(game.homeTeam.id)
            guard let awayScore = game.awayScore,
                  let homeScore = game.homeScore else {
                continue
            }

            aggregateByTeamID[awayID, default: _ScoringAggregate()].record(scored: awayScore, allowed: homeScore)
            aggregateByTeamID[homeID, default: _ScoringAggregate()].record(scored: homeScore, allowed: awayScore)
            totalRuns += Double(awayScore + homeScore)
            totalTeamGames += 2
        }

        let leagueAverageRuns = totalTeamGames > 0 ? totalRuns / totalTeamGames : 4.5
        var rates: [String: _ScoringRate] = [:]

        for (teamID, aggregate) in aggregateByTeamID {
            let gamesPlayed = Double(aggregate.gamesPlayed)
            let offense = (
                Double(aggregate.runsScored) + (leagueAverageRuns * shrinkageGames)
            ) / max(1, gamesPlayed + shrinkageGames)
            let defense = (
                Double(aggregate.runsAllowed) + (leagueAverageRuns * shrinkageGames)
            ) / max(1, gamesPlayed + shrinkageGames)
            rates[teamID] = _ScoringRate(
                offense: max(0.25, offense),
                defense: max(0.25, defense)
            )
        }

        rates.leagueAverageRuns = max(0.25, leagueAverageRuns)
        return rates
    }

    private func matchupRunExpectation(
        offense: Double,
        defense: Double,
        homeFieldMultiplier: Double
    ) -> Double {
        max(0.25, sqrt(offense * defense) * homeFieldMultiplier)
    }

    private func deterministicSeed(teams: [Team], games: [GameDetail]) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603

        func mix(_ string: String) {
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }

        for team in teams.sorted(by: { $0.id < $1.id }) {
            mix(Self.canonicalTeamIdentifier(team.id))
        }

        for game in games.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
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

        return hash == 0 ? 0x9E37_79B9_7F4A_7C15 : hash
    }

    private func recordSortComparator(_ lhs: _ProbabilityRecord, _ rhs: _ProbabilityRecord) -> Bool {
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

    private func hasSameWinPercentage(_ lhs: _ProbabilityRecord, _ rhs: _ProbabilityRecord) -> Bool {
        let lhsDecisions = lhs.wins + lhs.losses
        let rhsDecisions = rhs.wins + rhs.losses
        if lhsDecisions == 0 || rhsDecisions == 0 {
            return lhsDecisions == rhsDecisions
        }
        return lhs.wins * rhsDecisions == rhs.wins * lhsDecisions
    }

    private static func canonicalTeamIdentifier(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct _ProbabilityRecord: Hashable, Sendable {
    let teamID: String
    var wins = 0
    var losses = 0
    var ties = 0

    var winPercentage: Double? {
        let decisions = wins + losses
        guard decisions > 0 else { return nil }
        return Double(wins) / Double(decisions)
    }
}

private struct _ScoringAggregate: Hashable, Sendable {
    var runsScored = 0
    var runsAllowed = 0
    var gamesPlayed = 0

    mutating func record(scored: Int, allowed: Int) {
        runsScored += scored
        runsAllowed += allowed
        gamesPlayed += 1
    }
}

private struct _ScoringRate: Hashable, Sendable {
    let offense: Double
    let defense: Double
}

private struct SplitMix64: Sendable {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnitInterval() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func samplePoisson(lambda: Double) -> Int {
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
    var leagueAverageRuns: Double {
        get { self["__league_average__", default: _ScoringRate(offense: 4.5, defense: 4.5)].offense }
        set { self["__league_average__"] = _ScoringRate(offense: newValue, defense: newValue) }
    }
}
