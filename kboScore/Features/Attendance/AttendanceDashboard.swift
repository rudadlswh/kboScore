import Foundation

enum AttendanceGameSide: Hashable, Sendable {
    case home
    case away

    var title: String {
        switch self {
        case .home:
            "홈"
        case .away:
            "원정"
        }
    }
}

struct AttendanceRecordSummary: Hashable, Sendable {
    let games: Int
    let wins: Int
    let losses: Int
    let draws: Int

    static let empty = AttendanceRecordSummary(games: 0, wins: 0, losses: 0, draws: 0)

    var hasGames: Bool {
        games > 0
    }

    var winPercentage: Double? {
        let decisions = wins + losses
        guard decisions > 0 else { return nil }
        return Double(wins) / Double(decisions)
    }

    var gamesText: String {
        "\(games)경기"
    }

    var recordText: String {
        "\(wins)승 \(losses)패 \(draws)무"
    }

    var winPercentageText: String {
        guard let winPercentage else { return "---" }
        return String(format: "%.3f", winPercentage)
    }
}

struct AttendanceGameRecord: Identifiable, Hashable, Sendable {
    let id: String
    let gameIdentity: String
    let side: AttendanceGameSide
    let opponentName: String
    let stadium: String
    let scoreText: String
    let gameDate: Date
    let result: TeamGameResult
}

struct AttendanceDashboard: Hashable, Sendable {
    let overall: AttendanceRecordSummary
    let home: AttendanceRecordSummary
    let away: AttendanceRecordSummary
    let games: [AttendanceGameRecord]

    static let empty = AttendanceDashboard(
        overall: .empty,
        home: .empty,
        away: .empty,
        games: []
    )

    var hasGames: Bool {
        overall.hasGames
    }
}

struct AttendanceDashboardBuilder {
    static func build(attendedGames games: [GameDetail], favoriteTeamID: String?) -> AttendanceDashboard {
        guard let favoriteTeamID else { return .empty }

        var seenKeys: Set<String> = []
        var homeRecords: [AttendanceGameRecord] = []
        var awayRecords: [AttendanceGameRecord] = []

        for game in games.sorted(by: { $0.scheduledStart > $1.scheduledStart }) {
            guard seenKeys.insert(game.attendanceStorageKey).inserted,
                  let side = attendanceSide(for: game, favoriteTeamID: favoriteTeamID),
                  let result = game.finalResult(for: favoriteTeamID),
                  let opponent = opponentTeam(for: game, favoriteTeamID: favoriteTeamID) else {
                continue
            }

            let record = AttendanceGameRecord(
                id: game.attendanceStorageKey,
                gameIdentity: game.stableDetailIdentity,
                side: side,
                opponentName: opponent.displayName,
                stadium: game.venue,
                scoreText: game.finalScoreLine ?? "---",
                gameDate: game.scheduledStart,
                result: result
            )

            switch side {
            case .home:
                homeRecords.append(record)
            case .away:
                awayRecords.append(record)
            }
        }

        let allRecords = (homeRecords + awayRecords)
            .sorted { $0.gameDate > $1.gameDate }

        return AttendanceDashboard(
            overall: summary(for: allRecords),
            home: summary(for: homeRecords),
            away: summary(for: awayRecords),
            games: allRecords
        )
    }

    private static func attendanceSide(for game: GameDetail, favoriteTeamID: String) -> AttendanceGameSide? {
        if game.homeTeam.id == favoriteTeamID {
            return .home
        }
        if game.awayTeam.id == favoriteTeamID {
            return .away
        }
        return nil
    }

    private static func opponentTeam(for game: GameDetail, favoriteTeamID: String) -> Team? {
        if game.homeTeam.id == favoriteTeamID {
            return game.awayTeam
        }
        if game.awayTeam.id == favoriteTeamID {
            return game.homeTeam
        }
        return nil
    }

    private static func summary(for records: [AttendanceGameRecord]) -> AttendanceRecordSummary {
        var wins = 0
        var losses = 0
        var draws = 0

        for record in records {
            switch record.result {
            case .win:
                wins += 1
            case .loss:
                losses += 1
            case .tie:
                draws += 1
            }
        }

        return AttendanceRecordSummary(
            games: records.count,
            wins: wins,
            losses: losses,
            draws: draws
        )
    }
}
