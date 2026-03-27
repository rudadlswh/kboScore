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

struct FavoriteTeamLiveActivitySnapshot: Hashable, Sendable {
    let gameID: UUID
    let favoriteTeamID: String
    let favoriteTeamName: String
    let favoriteTeamShortName: String
    let opponentTeamID: String
    let opponentTeamName: String
    let opponentTeamShortName: String
    let favoriteScoreText: String
    let opponentScoreText: String
    let inningText: String
    let summaryText: String
    let venue: String
    let isHomeGame: Bool

    static func make(from game: GameDetail, favoriteTeamID: String?) -> FavoriteTeamLiveActivitySnapshot? {
        guard let favoriteTeamID else { return nil }

        let favoriteTeam: Team
        let opponentTeam: Team
        let favoriteScore: Int?
        let opponentScore: Int?
        let isHomeGame: Bool

        if game.homeTeam.id == favoriteTeamID {
            favoriteTeam = game.homeTeam
            opponentTeam = game.awayTeam
            favoriteScore = game.homeScore
            opponentScore = game.awayScore
            isHomeGame = true
        } else if game.awayTeam.id == favoriteTeamID {
            favoriteTeam = game.awayTeam
            opponentTeam = game.homeTeam
            favoriteScore = game.awayScore
            opponentScore = game.homeScore
            isHomeGame = false
        } else {
            return nil
        }

        return FavoriteTeamLiveActivitySnapshot(
            gameID: game.id,
            favoriteTeamID: favoriteTeam.id,
            favoriteTeamName: favoriteTeam.name,
            favoriteTeamShortName: favoriteTeam.shortName,
            opponentTeamID: opponentTeam.id,
            opponentTeamName: opponentTeam.name,
            opponentTeamShortName: opponentTeam.shortName,
            favoriteScoreText: favoriteScore.map(String.init) ?? "-",
            opponentScoreText: opponentScore.map(String.init) ?? "-",
            inningText: game.inningText ?? game.status.title,
            summaryText: game.status.title,
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
            favoriteScoreText: favoriteScoreText,
            opponentScoreText: opponentScoreText,
            inningText: inningText,
            summaryText: summaryText
        )
    }
    #endif
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

    init() {
        self.isSupported = FavoriteTeamLiveActivitySupport.isSupported
    }

    func startOrUpdate(using snapshot: FavoriteTeamLiveActivitySnapshot) async throws {
        guard isSupported else { return }

        let attributes = snapshot.activityAttributes()
        let contentState = snapshot.contentState()
        let content = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(120)
        )

        if let activity, activeGameID == snapshot.gameID {
            await activity.update(content)
        } else {
            if let activity {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        }

        activeGameID = snapshot.gameID
    }

    func endCurrent() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        activeGameID = nil
    }
}
#endif
