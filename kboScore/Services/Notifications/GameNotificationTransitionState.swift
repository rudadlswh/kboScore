struct GameCancellationNotificationState: Equatable {
    let status: GameStatus
    let isWeatherRelated: Bool
}

struct GameContentNotificationState: Equatable {
    let status: GameStatus
    let awayScore: Int?
    let homeScore: Int?
    let inningText: String?
    let bases: RunnerState?
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let currentBatterName: String?
    let currentPitcherName: String?

    init(game: GameDetail) {
        status = game.status
        awayScore = game.awayScore
        homeScore = game.homeScore
        inningText = game.inningText
        bases = game.bases
        balls = game.balls
        strikes = game.strikes
        outs = game.outs
        currentBatterName = game.currentBatterName
        currentPitcherName = game.currentPitcherName
    }
}
