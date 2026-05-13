//
//  GameBoxscoreClient.swift
//  kboScore
//
//  Created by Codex on 5/11/26.
//

import Foundation

protocol GameBoxscoreFetching: Sendable {
    nonisolated var cacheIdentity: String { get }
    nonisolated func fetchGameBoxscore(gameId: String) async throws -> GameBoxscoreResponse
}

struct GameBoxscoreResponse: Codable, Equatable, Sendable {
    let gameId: String
    let awayBatters: [GameBatterRecord]
    let homeBatters: [GameBatterRecord]
    let awayPitchers: [GamePitcherRecord]
    let homePitchers: [GamePitcherRecord]
    let updatedAt: String?
    let isStale: Bool

    var hasRecords: Bool {
        awayBatters.isEmpty == false ||
            homeBatters.isEmpty == false ||
            awayPitchers.isEmpty == false ||
            homePitchers.isEmpty == false
    }

    var sortedBySourceOrder: GameBoxscoreResponse {
        GameBoxscoreResponse(
            gameId: gameId,
            awayBatters: awayBatters.sortedBySourceOrder(),
            homeBatters: homeBatters.sortedBySourceOrder(),
            awayPitchers: awayPitchers.sortedBySourceOrder(),
            homePitchers: homePitchers.sortedBySourceOrder(),
            updatedAt: updatedAt,
            isStale: isStale
        )
    }

    static func empty(gameId: String) -> GameBoxscoreResponse {
        GameBoxscoreResponse(
            gameId: gameId,
            awayBatters: [],
            homeBatters: [],
            awayPitchers: [],
            homePitchers: [],
            updatedAt: nil,
            isStale: false
        )
    }
}

struct GameBatterRecord: Codable, Equatable, Sendable {
    let sourceOrder: Int
    let battingOrder: Int?
    let position: String?
    let playerName: String
    let atBats: Int?
    let runs: Int?
    let hits: Int?
    let rbi: Int?
    let homeRuns: Int?
    let walks: Int?
    let strikeouts: Int?
    let stolenBases: Int?
    let battingAverage: String?
}

struct GamePitcherRecord: Codable, Equatable, Sendable {
    let sourceOrder: Int
    let pitchingOrder: Int?
    let playerName: String
    let appearance: String?
    let decisionResult: String?
    let wins: Int?
    let losses: Int?
    let saves: Int?
    let inningsPitched: String?
    let battersFaced: Int?
    let pitchCount: Int?
    let atBats: Int?
    let hits: Int?
    let homeRuns: Int?
    let walksOrHitByPitch: Int?
    let strikeouts: Int?
    let runs: Int?
    let earnedRuns: Int?
    let era: String?
}

enum GameBoxscoreClientFactory {
    static func makeAppClient() -> any GameBoxscoreFetching {
        let processValue = ProcessInfo.processInfo.environment["KBO_BACKEND_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleValue = (Bundle.main.object(forInfoDictionaryKey: "KBOBackendBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        #if targetEnvironment(simulator)
        let candidates: [(source: String, value: String?)] = [
            ("default", "http://localhost:8088"),
            ("environment", processValue),
            ("plist", bundleValue)
        ]
        #else
        let candidates: [(source: String, value: String?)] = [
            ("environment", processValue),
            ("plist", bundleValue)
        ]
        #endif
        #else
        let candidates: [(source: String, value: String?)] = [
            ("environment", processValue),
            ("plist", bundleValue)
        ]
        #endif

        guard let resolved = candidates.compactMap(resolveCandidate).first else {
            #if DEBUG
            print("[GameBoxscore] backendBaseURL source=none resolved=<none> client=noop")
            #endif
            return NoOpGameBoxscoreClient()
        }
        #if DEBUG
        print("[GameBoxscore] backendBaseURL source=\(resolved.source) resolved=\(resolved.url.absoluteString)")
        #endif
        return BackendGameBoxscoreClient(baseURL: resolved.url)
    }

    private static func resolveCandidate(_ candidate: (source: String, value: String?)) -> (source: String, url: URL)? {
        guard let rawValue = candidate.value,
              rawValue.isEmpty == false,
              rawValue.hasPrefix("$(") == false,
              let url = URL(string: rawValue),
              isAllowed(url) else {
            #if DEBUG
            if let value = candidate.value, value.isEmpty == false, value.hasPrefix("$(") == false {
                print("[GameBoxscore] backendBaseURL rejected source=\(candidate.source) value=\(value)")
            }
            #endif
            return nil
        }
        return (candidate.source, url)
    }

    private static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              url.host?.isEmpty == false else {
            return false
        }
        #if DEBUG
        #if os(iOS) && !targetEnvironment(simulator)
        if isLocalhost(url) {
            return false
        }
        #endif
        return scheme == "http" || scheme == "https"
        #else
        return scheme == "https"
        #endif
    }

    private static func isLocalhost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

struct NoOpGameBoxscoreClient: GameBoxscoreFetching {
    nonisolated init() {}

    nonisolated var cacheIdentity: String { "noop" }

    nonisolated func fetchGameBoxscore(gameId: String) async throws -> GameBoxscoreResponse {
        GameBoxscoreResponse.empty(gameId: gameId)
    }
}

struct BackendGameBoxscoreClient: GameBoxscoreFetching {
    private let baseURL: URL
    private let session: URLSession

    nonisolated init(
        baseURL: URL,
        session: URLSession = .shared
    ) {
        if baseURL.absoluteString.hasSuffix("/") {
            self.baseURL = baseURL
        } else {
            self.baseURL = URL(string: baseURL.absoluteString + "/") ?? baseURL
        }
        self.session = session
    }

    nonisolated var cacheIdentity: String {
        baseURL.absoluteString
    }

    nonisolated func fetchGameBoxscore(gameId: String) async throws -> GameBoxscoreResponse {
        guard let encodedGameId = gameId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "api/v1/games/\(encodedGameId)/boxscore", relativeTo: baseURL)?.absoluteURL else {
            throw GameBoxscoreClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 2.5
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GameBoxscoreClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GameBoxscoreClientError.httpStatus(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(GameBoxscoreResponse.self, from: data)
        return decoded.sortedBySourceOrder
    }
}

enum GameBoxscoreClientError: Error, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
}

extension GameBoxscoreResponse {
    var gameCenterReview: GameCenterReview? {
        guard hasRecords else { return nil }
        return GameCenterReview(
            summaryItems: [],
            awayBatting: GameCenterBattingSection(lines: awayBatters.map(\.gameCenterLine), totals: nil),
            homeBatting: GameCenterBattingSection(lines: homeBatters.map(\.gameCenterLine), totals: nil),
            awayPitching: GameCenterPitchingSection(lines: awayPitchers.map(\.gameCenterLine)),
            homePitching: GameCenterPitchingSection(lines: homePitchers.map(\.gameCenterLine))
        )
    }
}

private extension GameBatterRecord {
    var gameCenterLine: GameCenterBattingLine {
        GameCenterBattingLine(
            battingOrder: battingOrder.map(String.init) ?? "",
            position: position ?? "",
            name: playerName,
            atBats: atBats.map(String.init),
            runs: runs.map(String.init),
            hits: hits.map(String.init),
            runsBattedIn: rbi.map(String.init),
            homeRuns: homeRuns.map(String.init),
            walks: walks.map(String.init),
            strikeouts: strikeouts.map(String.init),
            stolenBases: stolenBases.map(String.init),
            average: battingAverage,
            plateAppearanceHomeRuns: nil,
            plateAppearanceWalks: nil,
            plateAppearanceStrikeouts: nil
        )
    }
}

private extension GamePitcherRecord {
    var gameCenterLine: GameCenterPitchingLine {
        GameCenterPitchingLine(
            pitchingOrder: pitchingOrder.map(String.init),
            name: playerName,
            role: appearance,
            result: decisionResult,
            innings: inningsPitched,
            battersFaced: battersFaced.map(String.init),
            pitches: pitchCount.map(String.init),
            atBats: atBats.map(String.init),
            hitsAllowed: hits.map(String.init),
            walksAllowed: nil,
            hitBatters: nil,
            walksOrHitByPitch: walksOrHitByPitch.map(String.init),
            strikeouts: strikeouts.map(String.init),
            homeRunsAllowed: homeRuns.map(String.init),
            runsAllowed: runs.map(String.init),
            earnedRuns: earnedRuns.map(String.init),
            earnedRunAverage: era
        )
    }
}

private extension Array where Element == GameBatterRecord {
    func sortedBySourceOrder() -> [GameBatterRecord] {
        sorted { lhs, rhs in
            if lhs.sourceOrder == rhs.sourceOrder {
                return lhs.playerName < rhs.playerName
            }
            return lhs.sourceOrder < rhs.sourceOrder
        }
    }
}

private extension Array where Element == GamePitcherRecord {
    func sortedBySourceOrder() -> [GamePitcherRecord] {
        sorted { lhs, rhs in
            if lhs.sourceOrder == rhs.sourceOrder {
                return lhs.playerName < rhs.playerName
            }
            return lhs.sourceOrder < rhs.sourceOrder
        }
    }
}
