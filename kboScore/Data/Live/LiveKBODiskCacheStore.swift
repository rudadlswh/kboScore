//
//  LiveKBODiskCacheStore.swift
//  kboScore
//  기능 설명: 실시간 KBO 응답 캐시를 디스크에 저장하고 복원합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// BootstrapCachePayload 구조체는 BootstrapCachePayload 타입의 역할과 값을 정의합니다.
private struct BootstrapCachePayload: Codable, Sendable {
// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case payload
    }

    let payload: KBOBootstrapDTO

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(value: KBOBootstrapData) {
        payload = KBOBootstrapDTO(
            teams: value.teams.map(Self.makeTeamDTO),
            games: value.games.map(Self.makeGameDTO),
            notifications: value.notifications.map(Self.makeNotificationDTO),
            settings: value.settings
        )
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(payload: KBOBootstrapDTO) {
        self.payload = payload
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payload = try container.decode(KBOBootstrapDTO.self, forKey: .payload)
    }

    // encode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(payload, forKey: .payload)
    }

    nonisolated var bootstrapData: KBOBootstrapData {
        KBODataMapper.mapBootstrap(payload)
    }

    // makeTeamDTO 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated fileprivate static func makeTeamDTO(from team: Team) -> KBOTeamDTO {
        KBOTeamDTO(
            id: team.id,
            name: team.name,
            shortName: team.shortName,
            englishName: team.englishName,
            markText: team.markText
        )
    }

    // makeGameDTO 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated fileprivate static func makeGameDTO(from game: GameDetail) -> KBOGameDTO {
        KBOGameDTO(
            id: game.id,
            providerGameID: game.providerGameID,
            scheduledStart: game.scheduledStart,
            venue: game.venue,
            awayTeamID: game.awayTeam.id,
            homeTeamID: game.homeTeam.id,
            awayScore: game.awayScore,
            homeScore: game.homeScore,
            statusCode: statusCode(for: game.status),
            statusText: game.status.title,
            seasonClassification: game.seasonClassification.rawValue,
            inningText: game.inningText,
            bases: game.bases.map { KBORunnerStateDTO(first: $0.first, second: $0.second, third: $0.third) },
            balls: game.balls,
            strikes: game.strikes,
            outs: game.outs,
            highlightText: game.highlightText,
            events: game.events.map {
                KBOGameEventDTO(
                    id: $0.id,
                    type: $0.type.rawValue,
                    headline: $0.headline,
                    inningText: $0.inningText,
                    timestamp: $0.timestamp
                )
            },
            note: game.note,
            awayStartingPitcherName: game.awayStartingPitcherName,
            homeStartingPitcherName: game.homeStartingPitcherName,
            currentPitcherName: game.currentPitcherName,
            currentBatterName: game.currentBatterName
        )
    }

    // makeNotificationDTO 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated fileprivate static func makeNotificationDTO(from item: NotificationItem) -> KBONotificationDTO {
        KBONotificationDTO(
            id: item.id,
            type: item.type.rawValue,
            title: item.title,
            body: item.body,
            sentAt: item.sentAt,
            isRead: item.isRead,
            relatedGameID: item.relatedGameID,
            gamePublicID: item.gamePublicID ?? item.publicGameID,
            gameProviderID: item.gameProviderID,
            gameDatabaseID: item.gameDatabaseID,
            gameStableIdentity: item.gameStableIdentity,
            relatedTeamIDs: item.relatedTeamIDs
        )
    }

    // statusCode 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func statusCode(for status: GameStatus) -> String {
        switch status {
        case .upcoming:
            "PRE"
        case .live:
            "LIVE"
        case .final:
            "FINAL"
        case .rainDelay:
            "DELAY"
        case .cancelled:
            "CANCELLED"
        }
    }
}

// TeamRanksDiskCacheEntry 구조체는 TeamRanksDiskCacheEntry 타입의 역할과 값을 정의합니다.
private struct TeamRanksDiskCacheEntry: Codable, Sendable {
    let value: [TeamRankRow]
    let timestamp: Date

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case value
        case timestamp
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(value: [TeamRankRow], timestamp: Date) {
        self.value = value
        self.timestamp = timestamp
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode([TeamRankRow].self, forKey: .value)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    // encode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

// GamesCachePayload 구조체는 GamesCachePayload 타입의 역할과 값을 정의합니다.
private struct GamesCachePayload: Codable, Sendable {
// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case teams
        case games
    }

    let teams: [KBOTeamDTO]
    let games: [KBOGameDTO]

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(games value: [GameDetail]) {
        let uniqueTeams = value
            .flatMap { [$0.awayTeam, $0.homeTeam] }
            .reduce(into: [String: Team]()) { partialResult, team in
                partialResult[team.id] = team
            }
        teams = uniqueTeams.values
            .sorted { $0.id < $1.id }
            .map(BootstrapCachePayload.makeTeamDTO)
        games = value.map(BootstrapCachePayload.makeGameDTO)
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(teams: [KBOTeamDTO], games: [KBOGameDTO]) {
        self.teams = teams
        self.games = games
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teams = try container.decode([KBOTeamDTO].self, forKey: .teams)
        games = try container.decode([KBOGameDTO].self, forKey: .games)
    }

    // encode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(teams, forKey: .teams)
        try container.encode(games, forKey: .games)
    }

    nonisolated var domainGames: [GameDetail] {
        KBODataMapper.mapGames(games, teams: teams.map(KBODataMapper.mapTeam))
    }
}

// NotificationsCachePayload 구조체는 NotificationsCachePayload 타입의 역할과 값을 정의합니다.
private struct NotificationsCachePayload: Codable, Sendable {
// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case notifications
    }

    let notifications: [KBONotificationDTO]

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(notifications value: [NotificationItem]) {
        notifications = value.map(BootstrapCachePayload.makeNotificationDTO)
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(notifications: [KBONotificationDTO]) {
        self.notifications = notifications
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notifications = try container.decode([KBONotificationDTO].self, forKey: .notifications)
    }

    // encode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(notifications, forKey: .notifications)
    }

    nonisolated var domainNotifications: [NotificationItem] {
        KBODataMapper.mapNotifications(notifications)
    }
}

// BootstrapDiskCacheEntry 구조체는 BootstrapDiskCacheEntry 타입의 역할과 값을 정의합니다.
private struct BootstrapDiskCacheEntry: Codable, Sendable {
// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case value
        case timestamp
    }

    let value: BootstrapCachePayload
    let timestamp: Date

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(value: BootstrapCachePayload, timestamp: Date) {
        self.value = value
        self.timestamp = timestamp
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(BootstrapCachePayload.self, forKey: .value)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    // encode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

// GamesDiskCacheEntry 구조체는 GamesDiskCacheEntry 타입의 역할과 값을 정의합니다.
private struct GamesDiskCacheEntry: Codable, Sendable {
// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case value
        case timestamp
    }

    let value: GamesCachePayload
    let timestamp: Date

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(value: GamesCachePayload, timestamp: Date) {
        self.value = value
        self.timestamp = timestamp
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(GamesCachePayload.self, forKey: .value)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    // encode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

// NotificationsDiskCacheEntry 구조체는 NotificationsDiskCacheEntry 타입의 역할과 값을 정의합니다.
private struct NotificationsDiskCacheEntry: Codable, Sendable {
// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case value
        case timestamp
    }

    let value: NotificationsCachePayload
    let timestamp: Date

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(value: NotificationsCachePayload, timestamp: Date) {
        self.value = value
        self.timestamp = timestamp
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(NotificationsCachePayload.self, forKey: .value)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    // encode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

actor RepositoryDiskCache {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(directoryURL: URL?, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
    }

    // loadBootstrap 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadBootstrap() -> RepositoryCacheEntry<KBOBootstrapData>? {
        guard let entry = loadBootstrapEntry(fileName: "bootstrap.json") else {
            return nil
        }
        return RepositoryCacheEntry(value: entry.value.bootstrapData, timestamp: entry.timestamp)
    }

    // loadGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadGames() -> RepositoryCacheEntry<[GameDetail]>? {
        loadGamesEntry(fileName: "games.json").map {
            RepositoryCacheEntry(value: $0.value.domainGames, timestamp: $0.timestamp)
        }
    }

    // loadNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadNotifications() -> RepositoryCacheEntry<[NotificationItem]>? {
        loadNotificationsEntry(fileName: "notifications.json").map {
            RepositoryCacheEntry(value: $0.value.domainNotifications, timestamp: $0.timestamp)
        }
    }

    // loadMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadMonthlySchedule(for month: KBOMonthScheduleKey) -> RepositoryCacheEntry<[GameDetail]>? {
        loadGamesEntry(fileName: monthlyScheduleFileName(for: month)).map {
            RepositoryCacheEntry(
                value: $0.value.domainGames.sorted { $0.scheduledStart < $1.scheduledStart },
                timestamp: $0.timestamp
            )
        }
    }

    // loadTeamRanks 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadTeamRanks(season: Int) -> RepositoryCacheEntry<[TeamRankRow]>? {
        let fileURL = directoryURL.appendingPathComponent(teamRanksFileName(season: season))
        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? decoder.decode(TeamRanksDiskCacheEntry.self, from: data) else {
            return nil
        }
        return RepositoryCacheEntry(value: entry.value.sorted { $0.rank < $1.rank }, timestamp: entry.timestamp)
    }

    // storeBootstrap 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func storeBootstrap(_ value: KBOBootstrapData, timestamp: Date) {
        store(BootstrapDiskCacheEntry(value: BootstrapCachePayload(value: value), timestamp: timestamp), fileName: "bootstrap.json")
    }

    // storeGames 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func storeGames(_ value: [GameDetail], timestamp: Date) {
        store(GamesDiskCacheEntry(value: GamesCachePayload(games: value), timestamp: timestamp), fileName: "games.json")
    }

    // storeNotifications 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func storeNotifications(_ value: [NotificationItem], timestamp: Date) {
        store(
            NotificationsDiskCacheEntry(value: NotificationsCachePayload(notifications: value), timestamp: timestamp),
            fileName: "notifications.json"
        )
    }

    // storeMonthlySchedule 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func storeMonthlySchedule(_ value: [GameDetail], for month: KBOMonthScheduleKey, timestamp: Date) {
        store(
            GamesDiskCacheEntry(value: GamesCachePayload(games: value), timestamp: timestamp),
            fileName: monthlyScheduleFileName(for: month)
        )
    }

    // storeTeamRanks 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func storeTeamRanks(_ value: [TeamRankRow], season: Int, timestamp: Date) {
        store(
            TeamRanksDiskCacheEntry(value: value.sorted { $0.rank < $1.rank }, timestamp: timestamp),
            fileName: teamRanksFileName(season: season)
        )
    }

    // loadBootstrapEntry 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func loadBootstrapEntry(fileName: String) -> BootstrapDiskCacheEntry? {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(BootstrapDiskCacheEntry.self, from: data)
    }

    // loadGamesEntry 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func loadGamesEntry(fileName: String) -> GamesDiskCacheEntry? {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(GamesDiskCacheEntry.self, from: data)
    }

    // loadNotificationsEntry 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func loadNotificationsEntry(fileName: String) -> NotificationsDiskCacheEntry? {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(NotificationsDiskCacheEntry.self, from: data)
    }

    // store 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func store<Value: Codable & Sendable>(_ value: Value, fileName: String) {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            try RepositoryFileSecurity.applyProtection(toDirectory: directoryURL, fileManager: fileManager)
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
            try RepositoryFileSecurity.applyProtection(to: fileURL, fileManager: fileManager)
        } catch {
            #if DEBUG
            print("[RepositoryDiskCache] write failed file=\(fileName) error=\(error)")
            #endif
        }
    }

    // defaultDirectory 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func defaultDirectory(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent("kboScore", isDirectory: true)
            .appendingPathComponent("RepositoryCache-v1", isDirectory: true)
    }

    // monthlyScheduleFileName 메서드는 이 타입의 주요 동작을 수행합니다.
    private func monthlyScheduleFileName(for month: KBOMonthScheduleKey) -> String {
        "schedule-\(month.yearMonthText).json"
    }

    // teamRanksFileName 메서드는 이 타입의 주요 동작을 수행합니다.
    private func teamRanksFileName(season: Int) -> String {
        "team-ranks-\(season).json"
    }
}
