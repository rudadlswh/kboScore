//  기능 설명: 경기 상태 변화 알림을 만들기 위한 이전/현재 경기 상태 표현을 담당합니다.
//  경기 상태 변화와 사용자 설정을 연결해 필요한 알림만 중복 없이 전달합니다.
//  APNs 토큰 누락, 권한 거부, 취소 경기, 같은 이벤트 반복 수신을 방어해야 합니다.
//  TODO : 알림 실패 사유를 사용자에게 보여줄 수 있도록 진단 정보를 확장합니다.
// GameCancellationNotificationState 구조체는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
struct GameCancellationNotificationState: Equatable {
    let status: GameStatus
    let isWeatherRelated: Bool
}

// GameContentNotificationState 구조체는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
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

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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
