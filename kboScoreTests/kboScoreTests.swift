//
//  kboScoreTests.swift
//  kboScoreTests
//
//  Created by 조경민 on 3/25/26.
//

import Foundation
import Testing
import UserNotifications
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

    @Test func countDisplayNormalizesTransitionalValues() throws {
        #expect(KBOCountDisplay.balls(4) == 3)
        #expect(KBOCountDisplay.strikes(3) == 2)
        #expect(KBOCountDisplay.outs(3) == 2)
        #expect(KBOCountDisplay.balls(-1) == 0)
        #expect(KBOCountDisplay.strikes(nil) == nil)
    }

    @Test func inningFormatterUsesKoreanBaseballNotation() throws {
        #expect(KBOInningFormatter.korean("Top 1") == "1회 초")
        #expect(KBOInningFormatter.korean("Bottom 10") == "10회 말")
        #expect(KBOInningFormatter.korean("7회초") == "7회 초")
        #expect(KBOInningFormatter.korean(nil) == nil)
    }

    @Test func homeSummaryUsesStartingPitchersFromSupabaseRows() throws {
        let awayTeamID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let homeTeamID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let gameID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "kiwoom", name: "키움 히어로즈", shortName: "키움"),
            SupabaseTeamRow(id: homeTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데")
        ]
        let gameRows = try JSONDecoder().decode(
            [SupabaseGameRow].self,
            from: Data(
                """
                [
                  {
                    "id": "\(gameID.uuidString)",
                    "public_game_id": "20260428-LOT-KIW",
                    "provider": "kbo",
                    "provider_game_id": "20260428WOLT0",
                    "game_date": "2026-04-28",
                    "scheduled_at": "2026-04-28T18:30:00+09:00",
                    "stadium": "사직",
                    "status": "scheduled",
                    "home_team_id": "\(homeTeamID.uuidString)",
                    "away_team_id": "\(awayTeamID.uuidString)",
                    "home_score": null,
                    "away_score": null,
                    "inning_state": null,
                    "is_cancelled": false,
                    "is_postponed": false,
                    "away_starting_pitcher_name": "알칸타라",
                    "home_starting_pitcher_name": "김진욱"
                  }
                ]
                """.utf8
            )
        )
        let games = SupabaseKBOMapper.mapGames(gameRows: gameRows, teamRows: teamRows)
        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: SupabaseKBOMapper.mapTeams(teamRows),
                games: games,
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-04-28T12:00:00+09:00") }
        )

        let summary = try #require(model.filteredHomeGames.first)

        #expect(summary.awayTeam.id == "kiwoom")
        #expect(summary.homeTeam.id == "lotte")
        #expect(summary.awayStartingPitcherName == "알칸타라")
        #expect(summary.homeStartingPitcherName == "김진욱")
    }

    @Test func refreshHomeUpsertsTodaySchedulePitchersIntoLocalGames() async throws {
        let referenceDate = isoDate("2026-04-28T12:00:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let localGame = makeGameDetail(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260428WOLT0"
        )
        let supabaseTodayGame = makeGameDetail(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260428-LOT-KIW provider_game_id=20260428WOLT0 updated_at=2026-04-28T09:00:00+09:00",
            awayStartingPitcherName: "알칸타라",
            homeStartingPitcherName: "김진욱"
        )
        let repository = StubRepository(
            fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [localGame], notifications: [], settings: .default)
            },
            fetchGames: { [localGame] },
            fetchSchedule: { _ in [supabaseTodayGame] }
        )
        let model = AppModel(
            repository: repository,
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        await model.loadIfNeeded()

        let summary = try #require(model.filteredHomeGames.first)
        #expect(summary.awayStartingPitcherName == "알칸타라")
        #expect(summary.homeStartingPitcherName == "김진욱")
        #expect(model.games.count == 1)
    }

    @Test func refreshHomeDoesNotEraseExistingPitchersWhenTodayScheduleHasNilPitchers() async throws {
        let referenceDate = isoDate("2026-04-28T12:00:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let localGame = makeGameDetail(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260428WOLT0 updated_at=2026-04-28T08:00:00+09:00",
            awayStartingPitcherName: "알칸타라",
            homeStartingPitcherName: "김진욱"
        )
        let nilPitcherTodayGame = makeGameDetail(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 1,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260428WOLT0 updated_at=2026-04-28T09:00:00+09:00"
        )
        let repository = StubRepository(
            fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [localGame], notifications: [], settings: .default)
            },
            fetchGames: { [localGame] },
            fetchSchedule: { _ in [nilPitcherTodayGame] }
        )
        let model = AppModel(
            repository: repository,
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        await model.loadIfNeeded()

        let summary = try #require(model.filteredHomeGames.first)
        #expect(summary.status == .live)
        #expect(summary.awayScore == 1)
        #expect(summary.homeScore == 0)
        #expect(summary.awayStartingPitcherName == "알칸타라")
        #expect(summary.homeStartingPitcherName == "김진욱")
    }

    @Test func todayRefreshUpdatesExistingScheduledGameToLiveScoreAndInning() async throws {
        let referenceDate = isoDate("2026-04-28T12:00:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let scheduled = makeGameDetail(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260428WOLT0 updated_at=2026-04-28T09:30:00+09:00"
        )
        let live = makeGameDetail(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 3,
            homeScore: 2,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Top 6",
            note: "provider_game_id=20260428WOLT0 updated_at=2026-04-28T09:00:00+09:00"
        )
        let repository = StubRepository(
            fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [scheduled], notifications: [], settings: .default)
            },
            fetchGames: { [scheduled] },
            fetchSchedule: { _ in [live] }
        )
        let model = AppModel(
            repository: repository,
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        await model.loadIfNeeded()
        let summary = try #require(model.filteredHomeGames.first)

        #expect(model.games.count == 1)
        #expect(summary.status == .live)
        #expect(summary.awayScore == 3)
        #expect(summary.homeScore == 2)
        #expect(summary.inningText == "Top 6")
    }

    @Test func localMonthCacheDoesNotOverwriteTodayLiveStatus() async throws {
        let referenceDate = isoDate("2026-04-28T12:00:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let scheduled = makeGameDetail(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260428WOLT0"
        )
        let live = makeGameDetail(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 1,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Bottom 5",
            note: "provider_game_id=20260428WOLT0 updated_at=2026-04-28T09:00:00+09:00"
        )
        let repository = StubRepository(
            fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [scheduled], notifications: [], settings: .default)
            },
            fetchGames: { [scheduled] },
            fetchSchedule: { _ in [live] }
        )
        let model = AppModel(
            repository: repository,
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        await model.loadIfNeeded()
        await model.loadScheduleIfNeeded(for: referenceDate)
        let game = try #require(model.scheduleGames(on: referenceDate, filter: .all).first)

        #expect(game.status == .live)
        #expect(game.awayScore == 4)
        #expect(game.homeScore == 1)
        #expect(game.inningText == "Bottom 5")
    }

    @Test func todayOnlyScheduleRefreshPreservesOtherMonthGames() async throws {
        let referenceDate = isoDate("2026-04-28T12:00:00+09:00")
        let otherDate = isoDate("2026-04-29T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let todayScheduled = makeGameDetail(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-000000000001")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260428WOLT0"
        )
        let tomorrowScheduled = makeGameDetail(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-000000000002")!,
            scheduledStart: otherDate,
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260429WOLT0"
        )
        let todayLive = makeGameDetail(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-000000000003")!,
            scheduledStart: todayScheduled.scheduledStart,
            venue: todayScheduled.venue,
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 2,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "7회말",
            note: "provider_game_id=20260428WOLT0 updated_at=2026-04-28T19:30:00+09:00"
        )
        let repository = StubRepository(
            fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [todayScheduled], notifications: [], settings: .default)
            },
            fetchMonthlySchedule: { _ in [todayScheduled, tomorrowScheduled] },
            fetchSchedule: { _ in [todayLive] }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [todayScheduled], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        await model.loadScheduleIfNeeded(for: referenceDate)
        await model.refreshScheduleDay(for: referenceDate)

        let todayGame = try #require(model.scheduleGames(on: referenceDate, filter: .all).first)
        let tomorrowGame = try #require(model.scheduleGames(on: otherDate, filter: .all).first)

        #expect(todayGame.status == .live)
        #expect(todayGame.awayScore == 4)
        #expect(tomorrowGame.id == tomorrowScheduled.id)
        #expect(tomorrowGame.status == .upcoming)
    }

    @Test func detailLookupResolvesLatestMatchingGameInsteadOfStaleSelectedID() async throws {
        let referenceDate = isoDate("2026-04-28T12:00:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let stale = makeGameDetail(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )
        let latest = makeGameDetail(
            id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 2,
            homeScore: 5,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Top 5",
            note: "public_game_id=20260428-LOT-KIW"
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: teams, games: [stale, latest], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        let resolved = try #require(model.game(withID: stale.id))

        #expect(resolved.status == .live)
        #expect(resolved.awayScore == 2)
        #expect(resolved.homeScore == 5)
        #expect(resolved.inningText == "Top 5")
    }

    @Test func gameDetailViewModelRefreshesSelectedGameWithoutFetchingAllGames() async throws {
        let referenceDate = isoDate("2026-04-28T12:00:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let selected = makeGameDetail(
            id: UUID(uuidString: "abababab-abab-abab-abab-abababababab")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260428WOLT0"
        )
        let live = makeGameDetail(
            id: UUID(uuidString: "cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd")!,
            scheduledStart: selected.scheduledStart,
            venue: selected.venue,
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 2,
            homeScore: 1,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "6회초",
            note: "provider_game_id=20260428WOLT0 updated_at=2026-04-28T19:30:00+09:00",
            currentPitcherName: "김투수",
            currentBatterName: "홍길동"
        )
        let allGamesFetchCounter = FetchCounter()
        let detailFetchCounter = FetchCounter()
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(
                fetchBootstrapData: {
                    KBOBootstrapData(teams: teams, games: [selected], notifications: [], settings: .default)
                },
                fetchGames: {
                    await allGamesFetchCounter.increment()
                    return [selected]
                }
            ),
            fetchGameDetailSnapshot: { _, _, _ in
                await detailFetchCounter.increment()
                return live
            }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [selected], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = GameDetailViewModel(gameIdentity: selected.canonicalGameIdentityValue, initialGame: selected)

        let refreshed = await viewModel.refreshIfNeeded(appModel: model, bypassAutomaticThrottle: true)

        #expect(await detailFetchCounter.value == 1)
        #expect(await allGamesFetchCounter.value == 0)
        #expect(refreshed?.status == .live)
        #expect(refreshed?.currentBatterName == "홍길동")
        #expect(refreshed?.currentPitcherName == "김투수")
    }

    @Test func supabaseGameRowDecodesWithoutOfficialProviderGameID() throws {
        let awayTeamID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let homeTeamID = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
        let gameID = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!
        let row = try #require(JSONDecoder().decode(
            [SupabaseGameRow].self,
            from: Data(
                """
                [
                  {
                    "id": "\(gameID.uuidString)",
                    "public_game_id": "20260428-LOT-KIW",
                    "provider": "kbo",
                    "provider_game_id": "20260428WOLT0",
                    "game_date": "2026-04-28",
                    "scheduled_at": "2026-04-28T18:30:00+09:00",
                    "stadium": "사직",
                    "status": "live",
                    "home_team_id": "\(homeTeamID.uuidString)",
                    "away_team_id": "\(awayTeamID.uuidString)",
                    "home_score": 5,
                    "away_score": 4,
                    "inning_state": "Bottom 6",
                    "is_cancelled": false,
                    "is_postponed": false
                  }
                ]
                """.utf8
            )
        ).first)

        #expect(row.providerGameID == "20260428WOLT0")
        #expect(row.officialProviderGameID == nil)
        #expect(row.status == "live")
        #expect(row.homeScore == 5)
    }

    @Test func supabaseMapperPreservesScheduledAndOfficialProviderIdentifiers() throws {
        let awayTeamID = UUID(uuidString: "aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa")!
        let homeTeamID = UUID(uuidString: "bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb")!
        let row = try makeSupabaseGameRow(
            id: UUID(uuidString: "cccccccc-3333-3333-3333-cccccccccccc")!,
            publicGameID: "20260508-LOT-KIA",
            providerGameID: "sched-202605080930-799034c4-c5d5aa85",
            officialProviderGameID: "20260508HTLT0",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 4,
            homeScore: 3,
            inningState: "Final"
        )

        let game = SupabaseKBOMapper.mapGames(
            gameRows: [row],
            teamRows: [
                SupabaseTeamRow(id: awayTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데"),
                SupabaseTeamRow(id: homeTeamID, code: "kia", name: "KIA 타이거즈", shortName: "KIA")
            ]
        )[0]

        #expect(game.providerGameID == "sched-202605080930-799034c4-c5d5aa85")
        #expect(game.officialProviderGameID == "20260508HTLT0")
        #expect(game.publicGameID == "20260508-LOT-KIA")
    }

    @Test func supabaseLatestSnapshotMapsCurrentBatterAndPitcherFields() throws {
        let gameID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let row = try JSONDecoder().decode(
            SupabaseLatestGameSnapshotRow.self,
            from: Data(
                """
                {
                  "game_id": "\(gameID.uuidString)",
                  "inning_label": "7회말",
                  "balls": 2,
                  "strikes": 1,
                  "outs": 0,
                  "runner_on_first": true,
                  "runner_on_second": false,
                  "runner_on_third": true,
                  "current_pitcher_name": "김투수",
                  "current_batter_name": "홍길동"
                }
                """.utf8
            )
        )

        #expect(row.gameID == gameID)
        #expect(row.currentPitcherName == "김투수")
        #expect(row.currentBatterName == "홍길동")
    }

    @Test func supabaseLatestSnapshotDecodesBaseRunnerNames() throws {
        let gameID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let row = try JSONDecoder().decode(
            SupabaseLatestGameSnapshotRow.self,
            from: Data(
                """
                {
                  "game_id": "\(gameID.uuidString)",
                  "runner_on_first": true,
                  "runner_on_second": true,
                  "runner_on_third": false,
                  "first_base_runner_name": "1루주자",
                  "second_base_runner_name": "2루주자",
                  "third_base_runner_name": null
                }
                """.utf8
            )
        )

        #expect(row.firstBaseRunnerName == "1루주자")
        #expect(row.secondBaseRunnerName == "2루주자")
        #expect(row.thirdBaseRunnerName == nil)
    }

    @Test func supabaseSnapshotRunnerNameMapsIntoGameDetailWhenBaseIsOccupied() throws {
        let awayTeamID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let homeTeamID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let gameID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let gameRow = try makeSupabaseGameRow(
            id: gameID,
            publicGameID: "20260428-LOT-KIW",
            providerGameID: "20260428WOLT0",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 4,
            homeScore: 5,
            inningState: "Bottom 6"
        )
        let snapshot = try JSONDecoder().decode(
            SupabaseLatestGameSnapshotRow.self,
            from: Data(
                """
                {
                  "game_id": "\(gameID.uuidString)",
                  "runner_on_first": true,
                  "runner_on_second": false,
                  "runner_on_third": false,
                  "first_base_runner_name": "홍길동"
                }
                """.utf8
            )
        )

        let game = SupabaseKBOMapper.mapGames(
            gameRows: [gameRow],
            teamRows: [
                SupabaseTeamRow(id: awayTeamID, code: "kiwoom", name: "키움 히어로즈", shortName: "키움"),
                SupabaseTeamRow(id: homeTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데")
            ],
            snapshotRows: [snapshot]
        )[0]

        #expect(game.bases?.first == true)
        #expect(game.bases?.second == false)
        #expect(game.bases?.third == false)
        #expect(game.baseRunners?.first == "홍길동")
        #expect(game.baseRunners?.second == nil)
        #expect(game.baseRunners?.third == nil)
    }

    @Test func supabaseSnapshotWithOccupiedBaseAndNilRunnerNameKeepsFallbackState() throws {
        let awayTeamID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let homeTeamID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let gameID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let gameRow = try makeSupabaseGameRow(
            id: gameID,
            publicGameID: "20260428-LOT-KIW",
            providerGameID: "20260428WOLT0",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 4,
            homeScore: 5,
            inningState: "Bottom 6"
        )
        let snapshot = try JSONDecoder().decode(
            SupabaseLatestGameSnapshotRow.self,
            from: Data(
                """
                {
                  "game_id": "\(gameID.uuidString)",
                  "runner_on_first": true,
                  "runner_on_second": false,
                  "runner_on_third": false
                }
                """.utf8
            )
        )

        let game = SupabaseKBOMapper.mapGames(
            gameRows: [gameRow],
            teamRows: [
                SupabaseTeamRow(id: awayTeamID, code: "kiwoom", name: "키움 히어로즈", shortName: "키움"),
                SupabaseTeamRow(id: homeTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데")
            ],
            snapshotRows: [snapshot]
        )[0]

        #expect(game.bases?.first == true)
        #expect(game.baseRunners?.first == nil)
        #expect(game.summary(isMyTeamGame: false).baseRunners?.first == nil)
    }

    @Test func baseRunnerDisplayUsesSnapshotNameWhenFirstBaseOccupied() throws {
        var resolver = BaseRunnerDisplayResolver()
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "홍길동", second: nil, third: nil)
        )

        let display = resolver.resolve(gameIdentity: game.stableDetailIdentity, game: game)

        #expect(display.runners.first == "홍길동")
        #expect(display.source == "snapshot")
    }

    @Test func baseRunnerDisplayFallsBackForOccupiedFirstBaseWithNilName() throws {
        var resolver = BaseRunnerDisplayResolver()
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )

        let display = resolver.resolve(gameIdentity: game.stableDetailIdentity, game: game)

        #expect(display.runners.first == "주자")
        #expect(display.runners.second == nil)
        #expect(display.source == "fallback")
    }

    @Test func baseRunnerDisplayCarriesForwardSameBaseName() throws {
        var resolver = BaseRunnerDisplayResolver()
        let firstSnapshot = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "전민재", second: nil, third: nil)
        )
        _ = resolver.resolve(gameIdentity: firstSnapshot.stableDetailIdentity, game: firstSnapshot)
        let nextSnapshot = try makeBaseRunnerDisplayGame(
            id: firstSnapshot.id,
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )

        let display = resolver.resolve(gameIdentity: firstSnapshot.stableDetailIdentity, game: nextSnapshot)

        #expect(display.runners.first == "전민재")
        #expect(display.source == "carryForward")
    }

    @Test func baseRunnerDisplayClearsNameWhenBaseEmpties() throws {
        var resolver = BaseRunnerDisplayResolver()
        let occupied = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "전민재", second: nil, third: nil)
        )
        _ = resolver.resolve(gameIdentity: occupied.stableDetailIdentity, game: occupied)
        let empty = try makeBaseRunnerDisplayGame(
            id: occupied.id,
            bases: .empty,
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )

        let display = resolver.resolve(gameIdentity: occupied.stableDetailIdentity, game: empty)

        #expect(display.runners.first == nil)
        #expect(display.source == "empty")
    }

    @Test func baseRunnerDisplayStateIsKeyedByGameIdentity() throws {
        var resolver = BaseRunnerDisplayResolver()
        let firstGame = try makeBaseRunnerDisplayGame(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            providerGameID: "20260506WOLT0",
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "전민재", second: nil, third: nil)
        )
        let secondGame = try makeBaseRunnerDisplayGame(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            providerGameID: "20260506HTSS0",
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )
        _ = resolver.resolve(gameIdentity: firstGame.stableDetailIdentity, game: firstGame)

        let display = resolver.resolve(gameIdentity: secondGame.stableDetailIdentity, game: secondGame)

        #expect(display.runners.first == "주자")
    }

    @Test func baseRunnerDisplaySnapshotNameOverridesPriorFallback() throws {
        var resolver = BaseRunnerDisplayResolver()
        let unknown = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )
        _ = resolver.resolve(gameIdentity: unknown.stableDetailIdentity, game: unknown)
        let named = try makeBaseRunnerDisplayGame(
            id: unknown.id,
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "전민재", second: nil, third: nil)
        )

        let display = resolver.resolve(gameIdentity: unknown.stableDetailIdentity, game: named)

        #expect(display.runners.first == "전민재")
        #expect(display.source == "snapshot")
    }

    @Test func baseRunnerDisplayResolvesMultipleBasesIndependently() throws {
        var resolver = BaseRunnerDisplayResolver()
        let previous = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: false, second: true, third: false),
            baseRunners: GameBaseRunners(first: nil, second: "2루주자", third: nil)
        )
        _ = resolver.resolve(gameIdentity: previous.stableDetailIdentity, game: previous)
        let current = try makeBaseRunnerDisplayGame(
            id: previous.id,
            bases: RunnerState(first: true, second: true, third: true),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: "3루주자")
        )

        let display = resolver.resolve(gameIdentity: previous.stableDetailIdentity, game: current)

        #expect(display.runners.first == "주자")
        #expect(display.runners.second == "2루주자")
        #expect(display.runners.third == "3루주자")
        #expect(display.source == "snapshot+carryForward+fallback")
    }

    @Test func baseRunnerDisplayDoesNotCopyFirstRunnerNameToUnknownThirdBase() throws {
        var resolver = BaseRunnerDisplayResolver()
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: true),
            baseRunners: GameBaseRunners(first: "송찬의", second: nil, third: nil)
        )

        let display = resolver.resolve(gameIdentity: game.stableDetailIdentity, game: game)

        #expect(display.runners.first == "송찬의")
        #expect(display.runners.second == nil)
        #expect(display.runners.third == "주자")
    }

    @Test func baseRunnerDisplayKeepsEmptyBasesHidden() throws {
        var resolver = BaseRunnerDisplayResolver()
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: false, second: false, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )

        let display = resolver.resolve(gameIdentity: game.stableDetailIdentity, game: game)

        #expect(display.runners.first == nil)
        #expect(display.runners.second == nil)
        #expect(display.runners.third == nil)
        #expect(display.source == "empty")
    }

    @Test func baseRunnerDisplayShowsAllThreeOccupiedBaseNames() throws {
        var resolver = BaseRunnerDisplayResolver()
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: true, third: true),
            baseRunners: GameBaseRunners(first: "1루주자", second: "2루주자", third: "3루주자")
        )

        let display = resolver.resolve(gameIdentity: game.stableDetailIdentity, game: game)

        #expect(display.runners.first == "1루주자")
        #expect(display.runners.second == "2루주자")
        #expect(display.runners.third == "3루주자")
    }

    @MainActor
    @Test func gameDetailRefreshDoesNotEraseExistingRunnerNameWhenBaseStaysOccupied() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-05-06T18:30:00+09:00"))
        let existing = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "전민재", second: nil, third: nil)
        )
        let incoming = try makeBaseRunnerDisplayGame(
            id: existing.id,
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: base.teams, games: [existing], notifications: [], settings: base.settings)
            }),
            fetchGameDetailSnapshot: { _, _, _ in incoming }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: base.teams, games: [existing], notifications: [], settings: base.settings),
            usePersistedSettings: false
        )

        let refreshed = await model.refreshGameDetail(for: existing.canonicalGameIdentityValue, forceRefresh: true)

        #expect(refreshed?.baseRunners?.first == "전민재")
    }

    @Test func gameLookupResolvesProviderStableIdentityAndPublicRawID() throws {
        let teams = MockKBOData.makeBootstrap().teams
        let lotte = try #require(teams.first(where: { $0.id == "lotte" }))
        let kia = try #require(teams.first(where: { $0.id == "kia" }))
        let game = makeGameDetail(
            id: UUID(uuidString: "09090909-0909-0909-0909-090909090909")!,
            scheduledStart: isoDate("2026-05-09T17:00:00+09:00"),
            venue: "광주",
            awayTeam: lotte,
            homeTeam: kia,
            awayScore: 7,
            homeScore: 3,
            status: .final,
            note: "public_game_id=20260509-LOT-KIA provider_game_id=20260509HTLT0",
            providerGameID: "20260509HTLT0"
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        #expect(model.game(withIdentity: "provider:20260509HTLT0")?.publicGameID == "20260509-LOT-KIA")
        #expect(model.game(withIdentity: "20260509-LOT-KIA")?.providerGameID == "20260509HTLT0")
        #expect(model.game(withIdentity: "public:20260509-LOT-KIA")?.providerGameID == "20260509HTLT0")
    }

    @Test func gameLookupResolvesOfficialAndScheduledProviderIdentities() throws {
        let game = try makeIdentityLookupGame(
            id: UUID(uuidString: "08080808-0808-0808-0808-080808080808")!,
            publicGameID: "20260508-LOT-KIA",
            providerGameID: "sched-202605080930-799034c4-c5d5aa85",
            officialProviderGameID: "20260508HTLT0",
            scheduledStart: isoDate("2026-05-08T18:30:00+09:00")
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        #expect(model.game(withIdentity: "provider:20260508HTLT0")?.publicGameID == "20260508-LOT-KIA")
        #expect(model.game(withIdentity: "20260508HTLT0")?.publicGameID == "20260508-LOT-KIA")
        #expect(model.game(withIdentity: "provider:sched-202605080930-799034c4-c5d5aa85")?.publicGameID == "20260508-LOT-KIA")
        #expect(model.game(withIdentity: "sched-202605080930-799034c4-c5d5aa85")?.publicGameID == "20260508-LOT-KIA")
        #expect(model.game(withIdentity: "public:20260508-LOT-KIA")?.publicGameID == "20260508-LOT-KIA")
        #expect(model.game(withIdentity: "20260508-LOT-KIA")?.publicGameID == "20260508-LOT-KIA")
    }

    @Test func gameLookupResolvesRawOfficialProviderIdentity() throws {
        let game = try makeIdentityLookupGame(
            id: UUID(uuidString: "09090909-0909-0909-0909-090909090901")!,
            publicGameID: "20260509-LOT-KIA",
            providerGameID: "sched-202605091700-799034c4-c5d5aa85",
            officialProviderGameID: "20260509HTLT0",
            scheduledStart: isoDate("2026-05-09T17:00:00+09:00")
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        #expect(model.game(withIdentity: "20260509HTLT0")?.publicGameID == "20260509-LOT-KIA")
    }

    @Test func gameLookupKeepsKnownScheduledProviderStableIdentityWorking() throws {
        let game = try makeIdentityLookupGame(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
            publicGameID: "20260513-KIW-HAN",
            providerGameID: "sched-202605130930-c5d5aa85-89747089",
            officialProviderGameID: nil,
            scheduledStart: isoDate("2026-05-13T18:30:00+09:00"),
            awayTeamID: "kiwoom",
            homeTeamID: "hanwha"
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        #expect(model.game(withIdentity: "provider:sched-202605130930-c5d5aa85-89747089")?.publicGameID == "20260513-KIW-HAN")
    }

    @Test func gameLookupDoesNotChooseAmbiguousSamePriorityProviderMatch() throws {
        let first = try makeIdentityLookupGame(
            id: UUID(uuidString: "08080808-0808-0808-0808-080808080801")!,
            publicGameID: "20260508-LOT-KIA",
            providerGameID: "sched-202605080930-aaaaaaaa-bbbbbbbb",
            officialProviderGameID: "20260508HTLT0",
            scheduledStart: isoDate("2026-05-08T18:30:00+09:00")
        )
        let second = try makeIdentityLookupGame(
            id: UUID(uuidString: "08080808-0808-0808-0808-080808080802")!,
            publicGameID: "20260508-KIA-LOT",
            providerGameID: "sched-202605080930-cccccccc-dddddddd",
            officialProviderGameID: "20260508HTLT0",
            scheduledStart: isoDate("2026-05-08T18:30:00+09:00"),
            awayTeamID: "kia",
            homeTeamID: "lotte"
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [first, second], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        #expect(model.game(withIdentity: "provider:20260508HTLT0") == nil)
    }

    @Test func gameDetailBoxscoreUsesPublicIDAfterOfficialProviderResolution() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let game = try makeIdentityLookupGame(
            id: UUID(uuidString: "08080808-0808-0808-0808-080808080803")!,
            publicGameID: "20260508-LOT-KIA",
            providerGameID: "sched-202605080930-799034c4-c5d5aa85",
            officialProviderGameID: "20260508HTLT0",
            scheduledStart: isoDate("2026-05-08T18:30:00+09:00")
        )
        let appModel = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )
        let selected = try #require(appModel.game(withIdentity: "provider:20260508HTLT0"))
        let state = RecordingBoxscoreState(result: .success(GameBoxscoreResponse.empty(gameId: "20260508-LOT-KIA")))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: state),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            }
        )

        await model.load(for: selected)
        await model.waitForBoxscoreLoadForTesting()

        #expect(await state.requestedGameIDs == ["20260508-LOT-KIA"])
    }

    @Test func gameDetailRefreshFallsBackToRepositoryWhenOfficialProviderMissingLocally() async throws {
        let unrelated = try makeIdentityLookupGame(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131301")!,
            publicGameID: "20260513-KIW-HAN",
            providerGameID: "sched-202605130930-c5d5aa85-89747089",
            officialProviderGameID: nil,
            scheduledStart: isoDate("2026-05-13T18:30:00+09:00"),
            awayTeamID: "kiwoom",
            homeTeamID: "hanwha"
        )
        let source = try makeIdentityFallbackSupabaseSource(
            publicGameID: "20260509-LG-HAN",
            providerGameID: "sched-202605091700-lg-hanwha",
            officialProviderGameID: "20260509LGHH0",
            awayCode: "lg",
            homeCode: "hanwha"
        )
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default)
            }),
            source: source.supabaseSource,
            runtimeState: nil
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let refreshed = await model.refreshGameDetail(for: "provider:20260509LGHH0", forceRefresh: true)
        let lookups = await source.tracker.singleLookups

        #expect(refreshed?.publicGameID == "20260509-LG-HAN")
        #expect(model.game(withIdentity: "provider:20260509LGHH0")?.publicGameID == "20260509-LG-HAN")
        #expect(Array(lookups.prefix(2)) == [
            .providerGameID("20260509LGHH0"),
            .officialProviderGameID("20260509LGHH0")
        ])
    }

    @Test func gameDetailViewModelWithoutInitialGameUsesFallbackForRequestedIdentity() async throws {
        let unrelated = try makeIdentityLookupGame(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131306")!,
            publicGameID: "20260513-KIW-HAN",
            providerGameID: "sched-202605130930-c5d5aa85-89747089",
            officialProviderGameID: nil,
            scheduledStart: isoDate("2026-05-13T18:30:00+09:00"),
            awayTeamID: "kiwoom",
            homeTeamID: "hanwha"
        )
        let source = try makeIdentityFallbackSupabaseSource(
            publicGameID: "20260509-LG-HAN",
            providerGameID: "sched-202605091700-lg-hanwha",
            officialProviderGameID: "20260509LGHH0",
            awayCode: "lg",
            homeCode: "hanwha"
        )
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default)
            }),
            source: source.supabaseSource,
            runtimeState: nil
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default),
            usePersistedSettings: false
        )
        let viewModel = GameDetailViewModel(gameIdentity: "provider:20260509LGHH0", initialGame: nil)

        let refreshed = await viewModel.refreshIfNeeded(appModel: model, manual: true)
        let lookups = await source.tracker.singleLookups

        #expect(refreshed?.publicGameID == "20260509-LG-HAN")
        #expect(viewModel.game?.publicGameID == "20260509-LG-HAN")
        #expect(Array(lookups.prefix(2)) == [
            .providerGameID("20260509LGHH0"),
            .officialProviderGameID("20260509LGHH0")
        ])
    }

    @Test func gameDetailFallbackByOfficialProviderUsesPublicGameIDForBoxscore() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let unrelated = try makeIdentityLookupGame(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131302")!,
            publicGameID: "20260513-KIW-HAN",
            providerGameID: "sched-202605130930-c5d5aa85-89747089",
            officialProviderGameID: nil,
            scheduledStart: isoDate("2026-05-13T18:30:00+09:00"),
            awayTeamID: "kiwoom",
            homeTeamID: "hanwha"
        )
        let source = try makeIdentityFallbackSupabaseSource(
            publicGameID: "20260509-LOT-KIA",
            providerGameID: "sched-202605091700-799034c4-c5d5aa85",
            officialProviderGameID: "20260509HTLT0",
            awayCode: "lotte",
            homeCode: "kia"
        )
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default)
            }),
            source: source.supabaseSource,
            runtimeState: nil
        )
        let appModel = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default),
            usePersistedSettings: false
        )
        let selected = try #require(await appModel.refreshGameDetail(for: "provider:20260509HTLT0", forceRefresh: true))
        let boxscoreState = RecordingBoxscoreState(result: .success(GameBoxscoreResponse.empty(gameId: "20260509-LOT-KIA")))
        let screenModel = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: boxscoreState),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            }
        )

        await screenModel.load(for: selected)
        await screenModel.waitForBoxscoreLoadForTesting()

        #expect(selected.publicGameID == "20260509-LOT-KIA")
        #expect(await boxscoreState.requestedGameIDs == ["20260509-LOT-KIA"])
    }

    @Test func gameDetailRefreshKeepsExistingProviderFallbackBehavior() async throws {
        let unrelated = try makeIdentityLookupGame(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131307")!,
            publicGameID: "20260513-KIW-HAN",
            providerGameID: "sched-202605130930-c5d5aa85-89747089",
            officialProviderGameID: nil,
            scheduledStart: isoDate("2026-05-13T18:30:00+09:00"),
            awayTeamID: "kiwoom",
            homeTeamID: "hanwha"
        )
        let source = try makeIdentityFallbackSupabaseSource(
            publicGameID: "20260502-KIW-DOO",
            providerGameID: "20260502OBWO0",
            officialProviderGameID: nil,
            awayCode: "kiwoom",
            homeCode: "doosan"
        )
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default)
            }),
            source: source.supabaseSource,
            runtimeState: nil
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let refreshed = await model.refreshGameDetail(for: "provider:20260502OBWO0", forceRefresh: true)
        let lookups = await source.tracker.singleLookups

        #expect(refreshed?.publicGameID == "20260502-KIW-DOO")
        #expect(lookups.first == .providerGameID("20260502OBWO0"))
    }

    @Test func gameDetailRefreshFallsBackToRepositoryByScheduledProviderID() async throws {
        let unrelated = try makeIdentityLookupGame(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131303")!,
            publicGameID: "20260513-KIW-HAN",
            providerGameID: "sched-202605130930-c5d5aa85-89747089",
            officialProviderGameID: nil,
            scheduledStart: isoDate("2026-05-13T18:30:00+09:00"),
            awayTeamID: "kiwoom",
            homeTeamID: "hanwha"
        )
        let source = try makeIdentityFallbackSupabaseSource(
            publicGameID: "20260508-LOT-KIA",
            providerGameID: "sched-202605080930-799034c4-c5d5aa85",
            officialProviderGameID: "20260508HTLT0",
            awayCode: "lotte",
            homeCode: "kia"
        )
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default)
            }),
            source: source.supabaseSource,
            runtimeState: nil
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let refreshed = await model.refreshGameDetail(for: "provider:sched-202605080930-799034c4-c5d5aa85", forceRefresh: true)
        let lookups = await source.tracker.singleLookups

        #expect(refreshed?.publicGameID == "20260508-LOT-KIA")
        #expect(lookups.first == .providerGameID("sched-202605080930-799034c4-c5d5aa85"))
    }

    @Test func gameDetailRefreshUsesLocalCandidateWithoutIdentityFallback() async throws {
        let source = try makeIdentityFallbackSupabaseSource(
            publicGameID: "20260513-KIW-HAN",
            providerGameID: "sched-202605130930-c5d5aa85-89747089",
            officialProviderGameID: nil,
            awayCode: "kiwoom",
            homeCode: "hanwha"
        )
        let game = try makeIdentityLookupGame(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131304")!,
            publicGameID: "20260513-KIW-HAN",
            providerGameID: "sched-202605130930-c5d5aa85-89747089",
            officialProviderGameID: nil,
            scheduledStart: isoDate("2026-05-13T18:30:00+09:00"),
            awayTeamID: "kiwoom",
            homeTeamID: "hanwha"
        )
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default)
            }),
            source: source.supabaseSource,
            runtimeState: nil
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let refreshed = await model.refreshGameDetail(for: "provider:sched-202605130930-c5d5aa85-89747089", forceRefresh: true)
        let lookups = await source.tracker.singleLookups

        #expect(refreshed?.publicGameID == "20260513-KIW-HAN")
        #expect(lookups == [.providerGameID("sched-202605130930-c5d5aa85-89747089")])
    }

    @Test func gameDetailRefreshKeepsNoSelectedGameWhenIdentityFallbackMisses() async throws {
        let unrelated = try makeIdentityLookupGame(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131305")!,
            publicGameID: "20260513-KIW-HAN",
            providerGameID: "sched-202605130930-c5d5aa85-89747089",
            officialProviderGameID: nil,
            scheduledStart: isoDate("2026-05-13T18:30:00+09:00"),
            awayTeamID: "kiwoom",
            homeTeamID: "hanwha"
        )
        let source = try makeIdentityFallbackSupabaseSource(
            publicGameID: "20260508-LOT-KIA",
            providerGameID: "sched-202605080930-799034c4-c5d5aa85",
            officialProviderGameID: "20260508HTLT0",
            awayCode: "lotte",
            homeCode: "kia"
        )
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default)
            }),
            source: source.supabaseSource,
            runtimeState: nil
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [unrelated], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let refreshed = await model.refreshGameDetail(for: "provider:20260509LGHH0", forceRefresh: true)
        let lookups = await source.tracker.singleLookups

        #expect(refreshed == nil)
        #expect(lookups == [
            .providerGameID("20260509LGHH0"),
            .officialProviderGameID("20260509LGHH0")
        ])
    }

    @Test func gameCenterReviewReportsDisplayableRecordsWhenBattingLinesExist() throws {
        let line = GameCenterBattingLine(
            battingOrder: "1",
            position: "중",
            name: "홍길동",
            atBats: "3",
            runs: "1",
            hits: "2",
            runsBattedIn: "1",
            homeRuns: "0",
            walks: "1",
            strikeouts: "0",
            average: ".300"
        )
        let review = GameCenterReview(
            summaryItems: [],
            awayBatting: GameCenterBattingSection(lines: [line], totals: nil),
            homeBatting: GameCenterBattingSection(lines: [], totals: nil),
            awayPitching: GameCenterPitchingSection(lines: []),
            homePitching: GameCenterPitchingSection(lines: [])
        )

        #expect(review.hasDisplayableRecords)
    }

    @Test func supabaseLatestSnapshotMapsKnownPlayerAliases() throws {
        let gameID = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
        let row = try JSONDecoder().decode(
            SupabaseLatestGameSnapshotRow.self,
            from: Data(
                """
                {
                  "game_id": "\(gameID.uuidString)",
                  "inning_label": "8회초",
                  "pitcher_name": "박투수",
                  "hitter_name": "이타자"
                }
                """.utf8
            )
        )

        #expect(row.currentPitcherName == "박투수")
        #expect(row.currentBatterName == "이타자")
    }

    @Test func supabaseGamesSelectUsesOnlyCurrentGamesSchemaColumns() throws {
        let columns = SupabaseKBORepository.gameSelectColumns
            .split(separator: ",")
            .map(String.init)
        let currentSchemaColumns: Set<String> = [
            "id",
            "public_game_id",
            "provider",
            "provider_game_id",
            "game_date",
            "scheduled_at",
            "stadium",
            "status",
            "home_team_id",
            "away_team_id",
            "home_score",
            "away_score",
            "inning_state",
            "is_cancelled",
            "is_postponed",
            "source_updated_at",
            "created_at",
            "updated_at",
            "cancel_reason",
            "raw_cancel_text",
            "home_starting_pitcher_name",
            "away_starting_pitcher_name",
            "lineup_data",
            "status_reason",
            "final_confirmed_at",
            "live_last_checked_at",
            "official_provider_game_id"
        ]

        #expect(columns.contains("stadium_code") == false)
        #expect(columns.contains("stadium") == true)
        #expect(columns.contains("official_provider_game_id") == true)
        #expect(Set(columns).isSubset(of: currentSchemaColumns))
    }

    @Test func supabaseGameRowMapsStadiumIntoVenueWithoutStadiumCode() throws {
        let awayTeamID = UUID(uuidString: "10101010-1010-1010-1010-101010101010")!
        let homeTeamID = UUID(uuidString: "20202020-2020-2020-2020-202020202020")!
        let gameID = UUID(uuidString: "30303030-3030-3030-3030-303030303030")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "kiwoom", name: "키움 히어로즈", shortName: "키움"),
            SupabaseTeamRow(id: homeTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데")
        ]
        let gameRows = try JSONDecoder().decode(
            [SupabaseGameRow].self,
            from: Data(
                """
                [
                  {
                    "id": "\(gameID.uuidString)",
                    "public_game_id": "20260428-LOT-KIW",
                    "provider": "kbo",
                    "provider_game_id": "20260428WOLT0",
                    "official_provider_game_id": "20260428WOLT0",
                    "game_date": "2026-04-28",
                    "scheduled_at": "2026-04-28T18:30:00+09:00",
                    "stadium": "고척",
                    "status": "live",
                    "home_team_id": "\(homeTeamID.uuidString)",
                    "away_team_id": "\(awayTeamID.uuidString)",
                    "home_score": 6,
                    "away_score": 2,
                    "inning_state": "Top 7",
                    "is_cancelled": false,
                    "is_postponed": false,
                    "away_starting_pitcher_name": "후라도",
                    "home_starting_pitcher_name": "박세웅"
                  }
                ]
                """.utf8
            )
        )

        let game = try #require(SupabaseKBOMapper.mapGames(gameRows: gameRows, teamRows: teamRows).first)

        #expect(game.venue == "고척")
        #expect(game.status == .live)
        #expect(game.awayScore == 2)
        #expect(game.homeScore == 6)
        #expect(game.inningText == "Top 7")
        #expect(game.awayStartingPitcherName == "후라도")
        #expect(game.homeStartingPitcherName == "박세웅")
    }

    @Test func supabaseTodayRefreshSuppressesLocalFallbackWhenBypassingCache() async throws {
        let referenceDate = isoDate("2026-04-28T12:00:00+09:00")
        let tracker = ScheduleSyncTestTracker()
        let bootstrap = MockKBOData.makeBootstrap()
        let repository = SupabaseBackedKBORepository(
            base: ScheduleSyncTestRepository(
                bootstrap: bootstrap,
                remoteCount: bootstrap.games.count,
                missingGames: [],
                todayGames: bootstrap.games,
                tracker: tracker
            ),
            source: FailingSupabaseSource(),
            runtimeState: nil
        )

        var didThrow = false
        do {
            _ = try await repository.fetchSchedule(for: referenceDate, bypassingCache: true)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(await tracker.dailyScheduleFetches == 0)
    }

    @Test func todayFallbackUpcomingRowsDoNotOverwriteLiveTodayRows() async throws {
        let referenceDate = isoDate("2026-04-28T12:00:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let live = makeGameDetail(
            id: UUID(uuidString: "40404040-4040-4040-4040-404040404040")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 8,
            homeScore: 7,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Bottom 8",
            note: "provider_game_id=20260428WOLT0 updated_at=2026-04-28T09:00:00+09:00",
            awayStartingPitcherName: "후라도",
            homeStartingPitcherName: "박세웅"
        )
        let fallbackUpcoming = makeGameDetail(
            id: UUID(uuidString: "50505050-5050-5050-5050-505050505050")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260428WOLT0"
        )
        let repository = StubRepository(
            fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [live], notifications: [], settings: .default)
            },
            fetchGames: { [live] },
            fetchSchedule: { _ in [fallbackUpcoming] }
        )
        let model = AppModel(
            repository: repository,
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        await model.loadIfNeeded()
        let game = try #require(model.filteredHomeGames.first)

        #expect(game.status == .live)
        #expect(game.awayScore == 8)
        #expect(game.homeScore == 7)
        #expect(game.inningText == "Bottom 8")
        #expect(game.awayStartingPitcherName == "후라도")
        #expect(game.homeStartingPitcherName == "박세웅")
    }

    @Test func gameDetailSingleFetchByPublicGameIDReturnsOneRowWithoutDateFetch() async throws {
        let referenceDate = isoDate("2026-04-28T18:30:00+09:00")
        let awayTeamID = UUID(uuidString: "61616161-6161-6161-6161-616161616161")!
        let homeTeamID = UUID(uuidString: "62626262-6262-6262-6262-626262626262")!
        let teams = [
            SupabaseTeamRow(id: awayTeamID, code: "kiwoom", name: "키움 히어로즈", shortName: "키움"),
            SupabaseTeamRow(id: homeTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데")
        ]
        let selected = makeGameDetail(
            id: UUID(uuidString: "63636363-6363-6363-6363-636363636363")!,
            scheduledStart: referenceDate,
            venue: "사직",
            awayTeam: SupabaseKBOMapper.mapTeam(teams[0]),
            homeTeam: SupabaseKBOMapper.mapTeam(teams[1]),
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260428-LOT-KIW"
        )
        let row = try makeSupabaseGameRow(
            id: UUID(uuidString: "64646464-6464-6464-6464-646464646464")!,
            publicGameID: "20260428-LOT-KIW",
            providerGameID: "20260428WOLT0",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 2,
            homeScore: 5,
            inningState: "Top 8"
        )
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(),
            source: TrackingSupabaseSource(teamRows: teams, gameRows: [row], tracker: tracker),
            runtimeState: nil
        )

        let snapshot = try await repository.fetchGameDetailSnapshot(
            for: selected,
            identity: selected.canonicalGameIdentityValue,
            cachedTeams: [selected.awayTeam, selected.homeTeam]
        )

        #expect(snapshot?.status == .live)
        #expect(snapshot?.awayScore == 2)
        #expect(snapshot?.homeScore == 5)
        #expect(snapshot?.inningText == "Top 8")
        #expect(await tracker.singleLookups == [.publicGameID("20260428-LOT-KIW")])
        #expect(await tracker.dateFetches == 0)
        #expect(await tracker.teamFetches == 0)
    }

    @Test func gameDetailSingleFetchByProviderGameIDReturnsOneRow() async throws {
        let referenceDate = isoDate("2026-04-28T18:30:00+09:00")
        let awayTeamID = UUID(uuidString: "71717171-7171-7171-7171-717171717171")!
        let homeTeamID = UUID(uuidString: "72727272-7272-7272-7272-727272727272")!
        let teams = [
            SupabaseTeamRow(id: awayTeamID, code: "kiwoom", name: "키움 히어로즈", shortName: "키움"),
            SupabaseTeamRow(id: homeTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데")
        ]
        let selected = makeGameDetail(
            id: UUID(uuidString: "73737373-7373-7373-7373-737373737373")!,
            scheduledStart: referenceDate,
            venue: "사직",
            awayTeam: SupabaseKBOMapper.mapTeam(teams[0]),
            homeTeam: SupabaseKBOMapper.mapTeam(teams[1]),
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260428-LOT-KIW provider_game_id=20260428WOLT0"
        )
        let row = try makeSupabaseGameRow(
            id: UUID(uuidString: "74747474-7474-7474-7474-747474747474")!,
            publicGameID: "20260428-LOT-KIW",
            providerGameID: "20260428WOLT0",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 3,
            homeScore: 4,
            inningState: "Bottom 7"
        )
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(),
            source: TrackingSupabaseSource(teamRows: teams, gameRows: [row], tracker: tracker),
            runtimeState: nil
        )

        let snapshot = try await repository.fetchGameDetailSnapshot(
            for: selected,
            identity: selected.canonicalGameIdentityValue,
            cachedTeams: [selected.awayTeam, selected.homeTeam]
        )

        #expect(snapshot?.status == .live)
        #expect(snapshot?.awayScore == 3)
        #expect(snapshot?.homeScore == 4)
        #expect(await tracker.singleLookups == [.providerGameID("20260428WOLT0")])
        #expect(await tracker.dateFetches == 0)
        #expect(await tracker.teamFetches == 0)
    }

    @Test func gameDetailSingleFetchFallsBackByDateAndTeams() async throws {
        let referenceDate = isoDate("2026-04-28T18:30:00+09:00")
        let awayTeamID = UUID(uuidString: "81818181-8181-8181-8181-818181818181")!
        let homeTeamID = UUID(uuidString: "82828282-8282-8282-8282-828282828282")!
        let teams = [
            SupabaseTeamRow(id: awayTeamID, code: "kiwoom", name: "키움 히어로즈", shortName: "키움"),
            SupabaseTeamRow(id: homeTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데")
        ]
        let selected = makeGameDetail(
            id: UUID(uuidString: "83838383-8383-8383-8383-838383838383")!,
            scheduledStart: referenceDate,
            venue: "사직",
            awayTeam: SupabaseKBOMapper.mapTeam(teams[0]),
            homeTeam: SupabaseKBOMapper.mapTeam(teams[1]),
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )
        let row = try makeSupabaseGameRow(
            id: UUID(uuidString: "84848484-8484-8484-8484-848484848484")!,
            publicGameID: "20260428-LOT-KIW",
            providerGameID: "20260428WOLT0",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 1,
            homeScore: 6,
            inningState: "Top 5"
        )
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(),
            source: TrackingSupabaseSource(teamRows: teams, gameRows: [row], tracker: tracker),
            runtimeState: nil
        )

        let snapshot = try await repository.fetchGameDetailSnapshot(
            for: selected,
            identity: selected.id.uuidString,
            cachedTeams: [selected.awayTeam, selected.homeTeam]
        )

        #expect(snapshot?.status == .live)
        #expect(snapshot?.awayScore == 1)
        #expect(snapshot?.homeScore == 6)
        #expect(snapshot?.inningText == "Top 5")
        #expect(await tracker.singleLookups == [
            .databaseID(selected.id),
            .dateTeamIDs(gameDate: "2026-04-28", awayTeamID: awayTeamID, homeTeamID: homeTeamID)
        ])
        #expect(await tracker.dateFetches == 0)
        #expect(await tracker.teamFetches == 1)
    }

    @Test func gameDetailRefreshUpdatesOnlySelectedEquivalentGame() async throws {
        let referenceDate = isoDate("2026-04-28T12:00:00+09:00")
        let awayTeamID = UUID(uuidString: "91919191-9191-9191-9191-919191919191")!
        let homeTeamID = UUID(uuidString: "92929292-9292-9292-9292-929292929292")!
        let teams = [
            SupabaseTeamRow(id: awayTeamID, code: "kiwoom", name: "키움 히어로즈", shortName: "키움"),
            SupabaseTeamRow(id: homeTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데")
        ]
        let awayTeam = SupabaseKBOMapper.mapTeam(teams[0])
        let homeTeam = SupabaseKBOMapper.mapTeam(teams[1])
        let selected = makeGameDetail(
            id: UUID(uuidString: "93939393-9393-9393-9393-939393939393")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260428-LOT-KIW provider_game_id=20260428WOLT0"
        )
        let other = makeGameDetail(
            id: UUID(uuidString: "94949494-9494-9494-9494-949494949494")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: homeTeam,
            homeTeam: awayTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260428-KIW-LOT provider_game_id=20260428LTWO0"
        )
        let selectedRow = try makeSupabaseGameRow(
            id: UUID(uuidString: "95959595-9595-9595-9595-959595959595")!,
            publicGameID: "20260428-LOT-KIW",
            providerGameID: "20260428WOLT0",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 2,
            homeScore: 5,
            inningState: "Top 8"
        )
        let otherRow = try makeSupabaseGameRow(
            id: UUID(uuidString: "96969696-9696-9696-9696-969696969696")!,
            publicGameID: "20260428-KIW-LOT",
            providerGameID: "20260428LTWO0",
            stadium: "잠실",
            awayTeamID: homeTeamID,
            homeTeamID: awayTeamID,
            awayScore: 7,
            homeScore: 7,
            inningState: "Bottom 9"
        )
        let tracker = DetailFetchTracker()
        let supabaseRepository = SupabaseBackedKBORepository(
            base: StubRepository(fetchGames: { [selected, other] }),
            source: TrackingSupabaseSource(teamRows: teams, gameRows: [selectedRow, otherRow], tracker: tracker),
            runtimeState: nil
        )
        let repository = AnyKBORepository(
            CachedKBORepository(
                base: AnyKBORepository(supabaseRepository),
                configuration: .supabaseStartup,
                runtimeState: nil
            )
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: [awayTeam, homeTeam], games: [selected, other], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        let refreshed = await model.refreshGameDetail(for: selected.canonicalGameIdentityValue)
        let selectedAfter = try #require(model.game(withIdentity: selected.canonicalGameIdentityValue))
        let otherAfter = try #require(model.game(withIdentity: other.canonicalGameIdentityValue))

        #expect(refreshed?.status == .live)
        #expect(selectedAfter.status == .live)
        #expect(selectedAfter.awayScore == 2)
        #expect(selectedAfter.homeScore == 5)
        #expect(selectedAfter.inningText == "Top 8")
        #expect(otherAfter.status == .upcoming)
        #expect(otherAfter.awayScore == nil)
        #expect(otherAfter.homeScore == nil)
        #expect(await tracker.dateFetches == 0)
        #expect(await tracker.singleLookups == [.providerGameID("20260428WOLT0")])
        #expect(await tracker.teamFetches == 0)
    }

    @Test func repositoryCacheUpsertPreservesExistingPitchersWhenIncomingPitchersAreNil() async throws {
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let existing = makeGameDetail(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260428WOLT0 updated_at=2026-04-28T08:00:00+09:00",
            awayStartingPitcherName: "알칸타라",
            homeStartingPitcherName: "김진욱"
        )
        let incoming = makeGameDetail(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 1,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260428WOLT0 updated_at=2026-04-28T09:00:00+09:00"
        )
        let cacheDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let repository = CachedKBORepository(
            base: StubRepository(fetchGames: { [existing] }),
            configuration: RepositoryCacheConfiguration(
                bootstrapTTL: 60,
                gamesTTL: 60,
                notificationsTTL: 60,
                monthlyScheduleTTL: 60,
                diskCacheDirectory: cacheDirectory
            ),
            runtimeState: nil
        )

        _ = try await repository.fetchGames()
        let result = await repository.upsertLocalGames([incoming])
        let cached = try await repository.fetchGames()
        let game = try #require(cached.first)

        #expect(result.updated == 1)
        #expect(cached.count == 1)
        #expect(game.status == .live)
        #expect(game.awayStartingPitcherName == "알칸타라")
        #expect(game.homeStartingPitcherName == "김진욱")
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

    @Test func scheduleEntryUsesLocalScheduleWhenRemoteCountMatches() async throws {
        let bootstrap = MockKBOData.makeBootstrap(now: isoDate("2026-04-01T09:00:00+09:00"))
        let tracker = ScheduleSyncTestTracker()
        let repository = ScheduleSyncTestRepository(
            bootstrap: bootstrap,
            remoteCount: bootstrap.games.count,
            missingGames: [],
            todayGames: [],
            tracker: tracker
        )
        let model = AppModel(
            repository: repository,
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-04-01T09:00:00+09:00") }
        )
        let sampleMonth = isoDate("2026-03-01T09:00:00+09:00")

        await model.loadScheduleIfNeeded(for: sampleMonth)
        await model.loadScheduleIfNeeded(for: isoDate("2026-05-01T09:00:00+09:00"))

        #expect(await tracker.remoteCountChecks == 1)
        #expect(await tracker.missingFetches == 0)
        #expect(await tracker.monthlyScheduleFetches == 0)
    }

    @Test func scheduleEntrySyncsMissingGamesOnceWhenCountsDiffer() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-01T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let ssg = try #require(base.teams.first(where: { $0.id == "ssg" }))
        let missingGame = makeGameDetail(
            id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
            scheduledStart: isoDate("2026-04-12T14:00:00+09:00"),
            venue: "잠실야구장",
            awayTeam: ssg,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            providerGameID: "20260412SSGLG0"
        )
        let bootstrap = KBOBootstrapData(
            teams: base.teams,
            games: [],
            notifications: [],
            settings: base.settings
        )
        let tracker = ScheduleSyncTestTracker()
        let repository = ScheduleSyncTestRepository(
            bootstrap: bootstrap,
            remoteCount: 1,
            missingGames: [missingGame],
            todayGames: [],
            tracker: tracker
        )
        let model = AppModel(
            repository: repository,
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-04-01T09:00:00+09:00") }
        )
        let sampleMonth = isoDate("2026-04-01T09:00:00+09:00")

        await model.loadScheduleIfNeeded(for: sampleMonth)
        await model.loadScheduleIfNeeded(for: sampleMonth)

        let scheduleGames = model.scheduleGames(on: missingGame.scheduledStart, filter: .all)
        #expect(scheduleGames.contains { $0.providerGameID == "20260412SSGLG0" })
        #expect(await tracker.remoteCountChecks == 1)
        #expect(await tracker.missingFetches == 1)
        #expect(await tracker.monthlyScheduleFetches == 0)
    }

    @Test func scheduleEntryRefreshesTodayWithDateLimitedFetchOnly() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-01T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let ssg = try #require(base.teams.first(where: { $0.id == "ssg" }))
        let todayGame = makeGameDetail(
            id: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!,
            scheduledStart: isoDate("2026-04-01T18:30:00+09:00"),
            venue: "잠실야구장",
            awayTeam: ssg,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            providerGameID: "20260401SSGLG0"
        )
        let bootstrap = KBOBootstrapData(
            teams: base.teams,
            games: [todayGame],
            notifications: [],
            settings: base.settings
        )
        let tracker = ScheduleSyncTestTracker()
        let repository = ScheduleSyncTestRepository(
            bootstrap: bootstrap,
            remoteCount: 1,
            missingGames: [],
            todayGames: [todayGame],
            tracker: tracker
        )
        let model = AppModel(
            repository: repository,
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-04-01T09:00:00+09:00") }
        )

        await model.loadScheduleIfNeeded(for: todayGame.scheduledStart)

        #expect(await tracker.dailyScheduleFetches == 1)
        #expect(await tracker.monthlyScheduleFetches == 0)
        #expect(await tracker.remoteCountChecks == 1)
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

    @Test func lotteWinDayUsesBlueSemanticAppearance() {
        let appearance = ScheduleDayResultAppearance.from(dominantStatus: .final, favoriteTeamResult: .win)
        #expect(appearance == .win)
    }

    @Test func lotteLossDayUsesRedSemanticAppearance() {
        let appearance = ScheduleDayResultAppearance.from(dominantStatus: .final, favoriteTeamResult: .loss)
        #expect(appearance == .loss)
    }

    @Test func drawDayUsesGraySemanticAppearance() {
        let appearance = ScheduleDayResultAppearance.from(dominantStatus: .final, favoriteTeamResult: .tie)
        #expect(appearance == .draw)
    }

    @Test func noFavoriteTeamResultUsesNeutralSemanticAppearance() {
        let appearance = ScheduleDayResultAppearance.from(dominantStatus: .final, favoriteTeamResult: nil)
        #expect(appearance == .neutral)
    }

    @Test func attendanceSummaryCountsOnlyCompletedFavoriteTeamResults() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-05T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let samsung = try #require(base.teams.first(where: { $0.id == "samsung" }))

        let completedWin = makeGameDetail(
            id: UUID(uuidString: "93000000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-04-01T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason
        )
        let completedLoss = makeGameDetail(
            id: UUID(uuidString: "93000000-0000-0000-0000-000000000002")!,
            scheduledStart: isoDate("2026-04-02T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: samsung,
            homeTeam: lg,
            awayScore: 6,
            homeScore: 3,
            status: .final,
            seasonClassification: .regularSeason
        )
        let completedTie = makeGameDetail(
            id: UUID(uuidString: "93000000-0000-0000-0000-000000000003")!,
            scheduledStart: isoDate("2026-04-03T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 4,
            homeScore: 4,
            status: .final,
            seasonClassification: .regularSeason
        )
        let upcoming = makeGameDetail(
            id: UUID(uuidString: "93000000-0000-0000-0000-000000000004")!,
            scheduledStart: isoDate("2026-04-04T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )
        let cancelled = makeGameDetail(
            id: UUID(uuidString: "93000000-0000-0000-0000-000000000005")!,
            scheduledStart: isoDate("2026-04-05T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: samsung,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .cancelled,
            seasonClassification: .regularSeason
        )

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan, samsung],
                games: [completedWin, completedLoss, completedTie, upcoming, cancelled],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )
        model.settings.favoriteTeamID = "lg"

        [completedWin, completedLoss, completedTie, upcoming, cancelled].forEach {
            model.toggleGameAttendance(for: $0)
        }

        let summary = model.myTeamAttendanceSummary
        #expect(summary.completedGames == 3)
        #expect(summary.wins == 1)
        #expect(summary.losses == 1)
        #expect(summary.ties == 1)
        #expect(summary.recordText == "1승 1패 1무")
        #expect(summary.winPercentageText == "0.500")

        model.toggleGameAttendance(for: completedWin)
        #expect(model.isGameAttended(completedWin) == false)
        #expect(model.myTeamAttendanceSummary.completedGames == 2)
    }

    @Test func attendanceSummaryKeepsCompletedBootstrapGameWhenMonthlyDuplicateIsStale() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-05T09:00:00+09:00"))
        let kt = try #require(base.teams.first(where: { $0.id == "kt" }))
        let hanwha = try #require(base.teams.first(where: { $0.id == "hanwha" }))
        let gameID = UUID(uuidString: "6b1ef981-021c-4f41-9e65-31e25f7095ee")!
        let scheduledStart = isoDate("2026-04-01T18:30:00+09:00")
        let bootstrapGame = makeGameDetail(
            id: gameID,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: 14,
            homeScore: 11,
            status: .final,
            seasonClassification: .regularSeason,
            note: "db_export provider_game_id=20260401KTHH0"
        )
        let staleMonthlyGame = makeGameDetail(
            id: gameID,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )
        let model = AppModel(
            repository: StubRepository(fetchMonthlySchedule: { _ in [staleMonthlyGame] }),
            bootstrap: KBOBootstrapData(
                teams: [kt, hanwha],
                games: [bootstrapGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )
        model.settings.favoriteTeamID = "hanwha"

        model.toggleGameAttendance(for: bootstrapGame)
        #expect(model.myTeamAttendanceSummary.completedGames == 1)
        #expect(model.myTeamAttendanceSummary.losses == 1)

        await model.loadScheduleIfNeeded(for: scheduledStart)

        #expect(model.isGameAttended(staleMonthlyGame))
        #expect(model.myTeamAttendanceSummary.completedGames == 1)
        #expect(model.myTeamAttendanceSummary.losses == 1)
    }

    @Test func scheduleCalendarDaysExposeAttendedGameMarker() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-01T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let referenceDate = isoDate("2026-04-01T18:30:00+09:00")
        let attendedGame = makeGameDetail(
            id: UUID(uuidString: "94000000-0000-0000-0000-000000000001")!,
            scheduledStart: referenceDate,
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: [attendedGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        model.toggleGameAttendance(for: attendedGame)

        let calendar = Calendar(identifier: .gregorian)
        let matchingDay = model.scheduleCalendarDays(for: referenceDate, filter: .all).first {
            calendar.isDate($0.date, inSameDayAs: referenceDate)
        }
        let day = try #require(matchingDay)

        #expect(model.isGameAttended(attendedGame))
        #expect(day.hasAttendedGame)
    }

    @Test func scheduleCalendarMarkerUsesEquivalentAttendanceIdentityForMonthlyDuplicate() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-05T09:00:00+09:00"))
        let kt = try #require(base.teams.first(where: { $0.id == "kt" }))
        let hanwha = try #require(base.teams.first(where: { $0.id == "hanwha" }))
        let gameID = UUID(uuidString: "6b1ef981-021c-4f41-9e65-31e25f7095ee")!
        let scheduledStart = isoDate("2026-04-01T18:30:00+09:00")
        let bootstrapGame = makeGameDetail(
            id: gameID,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: 14,
            homeScore: 11,
            status: .final,
            seasonClassification: .regularSeason,
            note: "db_export provider_game_id=20260401KTHH0"
        )
        let monthlyGame = makeGameDetail(
            id: gameID,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: 14,
            homeScore: 11,
            status: .final,
            seasonClassification: .regularSeason
        )
        let model = AppModel(
            repository: StubRepository(fetchMonthlySchedule: { _ in [monthlyGame] }),
            bootstrap: KBOBootstrapData(
                teams: [kt, hanwha],
                games: [bootstrapGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )
        model.settings.favoriteTeamID = "hanwha"

        model.toggleGameAttendance(for: bootstrapGame)
        await model.loadScheduleIfNeeded(for: scheduledStart)

        let calendar = Calendar(identifier: .gregorian)
        let matchingDay = model.scheduleCalendarDays(for: scheduledStart, filter: .all).first {
            calendar.isDate($0.date, inSameDayAs: scheduledStart)
        }
        let day = try #require(matchingDay)

        #expect(model.isGameAttended(monthlyGame))
        #expect(day.hasAttendedGame)

        model.toggleGameAttendance(for: bootstrapGame)
        #expect(model.isGameAttended(monthlyGame) == false)
        let dayAfterUnmark = try #require(model.scheduleCalendarDays(for: scheduledStart, filter: .all).first {
            calendar.isDate($0.date, inSameDayAs: scheduledStart)
        })
        #expect(dayAfterUnmark.hasAttendedGame == false)
    }

    @Test func scheduleDetailLookupUsesProviderIdentityAcrossDifferentRawIDs() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-05T09:00:00+09:00"))
        let kt = try #require(base.teams.first(where: { $0.id == "kt" }))
        let hanwha = try #require(base.teams.first(where: { $0.id == "hanwha" }))
        let providerID = "20260401KTHH0"
        let scheduledStart = isoDate("2026-04-01T18:30:00+09:00")
        let bootstrapGame = makeGameDetail(
            id: UUID(uuidString: "6b1ef981-021c-4f41-9e65-31e25f7095ee")!,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: 14,
            homeScore: 11,
            status: .final,
            seasonClassification: .regularSeason,
            note: "db_export provider_game_id=\(providerID)"
        )
        let monthlyGame = makeGameDetail(
            id: GameIdentifier.uuid(from: "20260401-HAN-KT")!,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            providerGameID: providerID
        )
        let model = AppModel(
            repository: StubRepository(fetchMonthlySchedule: { _ in [monthlyGame] }),
            bootstrap: KBOBootstrapData(
                teams: [kt, hanwha],
                games: [bootstrapGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )
        model.settings.favoriteTeamID = "hanwha"

        model.toggleGameAttendance(for: bootstrapGame)
        await model.loadScheduleIfNeeded(for: scheduledStart)

        let selectedGames = model.scheduleGames(on: scheduledStart, filter: .all)
        let selectedGame = try #require(selectedGames.first)
        let navigationIdentity = model.gameNavigationIdentity(for: selectedGame)
        let detailGame = try #require(model.game(withIdentity: navigationIdentity))

        #expect(selectedGames.count == 1)
        #expect(navigationIdentity == providerID)
        #expect(detailGame.id == bootstrapGame.id)
        #expect(detailGame.status == .final)
        #expect(model.isGameAttended(monthlyGame))
        #expect(model.myTeamAttendanceSummary.completedGames == 1)
    }

    @Test func scheduleRainoutTransitionSchedulesLocalNotificationOnce() async throws {
        let referenceNow = isoDate("2026-04-17T09:00:00+09:00")
        let scheduledStart = isoDate("2026-04-17T18:30:00+09:00")
        let base = MockKBOData.makeBootstrap(now: referenceNow)
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let lotte = try #require(base.teams.first(where: { $0.id == "lotte" }))
        let providerID = "20260417LTLG0"
        let bootstrapGame = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000001")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: lotte,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            providerGameID: providerID
        )
        let cancelledScheduleGame = makeGameDetail(
            id: GameIdentifier.uuid(from: "20260417-LG-LOTTE")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: lotte,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .cancelled,
            seasonClassification: .regularSeason,
            note: "우천 취소",
            providerGameID: providerID
        )
        let collector = NotificationRequestCollector()
        let model = AppModel(
            repository: StubRepository(fetchMonthlySchedule: { _ in [cancelledScheduleGame] }),
            bootstrap: KBOBootstrapData(
                teams: [lg, lotte],
                games: [bootstrapGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false,
            currentDateProvider: { referenceNow },
            cancellationNotificationScheduler: { request in
                await collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshSchedule(for: scheduledStart)
        await model.refreshSchedule(for: scheduledStart)

        #expect(collector.requests.count == 1)
        #expect(collector.requests.first?.content.body == "[LG] 금일 경기는 우천으로 인해 취소되었습니다.")
    }

    @Test func scoringTransitionDoesNotScheduleLocalNotification() async throws {
        let referenceNow = isoDate("2026-04-17T19:10:00+09:00")
        let scheduledStart = isoDate("2026-04-17T18:30:00+09:00")
        let base = MockKBOData.makeBootstrap(now: referenceNow)
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let lotte = try #require(base.teams.first(where: { $0.id == "lotte" }))
        let providerID = "20260417LTLG0"
        let previous = makeGameDetail(
            id: UUID(uuidString: "95100000-0000-0000-0000-000000000001")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: lotte,
            homeTeam: lg,
            awayScore: 0,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "3회말",
            providerGameID: providerID
        )
        let scoring = makeGameDetail(
            id: UUID(uuidString: "95100000-0000-0000-0000-000000000002")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: lotte,
            homeTeam: lg,
            awayScore: 0,
            homeScore: 2,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "3회말",
            providerGameID: providerID,
            highlightText: "적시타",
            currentPitcherName: "김투수",
            currentBatterName: "홍길동"
        )
        let collector = NotificationRequestCollector()
        let model = AppModel(
            repository: StubRepository(fetchMonthlySchedule: { _ in [scoring] }),
            bootstrap: KBOBootstrapData(teams: [lg, lotte], games: [previous], notifications: [], settings: base.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceNow },
            cancellationNotificationScheduler: { request in
                await collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshSchedule(for: scheduledStart)

        #expect(collector.requests.isEmpty)
    }

    @Test func inningOnlyLiveTransitionDoesNotScheduleNotification() async throws {
        let referenceNow = isoDate("2026-04-17T19:10:00+09:00")
        let scheduledStart = isoDate("2026-04-17T18:30:00+09:00")
        let base = MockKBOData.makeBootstrap(now: referenceNow)
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let lotte = try #require(base.teams.first(where: { $0.id == "lotte" }))
        let providerID = "20260417LTLG0"
        let previous = makeGameDetail(
            id: UUID(uuidString: "95200000-0000-0000-0000-000000000001")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: lotte,
            homeTeam: lg,
            awayScore: 0,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "3회말",
            providerGameID: providerID
        )
        let inningChanged = makeGameDetail(
            id: UUID(uuidString: "95200000-0000-0000-0000-000000000002")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: lotte,
            homeTeam: lg,
            awayScore: 0,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "4회초",
            providerGameID: providerID
        )
        let collector = NotificationRequestCollector()
        let model = AppModel(
            repository: StubRepository(fetchMonthlySchedule: { _ in [inningChanged] }),
            bootstrap: KBOBootstrapData(teams: [lg, lotte], games: [previous], notifications: [], settings: base.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceNow },
            cancellationNotificationScheduler: { request in
                await collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshSchedule(for: scheduledStart)

        #expect(collector.requests.isEmpty)
    }

    @Test func onBaseTransitionDoesNotScheduleLocalNotification() async throws {
        let referenceNow = isoDate("2026-04-17T19:10:00+09:00")
        let scheduledStart = isoDate("2026-04-17T18:30:00+09:00")
        let base = MockKBOData.makeBootstrap(now: referenceNow)
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let lotte = try #require(base.teams.first(where: { $0.id == "lotte" }))
        let providerID = "20260417LTLG0"
        let previous = makeGameDetail(
            id: UUID(uuidString: "95300000-0000-0000-0000-000000000001")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: lotte,
            homeTeam: lg,
            awayScore: 0,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "3회말",
            providerGameID: providerID,
            bases: .empty,
            outs: 1
        )
        let onBase = makeGameDetail(
            id: UUID(uuidString: "95300000-0000-0000-0000-000000000002")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: lotte,
            homeTeam: lg,
            awayScore: 0,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "3회말",
            providerGameID: providerID,
            bases: RunnerState(first: true, second: false, third: false),
            outs: 1,
            highlightText: "사구",
            currentPitcherName: "김투수",
            currentBatterName: "홍길동"
        )
        let collector = NotificationRequestCollector()
        let model = AppModel(
            repository: StubRepository(fetchMonthlySchedule: { _ in [onBase] }),
            bootstrap: KBOBootstrapData(teams: [lg, lotte], games: [previous], notifications: [], settings: base.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceNow },
            cancellationNotificationScheduler: { request in
                await collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshSchedule(for: scheduledStart)

        #expect(collector.requests.isEmpty)
    }

    @Test func homeRainoutTransitionSchedulesLocalNotificationOnce() async throws {
        let referenceNow = isoDate("2026-04-17T09:00:00+09:00")
        let scheduledStart = isoDate("2026-04-17T18:30:00+09:00")
        let base = MockKBOData.makeBootstrap(now: referenceNow)
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let providerID = "20260417OBLG0"
        let upcomingGame = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000002")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            providerGameID: providerID
        )
        let rainoutGame = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000002")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .rainDelay,
            seasonClassification: .regularSeason,
            providerGameID: providerID
        )
        let collector = NotificationRequestCollector()
        let model = AppModel(
            repository: StubRepository(fetchGames: { [rainoutGame] }),
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: [upcomingGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false,
            currentDateProvider: { referenceNow },
            cancellationNotificationScheduler: { request in
                await collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshHome()
        await model.refreshHome()

        #expect(collector.requests.count == 1)
        #expect(collector.requests.first?.content.userInfo["kbo_live"] != nil)
    }

    @Test func nonTodayCancelledGameDoesNotScheduleLocalNotification() async throws {
        let referenceNow = isoDate("2026-04-17T09:00:00+09:00")
        let scheduledStart = isoDate("2026-04-16T18:30:00+09:00")
        let base = MockKBOData.makeBootstrap(now: referenceNow)
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let upcomingGame = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000003")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            providerGameID: "20260416OBLG0"
        )
        let cancelledGame = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000003")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .cancelled,
            seasonClassification: .regularSeason,
            note: "우천 취소",
            providerGameID: "20260416OBLG0"
        )
        let collector = NotificationRequestCollector()
        let model = AppModel(
            repository: StubRepository(fetchGames: { [cancelledGame] }),
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: [upcomingGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false,
            currentDateProvider: { referenceNow },
            cancellationNotificationScheduler: { request in
                await collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshHome()

        #expect(collector.requests.isEmpty)
    }

    @Test func finalizedGameDoesNotScheduleCancellationNotification() async throws {
        let referenceNow = isoDate("2026-04-17T09:00:00+09:00")
        let scheduledStart = isoDate("2026-04-17T18:30:00+09:00")
        let base = MockKBOData.makeBootstrap(now: referenceNow)
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let upcomingGame = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000004")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            providerGameID: "20260417OBLG1"
        )
        let finalizedGame = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000004")!,
            scheduledStart: scheduledStart,
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason,
            providerGameID: "20260417OBLG1"
        )
        let collector = NotificationRequestCollector()
        let model = AppModel(
            repository: StubRepository(fetchGames: { [finalizedGame] }),
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: [upcomingGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false,
            currentDateProvider: { referenceNow },
            cancellationNotificationScheduler: { request in
                await collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshHome()

        #expect(collector.requests.isEmpty)
    }

    @Test func nonFavoriteCancelledGameDoesNotScheduleLocalNotification() async throws {
        let referenceNow = isoDate("2026-04-17T09:00:00+09:00")
        let scheduledStart = isoDate("2026-04-17T18:30:00+09:00")
        let base = MockKBOData.makeBootstrap(now: referenceNow)
        let kt = try #require(base.teams.first(where: { $0.id == "kt" }))
        let hanwha = try #require(base.teams.first(where: { $0.id == "hanwha" }))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let providerID = "20260417KTHH0"
        let upcomingGame = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000005")!,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            providerGameID: providerID
        )
        let cancelledGame = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000005")!,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: nil,
            homeScore: nil,
            status: .cancelled,
            seasonClassification: .regularSeason,
            note: "우천 취소",
            providerGameID: providerID
        )
        let collector = NotificationRequestCollector()
        let model = AppModel(
            repository: StubRepository(fetchGames: { [cancelledGame] }),
            bootstrap: KBOBootstrapData(
                teams: [kt, hanwha, lg],
                games: [upcomingGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false,
            currentDateProvider: { referenceNow },
            cancellationNotificationScheduler: { request in
                await collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshHome()

        #expect(collector.requests.isEmpty)
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

    @Test func homeFallbackWeeklyStandingsUseFiveActualPlayedGamesAfterRainout() async throws {
        let base = MockKBOData.makeBootstrap(now: Date())
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let referenceWeekStart = previousKBOWeekStart()

        let olderLoss = makeGameDetail(
            id: UUID(uuidString: "91000000-0000-0000-0000-000000000001")!,
            scheduledStart: dateInKBOWeek(start: previousKBOWeekStart(referenceDate: referenceWeekStart), dayOffset: 6),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 7,
            homeScore: 2,
            status: .final,
            seasonClassification: .regularSeason
        )
        let playedGames = [1, 2, 3, 4, 6].enumerated().map { index, dayOffset in
            makeGameDetail(
                id: UUID(uuidString: String(format: "91000000-0000-0000-0000-%012d", index + 2))!,
                scheduledStart: dateInKBOWeek(start: referenceWeekStart, dayOffset: dayOffset),
                venue: "잠실",
                awayTeam: doosan,
                homeTeam: lg,
                awayScore: 1,
                homeScore: 5,
                status: .final,
                seasonClassification: .regularSeason
            )
        }
        let rainout = makeGameDetail(
            id: UUID(uuidString: "91000000-0000-0000-0000-000000000007")!,
            scheduledStart: dateInKBOWeek(start: referenceWeekStart, dayOffset: 5),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .cancelled,
            seasonClassification: .regularSeason,
            note: "우천 취소"
        )

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: [olderLoss, rainout] + playedGames,
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let lgSnapshot = try #require(model.homeFallbackStandingsSnapshots.first(where: { $0.team.id == "lg" }))

        #expect(lgSnapshot.gamesPlayed == 5)
        #expect(lgSnapshot.wins == 5)
        #expect(lgSnapshot.recentResults.count == 5)
        #expect(lgSnapshot.recentResultsMetricTitle == "최근 5")
        #expect(lgSnapshot.recentResults == Array(repeating: TeamGameResult.win, count: 5))
        #expect(lgSnapshot.recentResultsText == "승 승 승 승 승")
        #expect(lgSnapshot.recentResultsText.contains("패") == false)
    }

    @Test func homeFallbackWeeklyStandingsUseSixActualPlayedGamesWhenAvailable() async throws {
        let base = MockKBOData.makeBootstrap(now: Date())
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let referenceWeekStart = previousKBOWeekStart()

        let olderLoss = makeGameDetail(
            id: UUID(uuidString: "92000000-0000-0000-0000-000000000001")!,
            scheduledStart: dateInKBOWeek(start: previousKBOWeekStart(referenceDate: referenceWeekStart), dayOffset: 6),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 7,
            homeScore: 2,
            status: .final,
            seasonClassification: .regularSeason
        )
        let playedGames = (1...6).map { dayOffset in
            makeGameDetail(
                id: UUID(uuidString: String(format: "92000000-0000-0000-0000-%012d", dayOffset + 1))!,
                scheduledStart: dateInKBOWeek(start: referenceWeekStart, dayOffset: dayOffset),
                venue: "잠실",
                awayTeam: doosan,
                homeTeam: lg,
                awayScore: 1,
                homeScore: 5,
                status: .final,
                seasonClassification: .regularSeason
            )
        }

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: [olderLoss] + playedGames,
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let lgSnapshot = try #require(model.homeFallbackStandingsSnapshots.first(where: { $0.team.id == "lg" }))

        #expect(lgSnapshot.gamesPlayed == 6)
        #expect(lgSnapshot.wins == 6)
        #expect(lgSnapshot.recentResults.count == 6)
        #expect(lgSnapshot.recentResultsMetricTitle == "최근 6")
        #expect(lgSnapshot.recentResults == Array(repeating: TeamGameResult.win, count: 6))
        #expect(lgSnapshot.recentResultsText == "승 승 승 승 승 승")
        #expect(lgSnapshot.recentResultsText.contains("패") == false)
    }

    @Test func homeFallbackUsesRecentCompletedGamesWhenTodayHasNoGames() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-27T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let completedGame = makeGameDetail(
            id: UUID(uuidString: "92500000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-04-26T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 6,
            status: .final,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260426OBLG0"
        )

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: [completedGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-04-27T09:00:00+09:00") }
        )

        #expect(model.todayGames.isEmpty)
        #expect(model.homeFallbackStandingsSnapshots.isEmpty == false)
        #expect(model.homeFallbackStandingsSnapshots.first?.wins == 1)
    }

    @Test func todayGamesUseKSTDateFiltering() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-27T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let earlyKSTGame = makeGameDetail(
            id: UUID(uuidString: "92600000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-04-27T00:30:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )
        let previousKSTGame = makeGameDetail(
            id: UUID(uuidString: "92600000-0000-0000-0000-000000000002")!,
            scheduledStart: isoDate("2026-04-26T23:30:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 1,
            homeScore: 3,
            status: .final,
            seasonClassification: .regularSeason
        )

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: [earlyKSTGame, previousKSTGame],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-04-27T09:00:00+09:00") }
        )

        #expect(model.todayGames.count == 1)
        #expect(model.todayGames.first?.id == earlyKSTGame.id)
    }

    @Test func standingsWinningStreakFireOnlyShowsForActiveThreeGameWinStreak() async throws {
        let base = MockKBOData.makeBootstrap(now: Date())
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))

        let threeWins = makeStandingsSnapshot(team: lg, recentResults: [.win, .win, .win])
        let fourWins = makeStandingsSnapshot(team: lg, recentResults: [.win, .win, .win, .win])
        let twoWins = makeStandingsSnapshot(team: lg, recentResults: [.win, .win, .loss])
        let mixedNonConsecutiveWins = makeStandingsSnapshot(team: lg, recentResults: [.win, .win, .loss, .win])
        let activeThreeAfterLoss = makeStandingsSnapshot(team: lg, recentResults: [.win, .win, .win, .loss])
        let losing = makeStandingsSnapshot(team: lg, recentResults: [.loss, .loss, .win, .win, .win])
        let tieBreaksStreak = makeStandingsSnapshot(team: lg, recentResults: [.win, .win, .tie, .win])

        #expect(threeWins.currentWinningStreakCount == 3)
        #expect(threeWins.showsWinningStreakFire)
        #expect(fourWins.showsWinningStreakFire)
        #expect(twoWins.currentWinningStreakCount == 2)
        #expect(twoWins.showsWinningStreakFire == false)
        #expect(mixedNonConsecutiveWins.showsWinningStreakFire == false)
        #expect(activeThreeAfterLoss.showsWinningStreakFire)
        #expect(losing.currentWinningStreakCount == 0)
        #expect(losing.showsWinningStreakFire == false)
        #expect(tieBreaksStreak.showsWinningStreakFire == false)
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

    @Test func standingsUseVirtualUnscheduledGamesWhenScheduleIsIncomplete() async throws {
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
        #expect(standings.first?.postseasonQualificationProbability != nil)
        #expect(standings.first?.postseasonProbabilityUnavailableReason == nil)
        #expect(standings.first?.virtualUnscheduledRemainingGames == 143)
        #expect(standings.first?.postseasonProbabilityEstimateText == "공식 미편성 143경기 포함 추정치")
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
        #expect(KBODataMapper.mapGameStatus(code: "in_progress", text: nil) == .live)
        #expect(KBODataMapper.mapGameStatus(code: "running", text: nil) == .live)
        #expect(KBODataMapper.mapGameStatus(code: "finished", text: nil) == .final)
        #expect(KBODataMapper.mapGameStatus(code: "completed", text: nil) == .final)
        #expect(KBODataMapper.mapGameStatus(code: nil, text: "우천 중단") == .rainDelay)
        #expect(KBODataMapper.mapGameStatus(code: nil, text: "경기 종료") == .final)
        #expect(KBODataMapper.mapGameStatus(code: "UNKNOWN", text: "준비중") == .upcoming)
        #expect(KBODataMapper.mapGameStatus(code: "UNKNOWN", text: nil, inningText: "1회초") == .live)
        #expect(KBODataMapper.mapGameStatus(code: nil, text: "scheduled", inningText: "Top 1") == .upcoming)
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

    @Test func gameDTOPrefersProviderGameIDForCanonicalIdentity() async throws {
        let data = """
        {
          "id": "20260401-HAN-KT",
          "providerGameID": "20260401KTHH0",
          "scheduledStart": "2026-04-01T18:30:00+09:00",
          "venue": "대전",
          "awayTeamID": "kt",
          "homeTeamID": "hanwha",
          "statusCode": "UPCOMING",
          "statusText": "경기 예정"
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(KBOGameDTO.self, from: data)

        #expect(dto.providerGameID == "20260401KTHH0")
        #expect(dto.id == GameIdentifier.uuid(from: "20260401KTHH0"))
        #expect(dto.id != GameIdentifier.uuid(from: "20260401-HAN-KT"))
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

    @Test func scoreNotificationPayloadExtractorBuildsPayloadFromBackendAPNsData() async throws {
        let payload = ScoreNotificationPayloadExtractor.payload(
            from: [
                "aps": [
                    "alert": [
                        "title": "출루",
                        "body": "롯데: 윤동희 출루 (볼넷)"
                    ]
                ],
                "data": [
                    "gameId": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                    "publicGameId": "20260409LTHT0",
                    "eventType": "ON_BASE",
                    "awayTeamId": "lotte",
                    "homeTeamId": "hanwha",
                    "eventTeamId": "lotte"
                ]
            ]
        )

        #expect(payload?.title == "출루")
        #expect(payload?.body == "롯데: 윤동희 출루 (볼넷)")
        #expect(payload?.eventType == .onBase)
        #expect(payload?.publicGameID == "20260409LTHT0")
        #expect(payload?.teamIDs == ["lotte", "hanwha"])
    }

    @Test func notificationHistoryDecodesOldRecordsSafely() throws {
        let id = UUID(uuidString: "abababab-abab-abab-abab-abababababab")!
        let data = """
        {
          "id": "\(id.uuidString)",
          "type": "scoreChange",
          "title": "득점",
          "body": "LG가 득점했습니다.",
          "sentAt": 1775727060,
          "isRead": false,
          "relatedTeamIDs": ["lg"]
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(NotificationItem.self, from: data)

        #expect(item.id == id)
        #expect(item.title == "득점")
        #expect(item.body == "LG가 득점했습니다.")
        #expect(item.receivedAt == nil)
        #expect(item.publicGameID == nil)
    }

    @MainActor
    @Test func receivedNotificationAppearsInNotificationListModel() async throws {
        let receivedAt = isoDate("2026-04-09T18:31:00+09:00")
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { receivedAt }
        )

        model.handleNotificationUserInfo([
            "aps": [
                "alert": [
                    "title": "이닝 교체",
                    "body": "3회 말로 전환되었습니다."
                ]
            ],
            "data": [
                "gameId": "20260409LTHT0",
                "publicGameId": "20260409LTHT0",
                "eventType": "INNING_CHANGED",
                "awayTeamId": "lotte",
                "homeTeamId": "hanwha"
            ]
        ])

        let item = try #require(model.filteredNotifications.first)
        #expect(item.title == "이닝 교체")
        #expect(item.body == "3회 말로 전환되었습니다.")
        #expect(item.type == .inningChange)
        #expect(item.sentAt == receivedAt)
        #expect(item.receivedAt == receivedAt)
        #expect(item.publicGameID == "20260409LTHT0")
        #expect(item.relatedTeamIDs == ["lotte", "hanwha"])
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
                rainDelay: false,
                onBaseEnabled: true,
                inningChangeEnabled: true,
                favoriteTeamOnlyEnabled: true,
                muteWhenLosingEnabled: true
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
        #expect(payload.platform == "ios")
        #expect(payload.environment == NotificationRegistrationEnvironment.current)
        #expect(payload.installationId.isEmpty == false)
        #expect(payload.favoriteTeamID == "lg")
        #expect(payload.notificationsAuthorized == true)
        #expect(payload.alertTypes == [.gameStart, .leadChange, .gameEnd])
        #expect(payload.quietHours == NotificationRegistrationQuietHours(startHour: 23, endHour: 7))
        #expect(payload.gameStartEnabled == true)
        #expect(payload.scoreChangeEnabled == false)
        #expect(payload.leadChangeEnabled == true)
        #expect(payload.gameEndEnabled == true)
        #expect(payload.onBaseEnabled == true)
        #expect(payload.inningChangeEnabled == true)
        #expect(payload.favoriteTeamOnlyEnabled == true)
        #expect(payload.muteWhenLosingEnabled == true)
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
        #expect(payload.platform == "ios")
        #expect(payload.environment == NotificationRegistrationEnvironment.current)
        #expect(payload.installationId.isEmpty == false)
        #expect(payload.alertTypes.contains(.scoreChange))
    }

    @Test func notificationPreferencesDefaultDetailedValuesMatchBackendDefaults() async throws {
        let preferences = NotificationPreferences()

        #expect(preferences.gameStartEnabled == true)
        #expect(preferences.scoreChangeEnabled == true)
        #expect(preferences.leadChangeEnabled == true)
        #expect(preferences.gameEndEnabled == true)
        #expect(preferences.onBaseEnabled == false)
        #expect(preferences.inningChangeEnabled == false)
        #expect(preferences.favoriteTeamOnlyEnabled == false)
        #expect(preferences.muteWhenLosingEnabled == false)
    }

    @Test func appSettingsPersistenceRoundTripPreservesDetailedNotificationPreferences() async throws {
        let settings = AppSettings(
            favoriteTeamID: "lotte",
            notificationPreferences: NotificationPreferences(
                gameStart: false,
                scoreChange: true,
                leadChange: false,
                gameEnd: true,
                rainDelay: true,
                onBaseEnabled: true,
                inningChangeEnabled: true,
                favoriteTeamOnlyEnabled: true,
                muteWhenLosingEnabled: false
            ),
            quietHours: QuietHours(isEnabled: false, startHour: 23, endHour: 7),
            liveActivitiesEnabled: true,
            appearance: .system,
            teamThemeMode: .favoriteTeam
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.notificationPreferences.gameStartEnabled == false)
        #expect(decoded.notificationPreferences.scoreChangeEnabled == true)
        #expect(decoded.notificationPreferences.leadChangeEnabled == false)
        #expect(decoded.notificationPreferences.gameEndEnabled == true)
        #expect(decoded.notificationPreferences.onBaseEnabled == true)
        #expect(decoded.notificationPreferences.inningChangeEnabled == true)
        #expect(decoded.notificationPreferences.favoriteTeamOnlyEnabled == true)
        #expect(decoded.notificationPreferences.muteWhenLosingEnabled == false)
    }

    @Test func notificationRegistrationKeyChangesWhenDetailedNotificationSettingsChange() async throws {
        let basePayload = NotificationRegistrationPayload(
            platform: "ios",
            environment: "sandbox",
            deviceToken: "abc123",
            installationId: "install-1",
            favoriteTeamID: "lg",
            notificationsAuthorized: true,
            alertTypes: [.gameStart, .scoreChange],
            quietHours: nil,
            scoreChangeEnabled: true
        )
        let updatedPayload = NotificationRegistrationPayload(
            platform: "ios",
            environment: "sandbox",
            deviceToken: "abc123",
            installationId: "install-1",
            favoriteTeamID: "lg",
            notificationsAuthorized: true,
            alertTypes: [.gameStart],
            quietHours: nil,
            scoreChangeEnabled: false
        )

        let baseKey = NotificationRegistrationKey(payload: basePayload, endpointDescription: "https://example.com/devices/register")
        let updatedKey = NotificationRegistrationKey(payload: updatedPayload, endpointDescription: "https://example.com/devices/register")

        #expect(baseKey != updatedKey)
    }

    @Test func notificationRegistrationDeduplicationSkipsDuplicateInFlightKey() async throws {
        let key = NotificationRegistrationKey(
            deviceToken: "abc123",
            environment: "sandbox",
            favoriteTeamID: "lotte",
            notificationsEnabled: true,
            endpointDescription: "https://example.com/devices/register"
        )
        var state = NotificationRegistrationDeduplicationState()

        #expect(state.start(key) == .start(keyChanged: false))
        #expect(state.start(key) == .skipInFlight)
        #expect(state.start(key) == .skipInFlight)
        #expect(state.inFlightRegistrationKeys == Set([key]))
    }

    @Test func notificationRegistrationDeduplicationSkipsAlreadyRegisteredKeyAfterSuccess() async throws {
        let key = NotificationRegistrationKey(
            deviceToken: "abc123",
            environment: "sandbox",
            favoriteTeamID: "lotte",
            notificationsEnabled: true,
            endpointDescription: "https://example.com/devices/register"
        )
        var state = NotificationRegistrationDeduplicationState()

        #expect(state.start(key) == .start(keyChanged: false))
        state.complete(key, status: .synced)

        #expect(state.start(key) == .skipAlreadyRegistered)
        #expect(state.lastSuccessfulRegistrationKey == key)
        #expect(state.inFlightRegistrationKeys.isEmpty)
    }

    @Test func notificationRegistrationDeduplicationStartsWhenRegistrationKeyChanges() async throws {
        let endpoint = "https://example.com/devices/register"
        let originalKey = NotificationRegistrationKey(
            deviceToken: "abc123",
            environment: "sandbox",
            favoriteTeamID: "lotte",
            notificationsEnabled: true,
            endpointDescription: endpoint
        )
        let changedTeamKey = NotificationRegistrationKey(
            deviceToken: "abc123",
            environment: "sandbox",
            favoriteTeamID: "lg",
            notificationsEnabled: true,
            endpointDescription: endpoint
        )
        let changedAuthorizationKey = NotificationRegistrationKey(
            deviceToken: "abc123",
            environment: "sandbox",
            favoriteTeamID: "lotte",
            notificationsEnabled: false,
            endpointDescription: endpoint
        )
        let changedTokenKey = NotificationRegistrationKey(
            deviceToken: "def456",
            environment: "sandbox",
            favoriteTeamID: "lotte",
            notificationsEnabled: true,
            endpointDescription: endpoint
        )
        var state = NotificationRegistrationDeduplicationState()

        #expect(state.start(originalKey) == .start(keyChanged: false))
        state.complete(originalKey, status: .synced)

        #expect(state.start(changedTeamKey) == .start(keyChanged: true))
        state.fail(changedTeamKey)
        #expect(state.start(changedAuthorizationKey) == .start(keyChanged: true))
        state.fail(changedAuthorizationKey)
        #expect(state.start(changedTokenKey) == .start(keyChanged: true))
    }

    @Test func notificationRegistrationDeduplicationDoesNotCacheFailedOrSkippedRequestsAsSuccess() async throws {
        let key = NotificationRegistrationKey(
            deviceToken: "abc123",
            environment: "sandbox",
            favoriteTeamID: "lotte",
            notificationsEnabled: true,
            endpointDescription: "https://example.com/devices/register"
        )
        var state = NotificationRegistrationDeduplicationState()

        #expect(state.start(key) == .start(keyChanged: false))
        state.fail(key)
        #expect(state.lastSuccessfulRegistrationKey == nil)
        #expect(state.start(key) == .start(keyChanged: false))

        state.complete(key, status: .skipped)
        #expect(state.lastSuccessfulRegistrationKey == nil)
        #expect(state.start(key) == .start(keyChanged: false))
    }

    @Test func backendDeviceRegistrationSkipsWhenNotificationsDisabled() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .authorized

        model.settings = notificationRegistrationSettings(
            favoriteTeamID: "lotte",
            preferences: disabledNotificationPreferences()
        )

        #expect(await client.requestCount() == 0)
        #expect(model.notificationRegistrationSyncStatus == .idle)
    }

    @Test func backendDeviceRegistrationSkipsWhenAuthorizationIsNotGranted() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .denied

        model.settings = notificationRegistrationSettings(favoriteTeamID: "lotte")

        #expect(await client.requestCount() == 0)
        #expect(model.notificationRegistrationSyncStatus == .idle)
    }

    @Test func backendDeviceRegistrationSkipsWhenFavoriteTeamIsMissing() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .authorized

        model.settings = notificationRegistrationSettings(favoriteTeamID: nil)

        #expect(await client.requestCount() == 0)
        #expect(model.notificationRegistrationSyncStatus == .idle)
    }

    @Test func backendDeviceRegistrationRunsWhenEligible() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .authorized

        model.settings = notificationRegistrationSettings(favoriteTeamID: "lotte")

        let didRegister = await eventually(timeout: 1.0) {
            await client.requestCount() == 1
        }
        #expect(didRegister)
        #expect(await client.favoriteTeamIDs() == ["lotte"])
        #expect(model.notificationRegistrationSyncStatus == .synced)
    }

    @Test func backendDeviceRegistrationRunsWhenAuthorizationIsProvisional() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .provisional

        model.settings = notificationRegistrationSettings(favoriteTeamID: "hanwha")

        let didRegister = await eventually(timeout: 1.0) {
            await client.requestCount() == 1
        }
        #expect(didRegister)
        #expect(await client.favoriteTeamIDs() == ["hanwha"])
    }

    @Test func remoteNotificationRegistrationClientPostsJSONPayload() async throws {
        let session = makeStubSession()
        let client = RemoteNotificationRegistrationClient(
            endpointURL: URL(string: "https://example.com/devices/register")!,
            session: session
        )
        let payload = NotificationRegistrationPayload(
            platform: "ios",
            environment: "sandbox",
            deviceToken: "abc123",
            installationId: "install-1",
            favoriteTeamID: "lg",
            notificationsAuthorized: true,
            alertTypes: [.gameStart, .scoreChange],
            quietHours: NotificationRegistrationQuietHours(startHour: 23, endHour: 7)
        )

        URLProtocolStub.testResponses = [
            "https://example.com/devices/register": StubResponse(statusCode: 200, data: Data())
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        let status = try await client.syncRegistration(payload)
        let request = try #require(URLProtocolStub.lastRequest)
        let body = try #require(httpBodyData(from: request))
        let decoded = try JSONDecoder().decode(NotificationRegistrationPayload.self, from: body)

        #expect(status == .synced)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(decoded == payload)
        #expect(decoded.installationId == "install-1")
        #expect(decoded.gameStartEnabled == true)
        #expect(decoded.scoreChangeEnabled == true)
        #expect(decoded.leadChangeEnabled == true)
        #expect(decoded.gameEndEnabled == true)
        #expect(decoded.onBaseEnabled == false)
        #expect(decoded.inningChangeEnabled == false)
        #expect(decoded.favoriteTeamOnlyEnabled == false)
        #expect(decoded.muteWhenLosingEnabled == false)
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

    @Test func favoriteTeamOnboardingCatalogContainsAllTenTeamsOffline() throws {
        let teams = FavoriteTeamCatalog.teams
        let expectedIDs = Set(["kia", "samsung", "lg", "doosan", "kt", "ssg", "lotte", "hanwha", "nc", "kiwoom"])

        #expect(teams.count == 10)
        #expect(Set(teams.map(\.id)) == expectedIDs)
        #expect(teams.map(\.id) == FavoriteTeamCatalog.orderedTeamIDs)
    }

    @Test func favoriteTeamOnboardingCatalogUsesUniqueIDs() throws {
        let teams = FavoriteTeamCatalog.teams

        #expect(Set(teams.map(\.id)).count == teams.count)
    }

    @Test func favoriteTeamOnboardingDoesNotDependOnRepositoryTeamsWhenSupabaseUnavailable() async throws {
        let repository = StubRepository(
            fetchBootstrapData: {
                throw TestRepositoryError.supabaseUnavailable
            },
            fetchGames: {
                throw TestRepositoryError.supabaseUnavailable
            }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: [], games: [], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        #expect(model.teams.isEmpty)
        #expect(FavoriteTeamCatalog.teams.count == 10)
        #expect(FavoriteTeamCatalog.teams.contains { $0.id == "lotte" })
        #expect(FavoriteTeamCatalog.teams.contains { $0.id == "hanwha" })
    }

    @Test func firstInstallPickerOpeningDoesNotCallFavoriteTeamRemoteRefresh() async throws {
        let recorder = FavoriteScheduleCallRecorder()
        let repository = FavoriteScheduleCountingRepository(recorder: recorder)
        let model = AppModel(repository: repository, usePersistedSettings: false)
        model.settings.favoriteTeamID = nil

        await model.loadIfNeeded()

        #expect(FavoriteTeamCatalog.teams.count == 10)
        #expect(await recorder.callCount() == 0)
    }

    @Test func appStartupWithNoFavoriteTeamDoesNotCallHomeFavoriteGameRefresh() async throws {
        let recorder = FavoriteScheduleCallRecorder()
        let repository = FavoriteScheduleCountingRepository(recorder: recorder)
        let model = AppModel(repository: repository, usePersistedSettings: false)
        model.settings.favoriteTeamID = nil

        await model.loadIfNeeded()
        await model.refreshTodayOnForeground()

        #expect(await recorder.callCount() == 0)
    }

    @Test func favoriteTeamOnboardingSelectingLottePersistsExistingID() throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)

        model.completeFavoriteTeamOnboarding(with: "lotte")

        #expect(model.settings.favoriteTeamID == "lotte")
    }

    @Test func favoriteTeamOnboardingSelectingHanwhaPersistsExistingID() throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)

        model.completeFavoriteTeamOnboarding(with: "hanwha")

        #expect(model.settings.favoriteTeamID == "hanwha")
    }

    @Test func favoriteTeamDependentFlowsReadSelectedFavoriteTeamID() throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)

        model.completeFavoriteTeamOnboarding(with: "hanwha")

        #expect(model.settings.favoriteTeamID == "hanwha")
        #expect(model.currentTheme.id == .hanwha)
        #expect(model.favoriteTeam?.id == "hanwha")
    }

    @Test func favoriteTeamSelectionStartsPostOnboardingFavoriteRefresh() async throws {
        let recorder = FavoriteScheduleCallRecorder()
        let repository = FavoriteScheduleCountingRepository(recorder: recorder)
        let model = AppModel(repository: repository, usePersistedSettings: false)
        model.settings.favoriteTeamID = nil
        model.hasCompletedOnboarding = false

        await model.loadIfNeeded()
        #expect(await recorder.callCount() == 0)

        model.completeFavoriteTeamOnboarding(with: "lotte")

        let didRefresh = await eventually(timeout: 1.0) {
            await recorder.callCount() == 1
        }
        #expect(didRefresh)
        #expect(await recorder.favoriteTeamIDs() == ["lotte"])
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

    @Test func liveActivityContentStateIncludesCurrentBatterAndPitcher() async throws {
        #if canImport(ActivityKit)
        let bootstrap = MockKBOData.makeBootstrap()
        let baseGame = try #require(bootstrap.games.first(where: { $0.homeTeam.id == "lg" && $0.status == .live }))
        let game = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: baseGame.status,
            seasonClassification: baseGame.seasonClassification,
            inningText: baseGame.inningText,
            currentPitcherName: "김투수",
            currentBatterName: "홍길동"
        )

        let contentState = try #require(FavoriteTeamLiveActivitySnapshot.make(from: game, favoriteTeamID: "lg")).contentState()

        #expect(contentState.currentBatterName == "홍길동")
        #expect(contentState.currentPitcherName == "김투수")
        #else
        Issue.record("ActivityKit unavailable in this test environment")
        #endif
    }

    @Test func liveActivitySnapshotKeepsZeroZeroLiveScoreVisible() async throws {
        let bootstrap = MockKBOData.makeBootstrap()
        let baseGame = try #require(bootstrap.games.first(where: { $0.homeTeam.id == "lg" }))
        let game = makeGameDetail(
            id: baseGame.id,
            scheduledStart: Date().addingTimeInterval(3600),
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: 0,
            homeScore: 0,
            status: .live,
            seasonClassification: baseGame.seasonClassification,
            inningText: "Top 1"
        )

        let snapshot = try #require(FavoriteTeamLiveActivitySnapshot.make(from: game, favoriteTeamID: "lg"))

        #expect(snapshot.favoriteScoreText == "0")
        #expect(snapshot.opponentScoreText == "0")
        #expect(snapshot.inningText == "1회 초")
    }

    @Test func liveActivitySnapshotUsesLatestSnapshotCountAndPlayers() async throws {
        let bootstrap = MockKBOData.makeBootstrap()
        let baseGame = try #require(bootstrap.games.first(where: { $0.homeTeam.id == "lg" }))
        let game = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: 0,
            homeScore: 0,
            status: .live,
            seasonClassification: baseGame.seasonClassification,
            inningText: "Bottom 2",
            bases: RunnerState(first: true, second: false, third: true),
            balls: 3,
            strikes: 2,
            outs: 1,
            currentPitcherName: "최신투수",
            currentBatterName: "최신타자"
        )

        let snapshot = try #require(FavoriteTeamLiveActivitySnapshot.make(from: game, favoriteTeamID: "lg"))

        #expect(snapshot.balls == 3)
        #expect(snapshot.strikes == 2)
        #expect(snapshot.outs == 1)
        #expect(snapshot.runnerOnFirst == true)
        #expect(snapshot.runnerOnSecond == false)
        #expect(snapshot.runnerOnThird == true)
        #expect(snapshot.currentPitcherName == "최신투수")
        #expect(snapshot.currentBatterName == "최신타자")
    }

    @Test func liveActivityPregameStateShowsStartingPitchersOnly() async throws {
        #if canImport(ActivityKit)
        let bootstrap = MockKBOData.makeBootstrap()
        let baseGame = try #require(bootstrap.games.first(where: { $0.homeTeam.id == "lg" }))
        let game = makeGameDetail(
            id: baseGame.id,
            scheduledStart: Date().addingTimeInterval(3600),
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: 0,
            homeScore: 0,
            status: .upcoming,
            seasonClassification: baseGame.seasonClassification,
            inningText: "Top 1",
            awayStartingPitcherName: "원정선발",
            homeStartingPitcherName: "홈선발",
            currentPitcherName: "현재투수",
            currentBatterName: "현재타자"
        )

        let contentState = try #require(FavoriteTeamLiveActivitySnapshot.make(from: game, favoriteTeamID: "lg")).contentState()

        #expect(contentState.isPreGame)
        #expect(contentState.favoriteScoreText == "-")
        #expect(contentState.opponentScoreText == "-")
        #expect(contentState.inningText.isEmpty)
        #expect(contentState.favoriteStartingPitcherName == "홈선발")
        #expect(contentState.opponentStartingPitcherName == "원정선발")
        #expect(contentState.currentBatterName == nil)
        #expect(contentState.currentPitcherName == nil)
        #expect(contentState.balls == nil)
        #else
        Issue.record("ActivityKit unavailable in this test environment")
        #endif
    }

    @Test func liveActivityPregameSnapshotShowsProbableStartersWithoutLiveState() async throws {
        let bootstrap = MockKBOData.makeBootstrap()
        let baseGame = try #require(bootstrap.games.first(where: { $0.homeTeam.id == "lg" }))
        let game = makeGameDetail(
            id: baseGame.id,
            scheduledStart: Date().addingTimeInterval(3600),
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: baseGame.seasonClassification,
            inningText: nil,
            awayStartingPitcherName: "원정선발",
            homeStartingPitcherName: "홈선발"
        )

        let snapshot = try #require(FavoriteTeamLiveActivitySnapshot.make(from: game, favoriteTeamID: "lg"))

        #expect(snapshot.isPreGame)
        #expect(snapshot.favoriteStartingPitcherName == "홈선발")
        #expect(snapshot.opponentStartingPitcherName == "원정선발")
        #expect(snapshot.balls == nil)
        #expect(snapshot.currentBatterName == nil)
    }

    @Test func liveActivityUpdateDeduperSkipsIdenticalPayloadsOnly() async throws {
        let gameID = UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!
        var deduper = FavoriteTeamLiveActivityUpdateDeduper()
        let firstFingerprint = "4|3|7회말|B2|S1|O0|홍길동|김투수"
        let changedFingerprint = "4|3|7회말|B2|S1|O0|박타자|김투수"

        #expect(deduper.isDuplicate(gameID: gameID, contentFingerprint: firstFingerprint) == false)
        deduper.record(gameID: gameID, contentFingerprint: firstFingerprint)
        #expect(deduper.isDuplicate(gameID: gameID, contentFingerprint: firstFingerprint))
        #expect(deduper.isDuplicate(gameID: gameID, contentFingerprint: changedFingerprint) == false)
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

    @Test func liveActivityUpdateUsesMergedDetailAfterRefresh() async throws {
        let controller = TestLiveActivityController(isSupported: true)
        let referenceDate = isoDate("2026-04-28T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let selected = makeGameDetail(
            id: UUID(uuidString: "abababab-abab-abab-abab-abababababab")!,
            scheduledStart: referenceDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "provider_game_id=20260428WOLG0",
            awayStartingPitcherName: "원정선발",
            homeStartingPitcherName: "홈선발"
        )
        let latest = makeGameDetail(
            id: UUID(uuidString: "bcbcbcbc-bcbc-bcbc-bcbc-bcbcbcbcbcbc")!,
            scheduledStart: referenceDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 0,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Top 1",
            note: "provider_game_id=20260428WOLG0 updated_at=2026-04-28T18:35:00+09:00",
            bases: RunnerState(first: true, second: false, third: false),
            balls: 2,
            strikes: 1,
            outs: 0,
            currentPitcherName: "최신투수",
            currentBatterName: "최신타자"
        )
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [selected], notifications: [], settings: .default)
            }),
            fetchGameDetailSnapshot: { _, _, _ in latest }
        )
        let model = AppModel(
            repository: repository,
            liveActivityController: controller,
            bootstrap: KBOBootstrapData(teams: teams, games: [selected], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        model.settings.favoriteTeamID = "lg"

        let refreshed = try #require(await model.refreshGameDetail(for: selected.canonicalGameIdentityValue, forceRefresh: true))
        await model.startOrUpdateLiveActivityIfNeeded(for: refreshed)

        let snapshot = try #require(controller.snapshots.last)
        #expect(snapshot.favoriteScoreText == "0")
        #expect(snapshot.opponentScoreText == "0")
        #expect(snapshot.inningText == "1회 초")
        #expect(snapshot.balls == 2)
        #expect(snapshot.strikes == 1)
        #expect(snapshot.outs == 0)
        #expect(snapshot.currentPitcherName == "최신투수")
        #expect(snapshot.currentBatterName == "최신타자")
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
            "https://example.com/api/v1/games": StubResponse(statusCode: 200, data: bootstrapData),
            "https://example.com/api/v1/bootstrap": StubResponse(statusCode: 200, data: bootstrapData),
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
            "https://example.com/api/v1/games": StubResponse(statusCode: 200, data: officialGameList)
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
            "https://example.com/api/v1/schedule/month?year=2026&month=3": StubResponse(statusCode: 200, data: officialSchedule)
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

    @Test func liveRepositoryMapsBackendFinishedMonthlyScheduleGame() async throws {
        let month = KBOMonthScheduleKey(year: 2026, month: 4)
        let payload = """
        {
          "year": 2026,
          "month": 4,
          "totalCount": 1,
          "games": [
            {
              "gameId": "6b1ef981-021c-4f41-9e65-31e25f7095ee",
              "scheduledAt": "2026-04-01T18:30:00+09:00",
              "status": "finished",
              "seasonClassification": "unknown",
              "stadium": "대전",
              "homeTeam": {"teamId": "HANWHA", "nameKo": "한화 이글스", "shortName": "한화"},
              "awayTeam": {"teamId": "KT", "nameKo": "KT 위즈", "shortName": "KT"},
              "homeScore": 11,
              "awayScore": 14,
              "inningState": null
            }
          ]
        }
        """.data(using: .utf8)!
        let session = makeStubSession()
        let repository = LiveKBORepository(baseURL: URL(string: "https://example.com/api/")!, session: session)
        URLProtocolStub.testResponses = [
            "https://example.com/api/v1/schedule/month?year=2026&month=4": StubResponse(statusCode: 200, data: payload)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let games = try await repository.fetchMonthlySchedule(for: month)
        let game = try #require(games.first)

        #expect(game.id == UUID(uuidString: "6b1ef981-021c-4f41-9e65-31e25f7095ee"))
        #expect(game.awayTeam.id == "kt")
        #expect(game.homeTeam.id == "hanwha")
        #expect(game.status == .final)
        #expect(game.awayScore == 14)
        #expect(game.homeScore == 11)
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
            "https://example.com/api/v1/bootstrap": StubResponse(
                statusCode: 404,
                data: """
                {"detail":"Not Found"}
                """.data(using: .utf8)!
            ),
            "https://example.com/api/v1/schedule/month?year=\(month.year)&month=\(month.month)": StubResponse(
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

    @Test func officialGameCenterClientMapsLiveBaseRunnerNamesFromBattingOrderTable() async throws {
        let emptyGridTable = #"{"headers":[],"rows":[],"tfoot":[]}"#
        let awayOrderTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "4번" }, { "Text": "1루수" }, { "Text": "김민수" }] },
            { "row": [{ "Text": "9번" }, { "Text": "중견수" }, { "Text": "박철우" }] }
          ],
          "tfoot": []
        }
        """#
        let homeOrderTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "1" }, { "Text": "유격수" }, { "Text": "이정훈" }] }
          ],
          "tfoot": []
        }
        """#
        let officialGameList = """
        {
          "game": [
            {
              "LE_ID": 1,
              "SR_ID": 0,
              "SEASON_ID": 2026,
              "G_DT": "20260328",
              "G_DT_TXT": "2026.03.28(토)",
              "G_ID": "20260328KTLG0",
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
        let scoreboardPayload = """
        {
          "S_NM": "잠실",
          "START_TM": "14:00",
          "table2": \(try jsonStringLiteral(emptyGridTable)),
          "table3": \(try jsonStringLiteral(emptyGridTable))
        }
        """.data(using: .utf8)!
        let boxScorePayload = """
        {
          "arrHitter": [
            { "table1": \(try jsonStringLiteral(awayOrderTable)) },
            { "table1": \(try jsonStringLiteral(homeOrderTable)) }
          ]
        }
        """.data(using: .utf8)!
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: scoreboardPayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetBoxScoreScroll": StubResponse(statusCode: 200, data: boxScorePayload)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: Team(id: "kt", name: "KT 위즈", shortName: "KT", englishName: "KT Wiz", markText: "KT"),
            homeTeam: Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG"),
            awayScore: 3,
            homeScore: 2,
            status: .live,
            seasonClassification: .regularSeason,
            providerGameID: "20260328KTLG0"
        )

        let detail = try await client.fetchDetail(for: game)

        #expect(detail?.summary.bases?.first == true)
        #expect(detail?.summary.bases?.second == false)
        #expect(detail?.summary.bases?.third == true)
        #expect(detail?.summary.baseRunners?.first == "박철우")
        #expect(detail?.summary.baseRunners?.second == nil)
        #expect(detail?.summary.baseRunners?.third == "김민수")
    }

    @Test func officialGameCenterClientFallsBackToLineupAnalysisForLiveBaseRunnerNames() async throws {
        let emptyGridTable = #"{"headers":[],"rows":[],"tfoot":[]}"#
        let awayOrderTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "1" }, { "Text": "유격수" }, { "Text": "원정선수" }] }
          ],
          "tfoot": []
        }
        """#
        let homeOrderTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "1번" }, { "Text": "우익수" }, { "Text": "홍창기" }] },
            { "row": [{ "Text": "3번" }, { "Text": "지명타자" }, { "Text": "오스틴" }] }
          ],
          "tfoot": []
        }
        """#
        let officialGameList = """
        {
          "game": [
            {
              "LE_ID": 1,
              "SR_ID": 0,
              "SEASON_ID": 2026,
              "G_DT": "20260328",
              "G_DT_TXT": "2026.03.28(토)",
              "G_ID": "20260328KTLG0",
              "G_TM": "14:00",
              "S_NM": "잠실",
              "AWAY_ID": "KT",
              "HOME_ID": "LG",
              "AWAY_NM": "KT",
              "HOME_NM": "LG",
              "GAME_STATE_SC": "2",
              "CANCEL_SC_NM": "정상경기",
              "GAME_INN_NO": 7,
              "GAME_TB_SC_NM": "말",
              "T_SCORE_CN": "3",
              "B_SCORE_CN": "2",
              "OUT_CN": 1,
              "B1BATORDERNO": 3,
              "B2BATORDERNO": 0,
              "BASE3_BAT_ORDER_NO": 1
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let scoreboardPayload = """
        {
          "S_NM": "잠실",
          "START_TM": "14:00",
          "table2": \(try jsonStringLiteral(emptyGridTable)),
          "table3": \(try jsonStringLiteral(emptyGridTable))
        }
        """.data(using: .utf8)!
        let boxScorePayload = #"{"code":"100","msg":"성공"}"#.data(using: .utf8)!
        let lineupPayload = """
        [
          [{ "LINEUP_CK": true }],
          [{ "T_ID": "LG" }],
          [{ "T_ID": "KT" }],
          [\(try jsonStringLiteral(homeOrderTable))],
          [\(try jsonStringLiteral(awayOrderTable))]
        ]
        """.data(using: .utf8)!
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: scoreboardPayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetBoxScoreScroll": StubResponse(statusCode: 200, data: boxScorePayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetLineUpAnalysis": StubResponse(statusCode: 200, data: lineupPayload)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: Team(id: "kt", name: "KT 위즈", shortName: "KT", englishName: "KT Wiz", markText: "KT"),
            homeTeam: Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG"),
            awayScore: 3,
            homeScore: 2,
            status: .live,
            seasonClassification: .regularSeason,
            providerGameID: "20260328KTLG0"
        )

        let detail = try await client.fetchDetail(for: game)

        #expect(detail?.summary.bases?.first == true)
        #expect(detail?.summary.bases?.second == false)
        #expect(detail?.summary.bases?.third == true)
        #expect(detail?.summary.baseRunners?.first == "오스틴")
        #expect(detail?.summary.baseRunners?.second == nil)
        #expect(detail?.summary.baseRunners?.third == "홍창기")
    }

    @Test func officialGameCenterClientMapsLiveBoxScoreRecordSections() async throws {
        let emptyGridTable = #"{"headers":[],"rows":[],"tfoot":[]}"#
        let awayOrderTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "1" }, { "Text": "중견수" }, { "Text": "장두성" }] },
            { "row": [{ "Text": "2" }, { "Text": "좌익수" }, { "Text": "레이예스" }] },
            { "row": [{ "Text": "3" }, { "Text": "1루수" }, { "Text": "정훈" }] }
          ],
          "tfoot": []
        }
        """#
        let homeOrderTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "1" }, { "Text": "유격수" }, { "Text": "김혜성" }] }
          ],
          "tfoot": []
        }
        """#
        let awayBattingDetailTable = #"""
        {
          "headers": [
            { "row": [
              { "Text": "타수" }, { "Text": "득점" }, { "Text": "안타" },
              { "Text": "타점" }, { "Text": "홈런" }, { "Text": "볼넷" }, { "Text": "삼진" }
            ] }
          ],
          "rows": [
            { "row": [{ "Text": "3" }, { "Text": "0" }, { "Text": "2" }, { "Text": "0" }, { "Text": "0" }, { "Text": "0" }, { "Text": "1" }] },
            { "row": [{ "Text": "3" }, { "Text": "1" }, { "Text": "1" }, { "Text": "1" }, { "Text": "1" }, { "Text": "1" }, { "Text": "0" }] },
            { "row": [{ "Text": "1" }, { "Text": "0" }, { "Text": "0" }, { "Text": "0" }] }
          ],
          "tfoot": [
            { "row": [{ "Text": "7" }, { "Text": "1" }, { "Text": "3" }, { "Text": "1" }, { "Text": "1" }, { "Text": "1" }, { "Text": "1" }] }
          ]
        }
        """#
        let awayBattingSummaryTable = #"""
        {
          "headers": [
            { "row": [{ "Text": "타수" }, { "Text": "안타" }, { "Text": "타점" }, { "Text": "득점" }, { "Text": "타율" }] }
          ],
          "rows": [
            { "row": [{ "Text": "3" }, { "Text": "2" }, { "Text": "0" }, { "Text": "0" }, { "Text": "0.667" }] },
            { "row": [{ "Text": "3" }, { "Text": "1" }, { "Text": "1" }, { "Text": "1" }, { "Text": "0.333" }] },
            { "row": [{ "Text": "1" }, { "Text": "0" }, { "Text": "0" }, { "Text": "0" }, { "Text": "0.000" }] }
          ],
          "tfoot": [
            { "row": [{ "Text": "7" }, { "Text": "3" }, { "Text": "1" }, { "Text": "1" }, { "Text": "0.429" }] }
          ]
        }
        """#
        let homeBattingDetailTable = #"""
        {
          "headers": [
            { "row": [
              { "Text": "AB" }, { "Text": "R" }, { "Text": "H" },
              { "Text": "RBI" }, { "Text": "HRA" }, { "Text": "BB" }, { "Text": "K" }
            ] }
          ],
          "rows": [
            { "row": [{ "Text": "4" }, { "Text": "2" }, { "Text": "2" }, { "Text": "2" }, { "Text": "0" }, { "Text": "0" }, { "Text": "1" }] }
          ],
          "tfoot": [
            { "row": [{ "Text": "4" }, { "Text": "2" }, { "Text": "2" }, { "Text": "2" }, { "Text": "0" }, { "Text": "0" }, { "Text": "1" }] }
          ]
        }
        """#
        let awayPitchingTable = #"""
        {
          "headers": [
            { "row": [
              { "Text": "투수명" }, { "Text": "등판" }, { "Text": "결과" }, { "Text": "승" }, { "Text": "패" }, { "Text": "세" },
              { "Text": "이닝" }, { "Text": "타자" }, { "Text": "투구수" }, { "Text": "피홈런" },
              { "Text": "피안타" }, { "Text": "볼넷" }, { "Text": "사구" }, { "Text": "삼진" },
              { "Text": "실점" }, { "Text": "자책" }, { "Text": "평균자책점" }
            ] }
          ],
          "rows": [
            { "row": [
              { "Text": "로드리게스" }, { "Text": "선발" }, { "Text": "" }, { "Text": "" }, { "Text": "" }, { "Text": "" },
              { "Text": "6 1/3" }, { "Text": "25" }, { "Text": "91" }, { "Text": "1" },
              { "Text": "4" }, { "Text": "2" }, { "Text": "0" }, { "Text": "6" },
              { "Text": "3" }, { "Text": "3" }, { "Text": "3.21" }
            ] }
          ],
          "tfoot": []
        }
        """#
        let homePitchingTable = #"""
        {
          "headers": [
            { "row": [
              { "Text": "투수명" }, { "Text": "등판" }, { "Text": "결과" }, { "Text": "승" }, { "Text": "패" }, { "Text": "세" },
              { "Text": "이닝" }, { "Text": "타자" }, { "Text": "투구수" }, { "Text": "피홈런" },
              { "Text": "피안타" }, { "Text": "볼넷" }, { "Text": "사구" }, { "Text": "삼진" },
              { "Text": "실점" }, { "Text": "자책" }, { "Text": "평균자책점" }
            ] }
          ],
          "rows": [
            { "row": [
              { "Text": "김선발" }, { "Text": "선발" }, { "Text": "승" }, { "Text": "" }, { "Text": "" }, { "Text": "" },
              { "Text": "7" }, { "Text": "27" }, { "Text": "95" }, { "Text": "0" },
              { "Text": "5" }, { "Text": "1" }, { "Text": "1" }, { "Text": "5" },
              { "Text": "1" }, { "Text": "1" }, { "Text": "2.10" }
            ] }
          ],
          "tfoot": []
        }
        """#
        let officialGameList = """
        {
          "game": [
            {
              "LE_ID": 1,
              "SR_ID": 0,
              "SEASON_ID": 2026,
              "G_DT": "20260328",
              "G_DT_TXT": "2026.03.28(토)",
              "G_ID": "20260328KTLG0",
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
              "B_SCORE_CN": "2"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let scoreboardPayload = """
        {
          "S_NM": "잠실",
          "START_TM": "14:00",
          "table2": \(try jsonStringLiteral(emptyGridTable)),
          "table3": \(try jsonStringLiteral(emptyGridTable))
        }
        """.data(using: .utf8)!
        let boxScorePayload = """
        {
          "arrHitter": [
            {
              "table1": \(try jsonStringLiteral(awayOrderTable)),
              "table2": \(try jsonStringLiteral(awayBattingDetailTable)),
              "table3": \(try jsonStringLiteral(awayBattingSummaryTable))
            },
            {
              "table1": \(try jsonStringLiteral(homeOrderTable)),
              "table2": \(try jsonStringLiteral(homeBattingDetailTable))
            }
          ],
          "arrPitcher": [
            { "table": \(try jsonStringLiteral(awayPitchingTable)) },
            { "table": \(try jsonStringLiteral(homePitchingTable)) }
          ]
        }
        """.data(using: .utf8)!
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: scoreboardPayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetBoxScoreScroll": StubResponse(statusCode: 200, data: boxScorePayload)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "abababab-abab-abab-abab-abababababab")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: Team(id: "kt", name: "KT 위즈", shortName: "KT", englishName: "KT Wiz", markText: "KT"),
            homeTeam: Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG"),
            awayScore: 3,
            homeScore: 2,
            status: .live,
            seasonClassification: .regularSeason,
            providerGameID: "20260328KTLG0"
        )

        let detail = try await client.fetchDetail(for: game)

        #expect(detail?.review?.awayBatting.lines.first?.name == "장두성")
        #expect(detail?.review?.awayBatting.lines.first?.runs == "0")
        #expect(detail?.review?.awayBatting.lines.first?.hits == "2")
        #expect(detail?.review?.awayBatting.lines.first?.homeRuns == "0")
        #expect(detail?.review?.awayBatting.lines.first?.walks == "0")
        #expect(detail?.review?.awayBatting.lines.first?.strikeouts == "1")
        let missingExtendedStatsLine = detail?.review?.awayBatting.lines.dropFirst(2).first
        #expect(missingExtendedStatsLine?.homeRuns == nil)
        #expect(missingExtendedStatsLine?.walks == nil)
        #expect(missingExtendedStatsLine?.strikeouts == nil)
        #expect(detail?.review?.awayBatting.totals?.homeRuns == "1")
        #expect(detail?.review?.awayBatting.totals?.walks == "1")
        #expect(detail?.review?.awayBatting.totals?.strikeouts == "1")
        #expect(detail?.review?.homeBatting.lines.first?.homeRuns == "0")
        #expect(detail?.review?.homeBatting.lines.first?.walks == "0")
        #expect(detail?.review?.homeBatting.lines.first?.strikeouts == "1")
        #expect(detail?.review?.awayPitching.lines.first?.innings == "6 1/3")
        #expect(detail?.review?.awayPitching.lines.first?.hitsAllowed == "4")
        #expect(detail?.review?.awayPitching.lines.first?.hitBatters == "0")
        #expect(detail?.review?.awayPitching.lines.first?.homeRunsAllowed == "1")
        #expect(detail?.review?.awayPitching.lines.first?.pitches == "91")
        #expect(detail?.review?.homePitching.lines.first?.hitBatters == "1")
    }

    @Test func officialGameCenterClientRejectsPlayResultsFromBattingAggregateStats() async throws {
        let emptyGridTable = #"{"headers":[],"rows":[],"tfoot":[]}"#
        let awayOrderTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "1" }, { "Text": "중견수" }, { "Text": "장두성" }] },
            { "row": [{ "Text": "2" }, { "Text": "좌익수" }, { "Text": "레이예스" }] }
          ],
          "tfoot": []
        }
        """#
        let homeOrderTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "1" }, { "Text": "유격수" }, { "Text": "김혜성" }] }
          ],
          "tfoot": []
        }
        """#
        let awayPlayResultsTable = #"""
        {
          "headers": [
            { "row": [{ "Text": "1회" }, { "Text": "2회" }, { "Text": "3회" }, { "Text": "4회" }, { "Text": "5회" }, { "Text": "6회" }, { "Text": "7회" }] }
          ],
          "rows": [
            { "row": [{ "Text": "우홈,,중비,,우안,,우중홈,4구," }] },
            { "row": [{ "Text": "좌비" }, { "Text": "2땅" }, { "Text": "중비" }, { "Text": "우안" }, { "Text": "중안" }, { "Text": "3땅" }, { "Text": "좌안" }] }
          ],
          "tfoot": [
            { "row": [{ "Text": "우홈,,중비,,우안,,우중홈,4구," }] }
          ]
        }
        """#
        let awayAggregateStatsTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "4" }, { "Text": "3" }, { "Text": "2" }, { "Text": "3" }, { "Text": "0.324" }] },
            { "row": [{ "Text": "5" }, { "Text": "1" }, { "Text": "2" }, { "Text": "0" }, { "Text": "0.253" }] }
          ],
          "tfoot": [
            { "row": [{ "Text": "42" }, { "Text": "16" }, { "Text": "8" }, { "Text": "8" }, { "Text": "0.253" }] }
          ]
        }
        """#
        let homeAggregateStatsTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "4" }, { "Text": "0" }, { "Text": "0" }, { "Text": "0" }, { "Text": "0.000" }] }
          ],
          "tfoot": [
            { "row": [{ "Text": "4" }, { "Text": "0" }, { "Text": "0" }, { "Text": "0" }, { "Text": "0.000" }] }
          ]
        }
        """#
        let officialGameList = """
        {
          "game": [
            {
              "LE_ID": 1,
              "SR_ID": 0,
              "SEASON_ID": 2026,
              "G_DT": "20260328",
              "G_DT_TXT": "2026.03.28(토)",
              "G_ID": "20260328KTLG0",
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
              "B_SCORE_CN": "2"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let scoreboardPayload = """
        {
          "S_NM": "잠실",
          "START_TM": "14:00",
          "table2": \(try jsonStringLiteral(emptyGridTable)),
          "table3": \(try jsonStringLiteral(emptyGridTable))
        }
        """.data(using: .utf8)!
        let boxScorePayload = """
        {
          "arrHitter": [
            {
              "table1": \(try jsonStringLiteral(awayOrderTable)),
              "table2": \(try jsonStringLiteral(awayPlayResultsTable)),
              "table3": \(try jsonStringLiteral(awayAggregateStatsTable))
            },
            {
              "table1": \(try jsonStringLiteral(homeOrderTable)),
              "table3": \(try jsonStringLiteral(homeAggregateStatsTable))
            }
          ],
          "arrPitcher": [
            { "table": \(try jsonStringLiteral(emptyGridTable)) },
            { "table": \(try jsonStringLiteral(emptyGridTable)) }
          ]
        }
        """.data(using: .utf8)!
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: scoreboardPayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetBoxScoreScroll": StubResponse(statusCode: 200, data: boxScorePayload)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
            venue: "잠실",
            awayTeam: Team(id: "kt", name: "KT 위즈", shortName: "KT", englishName: "KT Wiz", markText: "KT"),
            homeTeam: Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG"),
            awayScore: 3,
            homeScore: 2,
            status: .live,
            seasonClassification: .regularSeason,
            providerGameID: "20260328KTLG0"
        )

        let detail = try await client.fetchDetail(for: game)
        let awayFirstLine = try #require(detail?.review?.awayBatting.lines.first)
        let awayAggregateValues = [
            awayFirstLine.atBats,
            awayFirstLine.runs,
            awayFirstLine.hits,
            awayFirstLine.runsBattedIn,
            awayFirstLine.homeRuns,
            awayFirstLine.walks,
            awayFirstLine.strikeouts
        ]
        let rejectedPlayResults = ["2땅", "좌안", "삼진", "좌비", "3안", "중안", "유땅"]

        #expect(awayFirstLine.atBats == "4")
        #expect(awayFirstLine.runs == "3")
        #expect(awayFirstLine.hits == "3")
        #expect(awayFirstLine.runsBattedIn == "2")
        #expect(awayFirstLine.average == "0.324")
        #expect(awayFirstLine.homeRuns == nil)
        #expect(awayFirstLine.walks == nil)
        #expect(awayFirstLine.strikeouts == nil)
        #expect(awayFirstLine.plateAppearanceHomeRuns == "2")
        #expect(awayFirstLine.plateAppearanceWalks == "1")
        #expect(awayFirstLine.plateAppearanceStrikeouts == "0")
        #expect(detail?.review?.awayBatting.lines.dropFirst().first?.plateAppearanceHomeRuns == "0")
        #expect(detail?.review?.awayBatting.lines.dropFirst().first?.plateAppearanceWalks == "0")
        #expect(detail?.review?.awayBatting.lines.dropFirst().first?.plateAppearanceStrikeouts == "0")
        #expect(awayAggregateValues.compactMap { $0 }.contains { rejectedPlayResults.contains($0) } == false)
        #expect(detail?.review?.awayBatting.totals?.atBats == "42")
        #expect(detail?.review?.awayBatting.totals?.runs == "8")
        #expect(detail?.review?.awayBatting.totals?.hits == "16")
        #expect(detail?.review?.awayBatting.totals?.runsBattedIn == "8")
        #expect(detail?.review?.awayBatting.totals?.homeRuns == nil)
        #expect(detail?.review?.awayBatting.totals?.plateAppearanceHomeRuns == "2")
        #expect(detail?.review?.awayBatting.totals?.plateAppearanceWalks == "1")
        #expect(detail?.review?.awayBatting.totals?.plateAppearanceStrikeouts == "0")
        #expect(detail?.review?.homeBatting.lines.first?.homeRuns == nil)
        #expect(detail?.review?.homeBatting.lines.first?.walks == nil)
        #expect(detail?.review?.homeBatting.lines.first?.strikeouts == nil)
        #expect(detail?.review?.homeBatting.lines.first?.plateAppearanceHomeRuns == nil)
        #expect(detail?.review?.homeBatting.lines.first?.plateAppearanceWalks == nil)
        #expect(detail?.review?.homeBatting.lines.first?.plateAppearanceStrikeouts == nil)
    }

    @Test func gameCenterKeyStatsDerivesHomeRunsAndStrikeoutsFromHitterRows() throws {
        let review = makeKeyStatsReview(
            awayLines: [
                makeKeyStatsBattingLine(name: "강백호", hits: "1", homeRuns: "2", strikeouts: "1"),
                makeKeyStatsBattingLine(name: "박병호", hits: "2", homeRuns: "0", strikeouts: "3")
            ],
            homeLines: [
                makeKeyStatsBattingLine(name: "홍창기", hits: "3", homeRuns: "1", strikeouts: "2")
            ]
        )

        let stats = review.keyStats(awayTeam: keyStatsAwayTeam, homeTeam: keyStatsHomeTeam, lineScore: nil)

        #expect(stats.away.homeRuns == 2)
        #expect(stats.home.homeRuns == 1)
        #expect(stats.away.strikeouts == 4)
        #expect(stats.home.strikeouts == 2)
    }

    @Test func gameCenterKeyStatsParsesStolenBasesAndDoublePlaysFromTableEtc() throws {
        let review = makeKeyStatsReview(
            summaryItems: [
                GameCenterSummaryItem(title: "도루", value: "강백호(2회), 박병호(4회), 홍창기(5회)"),
                GameCenterSummaryItem(title: "병살타", value: "강백호(1회), 오지환(3회), 오지환(7회)")
            ],
            awayLines: [
                makeKeyStatsBattingLine(name: "강백호"),
                makeKeyStatsBattingLine(name: "박병호")
            ],
            homeLines: [
                makeKeyStatsBattingLine(name: "홍창기"),
                makeKeyStatsBattingLine(name: "오지환")
            ]
        )

        let stats = review.keyStats(awayTeam: keyStatsAwayTeam, homeTeam: keyStatsHomeTeam, lineScore: nil)

        #expect(stats.away.stolenBases == 2)
        #expect(stats.home.stolenBases == 1)
        #expect(stats.away.doublePlays == 1)
        #expect(stats.home.doublePlays == 2)
    }

    @Test func gameCenterKeyStatsSupportsMixedKoreanAndEnglishExtraLabels() throws {
        let review = makeKeyStatsReview(
            summaryItems: [
                GameCenterSummaryItem(title: "SB", value: "unused", values: ["1", "0"]),
                GameCenterSummaryItem(title: "GIDP", value: "unused", values: ["2", "1"]),
                GameCenterSummaryItem(title: "홈런", value: "홍창기(3회)")
            ],
            awayLines: [
                makeKeyStatsBattingLine(name: "강백호", homeRuns: "3")
            ],
            homeLines: [
                makeKeyStatsBattingLine(name: "홍창기", homeRuns: "0")
            ]
        )

        let stats = review.keyStats(awayTeam: keyStatsAwayTeam, homeTeam: keyStatsHomeTeam, lineScore: nil)

        #expect(stats.away.stolenBases == 1)
        #expect(stats.home.stolenBases == 0)
        #expect(stats.away.doublePlays == 2)
        #expect(stats.home.doublePlays == 1)
        #expect(stats.away.homeRuns == 3)
        #expect(stats.home.homeRuns == 1)
    }

    @Test func gameCenterKeyStatsDefaultsMissingFieldsSafelyToZero() throws {
        let review = makeKeyStatsReview()

        let stats = review.keyStats(awayTeam: keyStatsAwayTeam, homeTeam: keyStatsHomeTeam, lineScore: nil)

        #expect(stats.away == GameCenterTeamKeyStats(hits: 0, homeRuns: 0, stolenBases: 0, strikeouts: 0, doublePlays: 0, errors: 0))
        #expect(stats.home == GameCenterTeamKeyStats(hits: 0, homeRuns: 0, stolenBases: 0, strikeouts: 0, doublePlays: 0, errors: 0))
    }

    @Test func gameCenterKeyStatsKeepsAwayHomeValuesInOrder() throws {
        let review = makeKeyStatsReview(
            summaryItems: [
                GameCenterSummaryItem(title: "SB", value: "KT: 3 · LG: 1"),
                GameCenterSummaryItem(title: "GDP", value: "KT: 0 · LG: 2")
            ]
        )
        let lineScore = GameCenterLineScore(
            inningLabels: [],
            awayInnings: [],
            homeInnings: [],
            awayTotals: GameCenterTeamLineTotals(runs: "4", hits: "7", errors: "1", walks: nil),
            homeTotals: GameCenterTeamLineTotals(runs: "2", hits: "5", errors: "0", walks: nil)
        )

        let stats = review.keyStats(awayTeam: keyStatsAwayTeam, homeTeam: keyStatsHomeTeam, lineScore: lineScore)

        #expect(stats.away.hits == 7)
        #expect(stats.home.hits == 5)
        #expect(stats.away.errors == 1)
        #expect(stats.home.errors == 0)
        #expect(stats.away.stolenBases == 3)
        #expect(stats.home.stolenBases == 1)
        #expect(stats.away.doublePlays == 0)
        #expect(stats.home.doublePlays == 2)
    }

    private var keyStatsAwayTeam: Team {
        Team(id: "kt", name: "KT 위즈", shortName: "KT", englishName: "KT Wiz", markText: "KT")
    }

    private var keyStatsHomeTeam: Team {
        Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG")
    }

    private func makeKeyStatsReview(
        summaryItems: [GameCenterSummaryItem] = [],
        awayLines: [GameCenterBattingLine] = [],
        homeLines: [GameCenterBattingLine] = []
    ) -> GameCenterReview {
        GameCenterReview(
            summaryItems: summaryItems,
            awayBatting: GameCenterBattingSection(lines: awayLines, totals: nil),
            homeBatting: GameCenterBattingSection(lines: homeLines, totals: nil),
            awayPitching: GameCenterPitchingSection(lines: []),
            homePitching: GameCenterPitchingSection(lines: [])
        )
    }

    private func makeKeyStatsBattingLine(
        name: String,
        hits: String? = nil,
        homeRuns: String? = nil,
        strikeouts: String? = nil
    ) -> GameCenterBattingLine {
        GameCenterBattingLine(
            battingOrder: "1",
            position: "타자",
            name: name,
            atBats: nil,
            runs: nil,
            hits: hits,
            runsBattedIn: nil,
            homeRuns: homeRuns,
            walks: nil,
            strikeouts: strikeouts,
            average: nil
        )
    }

    private func makePositionBattingLine(name: String, position: String) -> GameCenterBattingLine {
        GameCenterBattingLine(
            battingOrder: "1",
            position: position,
            name: name,
            atBats: nil,
            runs: nil,
            hits: nil,
            runsBattedIn: nil,
            homeRuns: nil,
            walks: nil,
            strikeouts: nil,
            average: nil
        )
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
            configuration: AppRepositoryConfiguration(
                supabaseConfiguration: nil
            )
        )

        let snapshot = await bundle.runtimeState?.snapshot()

        #expect(snapshot?.activeSource == .mock)
        #expect(snapshot?.baseURL == nil)
    }

    @Test func supabaseFailureFallsBackToLocalRepository() async throws {
        let bundledDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: bundledDirectory) }

        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        try makeBootstrapJSON(teamName: "번들 LG").write(to: bundledURL, options: .atomic)

        let runtimeState = RepositoryRuntimeState(
            activeSource: .supabase,
            baseURL: "https://example.supabase.co",
            deliverySource: .supabase
        )
        let tracker = RepositoryCallTracker()
        let localRepository = TrackingKBORepository(
            base: BundledJSONKBORepository(
                bundledFileURLOverride: bundledURL,
                runtimeState: runtimeState,
                runtimeSource: .mockFallback,
                runtimeDelivery: .mockFallback
            ),
            tracker: tracker
        )
        let repository = SupabaseBackedKBORepository(
            base: localRepository,
            source: FailingSupabaseSource(),
            runtimeState: runtimeState
        )

        let bootstrap = try await repository.fetchBootstrapData()
        let snapshot = await runtimeState.snapshot()

        #expect(bootstrap.teams.first(where: { $0.id == "lg" })?.name == "번들 LG")
        #expect(await tracker.bootstrapFetchCount == 1)
        #expect(await tracker.monthlyScheduleFetchCount == 0)
        #expect(snapshot.deliverySource == .mockFallback)
        #expect(snapshot.localBootstrapSource == .bundled)
        #expect(snapshot.baseURL == "https://example.supabase.co")
    }

    @Test func supabaseBootstrapUsesLocalBootstrapWhenGamesExist() async throws {
        let runtimeState = RepositoryRuntimeState(
            activeSource: .supabase,
            baseURL: "https://example.supabase.co",
            deliverySource: .supabase
        )
        let tracker = RepositoryCallTracker()
        let localRepository = TrackingKBORepository(base: StubRepository(), tracker: tracker)
        let awayTeamID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let homeTeamID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let gameID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let source = StaticSupabaseSource(
            teamRows: [
                SupabaseTeamRow(id: awayTeamID, code: "lg", name: "LG 트윈스", shortName: "LG"),
                SupabaseTeamRow(id: homeTeamID, code: "doosan", name: "두산 베어스", shortName: "두산")
            ],
            gameRows: try JSONDecoder().decode(
                [SupabaseGameRow].self,
                from: Data(
                    """
                    [
                      {
                        "id": "\(gameID.uuidString)",
                        "public_game_id": "20260424-DOO-LG",
                        "provider": "kbo",
                        "provider_game_id": "20260424LGDO0",
                        "game_date": "2026-04-24",
                        "scheduled_at": 796554000,
                        "stadium": "잠실",
                        "status": "final",
                        "home_team_id": "\(homeTeamID.uuidString)",
                        "away_team_id": "\(awayTeamID.uuidString)",
                        "home_score": 2,
                        "away_score": 4,
                        "inning_state": "경기종료",
                        "is_cancelled": false,
                        "is_postponed": false,
                        "source_updated_at": 796565700,
                        "updated_at": 796565700,
                        "stadium_code": "JMS"
                      }
                    ]
                    """.utf8
                )
            )
        )
        let repository = SupabaseBackedKBORepository(
            base: localRepository,
            source: source,
            runtimeState: runtimeState
        )

        let bootstrap = try await repository.fetchBootstrapData()
        let snapshot = await runtimeState.snapshot()

        #expect(bootstrap.games.isEmpty == false)
        #expect(bootstrap.teams.count != 2)
        #expect(await tracker.bootstrapFetchCount == 1)
        #expect(snapshot.deliverySource == .supabase)
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

    @Test func repositoryFactoryIgnoresLegacyBackendURLWhenBuildingRuntimeRepository() async throws {
        let backendURL = try #require(URL(string: "http://127.0.0.1:8080"))
        let bundle = KBORepositoryFactory.makeAppRepositoryBundle(
            configuration: AppRepositoryConfiguration(
                backendBaseURL: backendURL,
                supabaseConfiguration: nil
            )
        )

        let snapshot = await bundle.runtimeState?.snapshot()

        #expect(snapshot?.activeSource == .mock)
        #expect(snapshot?.deliverySource == .mock)
        #expect(snapshot?.baseURL == nil)
    }

    @Test func liveRepositoryBuildsLocalhostBackendRequestURLs() async throws {
        let session = makeStubSession()
        let repository = LiveKBORepository(baseURL: URL(string: "http://localhost:8080")!, session: session)
        let payload = try fixtureData(named: "2026-preseason-bootstrap")

        URLProtocolStub.testResponses = [
            "http://localhost:8080/v1/games": StubResponse(statusCode: 200, data: payload)
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        _ = try await repository.fetchGames()
        let request = try #require(URLProtocolStub.lastRequest)

        #expect(request.url?.absoluteString == "http://localhost:8080/v1/games")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func gameBoxscoreResponseDecodesFullBatterAndPitcherRecords() throws {
        let response = try JSONDecoder().decode(GameBoxscoreResponse.self, from: sampleGameBoxscoreJSON()).sortedBySourceOrder

        #expect(response.gameId == "20260510-DOO-SSG")
        #expect(response.awayBatters.count == 2)
        #expect(response.homeBatters.count == 1)
        #expect(response.awayPitchers.count == 1)
        #expect(response.homePitchers.count == 1)
        #expect(response.updatedAt == "2026-05-11T02:04:00+09:00")
        #expect(response.isStale == false)
        #expect(response.awayBatters[0].playerName == "정수빈")
        #expect(response.awayBatters[0].atBats == 4)
        #expect(response.awayBatters[0].runs == 1)
        #expect(response.awayBatters[0].hits == 2)
        #expect(response.awayBatters[0].rbi == 1)
        #expect(response.awayBatters[0].battingAverage == "0.300")
        #expect(response.awayPitchers[0].playerName == "잭로그")
        #expect(response.awayPitchers[0].appearance == "선발")
        #expect(response.awayPitchers[0].decisionResult == "승")
        #expect(response.awayPitchers[0].inningsPitched == "6 1/3")
        #expect(response.awayPitchers[0].battersFaced == 24)
        #expect(response.awayPitchers[0].pitchCount == 88)
        #expect(response.awayPitchers[0].walksOrHitByPitch == 1)
        #expect(response.awayPitchers[0].era == "3.19")
    }

    @Test func gameBoxscoreResponseKeepsNullableBatterFieldsNil() throws {
        let response = try JSONDecoder().decode(GameBoxscoreResponse.self, from: sampleGameBoxscoreJSON()).sortedBySourceOrder
        let batter = try #require(response.awayBatters.first)

        #expect(batter.homeRuns == nil)
        #expect(batter.walks == nil)
        #expect(batter.strikeouts == nil)
        #expect(batter.stolenBases == nil)
    }

    @Test func gameDetailBatterStolenBaseDisplayDefaultsOnlyThatColumnToZero() throws {
        let missingStat: String? = nil

        #expect(missingStat.displayStolenBaseStat == "0")
        #expect((missingStat ?? "-") == "-")
    }

    @Test func gameRecordPositionFormatterDisplaysReadableBatterPositions() throws {
        #expect(GameRecordPositionFormatter.display(nil) == "-")
        #expect(GameRecordPositionFormatter.display("") == "-")
        #expect(GameRecordPositionFormatter.display("--") == "-")
        #expect(GameRecordPositionFormatter.display("포") == "C")
        #expect(GameRecordPositionFormatter.display("유") == "SS")
        #expect(GameRecordPositionFormatter.display("二") == "2B")
        #expect(GameRecordPositionFormatter.display("三") == "3B")
        #expect(GameRecordPositionFormatter.display("주우") == "PR·RF")
        #expect(GameRecordPositionFormatter.display("주二") == "PR·2B")
        #expect(GameRecordPositionFormatter.display("타유") == "PH·SS")
        #expect(GameRecordPositionFormatter.display("유三") == "SS·3B")
        #expect(GameRecordPositionFormatter.display("二유") == "2B·SS")
        #expect(GameRecordPositionFormatter.display("중우") == "CF·RF")
        #expect(GameRecordPositionFormatter.display("알수없음") == "알수없음")
    }

    @Test func gameRecordPositionFormatterCoversObservedDetailedBatterRows() throws {
        #expect(GameRecordPositionFormatter.display("주우") == "PR·RF")
        #expect(GameRecordPositionFormatter.display("주二") == "PR·2B")
        #expect(GameRecordPositionFormatter.display("유三") == "SS·3B")
        #expect(GameRecordPositionFormatter.display("二유") == "2B·SS")
    }

    @Test func gameRecordPositionEnrichmentUsesUnambiguousRicherSameTeamSource() throws {
        let current = GameCenterBattingSection(
            lines: [
                makePositionBattingLine(name: "정현창", position: "--"),
                makePositionBattingLine(name: "박민", position: "유"),
                makePositionBattingLine(name: "김규성", position: "주")
            ],
            totals: nil
        )
        let source = GameCenterBattingSection(
            lines: [
                makePositionBattingLine(name: "정현창", position: "二유"),
                makePositionBattingLine(name: "박민", position: "유三"),
                makePositionBattingLine(name: "김규성", position: "주二")
            ],
            totals: nil
        )

        let enriched = current.enrichingPositions(from: source, sideLabel: "away")

        #expect(GameRecordPositionFormatter.display(enriched.lines[0].position) == "2B·SS")
        #expect(GameRecordPositionFormatter.display(enriched.lines[1].position) == "SS·3B")
        #expect(GameRecordPositionFormatter.display(enriched.lines[2].position) == "PR·2B")
    }

    @Test func gameBoxscoreResponseSortsRecordsBySourceOrder() throws {
        let response = try JSONDecoder().decode(GameBoxscoreResponse.self, from: sampleGameBoxscoreJSON()).sortedBySourceOrder

        #expect(response.awayBatters.map(\.sourceOrder) == [0, 1])
        #expect(response.awayBatters.map(\.playerName) == ["정수빈", "허경민"])
    }

    @Test func backendGameBoxscoreClientFetchesExpectedEndpoint() async throws {
        let session = makeBoxscoreStubSession()
        let client = BackendGameBoxscoreClient(baseURL: URL(string: "http://localhost:8088")!, session: session)

        BoxscoreURLProtocolStub.testResponses = [
            "http://localhost:8088/api/v1/games/20260510-DOO-SSG/boxscore": StubResponse(statusCode: 200, data: sampleGameBoxscoreJSON())
        ]
        BoxscoreURLProtocolStub.lastRequest = nil
        defer {
            BoxscoreURLProtocolStub.testResponses = [:]
            BoxscoreURLProtocolStub.lastRequest = nil
        }

        let response = try await client.fetchGameBoxscore(gameId: "20260510-DOO-SSG")
        let request = try #require(BoxscoreURLProtocolStub.lastRequest)

        #expect(request.url?.absoluteString == "http://localhost:8088/api/v1/games/20260510-DOO-SSG/boxscore")
        #expect(request.httpMethod == "GET")
        #expect(request.timeoutInterval == 2.5)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(response.awayBatters.count == 2)
    }

    @Test func gameDetailScreenModelMergesBoxscoreWithoutClearingDetailState() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let state = RecordingBoxscoreState(result: .success(try JSONDecoder().decode(GameBoxscoreResponse.self, from: sampleGameBoxscoreJSON())))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: state),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            }
        )
        let game = try makeBoxscoreDetailGame()

        await model.load(for: game)
        await model.waitForBoxscoreLoadForTesting()

        #expect(model.detail?.summary.officialGameID == "20260510SKOB0")
        #expect(model.boxscore?.awayBatters.count == 2)
        #expect(model.boxscore?.awayPitchers.first?.walksOrHitByPitch == 1)
        #expect(await state.fetchCount == 1)
        #expect(await state.requestedGameIDs == ["20260510-DOO-SSG"])
    }

    @Test func gameDetailScreenModelAcceptsEmptyBoxscoreArrays() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let empty = GameBoxscoreResponse.empty(gameId: "20260510-DOO-SSG")
        let state = RecordingBoxscoreState(result: .success(empty))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: state),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            }
        )

        await model.load(for: try makeBoxscoreDetailGame())
        await model.waitForBoxscoreLoadForTesting()

        #expect(model.boxscore?.awayBatters.isEmpty == true)
        #expect(model.boxscore?.homePitchers.isEmpty == true)
        #expect(model.errorMessage == nil)
    }

    @Test func failedBoxscoreFetchDoesNotFailDetailLoad() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let state = RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: state),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            }
        )

        await model.load(for: try makeBoxscoreDetailGame())
        await model.waitForBoxscoreLoadForTesting()

        #expect(model.detail?.summary.officialGameID == "20260510SKOB0")
        #expect(model.boxscore == nil)
        #expect(model.errorMessage == nil)
        #expect(model.boxscoreErrorMessage != nil)
    }

    @Test func slowBoxscoreFetchDoesNotBlockDetailPayloadRendering() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let state = RecordingBoxscoreState(result: .success(try JSONDecoder().decode(GameBoxscoreResponse.self, from: sampleGameBoxscoreJSON())))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: state, delayNanoseconds: 300_000_000),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            }
        )

        await model.load(for: try makeBoxscoreDetailGame())

        #expect(model.detail?.summary.officialGameID == "20260510SKOB0")
        #expect(model.boxscore == nil)

        await model.waitForBoxscoreLoadForTesting()
        #expect(model.boxscore?.awayBatters.count == 2)
    }

    @Test func gameDetailScreenModelDoesNotRepeatBoxscoreFetchForSameGame() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let state = RecordingBoxscoreState(result: .success(try JSONDecoder().decode(GameBoxscoreResponse.self, from: sampleGameBoxscoreJSON())))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: state),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            }
        )
        let game = try makeBoxscoreDetailGame()

        await model.load(for: game)
        await model.waitForBoxscoreLoadForTesting()
        await model.load(for: game)
        await model.waitForBoxscoreLoadForTesting()

        #expect(await state.fetchCount == 1)
    }

    @Test func gameDetailScreenModelSkipsRepeatedFailedBoxscoreFetchDuringCooldown() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let state = RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))
        let firstModel = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: state),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            }
        )
        let secondModel = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: state),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            }
        )
        let game = try makeBoxscoreDetailGame()

        await firstModel.load(for: game)
        await firstModel.waitForBoxscoreLoadForTesting()
        await secondModel.load(for: game)
        await secondModel.waitForBoxscoreLoadForTesting()

        #expect(await state.fetchCount == 1)
        #expect(secondModel.detail?.summary.officialGameID == "20260510SKOB0")
        #expect(secondModel.boxscoreErrorMessage != nil)
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

    @Test func localProbabilityCalculatorAddsVirtualGamesForOfficialPairDeficits() throws {
        let teams = makeProbabilityTestTeams()
        let games = makePairDeficitRegularSeasonSchedule(
            teams: teams,
            gamesPerPair: 15,
            completedGamesPerPair: 1
        )
        let calculator = LocalPostseasonQualificationCalculator(
            regularSeasonLength: 144,
            simulationCount: 200
        )

        let signals = calculator.makeSignals(teams: teams, games: games)
        let team1Signal = try #require(signals["team1"])
        let team10Signal = try #require(signals["team10"])

        #expect(games.count == 675)
        #expect(team1Signal.postseasonQualificationProbability != nil)
        #expect(team1Signal.postseasonProbabilityUnavailableReason == nil)
        #expect(team1Signal.unknownClassificationGames == 0)
        #expect(team1Signal.virtualUnscheduledRemainingGames == 9)
        #expect(team10Signal.virtualUnscheduledRemainingGames == 9)
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

    @Test func localProbabilityCalculatorDoesNotTreatMappedSupabaseRegularSeasonRowsAsUnknown() throws {
        let awayTeamID = UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!
        let homeTeamID = UUID(uuidString: "bbbbbbbb-2222-2222-2222-222222222222")!
        let gameID = UUID(uuidString: "cccccccc-3333-3333-3333-333333333333")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "team1", name: "팀1", shortName: "T1"),
            SupabaseTeamRow(id: homeTeamID, code: "team2", name: "팀2", shortName: "T2")
        ]
        let gameRows = try JSONDecoder().decode(
            [SupabaseGameRow].self,
            from: Data(
                """
                [
                  {
                    "id": "\(gameID.uuidString)",
                    "public_game_id": "20260424-TEAM1-TEAM2",
                    "provider": "kbo",
                    "provider_game_id": "sched-202604241830-team1-team2",
                    "game_date": "2026-04-24",
                    "scheduled_at": "2026-04-24T18:30:00+09:00",
                    "stadium": "잠실",
                    "status": "final",
                    "home_team_id": "\(homeTeamID.uuidString)",
                    "away_team_id": "\(awayTeamID.uuidString)",
                    "home_score": 2,
                    "away_score": 4,
                    "inning_state": "경기종료",
                    "is_cancelled": false,
                    "is_postponed": false,
                    "source_updated_at": "2026-04-24T21:45:00+09:00",
                    "updated_at": "2026-04-24T21:45:00+09:00",
                    "stadium_code": "JMS"
                  }
                ]
                """.utf8
            )
        )
        let teams = SupabaseKBOMapper.mapTeams(teamRows)
        let games = SupabaseKBOMapper.mapGames(gameRows: gameRows, teamRows: teamRows)
        let calculator = LocalPostseasonQualificationCalculator(
            regularSeasonLength: 1,
            postseasonQualifierCount: 1,
            simulationCount: 10
        )

        let signals = calculator.makeSignals(teams: teams, games: games)

        #expect(games.count == 1)
        #expect(games[0].seasonClassification == .regularSeason)
        #expect(signals["team1"]?.unknownClassificationGames == 0)
        #expect(signals["team2"]?.unknownClassificationGames == 0)
        #expect(signals["team1"]?.postseasonProbabilityUnavailableReason != .unknownClassificationGames)
        #expect(signals["team2"]?.postseasonProbabilityUnavailableReason != .unknownClassificationGames)
        #expect(signals["team1"]?.postseasonQualificationProbability != nil)
        #expect(signals["team2"]?.postseasonQualificationProbability != nil)
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
            virtualUnscheduledRemainingGames: 9,
            postseasonQualificationProbability: 0.784
        )

        #expect(snapshot.postseasonQualificationText == "78.4%")
        #expect(snapshot.postseasonProbabilityEstimateText == "공식 미편성 9경기 포함 추정치")
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
            "https://example.com/api/v1/bootstrap": StubResponse(statusCode: 500, data: Data())
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
            "https://example.com/api/v1/schedule/month?year=2026&month=3": StubResponse(statusCode: 500, data: Data())
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

    @Test func cachedRepositoryBypassesFreshMonthlyScheduleCacheWhenRequested() async throws {
        let counter = FetchCounter()
        let fullSchedule = stubGames()
        let refreshedSchedule = Array(fullSchedule.prefix(1))
        let repository = CachedKBORepository(
            base: StubRepository(
                fetchMonthlySchedule: { _ in
                    let attempt = await counter.incrementAndReturn()
                    return attempt == 1 ? fullSchedule : refreshedSchedule
                }
            ),
            configuration: RepositoryCacheConfiguration(bootstrapTTL: 1, gamesTTL: 1, notificationsTTL: 1, monthlyScheduleTTL: 60),
            runtimeState: nil
        )

        let key = KBOMonthScheduleKey(year: 2026, month: 3)
        let first = try await repository.fetchMonthlySchedule(for: key)
        let refreshed = try await repository.fetchMonthlySchedule(for: key, bypassingCache: true)
        let cachedAfterRefresh = try await repository.fetchMonthlySchedule(for: key)

        #expect(first.count == fullSchedule.count)
        #expect(refreshed.count == refreshedSchedule.count)
        #expect(cachedAfterRefresh.count == refreshedSchedule.count)
        #expect(await counter.value == 2)
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

    @Test func scheduleDayLoadUsesLocalCacheForPastCompletedDate() async throws {
        let dayFetchCounter = FetchCounter()
        let referenceDate = ISO8601DateFormatter().date(from: "2026-03-12T18:30:00+09:00")!
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let completedGame = makeGameDetail(
            id: UUID(),
            scheduledStart: referenceDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 2,
            status: .final,
            seasonClassification: .regularSeason
        )

        let repository = StubRepository(
            fetchMonthlySchedule: { _ in [completedGame] },
            fetchSchedule: { _ in
                await dayFetchCounter.increment()
                return [completedGame]
            }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: {
                ISO8601DateFormatter().date(from: "2026-03-13T09:00:00+09:00")!
            }
        )

        await model.loadScheduleIfNeeded(for: referenceDate)
        await model.loadScheduleDayIfNeeded(for: referenceDate)

        #expect(await dayFetchCounter.value == 0)
    }

    @Test func scheduleDayLoadFetchesTodayOnly() async throws {
        let dayFetchCounter = FetchCounter()
        let referenceDate = ISO8601DateFormatter().date(from: "2026-03-12T18:30:00+09:00")!
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let todayGame = makeGameDetail(
            id: UUID(),
            scheduledStart: referenceDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )

        let repository = StubRepository(
            fetchMonthlySchedule: { _ in [todayGame] },
            fetchSchedule: { _ in
                await dayFetchCounter.increment()
                return [todayGame]
            }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        await model.loadScheduleIfNeeded(for: referenceDate)
        await model.loadScheduleDayIfNeeded(for: referenceDate)

        #expect(await dayFetchCounter.value == 1)
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
            "https://example.com/api/v1/schedule/month?year=2026&month=3": StubResponse(statusCode: 200, data: backendMonthlyPayload)
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

        #expect(requestedURL == "https://example.com/api/v1/schedule/month?year=2026&month=3")
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

    @Test func repositoryFactoryWithoutSupabaseConfigKeepsExistingRuntimeDefaults() async throws {
        let bundle = KBORepositoryFactory.makeAppRepositoryBundle(
            configuration: AppRepositoryConfiguration(
                supabaseConfiguration: nil
            )
        )
        let snapshot = await bundle.runtimeState?.snapshot()

        #expect(snapshot?.activeSource == .mock)
        #expect(snapshot?.deliverySource == .mock)
        #expect(snapshot?.baseURL == nil)
    }

    @Test func supabaseMapperDecodesRowsIntoExistingGameModels() throws {
        let awayTeamID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let homeTeamID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let gameID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "lg", name: "LG 트윈스", shortName: "LG"),
            SupabaseTeamRow(id: homeTeamID, code: "doosan", name: "두산 베어스", shortName: "두산")
        ]
        let gameRows = try JSONDecoder().decode(
            [SupabaseGameRow].self,
            from: Data(
                """
                [
                  {
                    "id": "\(gameID.uuidString)",
                    "public_game_id": "20260424-DOO-LG",
                    "provider": "kbo",
                    "provider_game_id": "20260424LGDO0",
                    "game_date": "2026-04-24",
                    "scheduled_at": "2026-04-24T18:30:00+09:00",
                    "stadium": "잠실",
                    "status": "final",
                    "home_team_id": "\(homeTeamID.uuidString)",
                    "away_team_id": "\(awayTeamID.uuidString)",
                    "home_score": 2,
                    "away_score": 4,
                    "inning_state": "경기종료",
                    "is_cancelled": false,
                    "is_postponed": false,
                    "source_updated_at": "2026-04-24T21:45:00+09:00",
                    "updated_at": "2026-04-24T21:45:00+09:00",
                    "stadium_code": "JMS",
                    "official_provider_game_id": "20260424LGDO0"
                  }
                ]
                """.utf8
            )
        )

        let games = SupabaseKBOMapper.mapGames(gameRows: gameRows, teamRows: teamRows)
        let game = try #require(games.first)
        var scheduleCalendar = Calendar(identifier: .gregorian)
        scheduleCalendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let components = scheduleCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: game.scheduledStart)

        #expect(games.count == 1)
        #expect(game.id == gameID)
        #expect(game.awayTeam.id == "lg")
        #expect(game.homeTeam.id == "doosan")
        #expect(game.providerGameID == "20260424LGDO0")
        #expect(game.status == .final)
        #expect(game.seasonClassification == .regularSeason)
        #expect(game.note?.contains("provider_game_id=20260424LGDO0") == true)
        #expect(components.year == 2026)
        #expect(components.month == 4)
        #expect(components.day == 24)
        #expect(components.hour == 18)
        #expect(components.minute == 30)
    }

    @Test func supabaseMapperTreatsValidKBOGameDateAsRegularSeasonWithoutNumericProviderGameID() throws {
        let awayTeamID = UUID(uuidString: "44444444-1111-1111-1111-111111111111")!
        let homeTeamID = UUID(uuidString: "55555555-2222-2222-2222-222222222222")!
        let gameID = UUID(uuidString: "66666666-3333-3333-3333-333333333333")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "lg", name: "LG 트윈스", shortName: "LG"),
            SupabaseTeamRow(id: homeTeamID, code: "doosan", name: "두산 베어스", shortName: "두산")
        ]
        let gameRows = try JSONDecoder().decode(
            [SupabaseGameRow].self,
            from: Data(
                """
                [
                  {
                    "id": "\(gameID.uuidString)",
                    "public_game_id": "20260425-DOO-LG",
                    "provider": "kbo",
                    "provider_game_id": "sched-202604251830-lg-doosan",
                    "game_date": "2026-04-25",
                    "scheduled_at": "2026-04-25T18:30:00+09:00",
                    "stadium": "잠실",
                    "status": "scheduled",
                    "home_team_id": "\(homeTeamID.uuidString)",
                    "away_team_id": "\(awayTeamID.uuidString)",
                    "home_score": null,
                    "away_score": null,
                    "inning_state": null,
                    "is_cancelled": false,
                    "is_postponed": false,
                    "source_updated_at": "2026-04-24T21:45:00+09:00",
                    "updated_at": "2026-04-24T21:45:00+09:00",
                    "stadium_code": "JMS"
                  }
                ]
                """.utf8
            )
        )

        let game = try #require(SupabaseKBOMapper.mapGames(gameRows: gameRows, teamRows: teamRows).first)

        #expect(game.providerGameID == "sched-202604251830-lg-doosan")
        #expect(game.seasonClassification == .regularSeason)
        #expect(game.status == .upcoming)
    }

    @Test func supabaseMapperPreservesExplicitPreseasonMarker() throws {
        let awayTeamID = UUID(uuidString: "77777777-1111-1111-1111-111111111111")!
        let homeTeamID = UUID(uuidString: "88888888-2222-2222-2222-222222222222")!
        let gameID = UUID(uuidString: "99999999-3333-3333-3333-333333333333")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "lg", name: "LG 트윈스", shortName: "LG"),
            SupabaseTeamRow(id: homeTeamID, code: "doosan", name: "두산 베어스", shortName: "두산")
        ]
        let gameRows = try JSONDecoder().decode(
            [SupabaseGameRow].self,
            from: Data(
                """
                [
                  {
                    "id": "\(gameID.uuidString)",
                    "public_game_id": "KBO_PRE_20260314-LG-DOO",
                    "provider": "kbo",
                    "provider_game_id": "kbo_pre_20260314LGDO0",
                    "game_date": "2026-03-14",
                    "scheduled_at": "2026-03-14T13:00:00+09:00",
                    "stadium": "잠실",
                    "status": "scheduled",
                    "home_team_id": "\(homeTeamID.uuidString)",
                    "away_team_id": "\(awayTeamID.uuidString)",
                    "home_score": null,
                    "away_score": null,
                    "inning_state": null,
                    "is_cancelled": false,
                    "is_postponed": false,
                    "source_updated_at": "2026-03-13T09:00:00+09:00",
                    "updated_at": "2026-03-13T09:00:00+09:00",
                    "stadium_code": "JMS"
                  }
                ]
                """.utf8
            )
        )

        let game = try #require(SupabaseKBOMapper.mapGames(gameRows: gameRows, teamRows: teamRows).first)

        #expect(game.seasonClassification == .exhibitionPreseason)
    }

    @Test func supabaseMapperPreservesExplicitPostseasonMarker() throws {
        let awayTeamID = UUID(uuidString: "aaaaaaaa-4444-4444-4444-444444444444")!
        let homeTeamID = UUID(uuidString: "bbbbbbbb-5555-5555-5555-555555555555")!
        let gameID = UUID(uuidString: "cccccccc-6666-6666-6666-666666666666")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "lg", name: "LG 트윈스", shortName: "LG"),
            SupabaseTeamRow(id: homeTeamID, code: "doosan", name: "두산 베어스", shortName: "두산")
        ]
        let gameRows = try JSONDecoder().decode(
            [SupabaseGameRow].self,
            from: Data(
                """
                [
                  {
                    "id": "\(gameID.uuidString)",
                    "public_game_id": "20261012-WILDCARD-LG-DOO",
                    "provider": "kbo",
                    "provider_game_id": "wildcard-20261012LGDO0",
                    "game_date": "2026-10-12",
                    "scheduled_at": "2026-10-12T18:30:00+09:00",
                    "stadium": "잠실",
                    "status": "scheduled",
                    "home_team_id": "\(homeTeamID.uuidString)",
                    "away_team_id": "\(awayTeamID.uuidString)",
                    "home_score": null,
                    "away_score": null,
                    "inning_state": null,
                    "is_cancelled": false,
                    "is_postponed": false,
                    "source_updated_at": "2026-10-11T09:00:00+09:00",
                    "updated_at": "2026-10-11T09:00:00+09:00",
                    "stadium_code": "JMS"
                  }
                ]
                """.utf8
            )
        )

        let game = try #require(SupabaseKBOMapper.mapGames(gameRows: gameRows, teamRows: teamRows).first)

        #expect(game.seasonClassification == .postseason)
    }

    @Test func supabaseTeamRowDecodesLegacyTeamCodeColumn() throws {
        let teamID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let row = try JSONDecoder().decode(
            SupabaseTeamRow.self,
            from: Data(
                """
                {
                  "id": "\(teamID.uuidString)",
                  "team_code": "lg",
                  "name": "LG 트윈스",
                  "short_name": "LG"
                }
                """.utf8
            )
        )

        #expect(row.id == teamID)
        #expect(row.code == "lg")
        #expect(row.name == "LG 트윈스")
        #expect(row.shortName == "LG")
    }

    @Test func standingsTabRendersLocalTeamRankRowsImmediately() async throws {
        let state = TeamRankFlowState(localRanks: sampleTeamRankRows())
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: isoDate("2026-05-06T12:00:00+09:00")),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-06T12:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()

        #expect(model.standingsSnapshots.map(\.team.id).prefix(2) == ["lg", "kia"])
        #expect(model.standingsSnapshots.map(\.rank).prefix(2) == [1, 2])
        #expect(await state.remoteFetchCount == 0)
    }

    @Test func standingsTabAutoFetchesTeamRankViewWhenLocalRankCacheIsEmpty() async throws {
        let state = TeamRankFlowState(localRanks: [], remoteRanks: sampleTeamRankRows())
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: isoDate("2026-05-06T12:00:00+09:00")),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-06T12:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()

        #expect(await state.remoteFetchCount == 1)
        #expect(await state.cachedRanksCount == 2)
        #expect(model.standingsSnapshots.map(\.rank).prefix(2) == [1, 2])
    }

    @Test func simultaneousStandingsBootstrapCoalescesTeamRankRemoteFetch() async throws {
        let gate = RankFetchGate()
        let state = TeamRankFlowState(
            localRanks: [],
            remoteRanks: sampleTeamRankRows(),
            gate: gate
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: isoDate("2026-05-06T12:00:00+09:00")),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-06T12:00:00+09:00") }
        )

        let firstLoad = Task { await model.loadStandingsIfNeeded() }
        await gate.waitUntilStarted()
        #expect(await state.remoteFetchCount == 1)

        let secondLoad = Task { await model.loadStandingsIfNeeded() }
        #expect(await state.remoteFetchCount == 1)

        await gate.release()
        await firstLoad.value
        await secondLoad.value

        #expect(await state.remoteFetchCount == 1)
        #expect(await state.localReplaceCount == 1)
        #expect(await state.cachedRanksCount == 2)
        #expect(model.standingsSnapshots.map(\.rank).prefix(2) == [1, 2])
    }

    @Test func manualStandingsRefreshFetchesTeamRankViewAndUpdatesLocalCache() async throws {
        let state = TeamRankFlowState(
            localRanks: [sampleTeamRankRows()[1]],
            remoteRanks: sampleTeamRankRows()
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: isoDate("2026-05-06T12:00:00+09:00")),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-06T12:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()
        await model.refreshStandings()

        #expect(await state.remoteFetchCount == 1)
        #expect(await state.cachedRanksCount == 2)
        #expect(model.standingsSnapshots.first?.team.id == "lg")
    }

    @Test func standingsAreNotClearedWhileTeamRankRefreshIsRunning() async throws {
        let gate = RankFetchGate()
        let state = TeamRankFlowState(
            localRanks: sampleTeamRankRows(),
            remoteRanks: Array(sampleTeamRankRows().reversed()),
            gate: gate
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: isoDate("2026-05-06T12:00:00+09:00")),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-06T12:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()
        let refreshTask = Task { await model.refreshStandings() }
        await gate.waitUntilStarted()

        #expect(model.standingsSnapshots.isEmpty == false)
        #expect(model.standingsSnapshots.first?.team.id == "lg")

        await gate.release()
        await refreshTask.value
    }

    @Test func emptyTeamRankViewFallsBackToGamesBasedStandingsCalculation() async throws {
        let teams = MockKBOData.makeBootstrap().teams
        let lg = try #require(teams.first { $0.id == "lg" })
        let kia = try #require(teams.first { $0.id == "kia" })
        let completedGame = makeGameDetail(
            id: UUID(),
            scheduledStart: isoDate("2026-04-10T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: kia,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason
        )
        let state = TeamRankFlowState(localRanks: [], remoteRanks: [], standingsGames: [completedGame])
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-06T12:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()

        #expect(await state.standingsSourceFetchCount == 1)
        #expect(model.standingsSnapshots.first?.team.id == "lg")
        #expect(model.standingsSnapshots.first?.wins == 1)
    }

    @Test func teamRankFetchFailureWithEmptyLocalCacheFallsBackToGamesBasedStandingsCalculation() async throws {
        let teams = MockKBOData.makeBootstrap().teams
        let lg = try #require(teams.first { $0.id == "lg" })
        let kia = try #require(teams.first { $0.id == "kia" })
        let completedGame = makeGameDetail(
            id: UUID(),
            scheduledStart: isoDate("2026-04-10T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: kia,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason
        )
        let state = TeamRankFlowState(
            localRanks: [],
            remoteError: TestRepositoryError.supabaseUnavailable,
            standingsGames: [completedGame]
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-06T12:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()

        #expect(await state.remoteFetchCount == 1)
        #expect(await state.standingsSourceFetchCount == 1)
        #expect(model.standingsSnapshots.first?.team.id == "lg")
        #expect(model.standingsSnapshots.first?.wins == 1)
    }

    @Test func teamRankFetchFailureKeepsExistingLocalRanksVisible() async throws {
        let state = TeamRankFlowState(
            localRanks: sampleTeamRankRows(),
            remoteError: TestRepositoryError.supabaseUnavailable
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: isoDate("2026-05-06T12:00:00+09:00")),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-06T12:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()
        await model.refreshStandings()

        #expect(model.standingsSnapshots.first?.team.id == "lg")
        #expect(model.standingsSnapshots.count == 2)
    }

    @Test func supabaseSnakeCaseColumnsDecodeIntoTeamRankRow() throws {
        let teamID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let rows = try JSONDecoder().decode(
            [TeamRankRow].self,
            from: Data(
                """
                [{
                  "season": 2026,
                  "team_id": "\(teamID.uuidString)",
                  "rank": 1,
                  "team_name": "LG 트윈스",
                  "games_played": 40,
                  "wins": 25,
                  "losses": 13,
                  "draws": 2,
                  "winning_percentage": "0.658",
                  "games_behind": "0.0",
                  "streak_type": "WIN",
                  "streak_count": 3,
                  "streak_text": "3승",
                  "last_game_date": "2026-05-05",
                  "calculated_at": "2026-05-06T12:00:00+09:00",
                  "updated_at": "2026-05-06T12:00:00+09:00",
                  "created_at": "2026-05-06T12:00:00+09:00"
                }]
                """.utf8
            )
        )

        let row = try #require(rows.first)
        #expect(row.teamID == teamID)
        #expect(row.teamName == "LG 트윈스")
        #expect(row.gamesPlayed == 40)
        #expect(row.winningPercentage == 0.658)
        #expect(row.gamesBehind == 0.0)
        #expect(row.streakType == "WIN")
        #expect(row.streakCount == 3)
        #expect(row.streakText == "3승")
        #expect(row.lastGameDate != nil)
        #expect(row.calculatedAt != nil)
        #expect(row.updatedAt != nil)
        #expect(row.createdAt != nil)
    }

    @Test func teamRankRowsRenderSortedByRankAscending() async throws {
        let state = TeamRankFlowState(localRanks: Array(sampleTeamRankRows().reversed()))
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: isoDate("2026-05-06T12:00:00+09:00")),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-06T12:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()

        #expect(model.standingsSnapshots.map(\.rank) == [1, 2])
        #expect(model.standingsSnapshots.map(\.team.id) == ["lg", "kia"])
    }

}

private func sampleTeamRankRows() -> [TeamRankRow] {
    [
        TeamRankRow(
            season: 2026,
            teamID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            teamCode: "lg",
            rank: 1,
            teamName: "LG 트윈스",
            gamesPlayed: 40,
            wins: 25,
            losses: 13,
            draws: 2,
            winningPercentage: 0.658,
            gamesBehind: 0.0,
            streakType: "WIN",
            streakCount: 3,
            streakText: "3승"
        ),
        TeamRankRow(
            season: 2026,
            teamID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            teamCode: "kia",
            rank: 2,
            teamName: "KIA 타이거즈",
            gamesPlayed: 41,
            wins: 23,
            losses: 16,
            draws: 2,
            winningPercentage: 0.590,
            gamesBehind: 3.0,
            streakType: "LOSS",
            streakCount: 1,
            streakText: "1패"
        )
    ]
}

private actor RankFetchGate {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var didRelease = false

    func wait() async {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil
        guard didRelease == false else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard didStart == false else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func release() {
        didRelease = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor TeamRankFlowState {
    private var localRanks: [TeamRankRow]
    private let remoteRanks: [TeamRankRow]
    private let remoteError: (any Error)?
    private let gate: RankFetchGate?
    private let standingsGames: [GameDetail]
    private(set) var remoteFetchCount = 0
    private(set) var localReplaceCount = 0
    private(set) var standingsSourceFetchCount = 0

    init(
        localRanks: [TeamRankRow],
        remoteRanks: [TeamRankRow] = [],
        remoteError: (any Error)? = nil,
        gate: RankFetchGate? = nil,
        standingsGames: [GameDetail] = []
    ) {
        self.localRanks = localRanks
        self.remoteRanks = remoteRanks
        self.remoteError = remoteError
        self.gate = gate
        self.standingsGames = standingsGames
    }

    var cachedRanksCount: Int {
        localRanks.count
    }

    func fetchLocalRanks(season: Int) -> [TeamRankRow] {
        localRanks.filter { $0.season == season }.sorted { $0.rank < $1.rank }
    }

    func replaceLocalRanks(_ ranks: [TeamRankRow], season: Int) -> Int {
        localRanks.removeAll { $0.season == season }
        localRanks.append(contentsOf: ranks)
        localReplaceCount += 1
        return ranks.count
    }

    func fetchRemoteRanks(season: Int) async throws -> [TeamRankRow] {
        remoteFetchCount += 1
        if let gate {
            await gate.wait()
        }
        if let remoteError {
            throw remoteError
        }
        return remoteRanks.filter { $0.season == season }.sorted { $0.rank < $1.rank }
    }

    func fetchStandingsSource(season: Int) -> [GameDetail] {
        standingsSourceFetchCount += 1
        return standingsGames
    }
}

private struct TeamRankFlowRepository: KBORepository, KBOTeamRankDataSource, KBOLocalTeamRankCacheDataSource, KBOLocalTeamRankCacheUpserting, KBOStandingsGameDataSource, Sendable {
    let state: TeamRankFlowState

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        MockKBOData.makeBootstrap()
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        []
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        []
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        []
    }

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        []
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        []
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        []
    }

    nonisolated func fetchTeamRanks(season: Int) async throws -> [TeamRankRow] {
        try await state.fetchRemoteRanks(season: season)
    }

    nonisolated func fetchLocalTeamRanks(season: Int) async -> [TeamRankRow] {
        await state.fetchLocalRanks(season: season)
    }

    nonisolated func replaceLocalTeamRanks(_ ranks: [TeamRankRow], season: Int) async -> Int {
        await state.replaceLocalRanks(ranks, season: season)
    }

    nonisolated func fetchStandingsSource(season: Int) async throws -> [GameDetail] {
        await state.fetchStandingsSource(season: season)
    }
}

private actor RepositoryCallTracker {
    private(set) var bootstrapFetchCount = 0
    private(set) var monthlyScheduleFetchCount = 0

    func recordBootstrapFetch() {
        bootstrapFetchCount += 1
    }

    func recordMonthlyScheduleFetch() {
        monthlyScheduleFetchCount += 1
    }
}

private struct TrackingKBORepository<Base: KBORepository>: KBORepository, Sendable {
    let base: Base
    let tracker: RepositoryCallTracker

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        await tracker.recordBootstrapFetch()
        return try await base.fetchBootstrapData()
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await base.fetchGames()
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await base.fetchNotifications()
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        await tracker.recordMonthlyScheduleFetch()
        return try await base.fetchMonthlySchedule(for: month)
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }
}

private struct StaticSupabaseSource: SupabaseKBOReading, Sendable {
    let teamRows: [SupabaseTeamRow]
    let gameRows: [SupabaseGameRow]

    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow] {
        teamRows
    }

    nonisolated func fetchGameCount() async throws -> Int {
        gameRows.count
    }

    nonisolated func fetchGames() async throws -> [SupabaseGameRow] {
        gameRows
    }

    nonisolated func fetchGames(excludingProviderGameIDs providerGameIDs: Set<String>) async throws -> [SupabaseGameRow] {
        gameRows.filter { row in
            guard let providerGameID = row.providerGameID else { return true }
            return providerGameIDs.contains(providerGameID) == false
        }
    }

    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow] {
        gameRows
    }

    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow] {
        gameRows
    }

    nonisolated func fetchGames(date: Date, favoriteTeamID: String) async throws -> [SupabaseGameRow] {
        gameRows
    }

    nonisolated func fetchGamesForStandings(season: Int) async throws -> [SupabaseGameRow] {
        gameRows
    }

    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow] {
        gameRows
    }

    nonisolated func fetchGame(lookup: SupabaseGameLookup) async throws -> [SupabaseGameRow] {
        Array(gameRows.filter { row in
            switch lookup {
            case .providerGameID(let providerGameID):
                return row.providerGameID == providerGameID
            case .officialProviderGameID(let officialProviderGameID):
                return row.officialProviderGameID == officialProviderGameID
            case .publicGameID(let publicGameID):
                return row.publicGameID == publicGameID
            case .databaseID(let id):
                return row.id == id
            case .dateTeamIDs(let gameDate, let awayTeamID, let homeTeamID):
                return row.gameDate == gameDate &&
                    row.awayTeamID == awayTeamID &&
                    row.homeTeamID == homeTeamID
            case .dateTeamVenue(let gameDate, let awayTeamID, let homeTeamID, let stadium):
                return row.gameDate == gameDate &&
                    row.awayTeamID == awayTeamID &&
                    row.homeTeamID == homeTeamID &&
                    row.stadium == stadium
            }
        }.prefix(1))
    }

    nonisolated func fetchLatestSnapshots(gameIDs: [UUID]) async throws -> [SupabaseLatestGameSnapshotRow] {
        []
    }

    nonisolated func fetchLatestSnapshot(gameID: UUID) async throws -> SupabaseLatestGameSnapshotRow? {
        nil
    }
}

private actor DetailFetchTracker {
    private(set) var singleLookups: [SupabaseGameLookup] = []
    private(set) var dateFetches = 0
    private(set) var teamFetches = 0

    func recordSingleLookup(_ lookup: SupabaseGameLookup) {
        singleLookups.append(lookup)
    }

    func recordDateFetch() {
        dateFetches += 1
    }

    func recordTeamFetch() {
        teamFetches += 1
    }
}

private struct TrackingSupabaseSource: SupabaseKBOReading, Sendable {
    let teamRows: [SupabaseTeamRow]
    let gameRows: [SupabaseGameRow]
    let tracker: DetailFetchTracker

    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow] {
        await tracker.recordTeamFetch()
        return teamRows
    }

    nonisolated func fetchGameCount() async throws -> Int {
        gameRows.count
    }

    nonisolated func fetchGames() async throws -> [SupabaseGameRow] {
        gameRows
    }

    nonisolated func fetchGames(excludingProviderGameIDs providerGameIDs: Set<String>) async throws -> [SupabaseGameRow] {
        gameRows.filter { row in
            guard let providerGameID = row.providerGameID else { return true }
            return providerGameIDs.contains(providerGameID) == false
        }
    }

    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow] {
        gameRows
    }

    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow] {
        await tracker.recordDateFetch()
        return gameRows
    }

    nonisolated func fetchGames(date: Date, favoriteTeamID: String) async throws -> [SupabaseGameRow] {
        await tracker.recordDateFetch()
        return gameRows
    }

    nonisolated func fetchGamesForStandings(season: Int) async throws -> [SupabaseGameRow] {
        gameRows
    }

    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow] {
        gameRows
    }

    nonisolated func fetchGame(lookup: SupabaseGameLookup) async throws -> [SupabaseGameRow] {
        await tracker.recordSingleLookup(lookup)
        return Array(gameRows.filter { row in
            switch lookup {
            case .providerGameID(let providerGameID):
                return row.providerGameID == providerGameID
            case .officialProviderGameID(let officialProviderGameID):
                return row.officialProviderGameID == officialProviderGameID
            case .publicGameID(let publicGameID):
                return row.publicGameID == publicGameID
            case .databaseID(let id):
                return row.id == id
            case .dateTeamIDs(let gameDate, let awayTeamID, let homeTeamID):
                return row.gameDate == gameDate &&
                    row.awayTeamID == awayTeamID &&
                    row.homeTeamID == homeTeamID
            case .dateTeamVenue(let gameDate, let awayTeamID, let homeTeamID, let stadium):
                return row.gameDate == gameDate &&
                    row.awayTeamID == awayTeamID &&
                    row.homeTeamID == homeTeamID &&
                    row.stadium == stadium
            }
        }.prefix(1))
    }

    nonisolated func fetchLatestSnapshots(gameIDs: [UUID]) async throws -> [SupabaseLatestGameSnapshotRow] {
        []
    }

    nonisolated func fetchLatestSnapshot(gameID: UUID) async throws -> SupabaseLatestGameSnapshotRow? {
        nil
    }
}

private actor ScheduleSyncTestTracker {
    private(set) var remoteCountChecks = 0
    private(set) var missingFetches = 0
    private(set) var monthlyScheduleFetches = 0
    private(set) var dailyScheduleFetches = 0

    func recordRemoteCountCheck() {
        remoteCountChecks += 1
    }

    func recordMissingFetch() {
        missingFetches += 1
    }

    func recordMonthlyScheduleFetch() {
        monthlyScheduleFetches += 1
    }

    func recordDailyScheduleFetch() {
        dailyScheduleFetches += 1
    }
}

private struct ScheduleSyncTestRepository: KBORepository, KBOScheduleRemoteSyncDataSource, Sendable {
    let bootstrap: KBOBootstrapData
    let remoteCount: Int
    let missingGames: [GameDetail]
    let todayGames: [GameDetail]
    let tracker: ScheduleSyncTestTracker

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        bootstrap
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        bootstrap.games
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        bootstrap.notifications
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        await tracker.recordMonthlyScheduleFetch()
        return bootstrap.games.filter { game in
            KBOMonthScheduleKey(date: game.scheduledStart) == month
        }
    }

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        await tracker.recordDailyScheduleFetch()
        let calendar = Calendar(identifier: .gregorian)
        return todayGames.filter { calendar.isDate($0.scheduledStart, inSameDayAs: date) }
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await fetchSchedule(for: date)
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        []
    }

    nonisolated func fetchRemoteGameCount() async throws -> Int {
        await tracker.recordRemoteCountCheck()
        return remoteCount
    }

    nonisolated func fetchMissingScheduleGames(excludingKnownGames knownGames: [GameDetail]) async throws -> KBOScheduleMissingGamesResult {
        await tracker.recordMissingFetch()
        let knownAliases = Set(knownGames.flatMap(\.gameIdentityAliases))
        let missing = missingGames.filter { game in
            game.gameIdentityAliases.isDisjoint(with: knownAliases)
        }
        return KBOScheduleMissingGamesResult(remoteCount: remoteCount, games: missing)
    }
}

private struct FailingSupabaseSource: SupabaseKBOReading, Sendable {
    private let error = TestRepositoryError.supabaseUnavailable

    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow] {
        throw error
    }

    nonisolated func fetchGameCount() async throws -> Int {
        throw error
    }

    nonisolated func fetchGames() async throws -> [SupabaseGameRow] {
        throw error
    }

    nonisolated func fetchGames(excludingProviderGameIDs providerGameIDs: Set<String>) async throws -> [SupabaseGameRow] {
        throw error
    }

    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow] {
        throw error
    }

    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow] {
        throw error
    }

    nonisolated func fetchGames(date: Date, favoriteTeamID: String) async throws -> [SupabaseGameRow] {
        throw error
    }

    nonisolated func fetchGamesForStandings(season: Int) async throws -> [SupabaseGameRow] {
        throw error
    }

    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow] {
        throw error
    }

    nonisolated func fetchGame(lookup: SupabaseGameLookup) async throws -> [SupabaseGameRow] {
        throw error
    }

    nonisolated func fetchLatestSnapshots(gameIDs: [UUID]) async throws -> [SupabaseLatestGameSnapshotRow] {
        throw error
    }

    nonisolated func fetchLatestSnapshot(gameID: UUID) async throws -> SupabaseLatestGameSnapshotRow? {
        throw error
    }
}

private enum TestRepositoryError: Error, Sendable {
    case supabaseUnavailable
}

private actor RecordingBoxscoreState {
    private let result: Result<GameBoxscoreResponse, Error>
    private(set) var fetchCount = 0
    private(set) var requestedGameIDs: [String] = []

    init(result: Result<GameBoxscoreResponse, Error>) {
        self.result = result
    }

    func fetch(gameId: String) throws -> GameBoxscoreResponse {
        fetchCount += 1
        requestedGameIDs.append(gameId)
        return try result.get()
    }
}

private struct RecordingBoxscoreClient: GameBoxscoreFetching {
    let state: RecordingBoxscoreState
    var delayNanoseconds: UInt64 = 0
    var cacheIdentity: String = "recording"

    nonisolated func fetchGameBoxscore(gameId: String) async throws -> GameBoxscoreResponse {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try await state.fetch(gameId: gameId)
    }
}

private final class BoxscoreURLProtocolStub: URLProtocol, @unchecked Sendable {
    static var testResponses: [String: StubResponse] = [:]
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.port == 8088 && request.url?.path.hasSuffix("/boxscore") == true
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

private func makeBoxscoreStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BoxscoreURLProtocolStub.self]
    return URLSession(configuration: configuration)
}

private func sampleGameBoxscoreJSON() -> Data {
    Data(
        """
        {
          "gameId": "20260510-DOO-SSG",
          "awayBatters": [
            {
              "sourceOrder": 1,
              "battingOrder": 2,
              "position": "삼",
              "playerName": "허경민",
              "atBats": 3,
              "runs": 0,
              "hits": 1,
              "rbi": 0,
              "homeRuns": 0,
              "walks": 1,
              "strikeouts": 0,
              "stolenBases": 1,
              "battingAverage": "0.280"
            },
            {
              "sourceOrder": 0,
              "battingOrder": 1,
              "position": "중",
              "playerName": "정수빈",
              "atBats": 4,
              "runs": 1,
              "hits": 2,
              "rbi": 1,
              "homeRuns": null,
              "walks": null,
              "strikeouts": null,
              "stolenBases": null,
              "battingAverage": "0.300"
            }
          ],
          "homeBatters": [
            {
              "sourceOrder": 0,
              "battingOrder": 1,
              "position": "유",
              "playerName": "안상현",
              "atBats": 3,
              "runs": 1,
              "hits": 0,
              "rbi": 0,
              "homeRuns": null,
              "walks": null,
              "strikeouts": null,
              "stolenBases": null,
              "battingAverage": "0.300"
            }
          ],
          "awayPitchers": [
            {
              "sourceOrder": 0,
              "pitchingOrder": 1,
              "playerName": "잭로그",
              "appearance": "선발",
              "decisionResult": "승",
              "wins": 1,
              "losses": 0,
              "saves": 0,
              "inningsPitched": "6 1/3",
              "battersFaced": 24,
              "pitchCount": 88,
              "atBats": 22,
              "hits": 5,
              "homeRuns": 0,
              "walksOrHitByPitch": 1,
              "strikeouts": 6,
              "runs": 1,
              "earnedRuns": 1,
              "era": "3.19"
            }
          ],
          "homePitchers": [
            {
              "sourceOrder": 0,
              "pitchingOrder": 1,
              "playerName": "최민준",
              "appearance": "선발",
              "decisionResult": "패",
              "wins": 0,
              "losses": 1,
              "saves": 0,
              "inningsPitched": "2",
              "battersFaced": 12,
              "pitchCount": 46,
              "atBats": 8,
              "hits": 3,
              "homeRuns": 1,
              "walksOrHitByPitch": 3,
              "strikeouts": 0,
              "runs": 3,
              "earnedRuns": 2,
              "era": "3.23"
            }
          ],
          "updatedAt": "2026-05-11T02:04:00+09:00",
          "isStale": false
        }
        """.utf8
    )
}

private func makeBoxscoreDetailGame() throws -> GameDetail {
    let teams = MockKBOData.makeBootstrap().teams
    let doosan = try #require(teams.first(where: { $0.id == "doosan" }))
    let ssg = try #require(teams.first(where: { $0.id == "ssg" }))
    return makeGameDetail(
        id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        scheduledStart: isoDate("2026-05-10T14:00:00+09:00"),
        venue: "잠실",
        awayTeam: doosan,
        homeTeam: ssg,
        awayScore: 3,
        homeScore: 1,
        status: .final,
        note: "public_game_id=20260510-DOO-SSG provider_game_id=20260510SKOB0",
        providerGameID: "20260510SKOB0"
    )
}

private func makeIdentityLookupGame(
    id: UUID,
    publicGameID: String,
    providerGameID: String,
    officialProviderGameID: String?,
    scheduledStart: Date,
    awayTeamID: String = "lotte",
    homeTeamID: String = "kia"
) throws -> GameDetail {
    let teams = MockKBOData.makeBootstrap().teams
    let awayTeam = try #require(teams.first(where: { $0.id == awayTeamID }))
    let homeTeam = try #require(teams.first(where: { $0.id == homeTeamID }))
    let officialToken = officialProviderGameID.map { " official_provider_game_id=\($0)" } ?? ""
    return makeGameDetail(
        id: id,
        scheduledStart: scheduledStart,
        venue: "광주",
        awayTeam: awayTeam,
        homeTeam: homeTeam,
        awayScore: 4,
        homeScore: 3,
        status: .final,
        seasonClassification: .regularSeason,
        note: "public_game_id=\(publicGameID) provider_game_id=\(providerGameID)\(officialToken)",
        providerGameID: providerGameID
    )
}

private struct IdentityFallbackSupabaseFixture {
    let tracker: DetailFetchTracker
    let supabaseSource: TrackingSupabaseSource
}

private func makeIdentityFallbackSupabaseSource(
    publicGameID: String,
    providerGameID: String,
    officialProviderGameID: String?,
    awayCode: String,
    homeCode: String
) throws -> IdentityFallbackSupabaseFixture {
    let awayTeamID = supabaseTeamUUID(for: awayCode)
    let homeTeamID = supabaseTeamUUID(for: homeCode)
    let row = try makeSupabaseGameRow(
        id: GameIdentifier.uuid(from: publicGameID) ?? UUID(),
        publicGameID: publicGameID,
        providerGameID: providerGameID,
        officialProviderGameID: officialProviderGameID,
        gameDate: supabaseGameDate(from: publicGameID),
        scheduledAt: "\(supabaseGameDate(from: publicGameID))T18:30:00+09:00",
        stadium: "잠실",
        awayTeamID: awayTeamID,
        homeTeamID: homeTeamID,
        awayScore: 4,
        homeScore: 3,
        inningState: "Final"
    )
    let tracker = DetailFetchTracker()
    return IdentityFallbackSupabaseFixture(
        tracker: tracker,
        supabaseSource: TrackingSupabaseSource(
            teamRows: [
                supabaseTeamRow(code: awayCode, id: awayTeamID),
                supabaseTeamRow(code: homeCode, id: homeTeamID)
            ],
            gameRows: [row],
            tracker: tracker
        )
    )
}

private func supabaseTeamUUID(for code: String) -> UUID {
    switch code {
    case "lg":
        return UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    case "hanwha":
        return UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    case "lotte":
        return UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    case "kia":
        return UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    case "kiwoom":
        return UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    case "doosan":
        return UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    default:
        return GameIdentifier.uuid(from: code) ?? UUID()
    }
}

private func supabaseTeamRow(code: String, id: UUID) -> SupabaseTeamRow {
    switch code {
    case "lg":
        return SupabaseTeamRow(id: id, code: "lg", name: "LG 트윈스", shortName: "LG")
    case "hanwha":
        return SupabaseTeamRow(id: id, code: "hanwha", name: "한화 이글스", shortName: "한화")
    case "lotte":
        return SupabaseTeamRow(id: id, code: "lotte", name: "롯데 자이언츠", shortName: "롯데")
    case "kia":
        return SupabaseTeamRow(id: id, code: "kia", name: "KIA 타이거즈", shortName: "KIA")
    case "kiwoom":
        return SupabaseTeamRow(id: id, code: "kiwoom", name: "키움 히어로즈", shortName: "키움")
    case "doosan":
        return SupabaseTeamRow(id: id, code: "doosan", name: "두산 베어스", shortName: "두산")
    default:
        return SupabaseTeamRow(id: id, code: code, name: code, shortName: code.uppercased())
    }
}

private func supabaseGameDate(from publicGameID: String) -> String {
    let compactDate = String(publicGameID.prefix(8))
    guard compactDate.count == 8 else { return "2026-01-01" }
    let year = compactDate.prefix(4)
    let monthStart = compactDate.index(compactDate.startIndex, offsetBy: 4)
    let monthEnd = compactDate.index(compactDate.startIndex, offsetBy: 6)
    let month = compactDate[monthStart..<monthEnd]
    let day = compactDate.suffix(2)
    return "\(year)-\(month)-\(day)"
}

private func sampleGameCenterDetailPayload(game: GameDetail) -> GameCenterDetailPayload {
    GameCenterDetailPayload(
        summary: GameCenterSummary(
            officialGameID: game.officialGameCenterID ?? "20260510SKOB0",
            dateText: "2026-05-10",
            stadium: game.venue,
            startTime: "14:00",
            endTime: nil,
            durationText: nil,
            crowdText: nil,
            status: game.status,
            inningText: game.inningText,
            awayScore: game.awayScore,
            homeScore: game.homeScore,
            balls: game.balls,
            strikes: game.strikes,
            outs: game.outs,
            bases: game.bases,
            baseRunners: nil,
            probableStarters: nil,
            winningPitcher: nil,
            losingPitcher: nil,
            savePitcher: nil
        ),
        lineScore: nil,
        review: nil,
        preview: nil
    )
}

private actor RecordingNotificationRegistrationClient: NotificationRegistrationClient {
    private var payloads: [NotificationRegistrationPayload] = []

    nonisolated var debugEndpointDescription: String? {
        "https://example.com/devices/register"
    }

    nonisolated func syncRegistration(_ payload: NotificationRegistrationPayload) async throws -> NotificationRegistrationSyncStatus {
        await record(payload)
        return .synced
    }

    private func record(_ payload: NotificationRegistrationPayload) {
        payloads.append(payload)
    }

    func requestCount() -> Int {
        payloads.count
    }

    func favoriteTeamIDs() -> [String?] {
        payloads.map(\.favoriteTeamID)
    }
}

private func notificationRegistrationSettings(
    favoriteTeamID: String?,
    preferences: NotificationPreferences = NotificationPreferences()
) -> AppSettings {
    AppSettings(
        favoriteTeamID: favoriteTeamID,
        notificationPreferences: preferences,
        quietHours: QuietHours(isEnabled: false, startHour: 23, endHour: 7),
        liveActivitiesEnabled: true,
        appearance: .system,
        teamThemeMode: .favoriteTeam
    )
}

private func disabledNotificationPreferences() -> NotificationPreferences {
    NotificationPreferences(
        gameStart: false,
        scoreChange: false,
        leadChange: false,
        gameEnd: false,
        rainDelay: false,
        onBaseEnabled: false,
        inningChangeEnabled: false,
        favoriteTeamOnlyEnabled: false,
        muteWhenLosingEnabled: false
    )
}

private actor FavoriteScheduleCallRecorder {
    private var recordedFavoriteTeamIDs: [String] = []

    func record(favoriteTeamID: String) {
        recordedFavoriteTeamIDs.append(favoriteTeamID)
    }

    func callCount() -> Int {
        recordedFavoriteTeamIDs.count
    }

    func favoriteTeamIDs() -> [String] {
        recordedFavoriteTeamIDs
    }
}

private struct FavoriteScheduleCountingRepository: KBORepository, KBOFavoriteTeamScheduleDataSource {
    let recorder: FavoriteScheduleCallRecorder
    let base: StubRepository

    init(
        recorder: FavoriteScheduleCallRecorder,
        base: StubRepository = StubRepository()
    ) {
        self.recorder = recorder
        self.base = base
    }

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        try await base.fetchBootstrapData()
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await base.fetchGames()
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await base.fetchNotifications()
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await base.fetchMonthlySchedule(for: month)
    }

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date)
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

    nonisolated func fetchFavoriteTeamSchedule(
        date _: Date,
        favoriteTeamId: Team.ID,
        bypassingCache _: Bool
    ) async throws -> [GameDetail] {
        await recorder.record(favoriteTeamID: favoriteTeamId)
        return []
    }
}

private func eventually(
    timeout: TimeInterval,
    interval: UInt64 = 50_000_000,
    condition: @escaping () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: interval)
    }
    return await condition()
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
        return host == "example.com" || host == "www.koreabaseball.com" || host == "localhost"
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

private func jsonStringLiteral(_ value: String) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    return String(data: data, encoding: .utf8) ?? "\"\""
}

private func httpBodyData(from request: URLRequest) -> Data? {
    if let httpBody = request.httpBody {
        return httpBody
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data.isEmpty ? nil : data
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
    private(set) var snapshots: [FavoriteTeamLiveActivitySnapshot] = []

    init(isSupported: Bool) {
        self.isSupported = isSupported
    }

    func startOrUpdate(using snapshot: FavoriteTeamLiveActivitySnapshot) async throws {
        activeGameID = snapshot.gameID
        snapshots.append(snapshot)
    }

    func endCurrent() async {
        activeGameID = nil
    }
}

@MainActor
private final class NotificationRequestCollector {
    private(set) var requests: [UNNotificationRequest] = []

    func append(_ request: UNNotificationRequest) {
        requests.append(request)
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
    var fetchScheduleHandler: @Sendable (Date) async throws -> [GameDetail] = { _ in
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
        fetchSchedule: @escaping @Sendable (Date) async throws -> [GameDetail] = { _ in stubGames() },
        fetchStandings: @escaping @Sendable () async throws -> [TeamStandingsSnapshot] = { [] }
    ) {
        self.fetchBootstrapDataHandler = fetchBootstrapData
        self.fetchGamesHandler = fetchGames
        self.fetchNotificationsHandler = fetchNotifications
        self.fetchMonthlyScheduleHandler = fetchMonthlySchedule
        self.fetchScheduleHandler = fetchSchedule
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

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await fetchScheduleHandler(date)
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await fetchScheduleHandler(date)
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await fetchStandingsHandler()
    }
}

private struct DetailSnapshotStubRepository: KBORepository, KBOGameDetailSnapshotDataSource {
    let base: StubRepository
    let fetchGameDetailSnapshotHandler: @Sendable (GameDetail, String, [Team]) async throws -> GameDetail?

    init(
        base: StubRepository,
        fetchGameDetailSnapshot: @escaping @Sendable (GameDetail, String, [Team]) async throws -> GameDetail?
    ) {
        self.base = base
        self.fetchGameDetailSnapshotHandler = fetchGameDetailSnapshot
    }

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        try await base.fetchBootstrapData()
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await base.fetchGames()
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await base.fetchNotifications()
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await base.fetchMonthlySchedule(for: month)
    }

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date)
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

    nonisolated func fetchGameDetailSnapshot(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        try await fetchGameDetailSnapshotHandler(game, identity, cachedTeams)
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

private func previousKBOWeekStart(referenceDate: Date = Date()) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 1
    let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)!.start
    return calendar.date(byAdding: .day, value: -7, to: currentWeekStart)!
}

private func dateInKBOWeek(start weekStart: Date, dayOffset: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar.date(
        byAdding: DateComponents(day: dayOffset, hour: 18, minute: 30),
        to: weekStart
    )!
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
    inningText: String? = nil,
    note: String? = nil,
    providerGameID: String? = nil,
    awayStartingPitcherName: String? = nil,
    homeStartingPitcherName: String? = nil,
    bases: RunnerState? = nil,
    baseRunners: GameBaseRunners? = nil,
    balls: Int? = nil,
    strikes: Int? = nil,
    outs: Int? = nil,
    highlightText: String? = nil,
    currentPitcherName: String? = nil,
    currentBatterName: String? = nil
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
        inningText: inningText ?? status.title,
        bases: bases,
        baseRunners: baseRunners,
        balls: balls,
        strikes: strikes,
        outs: outs,
        highlightText: highlightText,
        events: [],
        note: note,
        providerGameID: providerGameID,
        awayStartingPitcherName: awayStartingPitcherName,
        homeStartingPitcherName: homeStartingPitcherName,
        currentPitcherName: currentPitcherName,
        currentBatterName: currentBatterName
    )
}

private func makeBaseRunnerDisplayGame(
    id: UUID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
    providerGameID: String = "20260506WOLT0",
    bases: RunnerState,
    baseRunners: GameBaseRunners?
) throws -> GameDetail {
    let teams = MockKBOData.makeBootstrap().teams
    let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
    let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
    return makeGameDetail(
        id: id,
        scheduledStart: isoDate("2026-05-06T18:30:00+09:00"),
        venue: "사직",
        awayTeam: awayTeam,
        homeTeam: homeTeam,
        awayScore: 0,
        homeScore: 1,
        status: .live,
        inningText: "3회 초",
        providerGameID: providerGameID,
        bases: bases,
        baseRunners: baseRunners,
        balls: 0,
        strikes: 0,
        outs: 0,
        currentPitcherName: "보쉴리",
        currentBatterName: "손성빈"
    )
}

private func makeSupabaseGameRow(
    id: UUID,
    publicGameID: String,
    providerGameID: String,
    officialProviderGameID: String? = nil,
    gameDate: String = "2026-04-28",
    scheduledAt: String = "2026-04-28T18:30:00+09:00",
    stadium: String = "사직",
    status: String = "live",
    awayTeamID: UUID,
    homeTeamID: UUID,
    awayScore: Int,
    homeScore: Int,
    inningState: String
) throws -> SupabaseGameRow {
    let resolvedOfficialProviderGameID = officialProviderGameID ?? providerGameID
    let payload = """
    [
      {
        "id": "\(id.uuidString)",
        "public_game_id": "\(publicGameID)",
        "provider": "kbo",
        "provider_game_id": "\(providerGameID)",
        "official_provider_game_id": "\(resolvedOfficialProviderGameID)",
        "game_date": "\(gameDate)",
        "scheduled_at": "\(scheduledAt)",
        "stadium": "\(stadium)",
        "status": "\(status)",
        "home_team_id": "\(homeTeamID.uuidString)",
        "away_team_id": "\(awayTeamID.uuidString)",
        "home_score": \(homeScore),
        "away_score": \(awayScore),
        "inning_state": "\(inningState)",
        "is_cancelled": false,
        "is_postponed": false,
        "source_updated_at": "2026-04-28T20:00:00+09:00",
        "updated_at": "2026-04-28T20:00:00+09:00"
      }
    ]
    """
    return try JSONDecoder().decode([SupabaseGameRow].self, from: Data(payload.utf8))[0]
}

@MainActor
private func makeStandingsSnapshot(
    team: Team,
    recentResults: [TeamGameResult]
) -> TeamStandingsSnapshot {
    TeamStandingsSnapshot(
        team: team,
        rank: 1,
        wins: recentResults.filter { $0 == .win }.count,
        losses: recentResults.filter { $0 == .loss }.count,
        ties: recentResults.filter { $0 == .tie }.count,
        remainingRegularSeasonGames: 0,
        recentResults: recentResults
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

private func makePairDeficitRegularSeasonSchedule(
    teams: [Team],
    gamesPerPair: Int,
    completedGamesPerPair: Int
) -> [GameDetail] {
    precondition(completedGamesPerPair <= gamesPerPair)
    var games: [GameDetail] = []
    var identifierIndex = 1

    for firstIndex in teams.indices {
        for secondIndex in teams.index(after: firstIndex)..<teams.endIndex {
            for pairGameIndex in 0..<gamesPerPair {
                let awayTeam = pairGameIndex.isMultiple(of: 2) ? teams[firstIndex] : teams[secondIndex]
                let homeTeam = pairGameIndex.isMultiple(of: 2) ? teams[secondIndex] : teams[firstIndex]
                let identifier = String(format: "67000000-0000-0000-0000-%012d", identifierIndex)
                let isCompleted = pairGameIndex < completedGamesPerPair
                games.append(
                    makeGameDetail(
                        id: UUID(uuidString: identifier)!,
                        scheduledStart: isoDate("2026-04-01T18:30:00+09:00"),
                        venue: "잠실",
                        awayTeam: awayTeam,
                        homeTeam: homeTeam,
                        awayScore: isCompleted ? 3 : nil,
                        homeScore: isCompleted ? 5 : nil,
                        status: isCompleted ? .final : .upcoming,
                        seasonClassification: .regularSeason,
                        note: isCompleted ? "db_export provider_game_id=2026PAIR\(identifierIndex)" : nil
                    )
                )
                identifierIndex += 1
            }
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
