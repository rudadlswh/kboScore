//
//  kboScoreTests.swift
//  kboScoreTests
//
//  Created by 조경민 on 3/25/26.
//

import Foundation
import Testing
@testable import kboScore

@MainActor
struct kboScoreTests {

    @Test func homeSortingPrioritizesFavoriteTeamLiveGame() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap())

        let games = model.filteredHomeGames

        #expect(games.count == 4)
        #expect(games.first?.isMyTeamGame == true)
        #expect(games.first?.status == .live)
        #expect(games.first?.homeTeam.id == "lg")
    }

    @Test func myTeamNotificationFilterOnlyReturnsFavoriteTeamAlerts() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap())
        model.notificationFilter = .myTeam

        let notifications = model.filteredNotifications

        #expect(notifications.isEmpty == false)
        #expect(notifications.allSatisfy { $0.relatedTeamIDs.contains("lg") })
    }

    @Test func unreadNotificationsCountDropsWhenItemIsMarkedRead() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap())
        let unreadItem = try #require(model.notifications.first(where: { $0.isRead == false }))

        let before = model.unreadNotificationsCount
        model.markNotificationRead(unreadItem.id)

        #expect(model.unreadNotificationsCount == before - 1)
    }

    @Test func scheduleFilterAllIncludesWholeMonthGames() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)
        let sampleDate = ISO8601DateFormatter().date(from: "2026-03-23T13:00:00+09:00")!

        let games = model.scheduleGames(on: sampleDate, filter: .all)

        #expect(games.count == 4)
        #expect(games.contains { $0.awayTeam.id == "lotte" && $0.homeTeam.id == "ssg" })
        #expect(games.contains { $0.awayTeam.id == "kiwoom" && $0.homeTeam.id == "lg" })
    }

    @Test func scheduleFilterMyTeamOnlyReturnsFavoriteTeamGames() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)
        model.settings.favoriteTeamID = "lg"
        let sampleDate = ISO8601DateFormatter().date(from: "2026-03-23T13:00:00+09:00")!

        let games = model.scheduleGames(on: sampleDate, filter: .myTeam)

        #expect(games.count == 1)
        #expect(games.allSatisfy { $0.involves(teamID: "lg") })
    }

    @Test func scheduleMonthNavigationSkipsEmptyMonths() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-01T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let ssg = try #require(base.teams.first(where: { $0.id == "ssg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))

        let marchGame = makeGameDetail(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            scheduledStart: isoDate("2026-03-10T18:30:00+09:00"),
            venue: "잠실야구장",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let mayGame = makeGameDetail(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            scheduledStart: isoDate("2026-05-10T18:30:00+09:00"),
            venue: "문학",
            awayTeam: lg,
            homeTeam: ssg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: base.teams,
                games: [marchGame, mayGame],
                notifications: base.notifications,
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let aprilMonth = isoDate("2026-04-01T09:00:00+09:00")
        let marchMonth = model.startOfMonth(for: marchGame.scheduledStart)
        let mayMonth = model.startOfMonth(for: mayGame.scheduledStart)
        let resolvedMonth = model.nearestScheduleMonth(to: aprilMonth, filter: .all)
        let nextMonth = model.shiftedScheduleMonth(from: marchGame.scheduledStart, by: 1, filter: .all)
        let previousMonth = model.shiftedScheduleMonth(from: mayGame.scheduledStart, by: -1, filter: .all)

        #expect(resolvedMonth == mayMonth)
        #expect(nextMonth == mayMonth)
        #expect(previousMonth == marchMonth)
    }

    @Test func finalGameDerivesWinnerScoreAndTeamResult() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(now: isoDate("2026-03-23T15:00:00+09:00")), usePersistedSettings: false)
        let sampleDate = isoDate("2026-03-23T13:00:00+09:00")
        let allGames = model.scheduleGames(on: sampleDate, filter: .all)
        let matchingFinalGame = allGames.first { game in
            game.awayTeam.id == "lotte" && game.homeTeam.id == "ssg" && game.status == .final
        }
        let finalGame = try #require(matchingFinalGame)

        #expect(finalGame.finalWinningTeam?.id == "lotte")
        #expect(finalGame.finalScoreLine == "롯데 5 : 2 SSG")
        #expect(finalGame.finalResult(for: "lotte") == .win)
        #expect(finalGame.finalResult(for: "ssg") == .loss)
    }

    @Test func scheduleCalendarDaysExposeFavoriteTeamFinalResult() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(now: isoDate("2026-03-23T15:00:00+09:00")), usePersistedSettings: false)
        model.settings.favoriteTeamID = "lg"
        let referenceDate = isoDate("2026-03-22T09:00:00+09:00")
        let calendar = Calendar(identifier: .gregorian)
        let days = model.scheduleCalendarDays(for: referenceDate, filter: .all)
        let matchingDay = days.first { day in
            calendar.isDate(day.date, inSameDayAs: referenceDate)
        }
        let favoriteDay = try #require(matchingDay)

        #expect(favoriteDay.favoriteTeamResult == .win)
    }

    @Test func standingsExcludeExhibitionGamesAndRankByWinPercentage() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-01T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let samsung = try #require(base.teams.first(where: { $0.id == "samsung" }))

        let exhibition = makeGameDetail(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-03-15T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 3,
            homeScore: 8,
            status: .final,
            seasonClassification: .exhibitionPreseason,
            note: "db_export provider_game_id=kbo_pre_20260315_doosan_lg"
        )
        let regularOne = makeGameDetail(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason,
            note: "db_export provider_game_id=20260328_doosan_lg"
        )
        let regularTwo = makeGameDetail(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            scheduledStart: isoDate("2026-03-29T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: samsung,
            homeTeam: doosan,
            awayScore: 1,
            homeScore: 4,
            status: .final,
            seasonClassification: .regularSeason,
            note: "db_export provider_game_id=20260329_samsung_doosan"
        )

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan, samsung],
                games: [exhibition, regularOne, regularTwo],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let standings = model.standingsSnapshots

        #expect(standings.first?.team.id == "lg")
        #expect(standings.first?.recordText == "1승 0패 0무")
        #expect(standings.first?.winPercentageText == "1.000")
        #expect(standings[1].team.id == "doosan")
        #expect(standings[1].recordText == "1승 1패 0무")
        #expect(standings[1].winPercentageText == "0.500")
        #expect(model.regularSeasonGames.count == 2)
    }

    @Test func standingsRecentResultsAreLimitedToFiveMostRecentFinalGames() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-10T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))

        let games = (0..<6).map { index in
            makeGameDetail(
                id: UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", index + 1))!,
                scheduledStart: isoDate(String(format: "2026-04-%02dT18:30:00+09:00", 10 - index)),
                venue: "잠실",
                awayTeam: doosan,
                homeTeam: lg,
                awayScore: index.isMultiple(of: 2) ? 1 : 6,
                homeScore: index.isMultiple(of: 2) ? 5 : 2,
                status: .final,
                seasonClassification: .regularSeason,
                note: String(format: "db_export provider_game_id=202604%02d_doosan_lg", 10 - index)
            )
        }

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: games,
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let lgSnapshot = try #require(model.standingsSnapshots.first(where: { $0.team.id == "lg" }))

        #expect(lgSnapshot.recentResults.count == 5)
        #expect(lgSnapshot.recentResultsText == "승 패 승 패 승")
    }

    @Test func standingsDeriveRemainingRegularSeasonGamesFromStructuredClassification() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-01T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))

        let finished = makeGameDetail(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason
        )
        let exhibition = makeGameDetail(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            scheduledStart: isoDate("2026-03-15T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 1,
            homeScore: 0,
            status: .final,
            seasonClassification: .exhibitionPreseason
        )

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: [finished, exhibition],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let lgSnapshot = try #require(model.standingsSnapshots.first(where: { $0.team.id == "lg" }))
        let doosanSnapshot = try #require(model.standingsSnapshots.first(where: { $0.team.id == "doosan" }))

        #expect(lgSnapshot.gamesPlayed == 1)
        #expect(lgSnapshot.remainingRegularSeasonGames == 143)
        #expect(doosanSnapshot.gamesPlayed == 1)
        #expect(doosanSnapshot.remainingRegularSeasonGames == 143)
    }

    @Test func standingsUseLocalProbabilityUnavailableReasonWhenScheduleIsIncomplete() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-01T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))

        let regularSeasonGame = makeGameDetail(
            id: UUID(uuidString: "31000000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 1,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason
        )

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: [regularSeasonGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let standings = model.standingsSnapshots

        #expect(standings.first?.team.id == "lg")
        #expect(standings.first?.wins == 1)
        #expect(standings.first?.losses == 0)
        #expect(standings.first?.postseasonQualificationProbability == nil)
        #expect(standings.first?.postseasonProbabilityUnavailableReason == .incompleteRegularSeasonSchedule)
    }

    @Test func bundledBootstrapCompatibilityInfersRegularSeasonFromProviderGameIdentifier() async throws {
        let lg = Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG")
        let kt = Team(id: "kt", name: "KT 위즈", shortName: "KT", englishName: "KT Wiz", markText: "KT")
        let unknownGame = makeGameDetail(
            id: UUID(uuidString: "41000000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: kt,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .unknown,
            note: "db_export provider_game_id=20260328KTLG0"
        )

        let normalized = BundledJSONKBORepository.normalizeBundledSeasonClassification(
            in: KBOBootstrapData(
                teams: [lg, kt],
                games: [unknownGame],
                notifications: [],
                settings: .default
            )
        )
        let game = try #require(normalized.games.first)

        #expect(game.seasonClassification == .regularSeason)
    }

    @Test func uploadedLocalBootstrapProducesNonZeroStandingsRecords() async throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bootstrapURL = projectRoot.appendingPathComponent("kboScore/LocalBootstrapData.json")
        let data = try Data(contentsOf: bootstrapURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(KBOBootstrapDTO.self, from: data)
        let bootstrap = BundledJSONKBORepository.normalizeBundledSeasonClassification(
            in: KBODataMapper.mapBootstrap(payload)
        )
        let model = AppModel(bootstrap: bootstrap, usePersistedSettings: false)

        let standings = model.standingsSnapshots
        let ktSnapshot = try #require(standings.first(where: { $0.team.id == "kt" }))
        let totalGamesPlayed = standings.reduce(0) { $0 + $1.gamesPlayed }

        #expect(totalGamesPlayed > 0)
        #expect(ktSnapshot.gamesPlayed > 0)
        #expect(ktSnapshot.winPercentage != nil)
        #expect(ktSnapshot.postseasonQualificationProbability != nil)
        #expect(ktSnapshot.postseasonProbabilityUnavailableReason == nil)
        #expect(ktSnapshot.postseasonQualificationText != nil)
        #expect(ktSnapshot.visiblePostseasonProbabilityUnavailableReason == nil)
    }

    @Test func mapperHandlesExternalStatusesAndFallbacks() async throws {
        #expect(KBODataMapper.mapGameStatus(code: "LIVE", text: nil) == .live)
        #expect(KBODataMapper.mapGameStatus(code: nil, text: "우천 중단") == .rainDelay)
        #expect(KBODataMapper.mapGameStatus(code: nil, text: "경기 종료") == .final)
        #expect(KBODataMapper.mapGameStatus(code: "UNKNOWN", text: "준비중") == .upcoming)
        #expect(KBODataMapper.mapGameStatus(code: "UNKNOWN", text: nil, inningText: "1회초") == .live)
    }

    @Test func mapperBuildsStableDomainModelsFromDTOs() async throws {
        let bootstrap = MockKBOData.makeBootstrapDTO()
        let mapped = KBODataMapper.mapBootstrap(bootstrap)

        #expect(mapped.teams.count == 10)
        #expect(mapped.games.isEmpty == false)
        #expect(mapped.notifications.isEmpty == false)
        #expect(mapped.games.contains { $0.status == .rainDelay })
        #expect(mapped.games.contains { $0.status == .upcoming && $0.awayScore == nil && $0.homeScore == nil })
    }

    @Test func mapperUsesStructuredSeasonClassificationWhenAvailable() async throws {
        let team = Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG")
        let opponent = Team(id: "doosan", name: "두산 베어스", shortName: "두산", englishName: "Doosan Bears", markText: "DOO")
        let dto = KBOGameDTO(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
            venue: "잠실",
            awayTeamID: opponent.id,
            homeTeamID: team.id,
            awayScore: 2,
            homeScore: 5,
            statusCode: "FINAL",
            statusText: "경기 종료",
            seasonClassification: "regular_season",
            inningText: "종료",
            bases: nil,
            outs: nil,
            highlightText: nil,
            events: [],
            note: "db_export provider_game_id=kbo_pre_20260328_doosan_lg"
        )

        let mapped = KBODataMapper.mapGames([dto], teams: [team, opponent])
        let game = try #require(mapped.first)

        #expect(game.seasonClassification == .regularSeason)
    }

    @Test func scoreNotificationPayloadDecodesFromJSON() async throws {
        let data = """
        {
          "gameID": "20260328KTLG0",
          "eventType": "scoreChange",
          "title": "LG 득점",
          "body": "7회말 LG가 3-2로 앞섭니다.",
          "teamIDs": ["kt", "lg"],
          "routeHint": "gameDetail"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(ScoreNotificationPayload.self, from: data)

        #expect(payload.gameID == "20260328KTLG0")
        #expect(payload.eventType == .scoreChange)
        #expect(payload.teamIDs == ["kt", "lg"])
        #expect(payload.routeHint == .gameDetail)
    }

    @Test func scoreNotificationPayloadExtractorBuildsPayloadFromAPNSUserInfo() async throws {
        let payload = ScoreNotificationPayloadExtractor.payload(
            from: [
                "aps": [
                    "alert": [
                        "title": "경기 종료",
                        "body": "롯데가 SSG를 5-2로 이겼습니다."
                    ]
                ],
                "kbo_live": [
                    "gameId": "20260323LTSK0",
                    "eventType": "gameEnd",
                    "teamIds": ["lotte", "ssg"],
                    "routeHint": "gameDetail"
                ]
            ]
        )

        #expect(payload?.title == "경기 종료")
        #expect(payload?.body == "롯데가 SSG를 5-2로 이겼습니다.")
        #expect(payload?.eventType == .gameEnd)
        #expect(payload?.teamIDs == ["lotte", "ssg"])
    }

    @Test func scoreNotificationRouteResolvesOfficialGameIdentifierToStableUUID() async throws {
        let payload = ScoreNotificationPayload(
            gameID: "20260323WOLG0",
            eventType: .scoreChange,
            title: "득점",
            body: "키움이 득점했습니다.",
            teamIDs: ["kiwoom", "lg"],
            routeHint: .gameDetail
        )

        let route = ScoreNotificationPayloadExtractor.route(from: payload)

        #expect(route == .gameDetail(GameIdentifier.uuid(from: "20260323WOLG0")!))
    }

    @Test func notificationRouteCanTargetNotificationsScreenWithoutTabSelection() async throws {
        let payload = ScoreNotificationPayload(
            gameID: nil,
            eventType: .general,
            title: "알림 모음",
            body: "최근 알림을 확인합니다.",
            routeHint: .notifications
        )

        let route = ScoreNotificationPayloadExtractor.route(from: payload)

        #expect(route == .notifications)
    }

    @Test func notificationRegistrationPayloadMapsFavoriteTeamAlertsAndQuietHours() async throws {
        let settings = AppSettings(
            favoriteTeamID: "lg",
            notificationPreferences: NotificationPreferences(
                gameStart: true,
                scoreChange: false,
                leadChange: true,
                gameEnd: true,
                rainDelay: false
            ),
            quietHours: QuietHours(isEnabled: true, startHour: 23, endHour: 7),
            liveActivitiesEnabled: true,
            appearance: .system,
            teamThemeMode: .favoriteTeam
        )

        let payload = try #require(
            NotificationRegistrationPayload(
                deviceToken: "abc123",
                settings: settings,
                authorizationStatus: .authorized
            )
        )

        #expect(payload.deviceToken == "abc123")
        #expect(payload.favoriteTeamID == "lg")
        #expect(payload.notificationsAuthorized == true)
        #expect(payload.alertTypes == [.gameStart, .leadChange, .gameEnd])
        #expect(payload.quietHours == NotificationRegistrationQuietHours(startHour: 23, endHour: 7))
    }

    @Test func notificationRegistrationPayloadSupportsDeniedAuthorizationState() async throws {
        let payload = try #require(
            NotificationRegistrationPayload(
                deviceToken: "abc123",
                settings: .default,
                authorizationStatus: .denied
            )
        )

        #expect(payload.notificationsAuthorized == false)
        #expect(payload.alertTypes.contains(.scoreChange))
    }

    @Test func remoteNotificationRegistrationClientPostsJSONPayload() async throws {
        let session = makeStubSession()
        let client = RemoteNotificationRegistrationClient(
            endpointURL: URL(string: "https://example.com/api/notification-registrations")!,
            session: session
        )
        let payload = NotificationRegistrationPayload(
            deviceToken: "abc123",
            favoriteTeamID: "lg",
            notificationsAuthorized: true,
            alertTypes: [.gameStart, .scoreChange],
            quietHours: NotificationRegistrationQuietHours(startHour: 23, endHour: 7)
        )

        URLProtocolStub.testResponses = [
            "https://example.com/api/notification-registrations": StubResponse(statusCode: 200, data: Data())
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        let status = try await client.syncRegistration(payload)
        let request = try #require(URLProtocolStub.lastRequest)
        let body = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode(NotificationRegistrationPayload.self, from: body)

        #expect(status == .synced)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(decoded == payload)
    }

    @Test func teamIdentityCatalogUsesRealLogoAssetNames() async throws {
        let lgIdentity = TeamIdentity.catalog["lg"]
        let hanwhaIdentity = TeamIdentity.catalog["hanwha"]

        #expect(lgIdentity?.logoAssetName == "team-lg")
        #expect(hanwhaIdentity?.logoAssetName == "team-hanwha")
        #expect(lgIdentity?.hasLogoAsset == true)
        #expect(hanwhaIdentity?.hasLogoAsset == true)
        #expect(lgIdentity?.monogram == "LG")
        #expect(hanwhaIdentity?.themeID == .hanwha)
    }

    @Test func unknownTeamIdentityKeepsFallbackLogoPath() async throws {
        let team = Team(id: "unknown", name: "Unknown Team", shortName: "UNK", englishName: "Unknown", markText: "UNK")

        #expect(team.identity.logoAssetName == "team-unknown")
        #expect(team.identity.hasLogoAsset == false)
        #expect(team.identity.themeID == .neutral)
    }

    @Test func currentThemeFollowsFavoriteTeamPreference() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)

        model.settings.favoriteTeamID = "ssg"
        model.settings.teamThemeMode = .favoriteTeam
        #expect(model.currentTheme.id == .ssg)

        model.settings.teamThemeMode = .systemDefault
        #expect(model.currentTheme.id == .neutral)
    }

    @Test func favoriteTeamLiveGameFindsCurrentLiveMatch() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)
        model.settings.favoriteTeamID = "lg"

        let liveGame = try #require(model.favoriteTeamLiveGame)

        #expect(liveGame.status == .live)
        #expect(liveGame.involves(teamID: "lg"))
        #expect(model.shouldShowLiveActivityAction(for: liveGame))
    }

    @Test func favoriteTeamLiveActivitySnapshotMapsFavoriteSideAndStatus() async throws {
        let bootstrap = MockKBOData.makeBootstrap()
        let game = try #require(bootstrap.games.first(where: { $0.homeTeam.id == "lg" && $0.status == .live }))

        let snapshot = try #require(FavoriteTeamLiveActivitySnapshot.make(from: game, favoriteTeamID: "lg"))

        #expect(snapshot.favoriteTeamShortName == "LG")
        #expect(snapshot.opponentTeamShortName == "키움")
        #expect(snapshot.isHomeGame == true)
        #expect(snapshot.favoriteScoreText == "4")
        #expect(snapshot.opponentScoreText == "3")
        #expect(snapshot.inningText.contains("회"))
    }

    @Test func liveActivitySnapshotBuildsActivityAttributesAndContentState() async throws {
        #if canImport(ActivityKit)
        let bootstrap = MockKBOData.makeBootstrap()
        let game = try #require(bootstrap.games.first(where: { $0.homeTeam.id == "lg" && $0.status == .live }))
        let snapshot = try #require(FavoriteTeamLiveActivitySnapshot.make(from: game, favoriteTeamID: "lg"))

        let attributes = snapshot.activityAttributes()
        let contentState = snapshot.contentState()

        #expect(attributes.gameID == game.id.uuidString)
        #expect(attributes.favoriteTeamID == "lg")
        #expect(attributes.opponentTeamID == "kiwoom")
        #expect(attributes.isHomeGame == true)
        #expect(contentState.favoriteScoreText == "4")
        #expect(contentState.opponentScoreText == "3")
        #expect(contentState.summaryText == game.status.title)
        #else
        Issue.record("ActivityKit unavailable in this test environment")
        #endif
    }

    @Test func liveActivityToggleUsesSupportedControllerForFavoriteLiveGame() async throws {
        let controller = TestLiveActivityController(isSupported: true)
        let model = AppModel(
            liveActivityController: controller,
            bootstrap: MockKBOData.makeBootstrap(),
            usePersistedSettings: false
        )
        model.settings.favoriteTeamID = "lg"
        let game = try #require(model.favoriteTeamLiveGame)

        #expect(model.isLiveActivityActionEnabled(for: game))

        await model.toggleLiveActivity(for: game)

        #expect(model.isLiveActivityOn(for: game.id))
        #expect(controller.activeGameID == game.id)

        await model.toggleLiveActivity(for: game)

        #expect(model.isLiveActivityOn(for: game.id) == false)
        #expect(controller.activeGameID == nil)
    }

    @Test func preseasonBootstrapFixtureDecodes() async throws {
        let data = try fixtureData(named: "2026-preseason-bootstrap")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(KBOBootstrapDTO.self, from: data)

        #expect(decoded.teams.count == 10)
        #expect(decoded.games.count == 7)
        #expect(decoded.notifications.count == 5)
        #expect(decoded.games.contains { $0.statusCode == "FINAL" && $0.awayTeamID == "lotte" && $0.homeTeamID == "ssg" && $0.awayScore == 5 && $0.homeScore == 2 })
    }

    @Test func liveRepositoryFallsBackToBootstrapWhenCollectionEndpointsUseBootstrapShape() async throws {
        let bootstrapData = try fixtureData(named: "2026-preseason-bootstrap")

        let session = makeStubSession()
        let repository = LiveKBORepository(baseURL: URL(string: "https://example.com/api/")!, session: session)
        URLProtocolStub.testResponses = [
            "https://example.com/api/games": StubResponse(statusCode: 200, data: bootstrapData),
            "https://example.com/api/bootstrap": StubResponse(statusCode: 200, data: bootstrapData),
            "https://example.com/api/notifications": StubResponse(statusCode: 200, data: bootstrapData)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let games = try await repository.fetchGames()
        let notifications = try await repository.fetchNotifications()

        #expect(games.count == 7)
        #expect(games.first?.status == .live)
        #expect(notifications.count == 5)
    }

    @Test func preseasonFixtureMapsIntoDomainModels() async throws {
        let data = try fixtureData(named: "2026-preseason-bootstrap")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let bootstrap = try decoder.decode(KBOBootstrapDTO.self, from: data)
        let mapped = KBODataMapper.mapBootstrap(bootstrap)
        let calendar = Calendar(identifier: .gregorian)
        let sampleDay = ISO8601DateFormatter().date(from: "2026-03-23T13:00:00+09:00")!

        #expect(mapped.games.count == 7)
        #expect(mapped.games.filter { calendar.isDate($0.scheduledStart, inSameDayAs: sampleDay) }.count == 4)
        #expect(mapped.games.contains { $0.awayTeam.id == "lotte" && $0.homeTeam.id == "ssg" && $0.awayScore == 5 && $0.homeScore == 2 && $0.status == .final })
        #expect(mapped.games.contains { $0.awayTeam.id == "kia" && $0.homeTeam.id == "samsung" && $0.status == .rainDelay })
    }

    @Test func externalResponseAdapterNormalizesPreseasonFixturePayload() async throws {
        let data = try fixtureData(named: "2026-preseason-external-response")
        let normalized = try KBOExternalResponseAdapter.normalize(data: data)

        #expect(normalized.games.count == 2)
        #expect(normalized.teams.count == 4)
        #expect(normalized.notifications.count == 1)
        #expect(normalized.games.contains { $0.awayTeamID == "lotte" && $0.homeTeamID == "ssg" && $0.awayScore == 5 && $0.homeScore == 2 })
        #expect(normalized.games.contains { $0.awayTeamID == "kia" && $0.homeTeamID == "samsung" && $0.statusText == "우천 중단" })
    }

    @Test func officialGameListFixtureNormalizesIntoExistingDTOShape() async throws {
        let data = try fixtureData(named: "2026-kbo-official-game-list-20260323")
        let normalized = try KBOExternalResponseAdapter.normalize(data: data)

        #expect(normalized.games.count == 5)
        #expect(normalized.teams.count == 10)
        #expect(normalized.notifications.isEmpty)
        #expect(normalized.games.contains {
            $0.awayTeamID == "kiwoom" &&
            $0.homeTeamID == "lg" &&
            $0.awayScore == 13 &&
            $0.homeScore == 10 &&
            $0.statusCode == "FINAL"
        })
        #expect(normalized.games.contains {
            $0.awayTeamID == "nc" &&
            $0.homeTeamID == "hanwha" &&
            $0.venue == "대전"
        })
    }

    @Test func officialOpeningDayGameListFixtureNormalizesUpcomingGames() async throws {
        let data = try fixtureData(named: "2026-kbo-official-game-list-20260328")
        let normalized = try KBOExternalResponseAdapter.normalize(data: data)

        #expect(normalized.games.count == 2)
        #expect(normalized.teams.count == 4)
        #expect(normalized.games.contains {
            $0.awayTeamID == "kt" &&
            $0.homeTeamID == "lg" &&
            $0.statusCode == "UPCOMING" &&
            $0.venue == "잠실"
        })
        #expect(normalized.games.contains {
            $0.awayTeamID == "kia" &&
            $0.homeTeamID == "ssg" &&
            $0.scheduledStart.formatted(date: .omitted, time: .shortened).contains("2:00") &&
            $0.statusText == "경기 예정"
        })
    }

    @Test func officialScheduleFixtureNormalizesTableRowsIntoGames() async throws {
        let data = try fixtureData(named: "2026-kbo-official-schedule-list-202603")
        let normalized = try KBOExternalResponseAdapter.normalize(data: data)

        #expect(normalized.games.count == 4)
        #expect(normalized.teams.count == 8)
        #expect(normalized.games.contains {
            $0.awayTeamID == "lg" &&
            $0.homeTeamID == "nc" &&
            $0.awayScore == 11 &&
            $0.homeScore == 6 &&
            $0.venue == "마산"
        })
        #expect(normalized.games.contains {
            $0.awayTeamID == "ssg" &&
            $0.homeTeamID == "kia" &&
            $0.statusCode == "FINAL"
        })
    }

    @Test func externalResponseAdapterNormalizesStringValuesAndAlternateDates() async throws {
        let data = """
        [
          {
            "gameId": "33333333-3333-3333-3333-333333333333",
            "scheduledAt": "2026-03-26 18:30:00",
            "awayTeamId": "kia",
            "homeTeamId": "lotte",
            "awayScore": "2",
            "homeScore": "10",
            "status": {
              "code": "FINAL",
              "name": "경기 종료"
            }
          }
        ]
        """.data(using: .utf8)!

        let normalized = try KBOExternalResponseAdapter.normalize(data: data)

        #expect(normalized.games.count == 1)
        #expect(normalized.games.first?.statusCode == "FINAL")
        #expect(normalized.games.first?.homeScore == 10)
    }

    @Test func liveRepositoryMapsOfficialGameListFixtureWithoutSeparateTeamsEndpoint() async throws {
        let officialGameList = try fixtureData(named: "2026-kbo-official-game-list-20260323")

        let session = makeStubSession()
        let repository = LiveKBORepository(baseURL: URL(string: "https://example.com/api/")!, session: session)
        URLProtocolStub.testResponses = [
            "https://example.com/api/games": StubResponse(statusCode: 200, data: officialGameList)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let games = try await repository.fetchGames()

        #expect(games.count == 5)
        #expect(games.contains {
            $0.awayTeam.id == "lotte" &&
            $0.homeTeam.id == "ssg" &&
            $0.awayScore == 5 &&
            $0.homeScore == 2 &&
            $0.status == .final
        })
    }

    @Test func officialLivePayloadMapsStableIDsInningAndBases() async throws {
        let data = """
        {
          "game": [
            {
              "G_ID": "20260328KTLG0",
              "G_DT": "20260328",
              "G_TM": "14:00",
              "S_NM": "잠실",
              "AWAY_ID": "KT",
              "HOME_ID": "LG",
              "AWAY_NM": "KT",
              "HOME_NM": "LG",
              "GAME_STATE_SC": "2",
              "CANCEL_SC_NM": "정상경기",
              "GAME_INN_NO": 7,
              "GAME_TB_SC_NM": "초",
              "T_SCORE_CN": "3",
              "B_SCORE_CN": "2",
              "OUT_CN": 1,
              "B1_BAT_ORDER_NO": 9,
              "B2_BAT_ORDER_NO": 0,
              "B3_BAT_ORDER_NO": 4
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!

        let first = try KBOExternalResponseAdapter.normalize(data: data).games.first
        let second = try KBOExternalResponseAdapter.normalize(data: data).games.first

        #expect(first?.id == second?.id)
        #expect(first?.statusCode == "LIVE")
        #expect(first?.inningText == "7회 초")
        #expect(first?.bases?.first == true)
        #expect(first?.bases?.second == false)
        #expect(first?.bases?.third == true)
        #expect(first?.outs == 1)
    }

    @Test func liveRepositoryMapsOfficialMonthlyScheduleFixture() async throws {
        let officialSchedule = try fixtureData(named: "2026-kbo-official-schedule-list-202603")
        let session = makeStubSession()
        let repository = LiveKBORepository(baseURL: URL(string: "https://example.com/api/")!, session: session)
        URLProtocolStub.testResponses = [
            "https://example.com/api/schedule/month?year=2026&month=3": StubResponse(statusCode: 200, data: officialSchedule)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let games = try await repository.fetchMonthlySchedule(for: KBOMonthScheduleKey(year: 2026, month: 3))

        #expect(games.count == 4)
        #expect(games.contains {
            $0.awayTeam.id == "lg" &&
            $0.homeTeam.id == "nc" &&
            $0.status == .final &&
            $0.venue == "마산"
        })
    }

    @Test func liveRepositoryFallsBackToMonthlyScheduleWhenBootstrapEndpointIsMissing() async throws {
        let month = KBOMonthScheduleKey(year: 2026, month: 3)
        let backendMonthlyPayload = try makeBackendMonthPayloadJSON()
        let session = makeStubSession()
        let repository = LiveKBORepository(
            baseURL: URL(string: "https://example.com/api/")!,
            session: session,
            nowProvider: { ISO8601DateFormatter().date(from: "2026-03-27T12:00:00+09:00")! }
        )
        URLProtocolStub.testResponses = [
            "https://example.com/api/bootstrap": StubResponse(
                statusCode: 404,
                data: """
                {"detail":"Not Found"}
                """.data(using: .utf8)!
            ),
            "https://example.com/api/schedule/month?year=\(month.year)&month=\(month.month)": StubResponse(
                statusCode: 200,
                data: backendMonthlyPayload
            )
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let bootstrap = try await repository.fetchBootstrapData()

        #expect(bootstrap.games.count == 15)
        #expect(bootstrap.teams.isEmpty == false)
        #expect(bootstrap.notifications.isEmpty)
    }

    @Test func liveRepositoryUsesVerifiedOfficialKBORequestShapeForMonthlySchedule() async throws {
        let officialSchedule = try fixtureData(named: "2026-kbo-official-schedule-list-202603")
        let session = makeStubSession()
        let repository = LiveKBORepository(baseURL: URL(string: "https://www.koreabaseball.com/")!, session: session)
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScheduleList": StubResponse(statusCode: 200, data: officialSchedule)
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        _ = try await repository.fetchMonthlySchedule(for: KBOMonthScheduleKey(year: 2026, month: 3))
        let request = try #require(URLProtocolStub.lastRequest)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://www.koreabaseball.com/ws/Schedule.asmx/GetScheduleList")
        #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("application/x-www-form-urlencoded") == true)
        #expect(body?.contains("leId=1") == true)
        #expect(body?.contains("srIdList=0,9") == true)
        #expect(body?.contains("seasonId=2026") == true)
        #expect(body?.contains("gameMonth=03") == true)
        #expect(body?.contains("teamId=") == true)
    }

    @Test func liveRepositoryUsesVerifiedOfficialKBORequestShapeForLiveGames() async throws {
        let officialGameList = try fixtureData(named: "2026-kbo-official-game-list-20260323")
        let fixedDate = ISO8601DateFormatter().date(from: "2026-03-23T10:00:00+09:00")!
        let session = makeStubSession()
        let repository = LiveKBORepository(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session,
            nowProvider: { fixedDate }
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList)
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        _ = try await repository.fetchGames()
        let request = try #require(URLProtocolStub.lastRequest)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList")
        #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("application/x-www-form-urlencoded") == true)
        #expect(body?.contains("leId=1") == true)
        #expect((body?.contains("srId=0,1,3,4,5,6,7,8,9") == true) || (body?.contains("srId=0%2C1%2C3%2C4%2C5%2C6%2C7%2C8%2C9") == true))
        #expect(body?.contains("date=20260323") == true)
    }

    @Test func officialGameCenterClientReconcilesScheduleStartTimeFromOfficialGameList() async throws {
        let officialGameList = """
        {
          "game": [
            {
              "LE_ID": 1,
              "SR_ID": 0,
              "SEASON_ID": 2026,
              "G_DT": "20260328",
              "G_DT_TXT": "2026.03.28(토)",
              "G_ID": "20260328LGNC0",
              "G_TM": "17:00",
              "S_NM": "창원",
              "AWAY_ID": "LG",
              "HOME_ID": "NC",
              "AWAY_NM": "LG",
              "HOME_NM": "NC",
              "GAME_STATE_SC": "1",
              "CANCEL_SC_NM": "",
              "T_SCORE_CN": "0",
              "B_SCORE_CN": "0"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
            venue: "창원",
            awayTeam: Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG"),
            homeTeam: Team(id: "nc", name: "NC 다이노스", shortName: "NC", englishName: "NC Dinos", markText: "NC"),
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )

        let reconciled = await client.reconcileScheduledStartTimes(in: [game])

        #expect(reconciled.count == 1)
        #expect(reconciled[0].scheduledStart == isoDate("2026-03-28T17:00:00+09:00"))
    }

    @Test func liveRepositoryBuildsBootstrapFromOfficialLiveGamesPayload() async throws {
        let officialGameList = try fixtureData(named: "2026-kbo-official-game-list-20260323")
        let fixedDate = ISO8601DateFormatter().date(from: "2026-03-23T10:00:00+09:00")!
        let session = makeStubSession()
        let repository = LiveKBORepository(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session,
            nowProvider: { fixedDate }
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let bootstrap = try await repository.fetchBootstrapData()

        #expect(bootstrap.games.count == 5)
        #expect(bootstrap.teams.count == 10)
        #expect(bootstrap.notifications.isEmpty)
        #expect(bootstrap.games.contains {
            $0.awayTeam.id == "kiwoom" &&
            $0.homeTeam.id == "lg" &&
            $0.status == .final
        })
    }

    @Test func liveRepositoryUsesDefaultNonMarchSeriesRuleForOfficialMonthlySchedule() async throws {
        let officialSchedule = try fixtureData(named: "2026-kbo-official-schedule-list-202603")
        let session = makeStubSession()
        let repository = LiveKBORepository(baseURL: URL(string: "https://www.koreabaseball.com/")!, session: session)
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScheduleList": StubResponse(statusCode: 200, data: officialSchedule)
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        _ = try await repository.fetchMonthlySchedule(for: KBOMonthScheduleKey(year: 2026, month: 4))
        let request = try #require(URLProtocolStub.lastRequest)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8)

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("application/x-www-form-urlencoded") == true)
        #expect(body?.contains("leId=1") == true)
        #expect(body?.contains("srIdList=0") == true)
        #expect(body?.contains("srIdList=0,9") == false)
        #expect(body?.contains("seasonId=2026") == true)
        #expect(body?.contains("gameMonth=04") == true)
        #expect(body?.contains("teamId=") == true)
    }

    @Test func liveRepositoryMapsBackendStandingsPayload() async throws {
        let session = makeStubSession()
        let repository = LiveKBORepository(baseURL: URL(string: "https://example.com/v1/")!, session: session)
        let standingsPayload = """
        {
          "seasonId": 2026,
          "generatedAt": "2026-04-02T09:00:00+09:00",
          "hasUnknownClassificationGames": false,
          "standings": [
            {
              "team": { "teamId": "LG", "nameKo": "LG 트윈스" },
              "rank": 1,
              "wins": 5,
              "losses": 1,
              "ties": 0,
              "runsScored": 31,
              "runsAllowed": 18,
              "gamesPlayed": 6,
              "remainingRegularSeasonGames": 138,
              "winPercentage": 0.833,
              "recentResults": ["win", "win", "loss"],
              "unknownClassificationGames": 0,
              "rankingResolution": "resolved",
              "rankingResolutionPosition": null,
              "postseasonQualificationProbability": 0.84
            }
          ]
        }
        """.data(using: .utf8)!
        let teamsPayload = """
        {
          "teams": [
            { "teamId": "LG", "nameKo": "LG 트윈스", "nameEn": "LG Twins", "shortName": "LG" }
          ]
        }
        """.data(using: .utf8)!
        URLProtocolStub.testResponses = [
            "https://example.com/v1/standings": StubResponse(statusCode: 200, data: standingsPayload),
            "https://example.com/v1/teams": StubResponse(statusCode: 200, data: teamsPayload)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let standings = try await repository.fetchStandings()

        #expect(standings.count == 1)
        #expect(standings[0].team.id == "lg")
        #expect(standings[0].rank == 1)
        #expect(standings[0].recentResults == [.win, .win, .loss])
        #expect(standings[0].runsScored == 31)
        #expect(standings[0].runsAllowed == 18)
        #expect(standings[0].pythagoreanWinningPercentage == StandingsMetrics.pythagoreanWinningPercentage(runsScored: 31, runsAllowed: 18))
        #expect(standings[0].rankingResolution == .resolved)
        #expect(standings[0].postseasonQualificationProbability == 0.84)
    }

    @Test func liveRepositoryMapsBackendStandingsUnavailableProbabilityState() async throws {
        let session = makeStubSession()
        let repository = LiveKBORepository(baseURL: URL(string: "https://example.com/v1/")!, session: session)
        let standingsPayload = """
        {
          "seasonId": 2026,
          "generatedAt": "2026-04-02T09:00:00+09:00",
          "hasUnknownClassificationGames": true,
          "standings": [
            {
              "team": { "teamId": "LG", "nameKo": "LG 트윈스" },
              "rank": 1,
              "wins": 5,
              "losses": 1,
              "ties": 0,
              "gamesPlayed": 6,
              "remainingRegularSeasonGames": 138,
              "winPercentage": 0.833,
              "recentResults": ["win"],
              "unknownClassificationGames": 1,
              "rankingResolution": "resolved",
              "rankingResolutionPosition": null,
              "postseasonQualificationProbability": null,
              "postseasonProbabilityUnavailableReason": "unknown_classification_games"
            }
          ]
        }
        """.data(using: .utf8)!
        let teamsPayload = """
        {
          "teams": [
            { "teamId": "LG", "nameKo": "LG 트윈스", "nameEn": "LG Twins", "shortName": "LG" }
          ]
        }
        """.data(using: .utf8)!
        URLProtocolStub.testResponses = [
            "https://example.com/v1/standings": StubResponse(statusCode: 200, data: standingsPayload),
            "https://example.com/v1/teams": StubResponse(statusCode: 200, data: teamsPayload)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let standings = try await repository.fetchStandings()

        #expect(standings.count == 1)
        #expect(standings[0].postseasonQualificationProbability == nil)
        #expect(standings[0].postseasonProbabilityUnavailableReason == .unknownClassificationGames)
        #expect(standings[0].postseasonQualificationText == "산출 불가")
    }

    @Test func repositoryFactoryUsesBundledModeWhenBackendURLIsMissing() async throws {
        let bundle = KBORepositoryFactory.makeAppRepositoryBundle(
            configuration: AppRepositoryConfiguration(backendBaseURL: nil)
        )

        let snapshot = await bundle.runtimeState?.snapshot()

        #expect(snapshot?.activeSource == .mock)
        #expect(snapshot?.baseURL == nil)
    }

    @Test func bundledJSONRepositoryUsesDocumentsJSONWhenPresent() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        try makeBootstrapJSON(teamName: "문서 LG").write(to: documentsURL, options: .atomic)
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let runtimeState = RepositoryRuntimeState(activeSource: .mock, baseURL: nil, deliverySource: .mock)
        let repository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState
        )

        let bootstrap = try await repository.fetchBootstrapData()
        let snapshot = await runtimeState.snapshot()

        #expect(bootstrap.teams.first(where: { $0.id == "lg" })?.name == "문서 LG")
        #expect(snapshot.localBootstrapSource == .documents)
        #expect(snapshot.localBootstrapMessage == nil)
        #expect(snapshot.localBootstrapResolvedPath == documentsURL.path)
        #expect(snapshot.localBootstrapLoadedAt != nil)
    }

    @Test func bundledJSONRepositoryFallsBackToBundledJSONWhenDocumentsJSONIsMissing() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let runtimeState = RepositoryRuntimeState(activeSource: .mock, baseURL: nil, deliverySource: .mock)
        let repository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState
        )

        let bootstrap = try await repository.fetchBootstrapData()
        let snapshot = await runtimeState.snapshot()

        #expect(bootstrap.teams.first(where: { $0.id == "lg" })?.name == "번들 LG")
        #expect(snapshot.localBootstrapSource == .bundled)
        #expect(snapshot.localBootstrapMessage == nil)
        #expect(snapshot.localBootstrapResolvedPath == bundledURL.path)
        #expect(snapshot.localBootstrapLoadedAt != nil)
    }

    @Test func bundledJSONRepositoryFallsBackToBundledJSONWhenDocumentsJSONIsInvalid() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        try Data("{ invalid json".utf8).write(to: documentsURL, options: .atomic)
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let runtimeState = RepositoryRuntimeState(activeSource: .mock, baseURL: nil, deliverySource: .mock)
        let repository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState
        )

        let bootstrap = try await repository.fetchBootstrapData()
        let snapshot = await runtimeState.snapshot()

        #expect(bootstrap.teams.first(where: { $0.id == "lg" })?.name == "번들 LG")
        #expect(snapshot.localBootstrapSource == .bundled)
        #expect(snapshot.localBootstrapMessage?.contains(documentsURL.path) == true)
        #expect(snapshot.localBootstrapResolvedPath == bundledURL.path)
        #expect(snapshot.localBootstrapLoadedAt != nil)
    }

    @Test func externalDocumentsBootstrapStillDrivesStandingsAndProbabilityDerivation() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        let sourceData = try appLocalBootstrapFixtureData()
        try sourceData.write(to: documentsURL, options: .atomic)
        try sourceData.write(to: bundledURL, options: .atomic)

        let runtimeState = RepositoryRuntimeState(activeSource: .mock, baseURL: nil, deliverySource: .mock)
        let repository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState
        )
        let model = AppModel(
            repository: repository,
            repositoryRuntimeState: runtimeState,
            usePersistedSettings: false
        )

        await model.loadIfNeeded()

        #expect(model.regularSeasonGames.isEmpty == false)
        #expect(model.standingsSnapshots.count == model.teams.count)
        #expect(model.standingsSnapshots.contains { $0.wins + $0.losses + $0.ties > 0 })
        #expect(model.debugLocalBootstrapSource == "문서 JSON")
    }

    @Test func appModelRefreshReReadsEditedDocumentsBootstrapJSON() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        try makeBootstrapJSON(firstGameAwayScore: 1).write(to: documentsURL, options: .atomic)
        try makeBootstrapJSON(firstGameAwayScore: 9).write(to: bundledURL, options: .atomic)

        let runtimeState = RepositoryRuntimeState(activeSource: .mock, baseURL: nil, deliverySource: .mock)
        let repository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState
        )
        let model = AppModel(
            repository: repository,
            repositoryRuntimeState: runtimeState,
            usePersistedSettings: false
        )

        await model.loadIfNeeded()
        let targetGameID = try #require(UUID(uuidString: "0aedcdb0-e727-42c9-a7e5-e3c3bad99392"))
        let initialAwayScore = try #require(model.games.first(where: { $0.id == targetGameID })?.awayScore)
        #expect(initialAwayScore == 1)

        try makeBootstrapJSON(firstGameAwayScore: 7).write(to: documentsURL, options: .atomic)

        await model.refreshHome()

        #expect(model.games.first(where: { $0.id == targetGameID })?.awayScore == 7)
        #expect(model.debugLocalBootstrapSource == "문서 JSON")
        #expect(model.debugLocalBootstrapResolvedPath == documentsURL.path)
        #expect(model.debugLocalBootstrapLoadedAt != nil)
    }

    @Test func appModelRefreshHomeReappliesEditedDocumentsBootstrapTeams() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        try makeBootstrapJSON(teamName: "문서 LG").write(to: documentsURL, options: .atomic)
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let runtimeState = RepositoryRuntimeState(activeSource: .mock, baseURL: nil, deliverySource: .mock)
        let repository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState
        )
        let model = AppModel(
            repository: repository,
            repositoryRuntimeState: runtimeState,
            usePersistedSettings: false
        )

        await model.loadIfNeeded()
        #expect(model.teams.first(where: { $0.id == "lg" })?.name == "문서 LG")

        try makeBootstrapJSON(teamName: "수정 문서 LG").write(to: documentsURL, options: .atomic)

        await model.refreshHome()

        #expect(model.teams.first(where: { $0.id == "lg" })?.name == "수정 문서 LG")
        #expect(model.debugLocalBootstrapResolvedPath == documentsURL.path)
        #expect(model.debugLocalBootstrapLoadedAt != nil)
    }

    @Test func bundledJSONRepositoryRecoversAfterInvalidDocumentsJSONIsFixed() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        try Data("{ invalid json".utf8).write(to: documentsURL, options: .atomic)
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let runtimeState = RepositoryRuntimeState(activeSource: .mock, baseURL: nil, deliverySource: .mock)
        let repository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState
        )

        let fallbackBootstrap = try await repository.fetchBootstrapData()
        #expect(fallbackBootstrap.teams.first(where: { $0.id == "lg" })?.name == "번들 LG")

        try makeBootstrapJSON(teamName: "복구 문서 LG").write(to: documentsURL, options: .atomic)

        let documentsBootstrap = try await repository.fetchBootstrapData()
        let snapshot = await runtimeState.snapshot()

        #expect(documentsBootstrap.teams.first(where: { $0.id == "lg" })?.name == "복구 문서 LG")
        #expect(snapshot.localBootstrapSource == .documents)
        #expect(snapshot.localBootstrapMessage == nil)
        #expect(snapshot.localBootstrapResolvedPath == documentsURL.path)
    }

    @Test func repositoryFactoryUsesLiveModeWhenBackendURLIsProvided() async throws {
        let backendURL = try #require(URL(string: "http://127.0.0.1:8080"))
        let bundle = KBORepositoryFactory.makeAppRepositoryBundle(
            configuration: AppRepositoryConfiguration(backendBaseURL: backendURL)
        )

        let snapshot = await bundle.runtimeState?.snapshot()

        #expect(snapshot?.activeSource == .live)
        #expect(snapshot?.baseURL == backendURL.absoluteString)
    }

    @Test func bootstrapRefreshRepositoryWritesDocumentsJSONAndStoresETagOn200() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        let defaults = makeTemporaryUserDefaults()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let baseURL = try #require(URL(string: "https://example.com/api/"))
        let stateStore = BootstrapRefreshStateStore(baseURL: baseURL, defaults: defaults)
        let runtimeState = RepositoryRuntimeState(
            activeSource: .live,
            baseURL: baseURL.absoluteString,
            deliverySource: .live,
            bootstrapRefreshSnapshot: stateStore.load(isEnabled: true)
        )
        let localRepository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState,
            runtimeSource: .live,
            runtimeDelivery: .cache
        )
        let repository = BootstrapRefreshingKBORepository(
            base: StubRepository(),
            localBootstrapRepository: localRepository,
            bootstrapBaseURL: baseURL,
            session: makeStubSession(),
            runtimeState: runtimeState,
            stateStore: stateStore
        )

        URLProtocolStub.testResponses = [
            "https://example.com/api/v1/bootstrap": StubResponse(
                statusCode: 200,
                data: try makeBootstrapAPIResponseJSON(teamName: "업데이트 LG"),
                headers: ["ETag": "\"bootstrap-v1\""]
            )
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        let bootstrap = try await repository.fetchBootstrapData()
        let snapshot = await runtimeState.snapshot()
        let documentsData = try Data(contentsOf: documentsURL)

        #expect(bootstrap.teams.first(where: { $0.id == "lg" })?.name == "업데이트 LG")
        #expect(String(data: documentsData, encoding: .utf8)?.contains("업데이트 LG") == true)
        #expect(snapshot.localBootstrapSource == .documents)
        #expect(snapshot.bootstrapRefreshETag == "\"bootstrap-v1\"")
        #expect(snapshot.bootstrapLastResult == .updated)
        #expect(URLProtocolStub.lastRequest?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func bootstrapRefreshRepositorySendsStoredETagAndSkipsRewriteOn304() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        let defaults = makeTemporaryUserDefaults()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        let originalData = try makeBootstrapJSON(teamName: "문서 LG")
        try originalData.write(to: documentsURL, options: .atomic)
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let baseURL = try #require(URL(string: "https://example.com/api/"))
        let stateStore = BootstrapRefreshStateStore(baseURL: baseURL, defaults: defaults)
        stateStore.save(
            BootstrapRefreshDebugSnapshot(
                isEnabled: true,
                etag: "\"bootstrap-v1\"",
                lastFetchAt: isoDate("2026-04-03T11:00:00+09:00"),
                lastWriteAt: isoDate("2026-04-03T11:00:00+09:00"),
                lastResult: .updated
            )
        )
        let runtimeState = RepositoryRuntimeState(
            activeSource: .live,
            baseURL: baseURL.absoluteString,
            deliverySource: .live,
            bootstrapRefreshSnapshot: stateStore.load(isEnabled: true)
        )
        let localRepository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState,
            runtimeSource: .live,
            runtimeDelivery: .cache
        )
        let repository = BootstrapRefreshingKBORepository(
            base: StubRepository(),
            localBootstrapRepository: localRepository,
            bootstrapBaseURL: baseURL,
            session: makeStubSession(),
            runtimeState: runtimeState,
            stateStore: stateStore
        )

        URLProtocolStub.testResponses = [
            "https://example.com/api/v1/bootstrap": StubResponse(
                statusCode: 304,
                data: Data(),
                headers: ["ETag": "\"bootstrap-v1\""]
            )
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        let bootstrap = try await repository.fetchBootstrapData()
        let snapshot = await runtimeState.snapshot()
        let documentsData = try Data(contentsOf: documentsURL)

        #expect(bootstrap.teams.first(where: { $0.id == "lg" })?.name == "문서 LG")
        #expect(documentsData == originalData)
        #expect(snapshot.bootstrapLastResult == .notModified)
        #expect(snapshot.bootstrapRefreshETag == "\"bootstrap-v1\"")
        #expect(URLProtocolStub.lastRequest?.value(forHTTPHeaderField: "If-None-Match") == "\"bootstrap-v1\"")
    }

    @Test func bootstrapRefreshFailurePreservesExistingDocumentsJSON() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        let defaults = makeTemporaryUserDefaults()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        let originalData = try makeBootstrapJSON(teamName: "문서 LG")
        try originalData.write(to: documentsURL, options: .atomic)
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let baseURL = try #require(URL(string: "https://example.com/api/"))
        let stateStore = BootstrapRefreshStateStore(baseURL: baseURL, defaults: defaults)
        let runtimeState = RepositoryRuntimeState(
            activeSource: .live,
            baseURL: baseURL.absoluteString,
            deliverySource: .live,
            bootstrapRefreshSnapshot: stateStore.load(isEnabled: true)
        )
        let localRepository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState,
            runtimeSource: .live,
            runtimeDelivery: .cache
        )
        let repository = BootstrapRefreshingKBORepository(
            base: StubRepository(),
            localBootstrapRepository: localRepository,
            bootstrapBaseURL: baseURL,
            session: makeStubSession(),
            runtimeState: runtimeState,
            stateStore: stateStore
        )

        URLProtocolStub.testResponses = [
            "https://example.com/api/v1/bootstrap": StubResponse(statusCode: 500, data: Data())
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let bootstrap = try await repository.fetchBootstrapData()
        let snapshot = await runtimeState.snapshot()
        let documentsData = try Data(contentsOf: documentsURL)

        #expect(bootstrap.teams.first(where: { $0.id == "lg" })?.name == "문서 LG")
        #expect(documentsData == originalData)
        #expect(snapshot.localBootstrapSource == .documents)
        #expect(snapshot.bootstrapLastResult == .failed)
    }

    @Test func bootstrapRefreshFailureStillFallsBackToBundledJSONWithoutDocumentsFile() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        let defaults = makeTemporaryUserDefaults()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let baseURL = try #require(URL(string: "https://example.com/api/"))
        let stateStore = BootstrapRefreshStateStore(baseURL: baseURL, defaults: defaults)
        let runtimeState = RepositoryRuntimeState(
            activeSource: .live,
            baseURL: baseURL.absoluteString,
            deliverySource: .live,
            bootstrapRefreshSnapshot: stateStore.load(isEnabled: true)
        )
        let localRepository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState,
            runtimeSource: .live,
            runtimeDelivery: .cache
        )
        let repository = BootstrapRefreshingKBORepository(
            base: StubRepository(),
            localBootstrapRepository: localRepository,
            bootstrapBaseURL: baseURL,
            session: makeStubSession(),
            runtimeState: runtimeState,
            stateStore: stateStore
        )

        URLProtocolStub.testResponses = [
            "https://example.com/api/v1/bootstrap": StubResponse(statusCode: 500, data: Data())
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let bootstrap = try await repository.fetchBootstrapData()
        let snapshot = await runtimeState.snapshot()

        #expect(bootstrap.teams.first(where: { $0.id == "lg" })?.name == "번들 LG")
        #expect(snapshot.localBootstrapSource == .bundled)
        #expect(snapshot.bootstrapLastResult == .failed)
    }

    @Test func appModelRefreshHomeSkipsBootstrapReapplyWhenBootstrapIsNotModified() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        let defaults = makeTemporaryUserDefaults()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        try makeBootstrapJSON(teamName: "문서 LG").write(to: documentsURL, options: .atomic)
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let baseURL = try #require(URL(string: "https://example.com/api/"))
        let stateStore = BootstrapRefreshStateStore(baseURL: baseURL, defaults: defaults)
        stateStore.save(
            BootstrapRefreshDebugSnapshot(
                isEnabled: true,
                etag: "\"bootstrap-v1\"",
                lastFetchAt: isoDate("2026-04-03T11:00:00+09:00"),
                lastWriteAt: isoDate("2026-04-03T11:00:00+09:00"),
                lastResult: .updated
            )
        )
        let runtimeState = RepositoryRuntimeState(
            activeSource: .live,
            baseURL: baseURL.absoluteString,
            deliverySource: .live,
            bootstrapRefreshSnapshot: stateStore.load(isEnabled: true)
        )
        let localRepository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState,
            runtimeSource: .live,
            runtimeDelivery: .cache
        )

        let bootstrap = stubBootstrap()
        let lg = try #require(bootstrap.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(bootstrap.teams.first(where: { $0.id == "doosan" }))
        let mayGame = makeGameDetail(
            id: UUID(uuidString: "91000000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-05-01T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )
        let repository = BootstrapRefreshingKBORepository(
            base: StubRepository(fetchMonthlySchedule: { _ in [mayGame] }),
            localBootstrapRepository: localRepository,
            bootstrapBaseURL: baseURL,
            session: makeStubSession(),
            runtimeState: runtimeState,
            stateStore: stateStore
        )

        URLProtocolStub.testResponses = [
            "https://example.com/api/v1/bootstrap": StubResponse(
                statusCode: 304,
                data: Data(),
                headers: ["ETag": "\"bootstrap-v1\""]
            )
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        let model = AppModel(
            repository: repository,
            repositoryRuntimeState: runtimeState,
            usePersistedSettings: false
        )
        let mayReferenceDate = isoDate("2026-05-01T09:00:00+09:00")

        await model.loadIfNeeded()
        await model.loadScheduleIfNeeded(for: mayReferenceDate)
        #expect(model.scheduleGames(on: mayReferenceDate, filter: .all).count == 1)

        await model.refreshHome()

        #expect(model.scheduleGames(on: mayReferenceDate, filter: .all).count == 1)
        #expect(model.debugBootstrapLastResult == "변경 없음")
        #expect(URLProtocolStub.lastRequest?.value(forHTTPHeaderField: "If-None-Match") == "\"bootstrap-v1\"")
    }

    @Test func appModelRefreshHomeReappliesBootstrapAfterSuccessfulDownload() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        let defaults = makeTemporaryUserDefaults()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        try makeBootstrapJSON(teamName: "이전 LG").write(to: documentsURL, options: .atomic)
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let baseURL = try #require(URL(string: "https://example.com/api/"))
        let stateStore = BootstrapRefreshStateStore(baseURL: baseURL, defaults: defaults)
        stateStore.save(
            BootstrapRefreshDebugSnapshot(
                isEnabled: true,
                etag: "\"bootstrap-v1\"",
                lastFetchAt: isoDate("2026-04-03T11:00:00+09:00"),
                lastWriteAt: isoDate("2026-04-03T11:00:00+09:00"),
                lastResult: .updated
            )
        )
        let runtimeState = RepositoryRuntimeState(
            activeSource: .live,
            baseURL: baseURL.absoluteString,
            deliverySource: .live,
            bootstrapRefreshSnapshot: stateStore.load(isEnabled: true)
        )
        let localRepository = BundledJSONKBORepository(
            documentsDirectoryURL: documentsDirectory,
            bundledFileURLOverride: bundledURL,
            runtimeState: runtimeState,
            runtimeSource: .live,
            runtimeDelivery: .cache
        )
        let repository = BootstrapRefreshingKBORepository(
            base: StubRepository(),
            localBootstrapRepository: localRepository,
            bootstrapBaseURL: baseURL,
            session: makeStubSession(),
            runtimeState: runtimeState,
            stateStore: stateStore
        )

        URLProtocolStub.testResponses = [
            "https://example.com/api/v1/bootstrap": StubResponse(
                statusCode: 304,
                data: Data(),
                headers: ["ETag": "\"bootstrap-v1\""]
            )
        ]

        let model = AppModel(
            repository: repository,
            repositoryRuntimeState: runtimeState,
            usePersistedSettings: false
        )

        await model.loadIfNeeded()
        #expect(model.teams.first(where: { $0.id == "lg" })?.name == "이전 LG")

        URLProtocolStub.testResponses = [
            "https://example.com/api/v1/bootstrap": StubResponse(
                statusCode: 200,
                data: try makeBootstrapAPIResponseJSON(teamName: "최신 LG"),
                headers: ["ETag": "\"bootstrap-v2\""]
            )
        ]
        defer { URLProtocolStub.testResponses = [:] }

        await model.refreshHome()

        let documentsData = try Data(contentsOf: documentsURL)
        #expect(model.teams.first(where: { $0.id == "lg" })?.name == "최신 LG")
        #expect(String(data: documentsData, encoding: .utf8)?.contains("최신 LG") == true)
        #expect(model.debugBootstrapLastResult == "업데이트됨")
        #expect(model.debugBootstrapETag == "\"bootstrap-v2\"")
    }

    @Test func appModelMakesProbabilityAvailableBeforeThirtyPercentSeasonProgress() async throws {
        let teams = makeProbabilityTestTeams()
        let games = makeProbabilityThresholdSchedule(
            teams: teams,
            completedGamesPerTeam: 43,
            seasonLength: 144
        )
        let model = AppModel(
            repository: StubRepository(fetchStandings: { fatalError("standings fetch should not be required") }),
            bootstrap: KBOBootstrapData(
                teams: teams,
                games: games,
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false
        )

        let snapshot = try #require(model.standingsSnapshots.first(where: { $0.team.id == "team1" }))

        let probability = try #require(snapshot.postseasonQualificationProbability)
        #expect(probability > 0)
        #expect(probability < 1)
        #expect(snapshot.postseasonProbabilityUnavailableReason == nil)
        #expect(snapshot.postseasonQualificationText != nil)
        #expect(snapshot.visiblePostseasonProbabilityUnavailableReason == nil)
    }

    @Test func localProbabilityCalculatorMakesProbabilityAvailableAtThirtyPercentSeasonProgress() throws {
        let teams = makeProbabilityTestTeams()
        let games = makeProbabilityThresholdSchedule(
            teams: teams,
            completedGamesPerTeam: 44,
            seasonLength: 144
        )
        let calculator = LocalPostseasonQualificationCalculator(
            regularSeasonLength: 144,
            simulationCount: 400
        )

        let signals = calculator.makeSignals(teams: teams, games: games)
        let team1Probability = try #require(signals["team1"]?.postseasonQualificationProbability)

        #expect(team1Probability > 0)
        #expect(signals["team1"]?.postseasonProbabilityUnavailableReason == nil)
    }

    @Test func localProbabilityCalculatorMakesProbabilityAvailableAboveThirtyPercentSeasonProgress() throws {
        let teams = makeProbabilityTestTeams()
        let games = makeProbabilityThresholdSchedule(
            teams: teams,
            completedGamesPerTeam: 45,
            seasonLength: 144
        )
        let calculator = LocalPostseasonQualificationCalculator(
            regularSeasonLength: 144,
            simulationCount: 400
        )

        let signals = calculator.makeSignals(teams: teams, games: games)
        let team1Probability = try #require(signals["team1"]?.postseasonQualificationProbability)
        let team10Probability = try #require(signals["team10"]?.postseasonQualificationProbability)

        #expect(signals["team1"]?.postseasonProbabilityUnavailableReason == nil)
        #expect(team1Probability > 0)
        #expect(team1Probability < 1)
        #expect(team1Probability > team10Probability)
    }

    @Test func localProbabilityCalculatorReturnsDeterministicProbabilitiesForSameSnapshot() throws {
        let teams = makeProbabilityTestTeams()
        let games = makeProbabilityThresholdSchedule(
            teams: teams,
            completedGamesPerTeam: 44,
            seasonLength: 144
        )
        let calculator = LocalPostseasonQualificationCalculator(
            regularSeasonLength: 144,
            simulationCount: 400
        )

        let first = calculator.makeSignals(teams: teams, games: games)
        let second = calculator.makeSignals(teams: teams, games: games)

        #expect(first == second)
    }

    @Test func appModelDoesNotTreatEarlySevenAndOneLeaderAsClinched() throws {
        let teams = makeProbabilityTestTeams()
        let games = makeConservativeEarlySeasonProbabilitySchedule(
            teams: teams,
            completedGamesPerTeam: 8,
            seasonLength: 144
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: teams,
                games: games,
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false
        )

        let leader = try #require(model.standingsSnapshots.first(where: { $0.team.id == "team1" }))
        let leaderProbability = try #require(leader.postseasonQualificationProbability)

        #expect(leader.wins == 7)
        #expect(leader.losses == 1)
        #expect(leader.postseasonQualificationStatus == nil)
        #expect(leaderProbability > 0.5)
        #expect(leaderProbability < 0.95)
        #expect(leader.postseasonQualificationText != "100.0%")
    }

    @Test func appModelKeepsEarlyLowerRankedTeamsAboveNearZeroProbability() throws {
        let teams = makeProbabilityTestTeams()
        let games = makeConservativeEarlySeasonProbabilitySchedule(
            teams: teams,
            completedGamesPerTeam: 8,
            seasonLength: 144
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: teams,
                games: games,
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false
        )

        let trailing = try #require(model.standingsSnapshots.first(where: { $0.team.id == "team10" }))
        let trailingProbability = try #require(trailing.postseasonQualificationProbability)

        #expect(trailing.wins == 1)
        #expect(trailing.losses == 7)
        #expect(trailing.postseasonQualificationStatus == nil)
        #expect(trailingProbability > 0.02)
        #expect(trailing.postseasonQualificationText != "0.0%")
    }

    @Test func localProbabilityCalculatorReturnsCertainQualificationOutcomesWhenSeasonIsComplete() throws {
        let teams = makeProbabilityTestTeams()
        let games = makeProbabilityThresholdSchedule(
            teams: teams,
            completedGamesPerTeam: 144,
            seasonLength: 144
        )
        let calculator = LocalPostseasonQualificationCalculator(
            regularSeasonLength: 144,
            simulationCount: 400
        )

        let signals = calculator.makeSignals(teams: teams, games: games)
        let team1Probability = try #require(signals["team1"]?.postseasonQualificationProbability)
        let team10Probability = try #require(signals["team10"]?.postseasonQualificationProbability)

        #expect(team1Probability == 1)
        #expect(team10Probability == 0)
    }

    @Test func standingsRemainSortedByOfficialRecordWhenProbabilitiesExist() throws {
        let teams = makeProbabilityTestTeams()
        let games = makeProbabilityThresholdSchedule(
            teams: teams,
            completedGamesPerTeam: 44,
            seasonLength: 144
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: teams,
                games: games,
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false
        )

        let orderedTeamIDs = model.standingsSnapshots.map(\.team.id)

        #expect(orderedTeamIDs == [
            "team1", "team2", "team3", "team4", "team5",
            "team6", "team7", "team8", "team9", "team10"
        ])
    }

    @Test func localProbabilityCalculatorFallsBackToNeutralPriorWithoutPreviousSeasonRanks() throws {
        let teams = makeProbabilityTestTeams(includePreviousRanks: false)
        let games = makeConservativeEarlySeasonProbabilitySchedule(
            teams: teams,
            completedGamesPerTeam: 1,
            seasonLength: 144
        )
        let calculator = LocalPostseasonQualificationCalculator(
            regularSeasonLength: 144,
            simulationCount: 400
        )

        let signals = calculator.makeSignals(teams: teams, games: games)
        let team1Probability = try #require(signals["team1"]?.postseasonQualificationProbability)
        let team10Probability = try #require(signals["team10"]?.postseasonQualificationProbability)

        #expect(team1Probability > 0)
        #expect(team1Probability < 1)
        #expect(team10Probability > 0)
        #expect(team10Probability < 1)
    }

    @Test func localProbabilityCalculatorUsesUnavailableReasonForUnknownClassificationGames() throws {
        let teams = makeProbabilityTestTeams()
        let games = [
            makeGameDetail(
                id: UUID(uuidString: "52000000-0000-0000-0000-000000000001")!,
                scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
                venue: "잠실",
                awayTeam: teams[0],
                homeTeam: teams[1],
                awayScore: nil,
                homeScore: nil,
                status: .upcoming,
                seasonClassification: .unknown,
                note: "classification pending"
            )
        ]
        let calculator = LocalPostseasonQualificationCalculator(
            regularSeasonLength: 1,
            simulationCount: 100
        )

        let signals = calculator.makeSignals(teams: teams, games: games)

        #expect(signals["team1"]?.postseasonQualificationProbability == nil)
        #expect(signals["team1"]?.postseasonProbabilityUnavailableReason == .unknownClassificationGames)
        #expect(signals["team2"]?.unknownClassificationGames == 1)
    }

    @Test func snapshotShowsUnavailablePostseasonProbabilityStateWhenReasonExists() {
        let team = Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG")
        let snapshot = TeamStandingsSnapshot(
            team: team,
            rank: 1,
            wins: 4,
            losses: 0,
            ties: 0,
            remainingRegularSeasonGames: 140,
            recentResults: [.win, .win, .win, .win],
            postseasonQualificationProbability: nil,
            postseasonProbabilityUnavailableReason: .seasonProgressBelowThreshold
        )

        #expect(snapshot.shouldShowPostseasonProbability == true)
        #expect(snapshot.postseasonQualificationText == "산출 불가")
        #expect(snapshot.visiblePostseasonProbabilityUnavailableReason == .seasonProgressBelowThreshold)
    }

    @Test func snapshotKeepsUnavailablePostseasonStateVisibleAfterThresholdForRealDataIssues() {
        let team = Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG")
        let snapshot = TeamStandingsSnapshot(
            team: team,
            rank: 1,
            wins: 44,
            losses: 10,
            ties: 0,
            remainingRegularSeasonGames: 90,
            recentResults: [.win, .loss, .win, .win, .loss],
            postseasonQualificationProbability: nil,
            postseasonProbabilityUnavailableReason: .unknownClassificationGames
        )

        #expect(snapshot.shouldShowPostseasonProbability == true)
        #expect(snapshot.postseasonQualificationText == "산출 불가")
        #expect(snapshot.visiblePostseasonProbabilityUnavailableReason == .unknownClassificationGames)
    }

    @Test func snapshotFormatsPostseasonProbabilityAsOneDecimalPercent() {
        let team = Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG")
        let snapshot = TeamStandingsSnapshot(
            team: team,
            rank: 1,
            wins: 60,
            losses: 30,
            ties: 2,
            remainingRegularSeasonGames: 52,
            recentResults: [],
            postseasonQualificationProbability: 0.784
        )

        #expect(snapshot.postseasonQualificationText == "78.4%")
    }

    @Test func snapshotClampsExtremeNonCertainPostseasonProbabilityDisplay() {
        let team = Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG")
        let nearCertain = TeamStandingsSnapshot(
            team: team,
            rank: 1,
            wins: 7,
            losses: 1,
            ties: 0,
            remainingRegularSeasonGames: 136,
            recentResults: [.win, .win, .win, .loss],
            postseasonQualificationProbability: 1
        )
        let nearEliminated = TeamStandingsSnapshot(
            team: team,
            rank: 10,
            wins: 1,
            losses: 7,
            ties: 0,
            remainingRegularSeasonGames: 136,
            recentResults: [.loss, .loss, .loss, .win],
            postseasonQualificationProbability: 0
        )

        #expect(nearCertain.postseasonQualificationText == "99.9%")
        #expect(nearEliminated.postseasonQualificationText == "0.1%")
    }

    @Test func snapshotShowsExactPostseasonProbabilityForClinchedAndEliminatedTeams() {
        let team = Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG")
        let clinched = TeamStandingsSnapshot(
            team: team,
            rank: 1,
            wins: 90,
            losses: 40,
            ties: 0,
            remainingRegularSeasonGames: 0,
            recentResults: [],
            postseasonQualificationProbability: 1,
            postseasonQualificationStatus: .clinched
        )
        let eliminated = TeamStandingsSnapshot(
            team: team,
            rank: 10,
            wins: 40,
            losses: 90,
            ties: 0,
            remainingRegularSeasonGames: 0,
            recentResults: [],
            postseasonQualificationProbability: 0,
            postseasonQualificationStatus: .eliminated
        )

        #expect(clinched.postseasonQualificationText == "100.0%")
        #expect(eliminated.postseasonQualificationText == "0.0%")
    }

    @Test func snapshotCalculatesPythagoreanWinningPercentageFromRunsScoredAndAllowed() throws {
        let team = Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG")
        let positiveSnapshot = TeamStandingsSnapshot(
            team: team,
            rank: 1,
            wins: 10,
            losses: 5,
            ties: 0,
            runsScored: 90,
            runsAllowed: 60,
            remainingRegularSeasonGames: 129,
            recentResults: []
        )
        let negativeSnapshot = TeamStandingsSnapshot(
            team: team,
            rank: 1,
            wins: 5,
            losses: 10,
            ties: 0,
            runsScored: 60,
            runsAllowed: 90,
            remainingRegularSeasonGames: 129,
            recentResults: []
        )
        let evenSnapshot = TeamStandingsSnapshot(
            team: team,
            rank: 1,
            wins: 8,
            losses: 8,
            ties: 0,
            runsScored: 77,
            runsAllowed: 77,
            remainingRegularSeasonGames: 128,
            recentResults: []
        )

        let positiveValue = try #require(positiveSnapshot.pythagoreanWinningPercentage)
        let negativeValue = try #require(negativeSnapshot.pythagoreanWinningPercentage)
        let evenValue = try #require(evenSnapshot.pythagoreanWinningPercentage)

        #expect(positiveValue > 0.5)
        #expect(negativeValue < 0.5)
        #expect(abs(evenValue - 0.5) < 0.000_1)
    }

    @Test func snapshotPythagoreanWinningPercentageReturnsNeutralForZeroRuns() throws {
        let team = Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG")
        let snapshot = TeamStandingsSnapshot(
            team: team,
            rank: 1,
            wins: 0,
            losses: 0,
            ties: 0,
            runsScored: 0,
            runsAllowed: 0,
            remainingRegularSeasonGames: 144,
            recentResults: []
        )

        let value = try #require(snapshot.pythagoreanWinningPercentage)

        #expect(value == 0.5)
        #expect(snapshot.pythagoreanWinningPercentageText == "0.500")
    }

    @Test func snapshotPythagoreanWinningPercentageIsUnavailableWithoutRunData() {
        let team = Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG")
        let snapshot = TeamStandingsSnapshot(
            team: team,
            rank: 1,
            wins: 10,
            losses: 5,
            ties: 0,
            remainingRegularSeasonGames: 129,
            recentResults: []
        )

        #expect(snapshot.pythagoreanWinningPercentage == nil)
        #expect(snapshot.pythagoreanWinningPercentageText == "---")
    }

    @Test func standingsSnapshotUsesOnlyCompletedRegularSeasonGamesForRunTotalsAndPythagoreanWinningPercentage() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-03T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let samsung = try #require(base.teams.first(where: { $0.id == "samsung" }))

        let regularWin = makeGameDetail(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason
        )
        let regularLoss = makeGameDetail(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
            scheduledStart: isoDate("2026-03-29T14:00:00+09:00"),
            venue: "대구",
            awayTeam: lg,
            homeTeam: samsung,
            awayScore: 3,
            homeScore: 4,
            status: .final,
            seasonClassification: .regularSeason
        )
        let exhibition = makeGameDetail(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000003")!,
            scheduledStart: isoDate("2026-03-15T13:00:00+09:00"),
            venue: "잠실",
            awayTeam: samsung,
            homeTeam: lg,
            awayScore: 1,
            homeScore: 9,
            status: .final,
            seasonClassification: .exhibitionPreseason
        )
        let postseason = makeGameDetail(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
            scheduledStart: isoDate("2026-10-12T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 0,
            homeScore: 7,
            status: .final,
            seasonClassification: .postseason
        )
        let cancelled = makeGameDetail(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000005")!,
            scheduledStart: isoDate("2026-04-01T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .cancelled,
            seasonClassification: .regularSeason
        )
        let live = makeGameDetail(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000006")!,
            scheduledStart: isoDate("2026-04-02T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: samsung,
            homeTeam: lg,
            awayScore: 6,
            homeScore: 6,
            status: .live,
            seasonClassification: .regularSeason
        )

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan, samsung],
                games: [regularWin, regularLoss, exhibition, postseason, cancelled, live],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let lgSnapshot = try #require(model.standingsSnapshots.first(where: { $0.team.id == "lg" }))
        let doosanSnapshot = try #require(model.standingsSnapshots.first(where: { $0.team.id == "doosan" }))
        let samsungSnapshot = try #require(model.standingsSnapshots.first(where: { $0.team.id == "samsung" }))

        #expect(lgSnapshot.wins == 1)
        #expect(lgSnapshot.losses == 1)
        #expect(lgSnapshot.runsScored == 8)
        #expect(lgSnapshot.runsAllowed == 6)
        #expect(lgSnapshot.pythagoreanWinningPercentage == StandingsMetrics.pythagoreanWinningPercentage(runsScored: 8, runsAllowed: 6))

        #expect(doosanSnapshot.runsScored == 2)
        #expect(doosanSnapshot.runsAllowed == 5)
        #expect(doosanSnapshot.pythagoreanWinningPercentage == StandingsMetrics.pythagoreanWinningPercentage(runsScored: 2, runsAllowed: 5))

        #expect(samsungSnapshot.runsScored == 4)
        #expect(samsungSnapshot.runsAllowed == 3)
        #expect(samsungSnapshot.pythagoreanWinningPercentage == StandingsMetrics.pythagoreanWinningPercentage(runsScored: 4, runsAllowed: 3))
    }

    @Test func fallbackRepositoryUsesMockWhenLiveRequestFails() async throws {
        let session = makeStubSession()
        let live = LiveKBORepository(baseURL: URL(string: "https://example.com/api/")!, session: session)
        let repository = FallbackKBORepository(primary: live, fallback: MockKBORepository(), runtimeState: nil)
        URLProtocolStub.testResponses = [
            "https://example.com/api/bootstrap": StubResponse(statusCode: 500, data: Data())
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let bootstrap = try await repository.fetchBootstrapData()

        #expect(bootstrap.teams.count == 10)
        #expect(bootstrap.games.isEmpty == false)
    }

    @Test func fallbackRepositoryUsesMockMonthlyScheduleWhenLiveRequestFails() async throws {
        let session = makeStubSession()
        let live = LiveKBORepository(baseURL: URL(string: "https://example.com/api/")!, session: session)
        let repository = FallbackKBORepository(primary: live, fallback: MockKBORepository(), runtimeState: nil)
        URLProtocolStub.testResponses = [
            "https://example.com/api/schedule/month?year=2026&month=3": StubResponse(statusCode: 500, data: Data())
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let games = try await repository.fetchMonthlySchedule(for: KBOMonthScheduleKey(year: 2026, month: 3))

        #expect(games.isEmpty == false)
        #expect(games.contains { $0.awayTeam.id == "kiwoom" && $0.homeTeam.id == "lg" })
    }

    @Test func cachedRepositoryReusesFreshGameCache() async throws {
        let counter = FetchCounter()
        let repository = CachedKBORepository(
            base: StubRepository(
                fetchGames: {
                    await counter.increment()
                    return MockKBOData.makeBootstrap().games
                }
            ),
            configuration: RepositoryCacheConfiguration(bootstrapTTL: 1, gamesTTL: 60, notificationsTTL: 1, monthlyScheduleTTL: 60),
            runtimeState: nil
        )

        let first = try await repository.fetchGames()
        let second = try await repository.fetchGames()

        #expect(first.count == second.count)
        #expect(await counter.value == 1)
    }

    @Test func cachedRepositoryFallsBackToStaleCacheAfterFailedRefresh() async throws {
        let counter = FetchCounter()
        let runtimeState = RepositoryRuntimeState(activeSource: .live, baseURL: "https://example.com", deliverySource: .live)
        let repository = CachedKBORepository(
            base: StubRepository(
                fetchGames: {
                    let attempt = await counter.incrementAndReturn()
                    if attempt == 1 {
                        return MockKBOData.makeBootstrap().games
                    }
                    throw URLError(.timedOut)
                }
            ),
            configuration: RepositoryCacheConfiguration(bootstrapTTL: 1, gamesTTL: 0, notificationsTTL: 1, monthlyScheduleTTL: 60),
            runtimeState: runtimeState
        )

        let fresh = try await repository.fetchGames()
        let cached = try await repository.fetchGames()
        let snapshot = await runtimeState.snapshot()

        #expect(fresh.count == cached.count)
        #expect(await counter.value == 2)
        #expect(snapshot.deliverySource == .cache)
        #expect(snapshot.isUsingStaleCache == true)
    }

    @Test func cachedRepositoryReusesFreshMonthlyScheduleCache() async throws {
        let counter = FetchCounter()
        let repository = CachedKBORepository(
            base: StubRepository(
                fetchMonthlySchedule: { _ in
                    await counter.increment()
                    return stubGames()
                }
            ),
            configuration: RepositoryCacheConfiguration(bootstrapTTL: 1, gamesTTL: 1, notificationsTTL: 1, monthlyScheduleTTL: 60),
            runtimeState: nil
        )

        let key = KBOMonthScheduleKey(year: 2026, month: 3)
        let first = try await repository.fetchMonthlySchedule(for: key)
        let second = try await repository.fetchMonthlySchedule(for: key)

        #expect(first.count == second.count)
        #expect(await counter.value == 1)
    }

    @Test func cachedRepositoryFallsBackToPersistedGamesCacheAcrossInstances() async throws {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let configuration = RepositoryCacheConfiguration(
            bootstrapTTL: 1,
            gamesTTL: 0,
            notificationsTTL: 1,
            monthlyScheduleTTL: 60,
            diskCacheDirectory: cacheDirectory
        )
        let seededRepository = CachedKBORepository(
            base: StubRepository(fetchGames: { stubGames() }),
            configuration: configuration,
            runtimeState: nil
        )
        let expectedGames = try await seededRepository.fetchGames()

        let runtimeState = RepositoryRuntimeState(
            activeSource: .live,
            baseURL: "https://example.com",
            deliverySource: .live
        )
        let cachedRepository = CachedKBORepository(
            base: StubRepository(fetchGames: { throw URLError(.cannotConnectToHost) }),
            configuration: configuration,
            runtimeState: runtimeState
        )

        let cachedGames = try await cachedRepository.fetchGames()
        let snapshot = await runtimeState.snapshot()

        #expect(cachedGames == expectedGames)
        #expect(snapshot.deliverySource == .cache)
        #expect(snapshot.isUsingStaleCache == true)
    }

    @Test func cachedRepositoryFallsBackToPersistedMonthlyScheduleAcrossInstances() async throws {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let configuration = RepositoryCacheConfiguration(
            bootstrapTTL: 1,
            gamesTTL: 1,
            notificationsTTL: 1,
            monthlyScheduleTTL: 0,
            diskCacheDirectory: cacheDirectory
        )
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 3)
        let seededRepository = CachedKBORepository(
            base: StubRepository(fetchMonthlySchedule: { _ in stubGames() }),
            configuration: configuration,
            runtimeState: nil
        )
        let expectedSchedule = try await seededRepository.fetchMonthlySchedule(for: monthKey)

        let cachedRepository = CachedKBORepository(
            base: StubRepository(fetchMonthlySchedule: { _ in throw URLError(.timedOut) }),
            configuration: configuration,
            runtimeState: nil
        )

        let cachedSchedule = try await cachedRepository.fetchMonthlySchedule(for: monthKey)

        #expect(cachedSchedule == expectedSchedule)
    }

    @Test func appModelKeepsExistingGamesWhenRefreshFails() async throws {
        let repository = StubRepository(
            fetchGames: {
                throw URLError(.cannotLoadFromNetwork)
            }
        )
        let model = AppModel(repository: repository, bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)

        await model.refreshHome()

        #expect(model.games.isEmpty == false)
        #expect(model.loadErrorMessage == nil)
        #expect(model.isShowingStaleData == true)
        #expect(model.statusMessage(for: .home) != nil)
    }

    @Test func myTeamCalendarDerivesMonthGridFromExistingGames() async throws {
        let referenceDate = ISO8601DateFormatter().date(from: "2026-03-23T12:00:00+09:00")!
        let model = AppModel(
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false
        )

        model.settings.favoriteTeamID = "lg"
        let days = model.myTeamCalendarDays(for: referenceDate)
        let selectedDayGames = model.myTeamGames(on: referenceDate)

        #expect(days.count.isMultiple(of: 7))
        #expect(days.contains { Calendar(identifier: .gregorian).isDate($0.date, inSameDayAs: referenceDate) && $0.hasGames })
        #expect(selectedDayGames.contains { $0.awayTeam.id == "kiwoom" && $0.homeTeam.id == "lg" })
    }

    @Test func myTeamCalendarUsesLoadedOfficialMonthSchedule() async throws {
        let referenceDate = ISO8601DateFormatter().date(from: "2026-03-12T09:00:00+09:00")!
        let schedule = try KBODataMapper.mapGames(
            KBOExternalResponseAdapter.normalize(data: fixtureData(named: "2026-kbo-official-schedule-list-202603")).games,
            teams: KBODataMapper.mapBootstrap(MockKBOData.makeBootstrapDTO()).teams
        )
        let repository = StubRepository(fetchMonthlySchedule: { _ in schedule })
        let model = AppModel(repository: repository, bootstrap: MockKBOData.makeBootstrap(now: referenceDate), usePersistedSettings: false)

        model.settings.favoriteTeamID = "lg"
        await model.loadMyTeamScheduleIfNeeded(for: referenceDate)
        let games = model.myTeamGames(on: referenceDate)

        #expect(games.count == 1)
        #expect(games.first?.homeTeam.id == "nc")
        #expect(games.first?.awayTeam.id == "lg")
        #expect(model.myTeamCalendarDays(for: referenceDate).contains {
            Calendar(identifier: .gregorian).isDate($0.date, inSameDayAs: referenceDate) && $0.gameCount == 1
        })
    }

    @Test func scheduleLoadFetchesMonthlyDataWithoutFavoriteTeamSelection() async throws {
        let counter = FetchCounter()
        let referenceDate = ISO8601DateFormatter().date(from: "2026-03-12T09:00:00+09:00")!
        let schedule = try KBODataMapper.mapGames(
            KBOExternalResponseAdapter.normalize(data: fixtureData(named: "2026-kbo-official-schedule-list-202603")).games,
            teams: KBODataMapper.mapBootstrap(MockKBOData.makeBootstrapDTO()).teams
        )
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            await counter.increment()
            return schedule
        })
        let model = AppModel(repository: repository, bootstrap: MockKBOData.makeBootstrap(now: referenceDate), usePersistedSettings: false)

        model.settings.favoriteTeamID = nil
        await model.loadScheduleIfNeeded(for: referenceDate)

        #expect(await counter.value == 1)
        #expect(model.scheduleGames(on: referenceDate, filter: .all).count == 1)
        #expect(model.scheduleGames(on: referenceDate, filter: .myTeam).isEmpty)
    }

    @Test func scheduleStatusMessageExplicitlyShowsMissingLiveConfiguration() async throws {
        let referenceDate = ISO8601DateFormatter().date(from: "2026-03-12T09:00:00+09:00")!
        let runtimeState = RepositoryRuntimeState(activeSource: .mock, baseURL: nil, deliverySource: .mock)
        let repository = RuntimeStateReportingRepository(
            base: StubRepository(fetchMonthlySchedule: { _ in
                try KBODataMapper.mapGames(
                    KBOExternalResponseAdapter.normalize(data: fixtureData(named: "2026-kbo-official-schedule-list-202603")).games,
                    teams: KBODataMapper.mapBootstrap(MockKBOData.makeBootstrapDTO()).teams
                )
            }),
            source: .mock,
            delivery: .mock,
            runtimeState: runtimeState
        )
        let model = AppModel(
            repository: repository,
            repositoryRuntimeState: runtimeState,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false
        )

        await model.loadScheduleIfNeeded(for: referenceDate)

        #expect(model.scheduleStatusMessage(for: referenceDate) == "실데이터 URL 미설정 · 목 일정으로 표시 중입니다.")
        #expect(model.scheduleDebugSummary(for: referenceDate)?.contains("실데이터 URL 없음") == true)
    }

    @Test func scheduleDebugSummaryReflectsLiveMonthlyScheduleSource() async throws {
        let referenceDate = ISO8601DateFormatter().date(from: "2026-03-12T09:00:00+09:00")!
        let runtimeState = RepositoryRuntimeState(
            activeSource: .live,
            baseURL: "https://www.koreabaseball.com/",
            deliverySource: .live
        )
        let schedule = try KBODataMapper.mapGames(
            KBOExternalResponseAdapter.normalize(data: fixtureData(named: "2026-kbo-official-schedule-list-202603")).games,
            teams: KBODataMapper.mapBootstrap(MockKBOData.makeBootstrapDTO()).teams
        )
        let repository = RuntimeStateReportingRepository(
            base: StubRepository(fetchMonthlySchedule: { _ in schedule }),
            source: .live,
            delivery: .live,
            runtimeState: runtimeState
        )
        let model = AppModel(
            repository: repository,
            repositoryRuntimeState: runtimeState,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false
        )

        await model.loadScheduleIfNeeded(for: referenceDate)

        #expect(model.scheduleGames(on: referenceDate, filter: .all).count == 1)
        #expect(model.scheduleStatusMessage(for: referenceDate) == nil)
        #expect(model.scheduleDebugSummary(for: referenceDate)?.contains("소스 실데이터") == true)
        #expect(model.scheduleDebugSummary(for: referenceDate)?.contains("표시 실시간 응답") == true)
    }

    @Test func scheduleCalendarUsesBackendMonthResponseShapeAndProducesDayMarkers() async throws {
        let backendMonthlyPayload = try makeBackendMonthPayloadJSON()
        let session = makeStubSession()
        let repository = LiveKBORepository(baseURL: URL(string: "https://example.com/api/")!, session: session)
        URLProtocolStub.testResponses = [
            "https://example.com/api/schedule/month?year=2026&month=3": StubResponse(statusCode: 200, data: backendMonthlyPayload)
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        let monthKey = KBOMonthScheduleKey(year: 2026, month: 3)
        let schedule = try await repository.fetchMonthlySchedule(for: monthKey)
        let requestedURL = try #require(URLProtocolStub.lastRequest?.url?.absoluteString)
        print("[ScheduleDebugTest] requestedURL=\(requestedURL)")
        print("[ScheduleDebugTest] decodedGamesCount=\(schedule.count)")

        #expect(requestedURL == "https://example.com/api/schedule/month?year=2026&month=3")
        #expect(schedule.count == 15)

        let referenceDate = ISO8601DateFormatter().date(from: "2026-03-01T00:00:00+09:00")!
        let model = AppModel(repository: repository, bootstrap: MockKBOData.makeBootstrap(now: referenceDate), usePersistedSettings: false)
        await model.loadScheduleIfNeeded(for: referenceDate)
        let calendarDays = model.scheduleCalendarDays(for: referenceDate, filter: .all)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"

        let markerDays = calendarDays
            .filter { $0.isInDisplayedMonth && $0.hasGames }
            .map { formatter.string(from: $0.date) }
        print("[ScheduleDebugTest] groupedCalendarDateKeys=\(markerDays.sorted())")

        let targetDates = ["2026-03-28", "2026-03-29", "2026-03-31"]
        for targetDate in targetDates {
            let hasMarker = markerDays.contains(targetDate)
            print("[ScheduleDebugTest] calendarLookup date=\(targetDate) hasGames=\(hasMarker)")
            #expect(hasMarker)
        }
        #expect(markerDays.isEmpty == false)
    }

}

private struct StubResponse {
    let statusCode: Int
    let data: Data
    let headers: [String: String]

    init(
        statusCode: Int,
        data: Data,
        headers: [String: String] = [:]
    ) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    static var testResponses: [String: StubResponse] = [:]
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host == "example.com" || host == "www.koreabaseball.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        guard let url = request.url, let response = Self.testResponses[url.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: response.headers.merging(["Content-Type": "application/json"]) { current, _ in current }
        )!

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
}

private func fixtureData(named name: String) throws -> Data {
    let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
    return try Data(contentsOf: fixturesDirectory.appendingPathComponent("\(name).json"))
}

private func saveFixtureData(_ data: Data, named name: String) throws {
    let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
    try FileManager.default.createDirectory(at: fixturesDirectory, withIntermediateDirectories: true, attributes: nil)
    try data.write(to: fixturesDirectory.appendingPathComponent("\(name).json"), options: .atomic)
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
    return directory
}

private func makeTemporaryUserDefaults() -> UserDefaults {
    let suiteName = "kboScoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func appLocalBootstrapFixtureData() throws -> Data {
    let projectDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try Data(contentsOf: projectDirectory.appendingPathComponent("kboScore/LocalBootstrapData.json"))
}

private func makeBootstrapJSON(
    teamName: String? = nil,
    firstGameAwayScore: Int? = nil
) throws -> Data {
    guard var root = try JSONSerialization.jsonObject(with: appLocalBootstrapFixtureData()) as? [String: Any] else {
        throw CocoaError(.fileReadCorruptFile)
    }

    if let teamName {
        guard var teams = root["teams"] as? [[String: Any]],
              let teamIndex = teams.firstIndex(where: { ($0["id"] as? String) == "lg" }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        teams[teamIndex]["name"] = teamName
        root["teams"] = teams
    }

    if let firstGameAwayScore {
        guard var games = root["games"] as? [[String: Any]], games.isEmpty == false else {
            throw CocoaError(.fileReadCorruptFile)
        }
        games[0]["away_score"] = firstGameAwayScore
        root["games"] = games
    }

    return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
}

private func makeBootstrapAPIResponseJSON(
    teamName: String? = nil,
    firstGameAwayScore: Int? = nil,
    generatedAt: String = "2026-04-03T12:00:00+09:00",
    dataVersion: String = "test-revision-1"
) throws -> Data {
    guard var root = try JSONSerialization.jsonObject(
        with: makeBootstrapJSON(teamName: teamName, firstGameAwayScore: firstGameAwayScore)
    ) as? [String: Any] else {
        throw CocoaError(.fileReadCorruptFile)
    }

    root["generated_at"] = generatedAt
    root["data_version"] = dataVersion
    return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
}

private func makeBackendMonthPayloadJSON() throws -> Data {
    func team(_ code: String, _ nameKo: String, _ shortName: String, _ themeColor: String, _ logo: String) -> [String: Any] {
        [
            "code": code,
            "nameKo": nameKo,
            "shortName": shortName,
            "themeColor": themeColor,
            "logoAssetName": logo
        ]
    }

    let games: [[String: Any]] = [
        ["id": "bdd3ec7a-69aa-400d-9929-7b27e4f4cde7", "gameDate": "2026-03-28", "gameTime": "14:00", "status": "scheduled", "stadium": "문학", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SSG", "SSG 랜더스", "SSG", "#CE0E2D", "ssg"), "awayTeam": team("KIA", "KIA 타이거즈", "KIA", "#EA0029", "kia")],
        ["id": "19458f95-24ee-4de1-af30-ecc8152c24ee", "gameDate": "2026-03-28", "gameTime": "14:00", "status": "scheduled", "stadium": "잠실", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("LG", "LG 트윈스", "LG", "#C30452", "lg"), "awayTeam": team("KT", "KT 위즈", "KT", "#000000", "kt")],
        ["id": "3d17cfd0-358d-4e2c-b40c-35671ca041b2", "gameDate": "2026-03-28", "gameTime": "14:00", "status": "scheduled", "stadium": "창원", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("NC", "NC 다이노스", "NC", "#315288", "nc"), "awayTeam": team("DOOSAN", "두산 베어스", "두산", "#131230", "doosan")],
        ["id": "d3a57c14-2ad5-4baf-b2cf-a5ea4eb26c3b", "gameDate": "2026-03-28", "gameTime": "14:00", "status": "scheduled", "stadium": "대구", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SAMSUNG", "삼성 라이온즈", "삼성", "#0066B3", "samsung"), "awayTeam": team("LOTTE", "롯데 자이언츠", "롯데", "#041E42", "lotte")],
        ["id": "ba878f3f-ebe8-40b7-bc72-3f113801b71f", "gameDate": "2026-03-28", "gameTime": "14:00", "status": "scheduled", "stadium": "대전", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("HANWHA", "한화 이글스", "한화", "#FF6600", "hanwha"), "awayTeam": team("KIWOOM", "키움 히어로즈", "키움", "#570514", "kiwoom")],
        ["id": "8eb61818-1148-4f64-9176-eb08cd9e0371", "gameDate": "2026-03-29", "gameTime": "14:00", "status": "scheduled", "stadium": "문학", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SSG", "SSG 랜더스", "SSG", "#CE0E2D", "ssg"), "awayTeam": team("KIA", "KIA 타이거즈", "KIA", "#EA0029", "kia")],
        ["id": "ed85a6ff-d525-4fba-938c-1957da4b76c5", "gameDate": "2026-03-29", "gameTime": "14:00", "status": "scheduled", "stadium": "잠실", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("LG", "LG 트윈스", "LG", "#C30452", "lg"), "awayTeam": team("KT", "KT 위즈", "KT", "#000000", "kt")],
        ["id": "c08a2da6-8b3e-4182-a36b-8039c68cbf78", "gameDate": "2026-03-29", "gameTime": "14:00", "status": "scheduled", "stadium": "창원", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("NC", "NC 다이노스", "NC", "#315288", "nc"), "awayTeam": team("DOOSAN", "두산 베어스", "두산", "#131230", "doosan")],
        ["id": "347710af-708a-423e-807a-7805c2a32782", "gameDate": "2026-03-29", "gameTime": "14:00", "status": "scheduled", "stadium": "대구", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SAMSUNG", "삼성 라이온즈", "삼성", "#0066B3", "samsung"), "awayTeam": team("LOTTE", "롯데 자이언츠", "롯데", "#041E42", "lotte")],
        ["id": "1697aa01-16cb-41dc-8189-770415b6528b", "gameDate": "2026-03-29", "gameTime": "14:00", "status": "scheduled", "stadium": "대전", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("HANWHA", "한화 이글스", "한화", "#FF6600", "hanwha"), "awayTeam": team("KIWOOM", "키움 히어로즈", "키움", "#570514", "kiwoom")],
        ["id": "5cae24b4-c3b9-46fd-80dc-8072a84c8353", "gameDate": "2026-03-31", "gameTime": "18:30", "status": "scheduled", "stadium": "잠실", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("LG", "LG 트윈스", "LG", "#C30452", "lg"), "awayTeam": team("KIA", "KIA 타이거즈", "KIA", "#EA0029", "kia")],
        ["id": "32ac800e-88d6-4ad0-9c0c-312ccf71e0b8", "gameDate": "2026-03-31", "gameTime": "18:30", "status": "scheduled", "stadium": "대전", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("HANWHA", "한화 이글스", "한화", "#FF6600", "hanwha"), "awayTeam": team("KT", "KT 위즈", "KT", "#000000", "kt")],
        ["id": "558438b2-a0ed-4f8c-a766-27f332e4f69a", "gameDate": "2026-03-31", "gameTime": "18:30", "status": "scheduled", "stadium": "대구", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SAMSUNG", "삼성 라이온즈", "삼성", "#0066B3", "samsung"), "awayTeam": team("DOOSAN", "두산 베어스", "두산", "#131230", "doosan")],
        ["id": "7d91e0ac-642b-447f-a25b-18865a7a5719", "gameDate": "2026-03-31", "gameTime": "18:30", "status": "scheduled", "stadium": "창원", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("NC", "NC 다이노스", "NC", "#315288", "nc"), "awayTeam": team("LOTTE", "롯데 자이언츠", "롯데", "#041E42", "lotte")],
        ["id": "8428cc15-4999-4b38-9f3d-c02ee97c61d9", "gameDate": "2026-03-31", "gameTime": "18:30", "status": "scheduled", "stadium": "문학", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SSG", "SSG 랜더스", "SSG", "#CE0E2D", "ssg"), "awayTeam": team("KIWOOM", "키움 히어로즈", "키움", "#570514", "kiwoom")]
    ]

    let root: [String: Any] = [
        "year": 2026,
        "month": 3,
        "totalCount": 15,
        "games": games
    ]
    return try JSONSerialization.data(withJSONObject: root, options: [])
}

private actor FetchCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func incrementAndReturn() -> Int {
        count += 1
        return count
    }

    var value: Int { count }
}

@MainActor
private final class TestLiveActivityController: FavoriteTeamLiveActivityControlling {
    let isSupported: Bool

    private(set) var activeGameID: UUID?

    init(isSupported: Bool) {
        self.isSupported = isSupported
    }

    func startOrUpdate(using snapshot: FavoriteTeamLiveActivitySnapshot) async throws {
        activeGameID = snapshot.gameID
    }

    func endCurrent() async {
        activeGameID = nil
    }
}

private struct StubRepository: KBORepository {
    var fetchBootstrapDataHandler: @Sendable () async throws -> KBOBootstrapData = {
        stubBootstrap()
    }
    var fetchGamesHandler: @Sendable () async throws -> [GameDetail] = {
        stubGames()
    }
    var fetchNotificationsHandler: @Sendable () async throws -> [NotificationItem] = {
        stubNotifications()
    }
    var fetchMonthlyScheduleHandler: @Sendable (KBOMonthScheduleKey) async throws -> [GameDetail] = { _ in
        stubGames()
    }
    var fetchStandingsHandler: @Sendable () async throws -> [TeamStandingsSnapshot] = {
        []
    }

    init(
        fetchBootstrapData: @escaping @Sendable () async throws -> KBOBootstrapData = { stubBootstrap() },
        fetchGames: @escaping @Sendable () async throws -> [GameDetail] = { stubGames() },
        fetchNotifications: @escaping @Sendable () async throws -> [NotificationItem] = { stubNotifications() },
        fetchMonthlySchedule: @escaping @Sendable (KBOMonthScheduleKey) async throws -> [GameDetail] = { _ in stubGames() },
        fetchStandings: @escaping @Sendable () async throws -> [TeamStandingsSnapshot] = { [] }
    ) {
        self.fetchBootstrapDataHandler = fetchBootstrapData
        self.fetchGamesHandler = fetchGames
        self.fetchNotificationsHandler = fetchNotifications
        self.fetchMonthlyScheduleHandler = fetchMonthlySchedule
        self.fetchStandingsHandler = fetchStandings
    }

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        try await fetchBootstrapDataHandler()
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await fetchGamesHandler()
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await fetchNotificationsHandler()
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await fetchMonthlyScheduleHandler(month)
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await fetchStandingsHandler()
    }
}

private func stubBootstrap() -> KBOBootstrapData {
    MockKBOData.makeBootstrap()
}

private func stubGames() -> [GameDetail] {
    stubBootstrap().games
}

private func stubNotifications() -> [NotificationItem] {
    stubBootstrap().notifications
}

private func isoDate(_ rawValue: String) -> Date {
    ISO8601DateFormatter().date(from: rawValue)!
}

private func makeGameDetail(
    id: UUID,
    scheduledStart: Date,
    venue: String,
    awayTeam: Team,
    homeTeam: Team,
    awayScore: Int?,
    homeScore: Int?,
    status: GameStatus,
    seasonClassification: GameSeasonClassification = .unknown,
    note: String? = nil
) -> GameDetail {
    GameDetail(
        id: id,
        scheduledStart: scheduledStart,
        venue: venue,
        awayTeam: awayTeam,
        homeTeam: homeTeam,
        awayScore: awayScore,
        homeScore: homeScore,
        status: status,
        seasonClassification: seasonClassification,
        inningText: status.title,
        bases: nil,
        outs: nil,
        highlightText: nil,
        events: [],
        note: note,
        providerGameID: nil
    )
}

private func makeProbabilityTestTeams(includePreviousRanks: Bool = true) -> [Team] {
    (1...10).map { index in
        let previousRegularSeasonRank: Int? = includePreviousRanks ? index : nil
        return Team(
            id: "team\(index)",
            name: "팀\(index)",
            shortName: "T\(index)",
            englishName: "Team \(index)",
            markText: "T\(index)",
            previousRegularSeasonRank: previousRegularSeasonRank
        )
    }
}

private func makeProbabilityThresholdSchedule(
    teams: [Team],
    completedGamesPerTeam: Int,
    seasonLength: Int
) -> [GameDetail] {
    precondition(teams.count == 10)
    precondition((0...seasonLength).contains(completedGamesPerTeam))

    let pairings = [(0, 9), (1, 8), (2, 7), (3, 6), (4, 5)]
    var games: [GameDetail] = []
    var identifierIndex = 1

    for _ in 0..<completedGamesPerTeam {
        for (winnerIndex, loserIndex) in pairings {
            let identifier = String(format: "63000000-0000-0000-0000-%012d", identifierIndex)
            games.append(
                completedProbabilityGame(
                    id: identifier,
                    awayTeam: teams[loserIndex],
                    homeTeam: teams[winnerIndex],
                    awayScore: 2,
                    homeScore: 5
                )
            )
            identifierIndex += 1
        }
    }

    for _ in completedGamesPerTeam..<seasonLength {
        for (winnerIndex, loserIndex) in pairings {
            let identifier = String(format: "64000000-0000-0000-0000-%012d", identifierIndex)
            games.append(
                makeGameDetail(
                    id: UUID(uuidString: identifier)!,
                    scheduledStart: isoDate("2026-09-20T18:30:00+09:00"),
                    venue: "잠실",
                    awayTeam: teams[winnerIndex],
                    homeTeam: teams[loserIndex],
                    awayScore: nil,
                    homeScore: nil,
                    status: .upcoming,
                    seasonClassification: .regularSeason
                )
            )
            identifierIndex += 1
        }
    }

    return games
}

private func completedProbabilityGame(
    id: String,
    awayTeam: Team,
    homeTeam: Team,
    awayScore: Int,
    homeScore: Int
) -> GameDetail {
    makeGameDetail(
        id: UUID(uuidString: id)!,
        scheduledStart: isoDate("2026-09-19T18:30:00+09:00"),
        venue: "잠실",
        awayTeam: awayTeam,
        homeTeam: homeTeam,
        awayScore: awayScore,
        homeScore: homeScore,
        status: .final,
        seasonClassification: .regularSeason,
        note: "db_export provider_game_id=20260919\(awayTeam.shortName)\(homeTeam.shortName)0"
    )
}

private func makeConservativeEarlySeasonProbabilitySchedule(
    teams: [Team],
    completedGamesPerTeam: Int,
    seasonLength: Int
) -> [GameDetail] {
    var gaveTeam1OpeningLoss = false

    return makeRoundRobinProbabilitySchedule(
        teams: teams,
        completedGamesPerTeam: completedGamesPerTeam,
        seasonLength: seasonLength
    ) { _, awayTeam, homeTeam in
        let winningTeamID: String

        if awayTeam.id == "team1" || homeTeam.id == "team1" {
            if gaveTeam1OpeningLoss == false {
                gaveTeam1OpeningLoss = true
                winningTeamID = awayTeam.id == "team1" ? homeTeam.id : awayTeam.id
            } else {
                winningTeamID = "team1"
            }
        } else if awayTeam.id == "team10" || homeTeam.id == "team10" {
            winningTeamID = awayTeam.id == "team10" ? homeTeam.id : awayTeam.id
        } else {
            let awayRank = awayTeam.previousRegularSeasonRank ?? Int.max
            let homeRank = homeTeam.previousRegularSeasonRank ?? Int.max
            winningTeamID = awayRank <= homeRank ? awayTeam.id : homeTeam.id
        }

        if winningTeamID == awayTeam.id {
            return (awayScore: 5, homeScore: 3)
        }
        return (awayScore: 3, homeScore: 5)
    }
}

private func makeRoundRobinProbabilitySchedule(
    teams: [Team],
    completedGamesPerTeam: Int,
    seasonLength: Int,
    completedScoreProvider: (_ round: Int, _ awayTeam: Team, _ homeTeam: Team) -> (awayScore: Int, homeScore: Int)
) -> [GameDetail] {
    precondition(teams.count.isMultiple(of: 2))
    precondition((0...seasonLength).contains(completedGamesPerTeam))

    let roundPairings = roundRobinPairings(teamCount: teams.count)
    var games: [GameDetail] = []
    var identifierIndex = 1

    for round in 0..<seasonLength {
        let pairings = roundPairings[round % roundPairings.count]
        for (pairIndex, pairing) in pairings.enumerated() {
            let isHomeTeamSecond = (round + pairIndex).isMultiple(of: 2)
            let awayTeam = isHomeTeamSecond ? teams[pairing.first] : teams[pairing.second]
            let homeTeam = isHomeTeamSecond ? teams[pairing.second] : teams[pairing.first]
            let scheduledStart = isoDate(
                String(
                    format: "2026-%02d-%02dT18:30:00+09:00",
                    min(12, 3 + (round / 27)),
                    1 + (round % 27)
                )
            )

            if round < completedGamesPerTeam {
                let score = completedScoreProvider(round, awayTeam, homeTeam)
                let identifier = String(format: "65000000-0000-0000-0000-%012d", identifierIndex)
                games.append(
                    makeGameDetail(
                        id: UUID(uuidString: identifier)!,
                        scheduledStart: scheduledStart,
                        venue: "잠실",
                        awayTeam: awayTeam,
                        homeTeam: homeTeam,
                        awayScore: score.awayScore,
                        homeScore: score.homeScore,
                        status: .final,
                        seasonClassification: .regularSeason,
                        note: "db_export provider_game_id=2026RR\(identifierIndex)"
                    )
                )
            } else {
                let identifier = String(format: "66000000-0000-0000-0000-%012d", identifierIndex)
                games.append(
                    makeGameDetail(
                        id: UUID(uuidString: identifier)!,
                        scheduledStart: scheduledStart,
                        venue: "잠실",
                        awayTeam: awayTeam,
                        homeTeam: homeTeam,
                        awayScore: nil,
                        homeScore: nil,
                        status: .upcoming,
                        seasonClassification: .regularSeason
                    )
                )
            }

            identifierIndex += 1
        }
    }

    return games
}

private func roundRobinPairings(teamCount: Int) -> [[(first: Int, second: Int)]] {
    precondition(teamCount.isMultiple(of: 2))

    var rotation = Array(0..<teamCount)
    var rounds: [[(first: Int, second: Int)]] = []

    for _ in 0..<(teamCount - 1) {
        var round: [(first: Int, second: Int)] = []
        for pairIndex in 0..<(teamCount / 2) {
            round.append((first: rotation[pairIndex], second: rotation[teamCount - 1 - pairIndex]))
        }
        rounds.append(round)

        let fixed = rotation.removeFirst()
        let last = rotation.removeLast()
        rotation.insert(last, at: 0)
        rotation.insert(fixed, at: 0)
    }

    return rounds
}
