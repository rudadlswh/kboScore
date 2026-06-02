import Foundation
import UserNotifications

enum GameContentNotificationBuilder {
    static func makeRequest(
        for game: GameDetail,
        event: ScoreNotificationEventType,
        fingerprint: String,
        previousState: GameContentNotificationState,
        currentState: GameContentNotificationState
    ) -> UNNotificationRequest {
        let title: String
        let body: String
        switch event {
        case .gameStart:
            title = "경기 시작"
            body = "\(game.awayTeam.displayName) vs \(game.homeTeam.displayName) 경기가 시작되었습니다."
        case .scoreChange, .leadChange:
            title = event == .leadChange ? "리드 변경" : "점수 변경"
            let runCount = scoreDelta(previous: previousState, current: currentState)
            body = formattedLiveEventBody(
                game: game,
                method: liveEventMethod(from: game, fallback: "득점"),
                runCount: max(1, runCount)
            )
        case .onBase:
            title = "출루"
            body = formattedLiveEventBody(
                game: game,
                method: liveEventMethod(from: game, fallback: "출루"),
                runCount: nil
            )
        case .gameEnd:
            title = "경기 종료"
            body = game.finalScoreLine ?? "\(game.awayTeam.displayName) vs \(game.homeTeam.displayName) 경기가 종료되었습니다."
        case .inningChange:
            title = "이닝 교체"
            body = game.inningText ?? "\(game.awayTeam.displayName) vs \(game.homeTeam.displayName)"
        case .general:
            title = "경기 상황 업데이트"
            body = game.inningText ?? "\(game.awayTeam.displayName) vs \(game.homeTeam.displayName)"
        case .rainDelay:
            title = "우천/취소 알림"
            body = game.inningText ?? "경기 진행 상태가 변경되었습니다."
        }

        let payload = ScoreNotificationPayload(
            gameID: game.canonicalGameIdentityValue,
            eventType: event,
            title: title,
            body: body,
            publicGameID: game.publicGameID,
            providerGameID: game.officialGameCenterID ?? game.providerGameID,
            gameDatabaseID: game.id.uuidString,
            stableGameIdentity: game.stableDetailIdentity,
            teamIDs: [game.awayTeam.id, game.homeTeam.id],
            routeHint: .gameDetail
        )
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = payload.userInfo()
        let requestID = GameIdentifier.uuid(from: fingerprint)?.uuidString ?? UUID().uuidString
        return UNNotificationRequest(identifier: "game-content-\(requestID)", content: content, trigger: nil)
    }

    private static func formattedLiveEventBody(game: GameDetail, method: String, runCount: Int?) -> String {
        let batter = nonBlank(game.currentBatterName)
        let pitcher = nonBlank(game.currentPitcherName)
        let playText: String
        if let batter, let pitcher {
            playText = "\(batter) 이 \(pitcher) 을 상대로 \(method)."
        } else {
            playText = method + "."
        }
        guard let runCount else { return playText }
        return "\(playText)\n\(runCount)득점"
    }

    private static func liveEventMethod(from game: GameDetail, fallback: String) -> String {
        let text = ([game.highlightText, game.note, game.inningText].compactMap { $0 } + game.events.map(\.headline))
            .joined(separator: " ")
        for method in ["고의사구", "사구", "볼넷", "홈런", "적시타", "안타", "2루타", "3루타", "희생플라이", "실책"] where text.contains(method) {
            return method
        }
        return fallback
    }

    private static func scoreDelta(previous: GameContentNotificationState, current: GameContentNotificationState) -> Int {
        let awayDelta = max(0, (current.awayScore ?? 0) - (previous.awayScore ?? 0))
        let homeDelta = max(0, (current.homeScore ?? 0) - (previous.homeScore ?? 0))
        return awayDelta + homeDelta
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
