//
//  GameBoxscoreClient.swift
//  kboScore
//  기능 설명: 경기 상세 기록 데이터를 외부/원격 소스에서 가져오는 클라이언트 기능을 담당합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/11/26.
//

import Foundation

protocol GameBoxscoreFetching: Sendable {
    nonisolated var cacheIdentity: String { get }
    // fetchGameBoxscore 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameBoxscore(gameId: String) async throws -> GameBoxscoreResponse
}

// GameBoxscoreResponse 구조체는 GameBoxscoreResponse 타입의 역할과 값을 정의합니다.
nonisolated struct GameBoxscoreResponse: Codable, Equatable, Sendable {
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

    // empty 메서드는 이 타입의 주요 동작을 수행합니다.
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

// GameBatterRecord 구조체는 GameBatterRecord 타입의 역할과 값을 정의합니다.
nonisolated struct GameBatterRecord: Codable, Equatable, Sendable {
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
    let groundedIntoDoublePlay: Int?
    let errors: Int?
    let battingAverage: String?
}

// GamePitcherRecord 구조체는 GamePitcherRecord 타입의 역할과 값을 정의합니다.
nonisolated struct GamePitcherRecord: Codable, Equatable, Sendable {
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

// GameBoxscoreClientFactory 열거형는 실행 환경에 맞는 구현체 생성을 담당합니다.
nonisolated enum GameBoxscoreClientFactory {
    // makeAppClient 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // resolveCandidate 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
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

    // isAllowed 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
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

    // isLocalhost 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private static func isLocalhost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

// NoOpGameBoxscoreClient 구조체는 외부 서비스나 시스템 기능 호출을 캡슐화합니다.
struct NoOpGameBoxscoreClient: GameBoxscoreFetching {
    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init() {}

    nonisolated var cacheIdentity: String { "noop" }

    // fetchGameBoxscore 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameBoxscore(gameId: String) async throws -> GameBoxscoreResponse {
        GameBoxscoreResponse.empty(gameId: gameId)
    }
}

// BackendGameBoxscoreClient 구조체는 외부 서비스나 시스템 기능 호출을 캡슐화합니다.
struct BackendGameBoxscoreClient: GameBoxscoreFetching {
    private let baseURL: URL
    private let session: URLSession

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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

    // fetchGameBoxscore 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

// GameBoxscoreClientError 열거형는 실패 상황을 구분하고 호출자에게 전달합니다.
enum GameBoxscoreClientError: Error, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
}

extension GameBoxscoreResponse {
    var gameCenterReview: GameCenterReview? {
        guard hasRecords else { return nil }
        return GameCenterReview(
            summaryItems: gameCenterSummaryItems,
            awayBatting: GameCenterBattingSection(lines: awayBatters.map(\.gameCenterLine), totals: nil),
            homeBatting: GameCenterBattingSection(lines: homeBatters.map(\.gameCenterLine), totals: nil),
            awayPitching: GameCenterPitchingSection(lines: awayPitchers.map(\.gameCenterLine)),
            homePitching: GameCenterPitchingSection(lines: homePitchers.map(\.gameCenterLine)),
            recordSource: .fullBoxscore
        )
    }

    private var gameCenterSummaryItems: [GameCenterSummaryItem] {
        [
            teamTotalSummaryItem(title: "도루", away: awayBatters.total(\.stolenBases), home: homeBatters.total(\.stolenBases)),
            teamTotalSummaryItem(title: "병살타", away: awayBatters.total(\.groundedIntoDoublePlay), home: homeBatters.total(\.groundedIntoDoublePlay)),
            teamTotalSummaryItem(title: "실책", away: awayBatters.total(\.errors), home: homeBatters.total(\.errors))
        ].compactMap { $0 }
    }

    // teamTotalSummaryItem 메서드는 이 타입의 주요 동작을 수행합니다.
    private func teamTotalSummaryItem(title: String, away: Int?, home: Int?) -> GameCenterSummaryItem? {
        guard away != nil || home != nil else { return nil }
        let awayValue = String(away ?? 0)
        let homeValue = String(home ?? 0)
        return GameCenterSummaryItem(title: title, value: "\(awayValue) - \(homeValue)", values: [awayValue, homeValue])
    }
}

private extension Array where Element == GameBatterRecord {
    // total 메서드는 이 타입의 주요 동작을 수행합니다.
    func total(_ keyPath: KeyPath<GameBatterRecord, Int?>) -> Int? {
        let values = compactMap { $0[keyPath: keyPath] }
        return values.isEmpty ? nil : values.reduce(0, +)
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
    // sortedBySourceOrder 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    nonisolated func sortedBySourceOrder() -> [GameBatterRecord] {
        sorted { lhs, rhs in
            if lhs.sourceOrder == rhs.sourceOrder {
                return lhs.playerName < rhs.playerName
            }
            return lhs.sourceOrder < rhs.sourceOrder
        }
    }
}

private extension Array where Element == GamePitcherRecord {
    // sortedBySourceOrder 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    nonisolated func sortedBySourceOrder() -> [GamePitcherRecord] {
        sorted { lhs, rhs in
            if lhs.sourceOrder == rhs.sourceOrder {
                return lhs.playerName < rhs.playerName
            }
            return lhs.sourceOrder < rhs.sourceOrder
        }
    }
}
