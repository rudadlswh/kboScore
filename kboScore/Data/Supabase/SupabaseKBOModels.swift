//
//  SupabaseKBOModels.swift
//  kboScore
//  기능 설명: Supabase 공개 테이블 응답과 앱 도메인 모델 간 매핑을 정의합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 4/24/26.
//

import Foundation

// SupabaseConfiguration 구조체는 SupabaseConfiguration 타입의 역할과 값을 정의합니다.
nonisolated struct SupabaseConfiguration: Sendable {
    nonisolated static let productionSchema = "kbo_crawler_api"
    nonisolated static let developmentSchema = "kbo_crawler_api_dev"

    let url: URL
    let publishableKey: String
    let schema: String

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        url: URL,
        publishableKey: String,
        schema: String = Self.productionSchema
    ) {
        self.url = url
        self.publishableKey = publishableKey
        self.schema = schema
    }
}

private extension Array where Element == SupabaseGameBatterRecordRow {
    // total 메서드는 이 타입의 주요 동작을 수행합니다.
    func total(_ keyPath: KeyPath<SupabaseGameBatterRecordRow, Int?>) -> Int? {
        let values = compactMap { $0[keyPath: keyPath] }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

// SupabaseTeamRow 구조체는 SupabaseTeamRow 타입의 역할과 값을 정의합니다.
nonisolated struct SupabaseTeamRow: Decodable, Sendable {
    let id: UUID
    let code: String
    let name: String
    let shortName: String?

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case id
        case code = "team_code"
        case name
        case shortName = "short_name"
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        id: UUID,
        code: String,
        name: String,
        shortName: String?
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.shortName = shortName
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        code = try container.decodeIfPresent(String.self, forKey: .code) ??
            container.decode(String.self, forKey: .code)
        name = try container.decode(String.self, forKey: .name)
        shortName = try container.decodeIfPresent(String.self, forKey: .shortName)
    }
}

// SupabaseGameRow 구조체는 SupabaseGameRow 타입의 역할과 값을 정의합니다.
nonisolated struct SupabaseGameRow: Codable, Sendable {
    let id: UUID
    let publicGameID: String?
    let provider: String?
    let providerGameID: String?
    let gameDate: String
    let scheduledAt: Date?
    let stadium: String?
    let status: String?
    let homeTeamID: UUID
    let awayTeamID: UUID
    let homeScore: Int?
    let awayScore: Int?
    let inningState: String?
    let isCancelled: Bool?
    let isPostponed: Bool?
    let sourceUpdatedAt: Date?
    let updatedAt: Date?
    let statusReason: String?
    let finalConfirmedAt: Date?
    let liveLastCheckedAt: Date?
    let stadiumCode: String?
    let officialProviderGameID: String?
    let homeStartingPitcherName: String?
    let awayStartingPitcherName: String?

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case id
        case publicGameID = "public_game_id"
        case provider
        case providerGameID = "provider_game_id"
        case gameDate = "game_date"
        case scheduledAt = "scheduled_at"
        case stadium
        case status
        case homeTeamID = "home_team_id"
        case awayTeamID = "away_team_id"
        case homeScore = "home_score"
        case awayScore = "away_score"
        case inningState = "inning_state"
        case isCancelled = "is_cancelled"
        case isPostponed = "is_postponed"
        case sourceUpdatedAt = "source_updated_at"
        case updatedAt = "updated_at"
        case statusReason = "status_reason"
        case finalConfirmedAt = "final_confirmed_at"
        case liveLastCheckedAt = "live_last_checked_at"
        case stadiumCode = "stadium_code"
        case officialProviderGameID = "official_provider_game_id"
        case homeStartingPitcherName = "home_starting_pitcher_name"
        case awayStartingPitcherName = "away_starting_pitcher_name"
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        publicGameID = try container.decodeIfPresent(String.self, forKey: .publicGameID)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        providerGameID = try container.decodeIfPresent(String.self, forKey: .providerGameID)
        gameDate = try container.decode(String.self, forKey: .gameDate)
        scheduledAt = (try? container.decodeIfPresent(Date.self, forKey: .scheduledAt)) ??
            SupabaseDateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .scheduledAt))
        stadium = try container.decodeIfPresent(String.self, forKey: .stadium)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        homeTeamID = try container.decode(UUID.self, forKey: .homeTeamID)
        awayTeamID = try container.decode(UUID.self, forKey: .awayTeamID)
        homeScore = try container.decodeIfPresent(Int.self, forKey: .homeScore)
        awayScore = try container.decodeIfPresent(Int.self, forKey: .awayScore)
        inningState = try container.decodeIfPresent(String.self, forKey: .inningState)
        isCancelled = try container.decodeIfPresent(Bool.self, forKey: .isCancelled)
        isPostponed = try container.decodeIfPresent(Bool.self, forKey: .isPostponed)
        sourceUpdatedAt = (try? container.decodeIfPresent(Date.self, forKey: .sourceUpdatedAt)) ??
            SupabaseDateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .sourceUpdatedAt))
        updatedAt = (try? container.decodeIfPresent(Date.self, forKey: .updatedAt)) ??
            SupabaseDateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .updatedAt))
        statusReason = try container.decodeIfPresent(String.self, forKey: .statusReason)
        finalConfirmedAt = (try? container.decodeIfPresent(Date.self, forKey: .finalConfirmedAt)) ??
            SupabaseDateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .finalConfirmedAt))
        liveLastCheckedAt = (try? container.decodeIfPresent(Date.self, forKey: .liveLastCheckedAt)) ??
            SupabaseDateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .liveLastCheckedAt))
        stadiumCode = try container.decodeIfPresent(String.self, forKey: .stadiumCode)
        officialProviderGameID = try container.decodeIfPresent(String.self, forKey: .officialProviderGameID)
        homeStartingPitcherName = try container.decodeIfPresent(String.self, forKey: .homeStartingPitcherName)
        awayStartingPitcherName = try container.decodeIfPresent(String.self, forKey: .awayStartingPitcherName)
    }
}

// SupabaseLatestGameSnapshotRow 구조체는 SupabaseLatestGameSnapshotRow 타입의 역할과 값을 정의합니다.
nonisolated struct SupabaseLatestGameSnapshotRow: Decodable, Sendable {
    nonisolated static let selectColumns = "*"

    let gameID: UUID
    let inningLabel: String?
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let runnerOnFirst: Bool?
    let runnerOnSecond: Bool?
    let runnerOnThird: Bool?
    let firstBaseRunnerName: String?
    let secondBaseRunnerName: String?
    let thirdBaseRunnerName: String?
    let currentPitcherName: String?
    let currentBatterName: String?
    let homeScore: Int?
    let awayScore: Int?
    let sourceUpdatedAt: Date?
    let fetchedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
#if DEBUG
    let debugAvailableFieldNames: Set<String>
#endif

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        gameID = try container.decode(UUID.self, forKey: DynamicCodingKey("game_id"))
        inningLabel = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("inning_label"))
        balls = try container.decodeIfPresent(Int.self, forKey: DynamicCodingKey("balls"))
        strikes = try container.decodeIfPresent(Int.self, forKey: DynamicCodingKey("strikes"))
        outs = try container.decodeIfPresent(Int.self, forKey: DynamicCodingKey("outs"))
        runnerOnFirst = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKey("runner_on_first"))
        runnerOnSecond = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKey("runner_on_second"))
        runnerOnThird = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKey("runner_on_third"))
        firstBaseRunnerName = try Self.firstNonBlankString(
            in: container,
            keys: ["first_base_runner_name", "firstBaseRunnerName"]
        )
        secondBaseRunnerName = try Self.firstNonBlankString(
            in: container,
            keys: ["second_base_runner_name", "secondBaseRunnerName"]
        )
        thirdBaseRunnerName = try Self.firstNonBlankString(
            in: container,
            keys: ["third_base_runner_name", "thirdBaseRunnerName"]
        )
        currentPitcherName = try Self.firstNonBlankString(
            in: container,
            keys: ["current_pitcher_name", "pitcher_name", "pitcher", "currentPitcherName", "pitcherName"]
        )
        currentBatterName = try Self.firstNonBlankString(
            in: container,
            keys: ["current_batter_name", "batter_name", "current_hitter_name", "hitter_name", "batter", "hitter", "currentBatterName", "batterName"]
        )
        homeScore = try container.decodeIfPresent(Int.self, forKey: DynamicCodingKey("home_score"))
        awayScore = try container.decodeIfPresent(Int.self, forKey: DynamicCodingKey("away_score"))
        sourceUpdatedAt = Self.firstDate(in: container, keys: ["source_updated_at", "sourceUpdatedAt"])
        fetchedAt = Self.firstDate(in: container, keys: ["fetched_at", "fetchedAt", "source_updated_at", "sourceUpdatedAt"])
        createdAt = Self.firstDate(in: container, keys: ["snapshot_created_at", "snapshotCreatedAt", "created_at", "createdAt", "updated_at", "updatedAt"])
        updatedAt = Self.firstDate(in: container, keys: ["updated_at", "updatedAt", "snapshot_updated_at", "snapshotUpdatedAt"])
#if DEBUG
        debugAvailableFieldNames = Set(container.allKeys.map(\.stringValue))
#endif
    }

    // firstNonBlankString 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func firstNonBlankString(
        in container: KeyedDecodingContainer<DynamicCodingKey>,
        keys: [String]
    ) throws -> String? {
        for key in keys {
            let value = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(key))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, value.isEmpty == false {
                return value
            }
        }
        return nil
    }

    // firstDate 메서드는 snake_case/camelCase timestamp 필드 중 처음 디코딩 가능한 값을 반환합니다.
    private static func firstDate(
        in container: KeyedDecodingContainer<DynamicCodingKey>,
        keys: [String]
    ) -> Date? {
        for key in keys {
            let codingKey = DynamicCodingKey(key)
            if let date = try? container.decodeIfPresent(Date.self, forKey: codingKey) {
                return date
            }
            if let string = try? container.decodeIfPresent(String.self, forKey: codingKey),
               let date = SupabaseDateParser.parseTimestamp(string) {
                return date
            }
        }
        return nil
    }
}

// SupabaseGameBatterRecordRow 구조체는 SupabaseGameBatterRecordRow 타입의 역할과 값을 정의합니다.
struct SupabaseGameBatterRecordRow: Decodable, Sendable, Equatable {
    let id: UUID?
    let gameID: UUID
    let teamID: UUID
    let sourceOrder: Int?
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
    var sourceUpdatedAt: String? = nil
    var updatedAt: String? = nil

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case id
        case gameID = "game_id"
        case teamID = "team_id"
        case sourceOrder = "source_order"
        case battingOrder = "batting_order"
        case position
        case playerName = "player_name"
        case atBats = "at_bats"
        case runs
        case hits
        case rbi
        case homeRuns = "home_runs"
        case walks
        case strikeouts
        case stolenBases = "stolen_bases"
        case groundedIntoDoublePlay = "grounded_into_double_play"
        case errors
        case battingAverage = "batting_average"
        case sourceUpdatedAt = "source_updated_at"
        case updatedAt = "updated_at"
    }
}

// SupabaseGamePitcherRecordRow 구조체는 SupabaseGamePitcherRecordRow 타입의 역할과 값을 정의합니다.
struct SupabaseGamePitcherRecordRow: Decodable, Sendable, Equatable {
    let id: UUID?
    let gameID: UUID
    let teamID: UUID
    let sourceOrder: Int?
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
    var sourceUpdatedAt: String? = nil
    var updatedAt: String? = nil

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case id
        case gameID = "game_id"
        case teamID = "team_id"
        case sourceOrder = "source_order"
        case pitchingOrder = "pitching_order"
        case playerName = "player_name"
        case appearance
        case decisionResult = "decision_result"
        case wins
        case losses
        case saves
        case inningsPitched = "innings_pitched"
        case battersFaced = "batters_faced"
        case pitchCount = "pitch_count"
        case atBats = "at_bats"
        case hits
        case homeRuns = "home_runs"
        case walksOrHitByPitch = "walks_or_hit_by_pitch"
        case strikeouts
        case runs
        case earnedRuns = "earned_runs"
        case era
        case sourceUpdatedAt = "source_updated_at"
        case updatedAt = "updated_at"
    }
}

// SupabaseGameEventRow 구조체는 SupabaseGameEventRow 타입의 역할과 값을 정의합니다.
struct SupabaseGameEventRow: Decodable, Sendable, Equatable {
    let id: UUID?
    let gameID: UUID
    let providerEventID: String?
    let sequenceNumber: Int
    let inning: Int?
    let inningHalf: String?
    let eventType: String?
    let eventText: String

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case id
        case gameID = "game_id"
        case providerEventID = "provider_event_id"
        case sequenceNumber = "sequence_number"
        case inning
        case inningHalf = "inning_half"
        case eventType = "event_type"
        case eventText = "event_text"
    }
}

// DynamicCodingKey 구조체는 DynamicCodingKey 타입의 역할과 값을 정의합니다.
nonisolated private struct DynamicCodingKey: CodingKey, Hashable, Sendable {
    let stringValue: String
    let intValue: Int?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init?(stringValue: String) {
        self.init(stringValue)
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// SupabaseKBOMapper 열거형는 외부 데이터와 도메인 모델 사이의 변환을 담당합니다.
nonisolated enum SupabaseKBOMapper {
    // mapTeam 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func mapTeam(_ row: SupabaseTeamRow) -> Team {
        let normalizedCode = normalizeTeamCode(row.code)
        let identity = TeamIdentity.catalog[normalizedCode]
        let resolvedShortName = row.shortName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ??
            identity?.shortLabel ??
            row.name

        return Team(
            id: normalizedCode,
            name: row.name,
            shortName: resolvedShortName,
            englishName: identity?.displayName ?? row.name,
            markText: identity?.monogram ?? String(resolvedShortName.prefix(3)).uppercased()
        )
    }

    // mapTeams 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func mapTeams(_ rows: [SupabaseTeamRow]) -> [Team] {
        rows
            .map(mapTeam)
            .sorted { $0.id < $1.id }
    }

    // mapGames 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func mapGames(
        gameRows: [SupabaseGameRow],
        teamRows: [SupabaseTeamRow],
        snapshotRows: [SupabaseLatestGameSnapshotRow] = []
    ) -> [GameDetail] {
        let teamsByUUID = Dictionary(uniqueKeysWithValues: teamRows.map { ($0.id, mapTeam($0)) })
        let snapshotsByGameID = Dictionary(uniqueKeysWithValues: snapshotRows.map { ($0.gameID, $0) })
        let classifiedRows = gameRows.map(classifiedRow(from:))
#if DEBUG
        debugLogSeasonClassificationSummary(classifiedRows)
#endif
        let payload = classifiedRows.map { classifiedRow in
            mapGameDTO(
                classifiedRow,
                teamsByUUID: teamsByUUID,
                snapshot: snapshotsByGameID[classifiedRow.row.id]
            )
        }
        return KBODataMapper.mapGames(payload, teams: Array(teamsByUUID.values))
    }

    // mapGame 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func mapGame(
        row: SupabaseGameRow,
        teamRows: [SupabaseTeamRow],
        snapshot: SupabaseLatestGameSnapshotRow?,
        fallbackGame: GameDetail
    ) -> GameDetail {
        var teamsByUUID: [UUID: Team] = [
            row.awayTeamID: fallbackGame.awayTeam,
            row.homeTeamID: fallbackGame.homeTeam
        ]
        for teamRow in teamRows {
            teamsByUUID[teamRow.id] = mapTeam(teamRow)
        }

        let classifiedRow = classifiedRow(from: row)
#if DEBUG
        debugLogSeasonClassificationSummary([classifiedRow])
#endif
        let payload = [mapGameDTO(classifiedRow, teamsByUUID: teamsByUUID, snapshot: snapshot)]
        return KBODataMapper.mapGames(payload, teams: Array(teamsByUUID.values)).first ?? fallbackGame
    }

    // mapBootstrap 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func mapBootstrap(
        teamRows: [SupabaseTeamRow],
        gameRows: [SupabaseGameRow],
        notifications: [NotificationItem] = [],
        settings: AppSettings = .default
    ) -> KBOBootstrapData {
        let teams = mapTeams(teamRows)
        return KBOBootstrapData(
            teams: teams,
            games: mapGames(gameRows: gameRows, teamRows: teamRows),
            notifications: notifications,
            settings: settings
        )
    }

    // mapDetailedRecordReview 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    @MainActor
    static func mapDetailedRecordReview(
        game: GameDetail,
        recordGameID: UUID? = nil,
        awayTeamDatabaseID: UUID,
        homeTeamDatabaseID: UUID,
        batterRows: [SupabaseGameBatterRecordRow],
        pitcherRows: [SupabaseGamePitcherRecordRow],
        eventRows: [SupabaseGameEventRow] = []
    ) -> GameCenterReview? {
        let resolvedRecordGameID = recordGameID ?? game.id
        let awayBatters = sortedBatterRows(
            batterRows.filter { $0.gameID == resolvedRecordGameID && $0.teamID == awayTeamDatabaseID }
        )
        let homeBatters = sortedBatterRows(
            batterRows.filter { $0.gameID == resolvedRecordGameID && $0.teamID == homeTeamDatabaseID }
        )
        let awayPitchers = sortedPitcherRows(
            pitcherRows.filter { $0.gameID == resolvedRecordGameID && $0.teamID == awayTeamDatabaseID }
        )
        let homePitchers = sortedPitcherRows(
            pitcherRows.filter { $0.gameID == resolvedRecordGameID && $0.teamID == homeTeamDatabaseID }
        )

        guard awayBatters.isEmpty == false ||
            homeBatters.isEmpty == false ||
            awayPitchers.isEmpty == false ||
            homePitchers.isEmpty == false ||
            eventRows.isEmpty == false else {
            return nil
        }

        return GameCenterReview(
            summaryItems: gameCenterSummaryItems(awayBatters: awayBatters, homeBatters: homeBatters),
            awayBatting: GameCenterBattingSection(lines: awayBatters.map(mapBatterRecord), totals: nil),
            homeBatting: GameCenterBattingSection(lines: homeBatters.map(mapBatterRecord), totals: nil),
            awayPitching: GameCenterPitchingSection(lines: awayPitchers.map(mapPitcherRecord)),
            homePitching: GameCenterPitchingSection(lines: homePitchers.map(mapPitcherRecord)),
            recordSource: .dbLiveRecordsFresh
        )
    }

    // gameCenterSummaryItems 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    private static func gameCenterSummaryItems(
        awayBatters: [SupabaseGameBatterRecordRow],
        homeBatters: [SupabaseGameBatterRecordRow]
    ) -> [GameCenterSummaryItem] {
        [
            teamTotalSummaryItem(title: "도루", away: awayBatters.total(\.stolenBases), home: homeBatters.total(\.stolenBases)),
            teamTotalSummaryItem(title: "병살타", away: awayBatters.total(\.groundedIntoDoublePlay), home: homeBatters.total(\.groundedIntoDoublePlay)),
            teamTotalSummaryItem(title: "실책", away: awayBatters.total(\.errors), home: homeBatters.total(\.errors))
        ].compactMap { $0 }
    }

    // teamTotalSummaryItem 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    private static func teamTotalSummaryItem(title: String, away: Int?, home: Int?) -> GameCenterSummaryItem? {
        guard away != nil || home != nil else { return nil }
        let awayValue = String(away ?? 0)
        let homeValue = String(home ?? 0)
        return GameCenterSummaryItem(title: title, value: "\(awayValue) - \(homeValue)", values: [awayValue, homeValue])
    }

    // sortedBatterRows 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    @MainActor
    private static func sortedBatterRows(
        _ rows: [SupabaseGameBatterRecordRow]
    ) -> [SupabaseGameBatterRecordRow] {
        return rows.sorted { lhs, rhs in
            let lhsSourceOrder = lhs.sourceOrder ?? Int.max
            let rhsSourceOrder = rhs.sourceOrder ?? Int.max
            if lhsSourceOrder != rhsSourceOrder {
                return lhsSourceOrder < rhsSourceOrder
            }
            let lhsBattingOrder = lhs.battingOrder ?? Int.max
            let rhsBattingOrder = rhs.battingOrder ?? Int.max
            if lhsBattingOrder != rhsBattingOrder {
                return lhsBattingOrder < rhsBattingOrder
            }
            if lhs.playerName != rhs.playerName {
                return lhs.playerName < rhs.playerName
            }
            return false
        }
    }

    // sortedPitcherRows 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    @MainActor
    private static func sortedPitcherRows(
        _ rows: [SupabaseGamePitcherRecordRow]
    ) -> [SupabaseGamePitcherRecordRow] {
        return rows.sorted { lhs, rhs in
            let lhsPitchingOrder = lhs.pitchingOrder ?? Int.max
            let rhsPitchingOrder = rhs.pitchingOrder ?? Int.max
            if lhsPitchingOrder != rhsPitchingOrder {
                return lhsPitchingOrder < rhsPitchingOrder
            }
            let lhsSourceOrder = lhs.sourceOrder ?? Int.max
            let rhsSourceOrder = rhs.sourceOrder ?? Int.max
            if lhsSourceOrder != rhsSourceOrder {
                return lhsSourceOrder < rhsSourceOrder
            }
            if lhs.playerName != rhs.playerName {
                return lhs.playerName < rhs.playerName
            }
            return false
        }
    }

    // mapBatterRecord 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    @MainActor
    private static func mapBatterRecord(_ row: SupabaseGameBatterRecordRow) -> GameCenterBattingLine {
        GameCenterBattingLine(
            battingOrder: row.battingOrder.map(String.init) ?? "",
            position: row.position?.nilIfBlank ?? "",
            name: row.playerName,
            atBats: row.atBats.map(String.init),
            runs: row.runs.map(String.init),
            hits: row.hits.map(String.init),
            runsBattedIn: row.rbi.map(String.init),
            homeRuns: row.homeRuns.map(String.init),
            walks: row.walks.map(String.init),
            strikeouts: row.strikeouts.map(String.init),
            stolenBases: row.stolenBases.map(String.init),
            groundedIntoDoublePlay: row.groundedIntoDoublePlay.map(String.init),
            errors: row.errors.map(String.init),
            average: nil
        )
    }

    // mapPitcherRecord 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    @MainActor
    private static func mapPitcherRecord(_ row: SupabaseGamePitcherRecordRow) -> GameCenterPitchingLine {
        GameCenterPitchingLine(
            pitchingOrder: row.pitchingOrder.map(String.init),
            name: row.playerName,
            role: row.appearance?.nilIfBlank,
            result: row.decisionResult?.nilIfBlank,
            innings: row.inningsPitched?.nilIfBlank,
            battersFaced: row.battersFaced.map(String.init),
            pitches: row.pitchCount.map(String.init),
            atBats: row.atBats.map(String.init),
            hitsAllowed: row.hits.map(String.init),
            walksAllowed: nil,
            hitBatters: nil,
            walksOrHitByPitch: row.walksOrHitByPitch.map(String.init),
            strikeouts: row.strikeouts.map(String.init),
            homeRunsAllowed: row.homeRuns.map(String.init),
            runsAllowed: row.runs.map(String.init),
            earnedRuns: row.earnedRuns.map(String.init),
            earnedRunAverage: nil
        )
    }

    // mapGameDTO 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func mapGameDTO(
        _ classifiedRow: ClassifiedSupabaseGameRow,
        teamsByUUID: [UUID: Team],
        snapshot: SupabaseLatestGameSnapshotRow?
    ) -> KBOGameDTO {
        let row = classifiedRow.row
        let awayTeam = teamsByUUID[row.awayTeamID] ?? makeUnknownTeam(id: row.awayTeamID)
        let homeTeam = teamsByUUID[row.homeTeamID] ?? makeUnknownTeam(id: row.homeTeamID)

        let scheduledStart = row.scheduledAt ?? SupabaseDateParser.parseGameDate(row.gameDate) ?? .distantPast
        let resolvedStatus = statusText(for: row, scheduledStart: scheduledStart, snapshot: snapshot)
        let venue = row.stadium?.nilIfBlank ?? "장소 미정"
        let inningText = snapshot?.inningLabel?.nilIfBlank ?? row.inningState?.nilIfBlank
        let bases = snapshot.map {
            KBORunnerStateDTO(
                first: $0.runnerOnFirst ?? false,
                second: $0.runnerOnSecond ?? false,
                third: $0.runnerOnThird ?? false
            )
        }
        let currentPitcherName = snapshot?.currentPitcherName?.nilIfBlank
        let currentBatterName = snapshot?.currentBatterName?.nilIfBlank
        let baseRunners = snapshot.map {
            KBOBaseRunnersDTO(
                first: $0.firstBaseRunnerName?.nilIfBlank,
                second: $0.secondBaseRunnerName?.nilIfBlank,
                third: $0.thirdBaseRunnerName?.nilIfBlank
            )
        }
#if DEBUG
        if let snapshot {
            print("[BaseRunners] snapshot names first=\(snapshot.firstBaseRunnerName ?? "<nil>") second=\(snapshot.secondBaseRunnerName ?? "<nil>") third=\(snapshot.thirdBaseRunnerName ?? "<nil>")")
        }
#endif

        return KBOGameDTO(
            id: row.id,
            providerGameID: classifiedRow.providerGameID,
            scheduledStart: scheduledStart,
            venue: venue,
            awayTeamID: awayTeam.id,
            homeTeamID: homeTeam.id,
            awayScore: row.awayScore,
            homeScore: row.homeScore,
            statusCode: nil,
            statusText: resolvedStatus,
            seasonClassification: classifiedRow.seasonClassification.rawValue,
            inningText: inningText,
            bases: bases,
            baseRunners: baseRunners,
            balls: snapshot?.balls,
            strikes: snapshot?.strikes,
            outs: snapshot?.outs,
            highlightText: nil,
            events: [],
            note: makeNote(
                supabaseGameID: row.id,
                provider: row.provider,
                publicGameID: row.publicGameID,
                providerGameID: classifiedRow.providerGameID,
                officialProviderGameID: row.officialProviderGameID,
                sourceUpdatedAt: row.sourceUpdatedAt,
                updatedAt: row.updatedAt,
                liveLastCheckedAt: row.liveLastCheckedAt,
                finalConfirmedAt: row.finalConfirmedAt,
                statusReason: row.statusReason
            ),
            awayStartingPitcherName: row.awayStartingPitcherName?.nilIfBlank,
            homeStartingPitcherName: row.homeStartingPitcherName?.nilIfBlank,
            currentPitcherName: currentPitcherName,
            currentBatterName: currentBatterName
        )
    }

    // makeUnknownTeam 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated private static func makeUnknownTeam(id: UUID) -> Team {
        let fallbackID = "unknown-\(id.uuidString.lowercased())"
        return Team(
            id: fallbackID,
            name: "알 수 없는 팀",
            shortName: "미정",
            englishName: "Unknown Team",
            markText: "UNK"
        )
    }

    // makeNote 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated private static func makeNote(
        supabaseGameID: UUID,
        provider: String?,
        publicGameID: String?,
        providerGameID: String?,
        officialProviderGameID: String?,
        sourceUpdatedAt: Date?,
        updatedAt: Date?,
        liveLastCheckedAt: Date?,
        finalConfirmedAt: Date?,
        statusReason: String?
    ) -> String? {
        var components: [String] = []
        components.append("supabase_game_id=\(supabaseGameID.uuidString)")
        if let provider = provider?.nilIfBlank {
            components.append("provider=\(provider)")
        }
        if let publicGameID = publicGameID?.nilIfBlank {
            components.append("public_game_id=\(publicGameID)")
        }
        if let providerGameID = providerGameID?.nilIfBlank {
            components.append("provider_game_id=\(providerGameID)")
        }
        if let officialProviderGameID = officialProviderGameID?.nilIfBlank,
           officialProviderGameID != providerGameID?.nilIfBlank {
            components.append("official_provider_game_id=\(officialProviderGameID)")
        }
        if let sourceUpdatedAt {
            components.append("source_updated_at=\(SupabaseDateParser.debugTimestamp(sourceUpdatedAt))")
        }
        if let updatedAt {
            components.append("updated_at=\(SupabaseDateParser.debugTimestamp(updatedAt))")
        }
        if let liveLastCheckedAt {
            components.append("live_last_checked_at=\(SupabaseDateParser.debugTimestamp(liveLastCheckedAt))")
        }
        if let finalConfirmedAt {
            components.append("final_confirmed_at=\(SupabaseDateParser.debugTimestamp(finalConfirmedAt))")
        }
        if let statusReason = statusReason?.nilIfBlank {
            components.append("status_reason=\(statusReason)")
        }
        return components.isEmpty ? nil : components.joined(separator: " ")
    }

    // statusText 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func statusText(
        for row: SupabaseGameRow,
        scheduledStart: Date,
        snapshot: SupabaseLatestGameSnapshotRow? = nil
    ) -> String? {
        if row.isCancelled == true || row.isPostponed == true {
            logStatusMapping(
                row: row,
                rawStatus: row.status?.nilIfBlank,
                mappedStatus: .cancelled,
                resolvedStatusText: "cancelled",
                scheduledStart: scheduledStart,
                snapshot: snapshot,
                reason: row.isPostponed == true ? "postponedFlag" : "cancelledFlag",
                liveCorrection: "none"
            )
            return "cancelled"
        }
        let rowStatus = row.status?.nilIfBlank
        let mappedStatus = KBODataMapper.mapGameStatus(code: rowStatus, text: row.inningState?.nilIfBlank)
        if mappedStatus == .live,
           snapshotObservedDate(snapshot) == nil,
           snapshotHasLiveEvidence(snapshot) {
            logStatusMapping(
                row: row,
                rawStatus: rowStatus,
                mappedStatus: .live,
                resolvedStatusText: rowStatus ?? row.inningState?.nilIfBlank ?? "live",
                scheduledStart: scheduledStart,
                snapshot: snapshot,
                reason: "snapshotAt nil but accepted as live reason=liveProgressEvidence",
                liveCorrection: "accepted"
            )
            return rowStatus ?? row.inningState?.nilIfBlank ?? "live"
        }
        if mappedStatus == .live, !hasReliableLiveEvidence(row: row, snapshot: snapshot, scheduledStart: scheduledStart) {
            logStatusMapping(
                row: row,
                rawStatus: rowStatus,
                mappedStatus: .upcoming,
                resolvedStatusText: "scheduled",
                scheduledStart: scheduledStart,
                snapshot: snapshot,
                reason: liveRejectionReason(row: row, snapshot: snapshot, scheduledStart: scheduledStart),
                liveCorrection: "rejected"
            )
            return "scheduled"
        }
        if mappedStatus == .upcoming, snapshotHasFreshLiveProgress(snapshot, scheduledStart: scheduledStart) {
            logStatusMapping(
                row: row,
                rawStatus: rowStatus,
                mappedStatus: .live,
                resolvedStatusText: "live",
                scheduledStart: scheduledStart,
                snapshot: snapshot,
                reason: "freshSnapshotProgress",
                liveCorrection: "applied"
            )
            return "live"
        }
        let resolvedStatusText = rowStatus ?? row.inningState?.nilIfBlank
        logStatusMapping(
            row: row,
            rawStatus: rowStatus,
            mappedStatus: mappedStatus,
            resolvedStatusText: resolvedStatusText,
            scheduledStart: scheduledStart,
            snapshot: snapshot,
            reason: statusMappingReason(mappedStatus: mappedStatus, snapshot: snapshot, scheduledStart: scheduledStart),
            liveCorrection: "none"
        )
        return resolvedStatusText
    }

    // logStatusMapping 메서드는 Supabase 상태값이 앱 상태로 해석된 이유를 운영 로그에 남깁니다.
    nonisolated private static func logStatusMapping(
        row: SupabaseGameRow,
        rawStatus: String?,
        mappedStatus: GameStatus,
        resolvedStatusText: String?,
        scheduledStart: Date,
        snapshot: SupabaseLatestGameSnapshotRow?,
        reason: String,
        liveCorrection: String
    ) {
        let message = "[StatusMapping] game=\(logGameID(for: row)) raw=\(rawStatus ?? "<nil>") mapped=\(mappedStatus.rawValue) statusText=\(resolvedStatusText ?? "<nil>") reason=\(reason) scheduledAt=\(logTimeText(scheduledStart)) snapshotAt=\(logTimeText(snapshotObservedDate(snapshot))) stale=\(snapshotStaleText(snapshot, scheduledStart: scheduledStart)) liveCorrection=\(liveCorrection)"
        if liveCorrection == "rejected" || mappedStatus == .rainDelay || mappedStatus == .cancelled {
            AppLog.info(.statusMapping, message)
        } else {
            AppLog.debug(.statusMapping, message)
        }
    }

    // logGameID 메서드는 로그에서 추적 가능한 비민감 경기 식별자를 선택합니다.
    nonisolated private static func logGameID(for row: SupabaseGameRow) -> String {
        row.publicGameID?.nilIfBlank ??
            row.providerGameID?.nilIfBlank ??
            row.officialProviderGameID?.nilIfBlank ??
            row.id.uuidString
    }

    // statusMappingReason 메서드는 정상 매핑 경로의 대표 이유를 반환합니다.
    nonisolated private static func statusMappingReason(
        mappedStatus: GameStatus,
        snapshot: SupabaseLatestGameSnapshotRow?,
        scheduledStart: Date
    ) -> String {
        switch mappedStatus {
        case .rainDelay:
            "rainDelayOrSuspended"
        case .cancelled:
            "cancelledStatus"
        case .live:
            "officialLive"
        case .final:
            "officialFinal"
        case .upcoming:
            snapshot == nil ? "noSnapshot" : liveRejectionReason(row: nil, snapshot: snapshot, scheduledStart: scheduledStart)
        }
    }

    // liveRejectionReason 메서드는 live 승격을 거절한 구체적 이유를 반환합니다.
    nonisolated private static func liveRejectionReason(
        row: SupabaseGameRow?,
        snapshot: SupabaseLatestGameSnapshotRow?,
        scheduledStart: Date
    ) -> String {
        if let scheduledAt = row?.scheduledAt, Date() < scheduledAt {
            return "beforeScheduledAt"
        }
        guard let snapshot else {
            return "missingSnapshot"
        }
        guard let observedAt = snapshotObservedDate(snapshot) else {
            return "missingSnapshotTime"
        }
        if scheduledStart != .distantPast, observedAt < scheduledStart {
            return "staleSnapshot"
        }
        if snapshotHasLiveProgress(snapshot) == false {
            return "placeholderSnapshot"
        }
        return "noReliableLiveEvidence"
    }

    // snapshotObservedDate 메서드는 snapshot 관측 시각을 반환합니다.
    nonisolated private static func snapshotObservedDate(_ snapshot: SupabaseLatestGameSnapshotRow?) -> Date? {
        snapshot?.fetchedAt ?? snapshot?.createdAt
    }

    // snapshotStaleText 메서드는 scheduledStart 기준 snapshot stale 여부를 로그용 문자열로 반환합니다.
    nonisolated private static func snapshotStaleText(
        _ snapshot: SupabaseLatestGameSnapshotRow?,
        scheduledStart: Date
    ) -> String {
        guard scheduledStart != .distantPast, let observedAt = snapshotObservedDate(snapshot) else {
            return "unknown"
        }
        return observedAt < scheduledStart ? "true" : "false"
    }

    // logTimeText 메서드는 로그에 남길 시간을 KST HH:mm 형태로 축약합니다.
    nonisolated private static func logTimeText(_ date: Date?) -> String {
        guard let date, date != .distantPast else { return "<nil>" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // hasReliableLiveEvidence 메서드는 stale placeholder가 LIVE로 보이는 것을 막습니다.
    nonisolated private static func hasReliableLiveEvidence(
        row: SupabaseGameRow,
        snapshot: SupabaseLatestGameSnapshotRow?,
        scheduledStart: Date
    ) -> Bool {
        if let scheduledAt = row.scheduledAt, Date() < scheduledAt {
            return false
        }
        if hasExplicitLiveStatusReason(row.statusReason) {
            return true
        }
        if KBODataMapper.mapGameStatus(code: row.status?.nilIfBlank, text: nil) == .live,
           snapshotHasLiveEvidence(snapshot) {
            return true
        }
        if (row.awayScore ?? 0) > 0 || (row.homeScore ?? 0) > 0 {
            return true
        }
        return snapshotHasFreshLiveProgress(snapshot, scheduledStart: scheduledStart)
    }

    // hasExplicitLiveStatusReason 메서드는 공식 응답이 명시적으로 live임을 말하는 텍스트만 허용합니다.
    nonisolated private static func hasExplicitLiveStatusReason(_ value: String?) -> Bool {
        guard let value = value?.nilIfBlank else { return false }
        let lower = value.lowercased()
        let collapsed = value.replacingOccurrences(of: " ", with: "")
        return collapsed.contains("경기중") ||
            lower.contains("live") ||
            lower.contains("in_progress") ||
            lower.contains("in progress") ||
            lower.contains("running")
    }

    // snapshotHasFreshLiveProgress 메서드는 scheduledStart 이후 snapshot의 실제 진행 신호만 live 근거로 사용합니다.
    nonisolated private static func snapshotHasFreshLiveProgress(_ snapshot: SupabaseLatestGameSnapshotRow?, scheduledStart: Date) -> Bool {
        guard let snapshot, snapshotObservedAt(snapshot, scheduledStart: scheduledStart) else {
            return false
        }
        return snapshotHasLiveProgress(snapshot)
    }

    // snapshotHasLiveProgress 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated private static func snapshotHasLiveProgress(_ snapshot: SupabaseLatestGameSnapshotRow?) -> Bool {
        guard let snapshot else { return false }
        return inningLabelShowsProgress(snapshot.inningLabel) ||
            (snapshot.balls ?? 0) > 0 ||
            (snapshot.strikes ?? 0) > 0 ||
            (snapshot.outs ?? 0) > 0 ||
            snapshot.runnerOnFirst == true ||
            snapshot.runnerOnSecond == true ||
            snapshot.runnerOnThird == true
    }

    // snapshotHasLiveEvidence 메서드는 raw live 상태를 유지할 수 있는 최신 snapshot 필드 존재 여부를 판단합니다.
    nonisolated private static func snapshotHasLiveEvidence(_ snapshot: SupabaseLatestGameSnapshotRow?) -> Bool {
        guard let snapshot else { return false }
        return snapshotHasLiveProgress(snapshot) ||
            snapshot.balls != nil ||
            snapshot.strikes != nil ||
            snapshot.outs != nil ||
            snapshot.currentBatterName?.nilIfBlank != nil ||
            snapshot.currentPitcherName?.nilIfBlank != nil ||
            snapshot.runnerOnFirst != nil ||
            snapshot.runnerOnSecond != nil ||
            snapshot.runnerOnThird != nil ||
            snapshot.firstBaseRunnerName?.nilIfBlank != nil ||
            snapshot.secondBaseRunnerName?.nilIfBlank != nil ||
            snapshot.thirdBaseRunnerName?.nilIfBlank != nil
    }

    // snapshotObservedAt 메서드는 snapshot 자체가 scheduledStart 이후 관측됐는지 확인합니다.
    nonisolated private static func snapshotObservedAt(_ snapshot: SupabaseLatestGameSnapshotRow, scheduledStart: Date) -> Bool {
        guard scheduledStart != .distantPast, let observedAt = snapshot.fetchedAt ?? snapshot.createdAt else {
            return false
        }
        return observedAt >= scheduledStart
    }

    // inningLabelShowsProgress 메서드는 1회 초 0/0/0 placeholder를 live 근거로 쓰지 않습니다.
    nonisolated private static func inningLabelShowsProgress(_ value: String?) -> Bool {
        guard let value = value?.nilIfBlank else { return false }
        let lower = value.lowercased()
        if lower.contains("bottom") || lower.contains("bot") || value.contains("말") {
            return true
        }
        let numberText = value
            .map { $0.isNumber ? String($0) : " " }
            .joined()
            .split(separator: " ")
            .first
        if let numberText, let inning = Int(numberText), inning > 1 {
            return true
        }
        return false
    }

    // classifiedRow 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func classifiedRow(from row: SupabaseGameRow) -> ClassifiedSupabaseGameRow {
        let providerGameID = resolvedProviderGameID(for: row)
        return ClassifiedSupabaseGameRow(
            row: row,
            providerGameID: providerGameID,
            seasonClassification: inferredSeasonClassification(for: row, providerGameID: providerGameID)
        )
    }

    // resolvedProviderGameID 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    nonisolated private static func resolvedProviderGameID(for row: SupabaseGameRow) -> String? {
        row.providerGameID?.nilIfBlank ?? row.officialProviderGameID?.nilIfBlank
    }

    // inferredSeasonClassification 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func inferredSeasonClassification(
        for row: SupabaseGameRow,
        providerGameID: String?
    ) -> GameSeasonClassification {
        let searchableText = [
            providerGameID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            row.publicGameID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            row.provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ]
            .compactMap { $0 }
            .joined(separator: " ")

        if searchableText.contains("kbo_pre") ||
            searchableText.contains("preseason") ||
            searchableText.contains("exhibition") ||
            searchableText.contains("시범경기") {
            return .exhibitionPreseason
        }

        if searchableText.contains("wildcard") ||
            searchableText.contains("wild_card") ||
            searchableText.contains("playoff") ||
            searchableText.contains("semi_playoff") ||
            searchableText.contains("koreanseries") ||
            searchableText.contains("korean_series") ||
            searchableText.contains("postseason") ||
            searchableText.contains("준플레이오프") ||
            searchableText.contains("플레이오프") ||
            searchableText.contains("한국시리즈") {
            return .postseason
        }

        let normalizedProvider = row.provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedProvider == "kbo",
           SupabaseDateParser.parseGameDate(row.gameDate) != nil {
            return .regularSeason
        }

        if let providerGameID = providerGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           providerGameID.count >= 8,
           providerGameID.prefix(8).allSatisfy(\.isNumber) {
            return .regularSeason
        }

        if let publicGameID = row.publicGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           publicGameID.count >= 8,
           publicGameID.prefix(8).allSatisfy(\.isNumber) {
            return .regularSeason
        }

        return .unknown
    }

#if DEBUG
    // debugLogSeasonClassificationSummary 메서드는 화면 표시와 디버그에 사용할 문구를 구성합니다.
    nonisolated private static func debugLogSeasonClassificationSummary(_ rows: [ClassifiedSupabaseGameRow]) {
        let regularSeasonCount = rows.filter { $0.seasonClassification == .regularSeason }.count
        let preseasonCount = rows.filter { $0.seasonClassification == .exhibitionPreseason }.count
        let postseasonCount = rows.filter { $0.seasonClassification == .postseason }.count
        let unknownRows = rows.filter { $0.seasonClassification == .unknown }

        print(
            "[SupabaseKBO] classification counts total=\(rows.count) regularSeason=\(regularSeasonCount) preseason=\(preseasonCount) postseason=\(postseasonCount) unknown=\(unknownRows.count)"
        )

        for (index, row) in unknownRows.prefix(5).enumerated() {
            print(
                "[SupabaseKBO] unknown classification sample index=\(index + 1) provider=\(row.row.provider ?? "<nil>") provider_game_id=\(row.providerGameID ?? "<nil>") public_game_id=\(row.row.publicGameID ?? "<nil>") game_date=\(row.row.gameDate) status=\(row.row.status ?? row.row.inningState ?? "<nil>")"
            )
        }
    }
#endif

// ClassifiedSupabaseGameRow 구조체는 ClassifiedSupabaseGameRow 타입의 역할과 값을 정의합니다.
    nonisolated private struct ClassifiedSupabaseGameRow: Sendable {
        let row: SupabaseGameRow
        let providerGameID: String?
        let seasonClassification: GameSeasonClassification
    }

    // normalizeTeamCode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func normalizeTeamCode(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

// SupabaseDateParser 열거형는 원천 데이터를 앱에서 사용할 수 있는 값으로 해석합니다.
nonisolated enum SupabaseDateParser {
    // parseGameDate 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func parseGameDate(_ value: String?) -> Date? {
        KBODateParser.parseGameDate(value)
    }

    // parseTimestamp 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func parseTimestamp(_ value: String?) -> Date? {
        KBODateParser.parseTimestamp(value)
    }

    // debugTimestamp 메서드는 화면 표시와 디버그에 사용할 문구를 구성합니다.
    nonisolated static func debugTimestamp(_ date: Date) -> String {
        KBODateParser.debugTimestamp(date)
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
