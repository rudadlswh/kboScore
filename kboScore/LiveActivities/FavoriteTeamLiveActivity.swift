//
//  FavoriteTeamLiveActivity.swift
//  kboScore
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

    var contentFingerprint: String {
        var parts: [String] = []
        parts.append(gameID.uuidString)
        parts.append(isPreGame.description)
        parts.append(favoriteScoreText)
        parts.append(opponentScoreText)
        parts.append(inningText)
        parts.append(summaryText)
        parts.append(favoriteStartingPitcherName ?? "-")
        parts.append(opponentStartingPitcherName ?? "-")
        parts.append(balls.map(String.init) ?? "-")
        parts.append(strikes.map(String.init) ?? "-")
        parts.append(outs.map(String.init) ?? "-")
        parts.append(runnerOnFirst.map(String.init) ?? "-")
        parts.append(runnerOnSecond.map(String.init) ?? "-")
        parts.append(runnerOnThird.map(String.init) ?? "-")
        parts.append(currentBatterName ?? "-")
        parts.append(currentPitcherName ?? "-")
        return parts.joined(separator: "|")
    }

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
        let isPreGame = game.status == .upcoming || (game.status.isFinishedLike == false && Date() < game.scheduledStart)
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
            isHomeGame: isHomeGame
        )
    }

    #if canImport(ActivityKit)
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

public struct FavoriteTeamLiveActivityUpdateDeduper: Sendable {
    private var activeGameID: UUID?
    private var contentFingerprint: String?

    public init() {}

    public func isDuplicate(gameID: UUID, contentFingerprint: String) -> Bool {
        activeGameID == gameID && self.contentFingerprint == contentFingerprint
    }

    public mutating func record(gameID: UUID, contentFingerprint: String) {
        activeGameID = gameID
        self.contentFingerprint = contentFingerprint
    }

    public mutating func reset() {
        activeGameID = nil
        contentFingerprint = nil
    }
}

@MainActor
protocol FavoriteTeamLiveActivityControlling: AnyObject {
    var isSupported: Bool { get }
    var activeGameID: UUID? { get }

    func startOrUpdate(using snapshot: FavoriteTeamLiveActivitySnapshot) async throws
    func endCurrent() async
}

@MainActor
final class NoOpFavoriteTeamLiveActivityController: FavoriteTeamLiveActivityControlling {
    let isSupported: Bool = false
    let activeGameID: UUID? = nil

    func startOrUpdate(using snapshot: FavoriteTeamLiveActivitySnapshot) async throws {}

    func endCurrent() async {}
}

enum FavoriteTeamLiveActivitySupport {
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

    init() {
        self.isSupported = FavoriteTeamLiveActivitySupport.isSupported
    }

    func startOrUpdate(using snapshot: FavoriteTeamLiveActivitySnapshot) async throws {
        guard isSupported else { return }

        let attributes = snapshot.activityAttributes()
        let contentState = snapshot.contentState()
        let contentFingerprint = snapshot.contentFingerprint
        #if DEBUG
        print("[LiveActivityPayload] gameID=\(snapshot.gameID.uuidString) score=\(snapshot.favoriteScoreText):\(snapshot.opponentScoreText) inning=\(snapshot.inningText) balls=\(snapshot.balls.map(String.init) ?? "-") strikes=\(snapshot.strikes.map(String.init) ?? "-") outs=\(snapshot.outs.map(String.init) ?? "-") bases=\((snapshot.runnerOnFirst ?? false) ? "1" : "-")\((snapshot.runnerOnSecond ?? false) ? "2" : "-")\((snapshot.runnerOnThird ?? false) ? "3" : "-") batter=\(snapshot.currentBatterName ?? "<nil>") pitcher=\(snapshot.currentPitcherName ?? "<nil>")")
        #endif
        if activity != nil, updateDeduper.isDuplicate(gameID: snapshot.gameID, contentFingerprint: contentFingerprint) {
            #if DEBUG
            print("[LiveActivityPayload] skipped duplicate gameID=\(snapshot.gameID.uuidString)")
            #endif
            return
        }
        let content = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(120)
        )

        if activity == nil {
            activity = Activity<FavoriteTeamGameActivityAttributes>.activities.first {
                $0.attributes.gameID == snapshot.gameID.uuidString
            }
            activeGameID = activity == nil ? activeGameID : snapshot.gameID
        }

        if let activity, activeGameID == snapshot.gameID {
            await activity.update(content)
        } else {
            if let activity {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        }

        activeGameID = snapshot.gameID
        updateDeduper.record(gameID: snapshot.gameID, contentFingerprint: contentFingerprint)
    }

    func endCurrent() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        activeGameID = nil
        updateDeduper.reset()
    }
}
#endif
