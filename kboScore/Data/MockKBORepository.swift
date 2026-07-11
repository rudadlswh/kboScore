//
//  MockKBORepository.swift
//  kboScore
//  기능 설명: 개발과 테스트에서 사용할 목 KBO 데이터 저장소를 제공합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 3/25/26.
//

import Foundation

// MockKBORepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
struct MockKBORepository: KBORepository, KBOFavoriteTeamScheduleDataSource, Sendable {
    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init() {}

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        try await Task.sleep(for: .milliseconds(120))
        return KBODataMapper.mapBootstrap(MockKBOData.makeBootstrapDTO())
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await Task.sleep(for: .milliseconds(120))
        let payload = MockKBOData.makeBootstrapDTO()
        let teams = payload.teams.map {
            Team(id: $0.id, name: $0.name, shortName: $0.shortName, englishName: $0.englishName, markText: $0.markText)
        }
        return KBODataMapper.mapGames(payload.games, teams: teams)
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await Task.sleep(for: .milliseconds(120))
        return KBODataMapper.mapNotifications(MockKBOData.makeBootstrapDTO().notifications)
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await Task.sleep(for: .milliseconds(120))
        let calendar = Calendar(identifier: .gregorian)
        return KBODataMapper.mapBootstrap(MockKBOData.makeBootstrapDTO()).games
            .filter {
                let components = calendar.dateComponents([.year, .month], from: $0.scheduledStart)
                return components.year == month.year && components.month == month.month
            }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    // fetchFavoriteTeamSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchFavoriteTeamSchedule(
        date: Date,
        favoriteTeamId: Team.ID,
        bypassingCache: Bool
    ) async throws -> [GameDetail] {
        let calendar = Calendar(identifier: .gregorian)
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        return try await fetchMonthlySchedule(for: KBOMonthScheduleKey(date: date, calendar: calendar))
            .filter { game in
                let components = calendar.dateComponents([.year, .month, .day], from: game.scheduledStart)
                return components.year == dayComponents.year &&
                    components.month == dayComponents.month &&
                    components.day == dayComponents.day &&
                    game.involves(teamID: favoriteTeamId)
            }
    }
}

// BundledJSONKBORepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
struct BundledJSONKBORepository: KBORepository, KBOFavoriteTeamScheduleDataSource, Sendable {
    private let bundle: Bundle
    private let resourceName: String
    private let documentsDirectoryURL: URL?
    private let bundledFileURLOverride: URL?
    private let runtimeState: RepositoryRuntimeState?
    private let runtimeSource: RepositoryDataSourceKind
    private let runtimeDelivery: RepositoryDeliverySourceKind

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        bundle: Bundle = .main,
        resourceName: String = "LocalBootstrapData",
        documentsDirectoryURL: URL? = nil,
        bundledFileURLOverride: URL? = nil,
        runtimeState: RepositoryRuntimeState? = nil,
        runtimeSource: RepositoryDataSourceKind = .mock,
        runtimeDelivery: RepositoryDeliverySourceKind = .mock
    ) {
        self.bundle = bundle
        self.resourceName = resourceName
        self.documentsDirectoryURL = documentsDirectoryURL
        self.bundledFileURLOverride = bundledFileURLOverride
        self.runtimeState = runtimeState
        self.runtimeSource = runtimeSource
        self.runtimeDelivery = runtimeDelivery
    }

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        let bootstrap = try await loadBootstrap()
#if DEBUG
        print(
            "[RepositorySource] bootstrap source=LocalBootstrapData.json " +
            "teams=\(bootstrap.teams.count) games=\(bootstrap.games.count)"
        )
#endif
        return bootstrap
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        (try await loadBootstrap()).games
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        (try await loadBootstrap()).notifications
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        let calendar = Calendar(identifier: .gregorian)
        return (try await loadBootstrap()).games
            .filter {
                let components = calendar.dateComponents([.year, .month], from: $0.scheduledStart)
                return components.year == month.year && components.month == month.month
            }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    // fetchFavoriteTeamSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchFavoriteTeamSchedule(
        date: Date,
        favoriteTeamId: Team.ID,
        bypassingCache: Bool
    ) async throws -> [GameDetail] {
        let calendar = Calendar(identifier: .gregorian)
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        return try await fetchMonthlySchedule(for: KBOMonthScheduleKey(date: date, calendar: calendar))
            .filter { game in
                let components = calendar.dateComponents([.year, .month, .day], from: game.scheduledStart)
                return components.year == dayComponents.year &&
                    components.month == dayComponents.month &&
                    components.day == dayComponents.day &&
                    game.involves(teamID: favoriteTeamId)
            }
    }

    // loadBootstrap 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated private func loadBootstrap() async throws -> KBOBootstrapData {
        if let documentsURL = documentsFileURL, FileManager.default.fileExists(atPath: documentsURL.path) {
            do {
                let bootstrap = try loadBootstrap(from: documentsURL, source: .documents)
                await runtimeState?.record(
                    source: runtimeSource,
                    delivery: runtimeDelivery,
                    localBootstrapSource: .documents,
                    localBootstrapMessage: "",
                    localBootstrapResolvedPath: documentsURL.path,
                    localBootstrapLoadedAt: .now
                )
                return bootstrap
            } catch {
#if DEBUG
                print(
                    "[BundledJSONKBORepository] Documents JSON invalid at \(documentsURL.path). " +
                    "Falling back to bundled JSON. error=\(error)"
                )
#endif
                let bundledURL = try bundledFileURL()
                let fallback = try loadBootstrap(from: bundledURL, source: .bundled)
                await runtimeState?.record(
                    source: runtimeSource,
                    delivery: runtimeDelivery,
                    localBootstrapSource: .bundled,
                    localBootstrapMessage: "문서 JSON 해석 실패로 번들 JSON을 사용했습니다. 문서 경로: \(documentsURL.path)",
                    localBootstrapResolvedPath: bundledURL.path,
                    localBootstrapLoadedAt: .now
                )
                return fallback
            }
        }

        let bundledURL = try bundledFileURL()
        let bootstrap = try loadBootstrap(from: bundledURL, source: .bundled)
        await runtimeState?.record(
            source: runtimeSource,
            delivery: runtimeDelivery,
            localBootstrapSource: .bundled,
            localBootstrapMessage: "",
            localBootstrapResolvedPath: bundledURL.path,
            localBootstrapLoadedAt: .now
        )
        return bootstrap
    }

    nonisolated var localBootstrapFileURL: URL? {
        Self.localBootstrapFileURL(
            resourceName: resourceName,
            documentsDirectoryURL: documentsDirectoryURL
        )
    }

    nonisolated private var documentsFileURL: URL? {
#if DEBUG
        localBootstrapFileURL
#else
        nil
#endif
    }

    // bundledFileURL 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func bundledFileURL() throws -> URL {
#if DEBUG
        print("[BundledJSONKBORepository] Looking up \(resourceName).json in bundle: \(bundle.bundlePath)")
#endif
        if let bundledFileURLOverride {
            return bundledFileURLOverride
        }
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
#if DEBUG
            print("[BundledJSONKBORepository] Resource lookup failed: \(resourceName).json")
#endif
            throw BundledJSONRepositoryError.missingResource(name: resourceName)
        }
        return url
    }

    // loadBootstrap 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated private func loadBootstrap(
        from url: URL,
        source: LocalBootstrapSourceKind
    ) throws -> KBOBootstrapData {
#if DEBUG
        print("[BundledJSONKBORepository] Loading \(source.rawValue) from: \(url.path)")
#endif
        let data: Data
        do {
            data = try Data(contentsOf: url)
#if DEBUG
            print("[BundledJSONKBORepository] Data read success: \(data.count) bytes")
#endif
        } catch {
#if DEBUG
            print("[BundledJSONKBORepository] Data read failed: \(error)")
#endif
            throw error
        }

        do {
            let mapped = try Self.decodeBootstrapData(from: data)
#if DEBUG
            print(
                "[BundledJSONKBORepository] Mapping success: " +
                "teams=\(mapped.teams.count), games=\(mapped.games.count), notifications=\(mapped.notifications.count)"
            )
#endif
            return mapped
        } catch let decodingError as DecodingError {
#if DEBUG
            print("[BundledJSONKBORepository] JSON decode failed: \(Self.describe(decodingError: decodingError))")
#endif
            throw decodingError
        } catch {
#if DEBUG
            print("[BundledJSONKBORepository] Mapping failed: \(error)")
#endif
            throw error
        }
    }

    // localBootstrapFileURL 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func localBootstrapFileURL(
        resourceName: String = "LocalBootstrapData",
        documentsDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        let baseDirectory = documentsDirectoryURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        return baseDirectory?.appendingPathComponent("\(resourceName).json", isDirectory: false)
    }

    // decodeBootstrapData 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func decodeBootstrapData(from data: Data) throws -> KBOBootstrapData {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(KBOBootstrapDTO.self, from: data)
#if DEBUG
        print(
            "[BundledJSONKBORepository] JSON decode success: " +
            "teams=\(payload.teams.count), games=\(payload.games.count), notifications=\(payload.notifications.count)"
        )
#endif
        return normalizeBundledSeasonClassification(in: KBODataMapper.mapBootstrap(payload))
    }

    // describe 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func describe(decodingError: DecodingError) -> String {
        // codingPathText 메서드는 이 타입의 주요 동작을 수행합니다.
        func codingPathText(_ path: [CodingKey]) -> String {
            let joined = path.map(\.stringValue).joined(separator: ".")
            return joined.isEmpty ? "<root>" : joined
        }

        switch decodingError {
        case .typeMismatch(let type, let context):
            return "typeMismatch(\(type), path=\(codingPathText(context.codingPath)), debug=\(context.debugDescription), underlying=\(String(describing: context.underlyingError)))"
        case .valueNotFound(let type, let context):
            return "valueNotFound(\(type), path=\(codingPathText(context.codingPath)), debug=\(context.debugDescription), underlying=\(String(describing: context.underlyingError)))"
        case .keyNotFound(let key, let context):
            return "keyNotFound(\(key.stringValue), path=\(codingPathText(context.codingPath)), debug=\(context.debugDescription), underlying=\(String(describing: context.underlyingError)))"
        case .dataCorrupted(let context):
            return "dataCorrupted(path=\(codingPathText(context.codingPath)), debug=\(context.debugDescription), underlying=\(String(describing: context.underlyingError)))"
        @unknown default:
            return "unknown DecodingError: \(decodingError)"
        }
    }

    // normalizeBundledSeasonClassification 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func normalizeBundledSeasonClassification(
        in bootstrap: KBOBootstrapData
    ) -> KBOBootstrapData {
        KBOBootstrapData(
            teams: bootstrap.teams,
            games: bootstrap.games.map(normalizeBundledGame),
            notifications: bootstrap.notifications,
            settings: bootstrap.settings
        )
    }

    // normalizeBundledGame 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func normalizeBundledGame(_ game: GameDetail) -> GameDetail {
        guard game.seasonClassification == .unknown else {
            return game
        }
        guard let inferredClassification = bundledSeasonClassification(from: game.note) else {
            return game
        }

        return GameDetail(
            id: game.id,
            scheduledStart: game.scheduledStart,
            venue: game.venue,
            awayTeam: game.awayTeam,
            homeTeam: game.homeTeam,
            awayScore: game.awayScore,
            homeScore: game.homeScore,
            status: game.status,
            seasonClassification: inferredClassification,
            inningText: game.inningText,
            bases: game.bases,
            balls: game.balls,
            strikes: game.strikes,
            outs: game.outs,
            highlightText: game.highlightText,
            events: game.events,
            note: game.note,
            providerGameID: game.providerGameID,
            awayStartingPitcherName: game.awayStartingPitcherName,
            homeStartingPitcherName: game.homeStartingPitcherName,
            currentPitcherName: game.currentPitcherName,
            currentBatterName: game.currentBatterName
        )
    }

    // bundledSeasonClassification 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func bundledSeasonClassification(from note: String?) -> GameSeasonClassification? {
        guard let normalizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              normalizedNote.isEmpty == false else {
            return nil
        }

        if normalizedNote.contains("provider_game_id=kbo_pre_") ||
            normalizedNote.contains("시범경기") ||
            normalizedNote.contains("preseason") ||
            normalizedNote.contains("exhibition") {
            return .exhibitionPreseason
        }

        if normalizedNote.contains("포스트시즌") ||
            normalizedNote.contains("와일드카드") ||
            normalizedNote.contains("준플레이오프") ||
            normalizedNote.contains("플레이오프") ||
            normalizedNote.contains("한국시리즈") ||
            normalizedNote.contains("postseason") ||
            normalizedNote.contains("wildcard") ||
            normalizedNote.contains("playoff") {
            return .postseason
        }

        guard let providerIDRange = normalizedNote.range(of: "provider_game_id=") else {
            return nil
        }
        let suffix = normalizedNote[providerIDRange.upperBound...]
        let token = suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first ?? ""
        let providerID = String(token)
        guard providerID.count >= 8 else {
            return nil
        }
        let leadingDateToken = providerID.prefix(8)
        guard leadingDateToken.allSatisfy(\.isNumber) else {
            return nil
        }
        return .regularSeason
    }
}

// BundledJSONRepositoryError 열거형는 실패 상황을 구분하고 호출자에게 전달합니다.
enum BundledJSONRepositoryError: LocalizedError {
    case missingResource(name: String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "Bundled JSON resource is missing: \(name).json"
        }
    }
}

// MockKBOData 열거형는 MockKBOData 타입의 역할과 값을 정의합니다.
enum MockKBOData: Sendable {
    private nonisolated static let sampleTimeZone = TimeZone(identifier: "Asia/Seoul") ?? .current

    // makeBootstrap 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated static func makeBootstrap(now: Date = .now) -> KBOBootstrapData {
        KBODataMapper.mapBootstrap(makeBootstrapDTO(now: now))
    }

    // Real fixture baseline:
    // 2026 KBO preseason schedule/results from the official KBO daily schedule on 2026-03-22 to 2026-03-24.
    // Synthetic edge fixtures remain only for live and rain-delay states because no captured preseason payload exists in-project.
    // makeBootstrapDTO 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated static func makeBootstrapDTO(now: Date = .now) -> KBOBootstrapDTO {
        let teams = [
            KBOTeamDTO(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG"),
            KBOTeamDTO(id: "doosan", name: "두산 베어스", shortName: "두산", englishName: "Doosan Bears", markText: "두"),
            KBOTeamDTO(id: "ssg", name: "SSG 랜더스", shortName: "SSG", englishName: "SSG Landers", markText: "SSG"),
            KBOTeamDTO(id: "samsung", name: "삼성 라이온즈", shortName: "삼성", englishName: "Samsung Lions", markText: "삼"),
            KBOTeamDTO(id: "kia", name: "KIA 타이거즈", shortName: "KIA", englishName: "KIA Tigers", markText: "KIA"),
            KBOTeamDTO(id: "lotte", name: "롯데 자이언츠", shortName: "롯데", englishName: "Lotte Giants", markText: "롯"),
            KBOTeamDTO(id: "hanwha", name: "한화 이글스", shortName: "한화", englishName: "Hanwha Eagles", markText: "한"),
            KBOTeamDTO(id: "kt", name: "KT 위즈", shortName: "KT", englishName: "KT Wiz", markText: "KT"),
            KBOTeamDTO(id: "nc", name: "NC 다이노스", shortName: "NC", englishName: "NC Dinos", markText: "NC"),
            KBOTeamDTO(id: "kiwoom", name: "키움 히어로즈", shortName: "키움", englishName: "Kiwoom Heroes", markText: "키")
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sampleTimeZone
        let today = calendar.startOfDay(for: now)

        // date 메서드는 이 타입의 주요 동작을 수행합니다.
        func date(dayOffset: Int, hour: Int, minute: Int) -> Date {
            let baseDay = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDay) ?? baseDay
        }

        // relative 메서드는 이 타입의 주요 동작을 수행합니다.
        func relative(minutesAgo: Int) -> Date {
            calendar.date(byAdding: .minute, value: -minutesAgo, to: now) ?? now
        }

        let liveGameID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let rainDelayGameID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let upcomingGameID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let finalGameID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let recentLGGameID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let nextLGGameID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let finalDoosanKTGameID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!

        let games = [
            KBOGameDTO(
                id: liveGameID,
                scheduledStart: date(dayOffset: 0, hour: 13, minute: 0),
                venue: "잠실야구장",
                awayTeamID: "kiwoom",
                homeTeamID: "lg",
                awayScore: 8,
                homeScore: 7,
                statusCode: "LIVE",
                statusText: "7회말",
                inningText: "7회말",
                bases: KBORunnerStateDTO(first: true, second: false, third: true),
                outs: 1,
                highlightText: "이영빈 적시타로 LG가 1점 차까지 추격",
                events: [
                    KBOGameEventDTO(id: UUID(), type: "score", headline: "이영빈 적시타로 LG가 7-8까지 추격", inningText: "7회말", timestamp: relative(minutesAgo: 3)),
                    KBOGameEventDTO(id: UUID(), type: "pitching", headline: "키움 불펜이 무사 1,3루 위기 진화", inningText: "7회말", timestamp: relative(minutesAgo: 5)),
                    KBOGameEventDTO(id: UUID(), type: "keyPlay", headline: "문보경 볼넷으로 찬스 연결", inningText: "7회말", timestamp: relative(minutesAgo: 7))
                ],
                note: "2026-03-23 잠실 공식 시범경기 매치업 기반 synthetic live fixture"
            ),
            KBOGameDTO(
                id: finalGameID,
                scheduledStart: date(dayOffset: 0, hour: 13, minute: 0),
                venue: "인천 SSG랜더스필드",
                awayTeamID: "lotte",
                homeTeamID: "ssg",
                awayScore: 5,
                homeScore: 2,
                statusCode: "FINAL",
                statusText: "종료",
                inningText: "종료",
                bases: nil,
                outs: nil,
                highlightText: "롯데가 문학 시범경기에서 SSG를 5-2로 제압",
                events: [
                    KBOGameEventDTO(id: UUID(), type: "score", headline: "롯데가 문학 원정 시범경기를 5-2로 마무리", inningText: "종료", timestamp: relative(minutesAgo: 70)),
                    KBOGameEventDTO(id: UUID(), type: "note", headline: "SSG는 9회말 추격에 실패", inningText: "종료", timestamp: relative(minutesAgo: 74))
                ],
                note: "실제 2026 시범경기 결과"
            ),
            KBOGameDTO(
                id: finalDoosanKTGameID,
                scheduledStart: date(dayOffset: 0, hour: 13, minute: 0),
                venue: "수원KT위즈파크",
                awayTeamID: "doosan",
                homeTeamID: "kt",
                awayScore: 12,
                homeScore: 7,
                statusCode: "FINAL",
                statusText: "종료",
                inningText: "종료",
                bases: nil,
                outs: nil,
                highlightText: "두산이 수원 시범경기에서 KT를 12-7로 제압",
                events: [
                    KBOGameEventDTO(id: UUID(), type: "score", headline: "두산이 장단 15안타로 12-7 승리", inningText: "종료", timestamp: relative(minutesAgo: 68)),
                    KBOGameEventDTO(id: UUID(), type: "note", headline: "KT는 중반 추격에도 마운드가 버티지 못함", inningText: "종료", timestamp: relative(minutesAgo: 72))
                ],
                note: "실제 2026 시범경기 결과"
            ),
            KBOGameDTO(
                id: upcomingGameID,
                scheduledStart: date(dayOffset: 0, hour: 18, minute: 0),
                venue: "대전 한화생명 볼파크",
                awayTeamID: "nc",
                homeTeamID: "hanwha",
                awayScore: nil,
                homeScore: nil,
                statusCode: "PRE",
                statusText: "경기 예정",
                inningText: nil,
                bases: nil,
                outs: nil,
                highlightText: "3월 23일 18:00 대전 시범경기 공식 일정",
                events: [
                    KBOGameEventDTO(id: UUID(), type: "note", headline: "NC vs 한화 시범경기 18:00 시작 예정", inningText: "프리뷰", timestamp: relative(minutesAgo: 30))
                ],
                note: "실제 2026 시범경기 일정"
            ),
            KBOGameDTO(
                id: recentLGGameID,
                scheduledStart: date(dayOffset: -1, hour: 13, minute: 0),
                venue: "대구삼성라이온즈파크",
                awayTeamID: "lg",
                homeTeamID: "samsung",
                awayScore: 14,
                homeScore: 13,
                statusCode: "FINAL",
                statusText: "종료",
                inningText: "종료",
                bases: nil,
                outs: nil,
                highlightText: "LG가 대구 시범경기에서 삼성을 14-13으로 제압",
                events: [
                    KBOGameEventDTO(id: UUID(), type: "score", headline: "LG가 3월 22일 대구 시범경기에서 14-13 승리", inningText: "종료", timestamp: relative(minutesAgo: 1_020)),
                    KBOGameEventDTO(id: UUID(), type: "note", headline: "삼성은 9회 추격에도 1점 차 패배", inningText: "종료", timestamp: relative(minutesAgo: 1_030))
                ],
                note: "실제 2026 시범경기 결과"
            ),
            KBOGameDTO(
                id: nextLGGameID,
                scheduledStart: date(dayOffset: 1, hour: 13, minute: 0),
                venue: "잠실야구장",
                awayTeamID: "kiwoom",
                homeTeamID: "lg",
                awayScore: nil,
                homeScore: nil,
                statusCode: "PRE",
                statusText: "경기 예정",
                inningText: nil,
                bases: nil,
                outs: nil,
                highlightText: "3월 24일 잠실 시범경기 공식 일정",
                events: [
                    KBOGameEventDTO(id: UUID(), type: "note", headline: "키움 vs LG 시범경기 13:00 예정", inningText: "프리뷰", timestamp: relative(minutesAgo: 20))
                ],
                note: "실제 2026 시범경기 일정"
            ),
            KBOGameDTO(
                id: rainDelayGameID,
                scheduledStart: date(dayOffset: 1, hour: 13, minute: 0),
                venue: "대구삼성라이온즈파크",
                awayTeamID: "kia",
                homeTeamID: "samsung",
                awayScore: 2,
                homeScore: 2,
                statusCode: "DELAY",
                statusText: "우천 중단",
                inningText: "5회초",
                bases: KBORunnerStateDTO(first: false, second: false, third: false),
                outs: 0,
                highlightText: "갑작스러운 비로 시범경기 진행이 중단된 synthetic edge fixture",
                events: [
                    KBOGameEventDTO(id: UUID(), type: "weather", headline: "우천으로 경기 중단, 재개 시각 미정", inningText: "5회초", timestamp: relative(minutesAgo: 18)),
                    KBOGameEventDTO(id: UUID(), type: "score", headline: "5회초 2-2 동점 이후 강우 시작", inningText: "5회초", timestamp: relative(minutesAgo: 26))
                ],
                note: "실제 2026-03-24 대구 시범경기 매치업 기반 synthetic rain-delay fixture"
            )
        ]

        let notifications = [
            KBONotificationDTO(
                id: UUID(),
                type: "scoreChange",
                title: "실시간 스코어",
                body: "LG 7 - 8 키움 (7회말)",
                sentAt: relative(minutesAgo: 3),
                isRead: false,
                relatedGameID: liveGameID,
                relatedTeamIDs: ["lg", "kiwoom"]
            ),
            KBONotificationDTO(
                id: UUID(),
                type: "leadChange",
                title: "리드 변경",
                body: "키움이 잠실 시범경기에서 8-7로 다시 앞섰습니다.",
                sentAt: relative(minutesAgo: 4),
                isRead: false,
                relatedGameID: liveGameID,
                relatedTeamIDs: ["lg", "kiwoom"]
            ),
            KBONotificationDTO(
                id: UUID(),
                type: "gameEnd",
                title: "경기 종료",
                body: "롯데 5 - 2 SSG, 문학 시범경기가 종료되었습니다.",
                sentAt: relative(minutesAgo: 45),
                isRead: true,
                relatedGameID: finalGameID,
                relatedTeamIDs: ["lotte", "ssg"]
            ),
            KBONotificationDTO(
                id: UUID(),
                type: "gameStart",
                title: "경기 시작",
                body: "NC vs 한화 시범경기가 18:00 대전에서 시작 예정입니다.",
                sentAt: relative(minutesAgo: 35),
                isRead: true,
                relatedGameID: upcomingGameID,
                relatedTeamIDs: ["nc", "hanwha"]
            ),
            KBONotificationDTO(
                id: UUID(),
                type: "rainDelay",
                title: "우천 중단",
                body: "KIA vs 삼성 경기는 synthetic edge fixture로 우천 중단 상태를 유지합니다.",
                sentAt: relative(minutesAgo: 18),
                isRead: true,
                relatedGameID: rainDelayGameID,
                relatedTeamIDs: ["kia", "samsung"]
            )
        ]

        return KBOBootstrapDTO(
            teams: teams,
            games: games.sorted { $0.scheduledStart > $1.scheduledStart },
            notifications: notifications.sorted { $0.sentAt > $1.sentAt },
            settings: AppSettings(
                favoriteTeamID: "lg",
                notificationPreferences: NotificationPreferences(),
                quietHours: QuietHours(isEnabled: false, startHour: 23, endHour: 7),
                liveActivitiesEnabled: true,
                appearance: .system,
                teamThemeMode: .favoriteTeam
            )
        )
    }
}
