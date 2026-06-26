//
//  FavoriteTeamLiveActivity.swift
//  kboScore
//  기능 설명: 마이팀 경기 Live Activity의 시작, 갱신, 종료 제어를 담당합니다.
//  앱 밖에서도 마이팀 경기 흐름을 이어서 볼 수 있도록 Live Activity와 위젯용 스냅샷을 분리합니다.
//  확장 프로세스, App Group 저장소, 푸시 토큰, 시스템 권한 상태에 따라 갱신이 실패할 수 있습니다.
//  TODO : 실기기 권한 상태별 동작과 종료 조건을 더 촘촘히 검증합니다.
//
//  Created by Codex on 3/26/26.
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// FavoriteTeamLiveActivitySnapshot 구조체는 FavoriteTeamLiveActivitySnapshot 타입의 역할과 값을 정의합니다.
struct FavoriteTeamLiveActivitySnapshot: Hashable, Sendable {
    let gameID: UUID
    let favoriteTeamID: String
    let favoriteTeamName: String
    let favoriteTeamShortName: String
    let opponentTeamID: String
    let opponentTeamName: String
    let opponentTeamShortName: String
    let isPreGame: Bool
    let favoriteScoreText: String
    let opponentScoreText: String
    let inningText: String
    let summaryText: String
    let favoriteStartingPitcherName: String?
    let opponentStartingPitcherName: String?
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let runnerOnFirst: Bool?
    let runnerOnSecond: Bool?
    let runnerOnThird: Bool?
    let currentBatterName: String?
    let currentPitcherName: String?
    let venue: String
    let isHomeGame: Bool
    let publicGameID: String?
    let providerGameID: String?
    let databaseID: String
    let stableDetailIdentity: String

    var contentStateKey: FavoriteTeamLiveActivityContentStateKey {
        FavoriteTeamLiveActivityContentStateKey(
            isPreGame: isPreGame,
            favoriteScoreText: favoriteScoreText,
            opponentScoreText: opponentScoreText,
            inningText: inningText,
            summaryText: summaryText,
            favoriteStartingPitcherName: favoriteStartingPitcherName,
            opponentStartingPitcherName: opponentStartingPitcherName,
            balls: balls,
            strikes: strikes,
            outs: outs,
            runnerOnFirst: runnerOnFirst,
            runnerOnSecond: runnerOnSecond,
            runnerOnThird: runnerOnThird,
            currentBatterName: currentBatterName,
            currentPitcherName: currentPitcherName
        )
    }

    // make 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    static func make(from game: GameDetail, favoriteTeamID: String?) -> FavoriteTeamLiveActivitySnapshot? {
        guard let favoriteTeamID else { return nil }

        let favoriteTeam: Team
        let opponentTeam: Team
        let favoriteScore: Int?
        let opponentScore: Int?
        let favoriteStartingPitcherName: String?
        let opponentStartingPitcherName: String?
        let isHomeGame: Bool

        if game.homeTeam.id == favoriteTeamID {
            favoriteTeam = game.homeTeam
            opponentTeam = game.awayTeam
            favoriteScore = game.homeScore
            opponentScore = game.awayScore
            favoriteStartingPitcherName = game.homeStartingPitcherName
            opponentStartingPitcherName = game.awayStartingPitcherName
            isHomeGame = true
        } else if game.awayTeam.id == favoriteTeamID {
            favoriteTeam = game.awayTeam
            opponentTeam = game.homeTeam
            favoriteScore = game.awayScore
            opponentScore = game.homeScore
            favoriteStartingPitcherName = game.awayStartingPitcherName
            opponentStartingPitcherName = game.homeStartingPitcherName
            isHomeGame = false
        } else {
            return nil
        }
        let isPreGame = game.status == .upcoming
        let startTimeText = game.scheduledStart.formatted(date: .omitted, time: .shortened)

        return FavoriteTeamLiveActivitySnapshot(
            gameID: game.id,
            favoriteTeamID: favoriteTeam.id,
            favoriteTeamName: favoriteTeam.displayName,
            favoriteTeamShortName: favoriteTeam.displayName,
            opponentTeamID: opponentTeam.id,
            opponentTeamName: opponentTeam.displayName,
            opponentTeamShortName: opponentTeam.displayName,
            isPreGame: isPreGame,
            favoriteScoreText: isPreGame ? "-" : (favoriteScore.map(String.init) ?? "-"),
            opponentScoreText: isPreGame ? "-" : (opponentScore.map(String.init) ?? "-"),
            inningText: isPreGame ? "" : (KBOInningFormatter.korean(game.inningText) ?? game.status.title),
            summaryText: isPreGame ? startTimeText : game.status.title,
            favoriteStartingPitcherName: favoriteStartingPitcherName?.nilIfBlank,
            opponentStartingPitcherName: opponentStartingPitcherName?.nilIfBlank,
            balls: isPreGame ? nil : game.balls,
            strikes: isPreGame ? nil : game.strikes,
            outs: isPreGame ? nil : game.outs,
            runnerOnFirst: isPreGame ? nil : game.bases?.first,
            runnerOnSecond: isPreGame ? nil : game.bases?.second,
            runnerOnThird: isPreGame ? nil : game.bases?.third,
            currentBatterName: isPreGame ? nil : game.currentBatterName,
            currentPitcherName: isPreGame ? nil : game.currentPitcherName,
            venue: game.venue,
            isHomeGame: isHomeGame,
            publicGameID: game.publicGameID,
            providerGameID: game.officialGameCenterID,
            databaseID: game.id.uuidString,
            stableDetailIdentity: game.stableDetailIdentity
        )
    }

    #if canImport(ActivityKit)
    // activityAttributes 메서드는 이 타입의 주요 동작을 수행합니다.
    func activityAttributes() -> FavoriteTeamGameActivityAttributes {
        FavoriteTeamGameActivityAttributes(
            gameID: gameID.uuidString,
            favoriteTeamID: favoriteTeamID,
            favoriteTeamName: favoriteTeamName,
            favoriteTeamShortName: favoriteTeamShortName,
            opponentTeamID: opponentTeamID,
            opponentTeamName: opponentTeamName,
            opponentTeamShortName: opponentTeamShortName,
            venue: venue,
            isHomeGame: isHomeGame
        )
    }

    // contentState 메서드는 이 타입의 주요 동작을 수행합니다.
    func contentState() -> FavoriteTeamGameActivityAttributes.ContentState {
        FavoriteTeamGameActivityAttributes.ContentState(
            isPreGame: isPreGame,
            favoriteScoreText: favoriteScoreText,
            opponentScoreText: opponentScoreText,
            inningText: inningText,
            summaryText: summaryText,
            favoriteStartingPitcherName: favoriteStartingPitcherName,
            opponentStartingPitcherName: opponentStartingPitcherName,
            balls: balls,
            strikes: strikes,
            outs: outs,
            runnerOnFirst: runnerOnFirst,
            runnerOnSecond: runnerOnSecond,
            runnerOnThird: runnerOnThird,
            currentBatterName: currentBatterName,
            currentPitcherName: currentPitcherName
        )
    }
    #endif
}

// FavoriteTeamLiveActivityContentStateKey 구조체는 FavoriteTeamLiveActivityContentStateKey 타입의 역할과 값을 정의합니다.
nonisolated struct FavoriteTeamLiveActivityContentStateKey: Hashable, Sendable, CustomStringConvertible {
    let isPreGame: Bool
    let favoriteScoreText: String
    let opponentScoreText: String
    let inningText: String
    let summaryText: String
    let favoriteStartingPitcherName: String?
    let opponentStartingPitcherName: String?
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let runnerOnFirst: Bool?
    let runnerOnSecond: Bool?
    let runnerOnThird: Bool?
    let currentBatterName: String?
    let currentPitcherName: String?

    var description: String {
        [
            "isPreGame=\(isPreGame)",
            "favoriteScoreText=\(favoriteScoreText)",
            "opponentScoreText=\(opponentScoreText)",
            "inningText=\(inningText)",
            "summaryText=\(summaryText)",
            "favoriteStartingPitcherName=\(favoriteStartingPitcherName ?? "nil")",
            "opponentStartingPitcherName=\(opponentStartingPitcherName ?? "nil")",
            "balls=\(balls.map(String.init) ?? "nil")",
            "strikes=\(strikes.map(String.init) ?? "nil")",
            "outs=\(outs.map(String.init) ?? "nil")",
            "runnerOnFirst=\(runnerOnFirst.map(String.init) ?? "nil")",
            "runnerOnSecond=\(runnerOnSecond.map(String.init) ?? "nil")",
            "runnerOnThird=\(runnerOnThird.map(String.init) ?? "nil")",
            "currentBatterName=\(currentBatterName ?? "nil")",
            "currentPitcherName=\(currentPitcherName ?? "nil")"
        ].joined(separator: "|")
    }

    // changedFields 메서드는 이 타입의 주요 동작을 수행합니다.
    func changedFields(comparedTo previous: FavoriteTeamLiveActivityContentStateKey?) -> [String] {
        guard let previous else {
            return ["initialContentState"]
        }
        var fields: [String] = []
        if isPreGame != previous.isPreGame { fields.append("isPreGame") }
        if favoriteScoreText != previous.favoriteScoreText { fields.append("favoriteScoreText") }
        if opponentScoreText != previous.opponentScoreText { fields.append("opponentScoreText") }
        if inningText != previous.inningText { fields.append("inningText") }
        if summaryText != previous.summaryText { fields.append("summaryText") }
        if favoriteStartingPitcherName != previous.favoriteStartingPitcherName { fields.append("favoriteStartingPitcherName") }
        if opponentStartingPitcherName != previous.opponentStartingPitcherName { fields.append("opponentStartingPitcherName") }
        if balls != previous.balls { fields.append("balls") }
        if strikes != previous.strikes { fields.append("strikes") }
        if outs != previous.outs { fields.append("outs") }
        if runnerOnFirst != previous.runnerOnFirst { fields.append("runnerOnFirst") }
        if runnerOnSecond != previous.runnerOnSecond { fields.append("runnerOnSecond") }
        if runnerOnThird != previous.runnerOnThird { fields.append("runnerOnThird") }
        if currentBatterName != previous.currentBatterName { fields.append("currentBatterName") }
        if currentPitcherName != previous.currentPitcherName { fields.append("currentPitcherName") }
        return fields
    }
}

// FavoriteTeamLiveActivityDedupeDecision 구조체는 FavoriteTeamLiveActivityDedupeDecision 타입의 역할과 값을 정의합니다.
nonisolated struct FavoriteTeamLiveActivityDedupeDecision: Sendable {
    let shouldSkip: Bool
    let previousContentStateKey: FavoriteTeamLiveActivityContentStateKey?
    let newContentStateKey: FavoriteTeamLiveActivityContentStateKey
    let changedFields: [String]
}

// FavoriteTeamLiveActivityUpdateDeduper 구조체는 FavoriteTeamLiveActivityUpdateDeduper 타입의 역할과 값을 정의합니다.
struct FavoriteTeamLiveActivityUpdateDeduper: Sendable {
    private var activeGameID: UUID?
    private var contentStateKey: FavoriteTeamLiveActivityContentStateKey?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init() {}

    // decision 메서드는 이 타입의 주요 동작을 수행합니다.
    func decision(gameID: UUID, contentStateKey newContentStateKey: FavoriteTeamLiveActivityContentStateKey) -> FavoriteTeamLiveActivityDedupeDecision {
        let previousContentStateKey = activeGameID == gameID ? contentStateKey : nil
        let changedFields = newContentStateKey.changedFields(comparedTo: previousContentStateKey)
        return FavoriteTeamLiveActivityDedupeDecision(
            shouldSkip: activeGameID == gameID && previousContentStateKey == newContentStateKey,
            previousContentStateKey: previousContentStateKey,
            newContentStateKey: newContentStateKey,
            changedFields: changedFields
        )
    }

    // record 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    mutating func record(gameID: UUID, contentStateKey: FavoriteTeamLiveActivityContentStateKey) {
        activeGameID = gameID
        self.contentStateKey = contentStateKey
    }

    // reset 메서드는 저장된 상태나 캐시 값을 정리합니다.
    mutating func reset() {
        activeGameID = nil
        contentStateKey = nil
    }
}

@MainActor
protocol FavoriteTeamLiveActivityControlling: AnyObject {
    var isSupported: Bool { get }
    var activeGameID: UUID? { get }

    // startOrUpdate 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func startOrUpdate(using snapshot: FavoriteTeamLiveActivitySnapshot) async throws
    // endCurrent 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func endCurrent() async
}

@MainActor
final class NoOpFavoriteTeamLiveActivityController: FavoriteTeamLiveActivityControlling {
    let isSupported: Bool = false
    let activeGameID: UUID? = nil

    // startOrUpdate 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func startOrUpdate(using snapshot: FavoriteTeamLiveActivitySnapshot) async throws {}

    // endCurrent 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func endCurrent() async {}
}

// FavoriteTeamLiveActivitySupport 열거형는 FavoriteTeamLiveActivitySupport 타입의 역할과 값을 정의합니다.
enum FavoriteTeamLiveActivitySupport {
    // hasWidgetExtension 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    static func hasWidgetExtension(in bundle: Bundle = .main) -> Bool {
        guard let pluginsURL = bundle.builtInPlugInsURL,
              let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil
              ) else {
            return false
        }

        return pluginURLs.contains { url in
            guard url.pathExtension == "appex",
                  let bundle = Bundle(url: url),
                  let extensionInfo = bundle.infoDictionary?["NSExtension"] as? [String: Any],
                  let extensionPoint = extensionInfo["NSExtensionPointIdentifier"] as? String else {
                return false
            }
            return extensionPoint == "com.apple.widgetkit-extension"
        }
    }

    static var isSupported: Bool {
        #if canImport(ActivityKit)
        guard hasWidgetExtension() else { return false }
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }
}

#if canImport(ActivityKit)
@MainActor
final class FavoriteTeamLiveActivityManager: FavoriteTeamLiveActivityControlling {
    let isSupported: Bool

    private var activity: Activity<FavoriteTeamGameActivityAttributes>?
    private(set) var activeGameID: UUID?
    private var updateDeduper = FavoriteTeamLiveActivityUpdateDeduper()
    private let tokenRegistrationClient: any LiveActivityTokenRegistrationClient
    private var pushTokenObservationTask: Task<Void, Never>?
    private var registeredTokenKeys: Set<LiveActivityTokenRegistrationKey> = []

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(tokenRegistrationClient: (any LiveActivityTokenRegistrationClient)? = nil) {
        self.isSupported = FavoriteTeamLiveActivitySupport.isSupported
        self.tokenRegistrationClient = tokenRegistrationClient ?? LiveActivityTokenRegistrationClientFactory.makeAppClient()
    }

    // startOrUpdate 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func startOrUpdate(using snapshot: FavoriteTeamLiveActivitySnapshot) async throws {
        guard isSupported else { return }

        let attributes = snapshot.activityAttributes()
        let contentState = snapshot.contentState()
        let contentStateKey = snapshot.contentStateKey
        let dedupeDecision = updateDeduper.decision(gameID: snapshot.gameID, contentStateKey: contentStateKey)
        AppLog.info(.liveActivity, "[LiveActivity] startOrUpdate received gameID=\(snapshot.gameID.uuidString) publicGameID=\(snapshot.publicGameID ?? "<nil>") providerGameID=\(snapshot.providerGameID ?? "<nil>") phase=\(snapshot.isPreGame ? "preGame" : "active")")
        #if DEBUG
        print("[LiveActivityPayload] gameID=\(snapshot.gameID.uuidString) score=\(snapshot.favoriteScoreText):\(snapshot.opponentScoreText) inning=\(snapshot.inningText) balls=\(snapshot.balls.map(String.init) ?? "-") strikes=\(snapshot.strikes.map(String.init) ?? "-") outs=\(snapshot.outs.map(String.init) ?? "-") bases=\((snapshot.runnerOnFirst ?? false) ? "1" : "-")\((snapshot.runnerOnSecond ?? false) ? "2" : "-")\((snapshot.runnerOnThird ?? false) ? "3" : "-") batter=\(snapshot.currentBatterName ?? "<nil>") pitcher=\(snapshot.currentPitcherName ?? "<nil>")")
        print("[LiveActivityPayload] dedupe previousContentStateKey=\(dedupeDecision.previousContentStateKey?.description ?? "<nil>") newContentStateKey=\(dedupeDecision.newContentStateKey.description)")
        #endif
        if activity != nil, dedupeDecision.shouldSkip {
            #if DEBUG
            print("[LiveActivityPayload] skip reason=contentStateUnchanged gameID=\(snapshot.gameID.uuidString) previousContentStateKey=\(dedupeDecision.previousContentStateKey?.description ?? "<nil>") newContentStateKey=\(dedupeDecision.newContentStateKey.description)")
            #endif
            AppLog.info(.liveActivity, "[LiveActivity] update skipped reason=contentStateUnchanged gameID=\(snapshot.gameID.uuidString)")
            return
        }
        #if DEBUG
        print("[LiveActivityPayload] update reason=contentStateChanged gameID=\(snapshot.gameID.uuidString) changedFields=\(dedupeDecision.changedFields)")
        #endif
        AppLog.info(.liveActivity, "[LiveActivity] update requested reason=contentStateChanged gameID=\(snapshot.gameID.uuidString) changedFields=\(dedupeDecision.changedFields)")
        let content = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(120)
        )
        #if DEBUG
        print("[LiveActivityPayload] local Activity.update payload gameID=\(snapshot.gameID.uuidString) contentState=\(contentState)")
        #endif

        if activity == nil {
            activity = Activity<FavoriteTeamGameActivityAttributes>.activities.first {
                $0.attributes.gameID == snapshot.gameID.uuidString
            }
            activeGameID = activity == nil ? activeGameID : snapshot.gameID
            if let activity {
                observePushTokens(for: activity, snapshot: snapshot)
            }
        }

        if let activity, activeGameID == snapshot.gameID {
            await activity.update(content)
            AppLog.info(.liveActivity, "[LiveActivity] update completed activityID=\(activity.id) gameID=\(snapshot.gameID.uuidString) phase=\(snapshot.isPreGame ? "preGame" : "active")")
        } else {
            if let activity {
                AppLog.info(.liveActivity, "[LiveActivity] end requested reason=replaceExisting activityID=\(activity.id) gameID=\(snapshot.gameID.uuidString)")
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            activity = try Activity.request(attributes: attributes, content: content, pushType: .token)
            if let activity {
                #if DEBUG
                print("[LiveActivity] activity started activityID=\(activity.id) gameID=\(snapshot.gameID.uuidString) pushType=token publicGameID=\(snapshot.publicGameID ?? "<nil>") providerGameID=\(snapshot.providerGameID ?? "<nil>") databaseID=\(snapshot.databaseID) stableDetailIdentity=\(snapshot.stableDetailIdentity)")
                #endif
                AppLog.info(.liveActivity, "[LiveActivity] start completed activityID=\(activity.id) gameID=\(snapshot.gameID.uuidString) pushType=token publicGameID=\(snapshot.publicGameID ?? "<nil>") providerGameID=\(snapshot.providerGameID ?? "<nil>")")
                observePushTokens(for: activity, snapshot: snapshot)
            }
        }

        activeGameID = snapshot.gameID
        updateDeduper.record(gameID: snapshot.gameID, contentStateKey: contentStateKey)
    }

    // endCurrent 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func endCurrent() async {
        guard let activity else { return }
        AppLog.info(.liveActivity, "[LiveActivity] end requested activityID=\(activity.id)")
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        activeGameID = nil
        updateDeduper.reset()
        pushTokenObservationTask?.cancel()
        pushTokenObservationTask = nil
        AppLog.info(.liveActivity, "[LiveActivity] end completed")
    }

    // observePushTokens 메서드는 이 타입의 주요 동작을 수행합니다.
    private func observePushTokens(for activity: Activity<FavoriteTeamGameActivityAttributes>, snapshot: FavoriteTeamLiveActivitySnapshot) {
        pushTokenObservationTask?.cancel()
        pushTokenObservationTask = Task { [tokenRegistrationClient] in
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                let payload = LiveActivityTokenRegistrationPayload(
                    activityId: activity.id,
                    activityToken: token,
                    favoriteTeamID: snapshot.favoriteTeamID,
                    publicGameID: snapshot.publicGameID,
                    providerGameID: snapshot.providerGameID,
                    databaseID: snapshot.databaseID,
                    stableDetailIdentity: snapshot.stableDetailIdentity
                )
                #if DEBUG
                print("[LiveActivity] push token received activityID=\(activity.id) tokenPrefix=\(token.prefix(8)) environment=\(payload.environment) buildConfiguration=\(AppBuildConfiguration.current)")
                #else
                print("[LiveActivity] push token received reason=tokenUpdate environment=\(payload.environment) buildConfiguration=\(AppBuildConfiguration.current)")
                #endif
                AppLog.info(.liveActivity, "[LiveActivity] push token received environment=\(payload.environment) buildConfiguration=\(AppBuildConfiguration.current)")
                let key = LiveActivityTokenRegistrationKey(payload: payload, endpointDescription: tokenRegistrationClient.debugEndpointDescription)
                await MainActor.run {
                    guard self.registeredTokenKeys.insert(key).inserted else {
                        #if DEBUG
                        print("[LiveActivity] token registration skipped duplicate \(key)")
                        #endif
                        AppLog.info(.liveActivity, "[LiveActivity] token registration skipped duplicate")
                        return
                    }
                }
                do {
                    _ = try await tokenRegistrationClient.register(payload)
                    #if DEBUG
                    print("[LiveActivity] token registration success activityID=\(activity.id) tokenPrefix=\(token.prefix(8)) environment=\(payload.environment) publicGameID=\(payload.publicGameID ?? "<nil>") providerGameID=\(payload.providerGameID ?? "<nil>") databaseID=\(payload.databaseID) stableDetailIdentity=\(payload.stableDetailIdentity)")
                    #else
                    print("[LiveActivity] token registration success reason=activityTokenRegistration environment=\(payload.environment)")
                    #endif
                    AppLog.info(.liveActivity, "[LiveActivity] token registration success environment=\(payload.environment)")
                } catch {
                    #if DEBUG
                    print("[LiveActivity] token registration failure activityID=\(activity.id) tokenPrefix=\(token.prefix(8)) environment=\(payload.environment) endpoint=\(tokenRegistrationClient.debugEndpointDescription ?? "missing") error=\(error)")
                    #else
                    print("[LiveActivity] token registration failure reason=activityTokenRegistration environment=\(payload.environment)")
                    #endif
                    AppLog.error(.liveActivity, "[LiveActivity] token registration failure environment=\(payload.environment) error=\(error)")
                }
            }
        }
    }
}
#endif
