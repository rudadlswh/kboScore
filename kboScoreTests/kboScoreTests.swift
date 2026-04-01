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
            headerFields: ["Content-Type": "application/json"]
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

    init(
        fetchBootstrapData: @escaping @Sendable () async throws -> KBOBootstrapData = { stubBootstrap() },
        fetchGames: @escaping @Sendable () async throws -> [GameDetail] = { stubGames() },
        fetchNotifications: @escaping @Sendable () async throws -> [NotificationItem] = { stubNotifications() },
        fetchMonthlySchedule: @escaping @Sendable (KBOMonthScheduleKey) async throws -> [GameDetail] = { _ in stubGames() }
    ) {
        self.fetchBootstrapDataHandler = fetchBootstrapData
        self.fetchGamesHandler = fetchGames
        self.fetchNotificationsHandler = fetchNotifications
        self.fetchMonthlyScheduleHandler = fetchMonthlySchedule
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
