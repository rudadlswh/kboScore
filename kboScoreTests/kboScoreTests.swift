//
//  kboScoreTests.swift
//  기능 설명: 전체 앱 동작을 검증하는 단위 테스트 모음을 담습니다.
//  회귀를 빠르게 찾고 핵심 사용자 흐름이 깨지지 않도록 테스트 의도를 코드 가까이에 둡니다.
//  테스트 데이터와 시뮬레이터 환경 차이에 따라 결과가 달라질 수 있어 고정 fixture와 명확한 대기 조건을 우선합니다.
//  TODO : 반복 실패가 발견되면 원인별 fixture와 경계 케이스를 보강합니다.
//  kboScoreTests
//
//  Created by 조경민 on 3/25/26.
//

import Foundation
import Testing
import UserNotifications
@testable import kboScore

// kboScoreTests 구조체는 kboScoreTests 타입의 역할과 값을 정의합니다.
@MainActor
struct kboScoreTests {

    // sseParserParsesSnapshotMessage 메서드는 SSE event/data/blank-line 형식의 snapshot 메시지를 해석하는지 검증합니다.
    @Test func sseParserParsesSnapshotMessage() throws {
        var parser = ServerSentEventParser()
        #expect(parser.parse(line: "event:snapshot\r").isEmpty)
        let events = parser.parse(line: #"data:{"publicGameId":"20260708-LOT-KIA","rawHash":"hash-1"}"#)
        #expect(events == [
            ServerSentEvent(
                event: "snapshot",
                data: #"{"publicGameId":"20260708-LOT-KIA","rawHash":"hash-1"}"#,
                id: nil
            )
        ])
        #expect(parser.parse(line: "\r").isEmpty)
    }

    // sseParserParsesHeartbeatMessage 메서드는 heartbeat 이벤트를 데이터 없이도 즉시 해석하는지 검증합니다.
    @Test func sseParserParsesHeartbeatMessage() throws {
        var parser = ServerSentEventParser()
        let events = parser.parse(line: "event:heartbeat\r")
        #expect(events == [ServerSentEvent(event: "heartbeat", data: "", id: nil)])
    }

    // homeSortingPrioritizesFavoriteTeamLiveGame 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func homeSortingPrioritizesFavoriteTeamLiveGame() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap())

        let games = model.filteredHomeGames

        #expect(games.count == 4)
        #expect(games.first?.isMyTeamGame == true)
        #expect(games.first?.status == .live)
        #expect(games.first?.homeTeam.id == "lg")
    }

    // homeContentStateSelectsExpectedDisplayBranch 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func homeContentStateSelectsExpectedDisplayBranch() throws {
        let bootstrap = MockKBOData.makeBootstrap()
        let game = try #require(bootstrap.games.first)
        let summary = game.summary(isMyTeamGame: false)
        let snapshot = TeamStandingsSnapshot(
            team: try #require(bootstrap.teams.first),
            rank: 1,
            wins: 1,
            losses: 0,
            ties: 0,
            remainingRegularSeasonGames: 143,
            recentResults: [.win]
        )

        if case .noGames = HomeContentState.make(
            todayGames: [],
            filteredGames: [],
            filteredGameDetails: [],
            fallbackTitle: "title",
            fallbackSubtitle: "subtitle",
            fallbackSnapshots: []
        ) {
        } else {
            Issue.record("Expected noGames")
        }

        if case let .fallbackStandings(title, subtitle, snapshots) = HomeContentState.make(
            todayGames: [],
            filteredGames: [],
            filteredGameDetails: [],
            fallbackTitle: "title",
            fallbackSubtitle: "subtitle",
            fallbackSnapshots: [snapshot]
        ) {
            #expect(title == "title")
            #expect(subtitle == "subtitle")
            #expect(snapshots == [snapshot])
        } else {
            Issue.record("Expected fallbackStandings")
        }

        if case .noFilteredGames = HomeContentState.make(
            todayGames: [game],
            filteredGames: [],
            filteredGameDetails: [],
            fallbackTitle: "title",
            fallbackSubtitle: "subtitle",
            fallbackSnapshots: [snapshot]
        ) {
        } else {
            Issue.record("Expected noFilteredGames")
        }

        if case let .games(games) = HomeContentState.make(
            todayGames: [game],
            filteredGames: [summary],
            filteredGameDetails: [game],
            fallbackTitle: "title",
            fallbackSubtitle: "subtitle",
            fallbackSnapshots: []
        ) {
            #expect(games.map(\.id) == [game.id])
        } else {
            Issue.record("Expected games")
        }
    }

    // homeHeroGamePresentationFormatsDisplayText 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func homeHeroGamePresentationFormatsDisplayText() throws {
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let liveSummary = GameSummary(
            id: UUID(uuidString: "93310000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 2,
            homeScore: 3,
            status: .final,
            inningText: "Top 3",
            recentEvent: nil,
            isMyTeamGame: false,
            awayStartingPitcherName: " ",
            homeStartingPitcherName: "임찬규",
            currentPitcherName: nil,
            currentBatterName: nil,
            bases: RunnerState(first: true, second: false, third: true),
            baseRunners: nil,
            balls: 4,
            strikes: 3,
            outs: 2
        )

        #expect(HomeHeroGamePresentation.timeText(for: liveSummary) == "3회 초")
        #expect(HomeHeroGamePresentation.venueText(for: liveSummary) == "잠실 · 서울")
        #expect(HomeHeroGamePresentation.countText(for: liveSummary) == "B 3 S 2 O 2")
        #expect(HomeHeroGamePresentation.basesText(for: liveSummary) == "1루 3루")
        #expect(HomeHeroGamePresentation.pitcherText(liveSummary.awayStartingPitcherName) == "선발 미정")
        #expect(HomeHeroGamePresentation.accessibilityLabel(for: liveSummary).contains("원정 선발 선발 미정"))

        let unknownVenueSummary = GameSummary(
            id: UUID(uuidString: "93310000-0000-0000-0000-000000000002")!,
            scheduledStart: isoDate("2026-04-28T18:30:00+09:00"),
            venue: "  ",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            inningText: nil,
            recentEvent: nil,
            isMyTeamGame: false,
            awayStartingPitcherName: nil,
            homeStartingPitcherName: nil,
            currentPitcherName: nil,
            currentBatterName: nil,
            bases: nil,
            baseRunners: nil,
            balls: nil,
            strikes: nil,
            outs: nil
        )

        #expect(HomeHeroGamePresentation.venueText(for: unknownVenueSummary) == "장소 미정")
        #expect(HomeHeroGamePresentation.countText(for: unknownVenueSummary) == nil)
        #expect(HomeHeroGamePresentation.basesText(for: unknownVenueSummary) == nil)
    }

    // gameMergeResolverUsesPublicGameIDBeforeWeakerIdentities 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameMergeResolverUsesPublicGameIDBeforeWeakerIdentities() throws {
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let existing = makeGameDetail(
            id: UUID(uuidString: "99010000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-05-01T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            note: "public_game_id=public-win",
            providerGameID: "existing-provider"
        )
        let providerOnly = makeGameDetail(
            id: UUID(uuidString: "99010000-0000-0000-0000-000000000002")!,
            scheduledStart: isoDate("2026-05-02T18:30:00+09:00"),
            venue: "광주",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 9,
            homeScore: 8,
            status: .final,
            providerGameID: "public-win"
        )
        let publicMatch = makeGameDetail(
            id: UUID(uuidString: "99010000-0000-0000-0000-000000000003")!,
            scheduledStart: isoDate("2026-05-01T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 3,
            status: .final,
            note: "public_game_id=public-win updated_at=2026-05-01T15:00:00Z",
            providerGameID: "updated-provider"
        )

        let equivalent = try #require(GameMergeResolver.equivalentGame(to: existing, in: [providerOnly, publicMatch]))
        let selected = try #require(SelectedGameResolver.match(for: "public-win", in: [providerOnly, existing, publicMatch])?.game)

        #expect(equivalent.id == publicMatch.id)
        #expect(selected.status == .final)
        #expect(selected.awayScore == 4)
        #expect(selected.providerGameID == "updated-provider")
    }

    // gameMergeResolverMatchesProviderDatabaseAndStableIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameMergeResolverMatchesProviderDatabaseAndStableIdentity() throws {
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kia" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "hanwha" }))
        let game = makeGameDetail(
            id: UUID(uuidString: "99010000-0000-0000-0000-000000000011")!,
            scheduledStart: isoDate("2026-05-03T14:00:00+09:00"),
            venue: "대전",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 5,
            homeScore: 2,
            status: .final,
            providerGameID: "provider-113"
        )
        let stableOnlyGame = makeGameDetail(
            id: UUID(uuidString: "99010000-0000-0000-0000-000000000012")!,
            scheduledStart: isoDate("2026-05-05T14:00:00+09:00"),
            venue: "대전",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )

        #expect(SelectedGameResolver.match(for: "provider:provider-113", in: [game])?.game.id == game.id)
        #expect(SelectedGameResolver.match(for: game.id.uuidString, in: [game])?.game.id == game.id)
        #expect(SelectedGameResolver.match(for: stableOnlyGame.stableDetailIdentity, in: [stableOnlyGame])?.game.id == stableOnlyGame.id)
    }

    // selectedGameResolverUsesBestEquivalentCandidateAndTransitiveAliases 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    @Test func selectedGameResolverUsesBestEquivalentCandidateAndTransitiveAliases() throws {
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let scheduledShell = makeGameDetail(
            id: UUID(uuidString: "99010000-0000-0000-0000-000000000021")!,
            scheduledStart: isoDate("2026-05-04T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            note: "public_game_id=chain-public"
        )
        let bridge = makeGameDetail(
            id: UUID(uuidString: "99010000-0000-0000-0000-000000000022")!,
            scheduledStart: isoDate("2026-05-04T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 1,
            homeScore: 1,
            status: .final,
            providerGameID: "chain-provider"
        )
        let officialFinal = makeGameDetail(
            id: UUID(uuidString: "99010000-0000-0000-0000-000000000023")!,
            scheduledStart: isoDate("2026-05-04T18:35:00+09:00"),
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 7,
            homeScore: 6,
            status: .final,
            providerGameID: "chain-provider"
        )

        let match = try #require(SelectedGameResolver.match(for: "public:chain-public", in: [scheduledShell, bridge, officialFinal]))

        #expect(match.reason == "publicGameID")
        #expect(match.game.status == .final)
        #expect(match.game.awayScore == 7)
        #expect(match.game.providerGameID == "chain-provider")
    }

    // scheduleDateKeyFormatterUsesKSTDayBoundary 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleDateKeyFormatterUsesKSTDayBoundary() throws {
        #expect(ScheduleDateKeyFormatter.dayKey(for: isoDate("2026-04-30T14:59:59Z")) == "2026-04-30")
        #expect(ScheduleDateKeyFormatter.dayKey(for: isoDate("2026-04-30T15:00:00Z")) == "2026-05-01")
        #expect(ScheduleDateKeyFormatter.dayKey(for: isoDate("2026-05-01T14:59:59Z")) == "2026-05-01")
    }

    // teamCanonicalIDRecognizesAppAliases 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func teamCanonicalIDRecognizesAppAliases() throws {
        #expect(Team.canonicalID(for: "LG") == "lg")
        #expect(Team.canonicalID(for: "KT 위즈") == "kt")
        #expect(Team.canonicalID(for: "KIA 타이거즈") == "kia")
        #expect(Team.canonicalID(for: "두산 베어스") == "doosan")
        #expect(Team.canonicalID(for: "DOO") == "doosan")
        #expect(Team.canonicalID(for: "OB") == "doosan")
        #expect(Team.canonicalID(for: "HAN") == "hanwha")
        #expect(Team.canonicalID(for: "SAM") == "samsung")
        #expect(Team.canonicalID(for: "LOT") == "lotte")
        #expect(Team.canonicalID(for: "KIW") == "kiwoom")
    }

    @Test func koreanTeamDisplayFieldsNormalizeFromEnglishInputs() throws {
        let cases = [
            ("samsung", "Samsung Lions", "SAM", "삼성 라이온즈", "삼성"),
            ("doosan", "Doosan Bears", "DOO", "두산 베어스", "두산"),
            ("hanwha", "Hanwha Eagles", "HAN", "한화 이글스", "한화"),
            ("lotte", "Lotte Giants", "LOT", "롯데 자이언츠", "롯데"),
            ("kiwoom", "Kiwoom Heroes", "KIW", "키움 히어로즈", "키움")
        ]

        for (id, name, shortName, expectedName, expectedShortName) in cases {
            let team = Team(
                id: id,
                name: name,
                shortName: shortName,
                englishName: name,
                markText: shortName
            )

            #expect(team.name == expectedName)
            #expect(team.shortName == expectedShortName)
            #expect(team.displayName == expectedShortName)
            #expect(team.markText == expectedShortName)
        }
    }

    // homeFavoriteGameRefreshPolicyPreservesRecentRefreshThrottle 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func homeFavoriteGameRefreshPolicyPreservesRecentRefreshThrottle() throws {
        let now = isoDate("2026-06-09T12:00:00+09:00")
        let recentRefresh = now.addingTimeInterval(-14)
        let staleRefresh = now.addingTimeInterval(-15)

        #expect(HomeFavoriteGameRefreshPolicy.shouldThrottleRecentRefresh(reason: "foreground") == true)
        #expect(HomeFavoriteGameRefreshPolicy.shouldThrottleRecentRefresh(reason: "homeRefresh") == false)
        #expect(HomeFavoriteGameRefreshPolicy.shouldThrottleRecentRefresh(reason: "favoriteTeamSelected") == false)
        #expect(HomeFavoriteGameRefreshPolicy.shouldThrottleRecentRefresh(reason: "sceneBackground") == false)
        #expect(HomeFavoriteGameRefreshPolicy.shouldThrottleRecentRefresh(reason: "backgroundTask") == false)

        #expect(HomeFavoriteGameRefreshPolicy.shouldSkipRecentRefresh(
            reason: "foreground",
            lastRefreshedAt: recentRefresh,
            now: now
        ) == true)
        #expect(HomeFavoriteGameRefreshPolicy.shouldSkipRecentRefresh(
            reason: "foreground",
            lastRefreshedAt: staleRefresh,
            now: now
        ) == false)
        #expect(HomeFavoriteGameRefreshPolicy.shouldSkipRecentRefresh(
            reason: "homeRefresh",
            lastRefreshedAt: recentRefresh,
            now: now
        ) == false)
        #expect(HomeFavoriteGameRefreshPolicy.shouldSkipRecentRefresh(
            reason: "foreground",
            lastRefreshedAt: nil,
            now: now
        ) == false)
    }

    // countDisplayNormalizesTransitionalValues 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func countDisplayNormalizesTransitionalValues() throws {
        #expect(KBOCountDisplay.balls(4) == 3)
        #expect(KBOCountDisplay.strikes(3) == 2)
        #expect(KBOCountDisplay.outs(3) == 2)
        #expect(KBOCountDisplay.balls(-1) == 0)
        #expect(KBOCountDisplay.strikes(nil) == nil)
    }

    // inningFormatterUsesKoreanBaseballNotation 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func inningFormatterUsesKoreanBaseballNotation() throws {
        #expect(KBOInningFormatter.korean("Top 1") == "1회 초")
        #expect(KBOInningFormatter.korean("Bottom 10") == "10회 말")
        #expect(KBOInningFormatter.korean("7회초") == "7회 초")
        #expect(KBOInningFormatter.korean(nil) == nil)
    }

    // gameDetailOnlyExposesOverviewSection 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailOnlyExposesOverviewSection() throws {
        for status in GameStatus.allCases {
            #expect(GameDetailSection.availableSections(for: status) == [.overview])
        }
    }

    // gameDetailOverviewUsesPreviewOnlyBeforeGame 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailOverviewUsesPreviewOnlyBeforeGame() throws {
        #expect(GameDetailOverviewContentKind.contentKind(for: .upcoming) == .preview)
        #expect(GameDetailOverviewContentKind.contentKind(for: .live) == .overview)
        #expect(GameDetailOverviewContentKind.contentKind(for: .rainDelay) == .overview)
        #expect(GameDetailOverviewContentKind.contentKind(for: .final) == .overview)
        #expect(GameDetailOverviewContentKind.contentKind(for: .cancelled) == .overview)
    }

    @Test func liveActivityAutoStartRejectsRainDelay() throws {
        let now = isoDate("2026-06-25T18:35:00+09:00")

        #expect(LiveActivityAutoStartEligibility.decision(
            status: .rainDelay,
            scheduledAt: isoDate("2026-06-25T18:30:00+09:00"),
            now: now
        ) == .delayed)
        #expect(LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
            status: .rainDelay,
            scheduledAt: isoDate("2026-06-25T18:30:00+09:00"),
            now: now
        ) == false)
        #expect(LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
            status: .final,
            scheduledAt: isoDate("2026-06-25T18:30:00+09:00"),
            now: now
        ) == true)
    }

    // homeSummaryUsesStartingPitchersFromSupabaseRows 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // refreshHomeUpsertsTodaySchedulePitchersIntoLocalGames 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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

    // refreshHomeDoesNotEraseExistingPitchersWhenTodayScheduleHasNilPitchers 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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

    // todayRefreshUpdatesExistingScheduledGameToLiveScoreAndInning 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // localMonthCacheDoesNotOverwriteTodayLiveStatus 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // todayOnlyScheduleRefreshPreservesOtherMonthGames 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // detailLookupResolvesLatestMatchingGameInsteadOfStaleSelectedID 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailViewModelRefreshesSelectedGameWithoutFetchingAllGames 메서드는 이 타입의 주요 동작을 수행합니다.
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
        let standingsRevisionBeforeRefresh = model.standingsRowsRevision

        let refreshed = await viewModel.refreshIfNeeded(appModel: model, bypassAutomaticThrottle: true)

        #expect(await detailFetchCounter.value == 1)
        #expect(await allGamesFetchCounter.value == 0)
        #expect(model.standingsRowsRevision == standingsRevisionBeforeRefresh)
        #expect(refreshed?.status == .live)
        #expect(refreshed?.currentBatterName == "홍길동")
        #expect(refreshed?.currentPitcherName == "김투수")
    }

    // supabaseGameRowDecodesWithoutOfficialProviderGameID 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseMapperPreservesScheduledAndOfficialProviderIdentifiers 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseLatestSnapshotMapsCurrentBatterAndPitcherFields 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseLatestSnapshotDecodesBaseRunnerNames 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseSnapshotRunnerNameMapsIntoGameDetailWhenBaseIsOccupied 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseSnapshotWithOccupiedBaseAndNilRunnerNameKeepsFallbackState 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // baseRunnerDisplayUsesSnapshotNameWhenFirstBaseOccupied 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // baseRunnerDisplayFallsBackForOccupiedFirstBaseWithNilName 메서드는 이 타입의 주요 동작을 수행합니다.
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

        let presentation = GameDetailPresentation(
            game: game,
            payload: nil,
            boxscore: nil,
            baseRunnerDisplay: display
        )
        #expect(presentation.displayBaseRunners == [BaseRunnerDisplayItem(base: "1B", name: "점유")])
    }

    // baseRunnerDisplayCarriesForwardSameBaseName 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // baseRunnerDisplayClearsNameWhenBaseEmpties 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // baseRunnerDisplayStateIsKeyedByGameIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // baseRunnerDisplaySnapshotNameOverridesPriorFallback 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // baseRunnerDisplayResolvesMultipleBasesIndependently 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // baseRunnerDisplayDoesNotCopyFirstRunnerNameToUnknownThirdBase 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // baseRunnerDisplayKeepsEmptyBasesHidden 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // baseRunnerDisplayShowsAllThreeOccupiedBaseNames 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailBaseSituationShowsOccupiedSecondBaseRunnerName 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailBaseSituationShowsOccupiedSecondBaseRunnerName() throws {
        var resolver = BaseRunnerDisplayResolver()
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: false, second: true, third: false),
            baseRunners: GameBaseRunners(first: nil, second: "홍창기", third: nil)
        )
        let resolvedDisplay = resolver.resolve(gameIdentity: game.stableDetailIdentity, game: game)
        let presentation = GameDetailPresentation(
            game: game,
            payload: nil,
            boxscore: nil,
            baseRunnerDisplay: resolvedDisplay
        )

        #expect(resolvedDisplay.runners.second == "홍창기")
        #expect(presentation.displayBaseRunners == [BaseRunnerDisplayItem(base: "2B", name: "홍창기")])
    }

    // gameDetailBaseSituationShowsOccupiedBaseRunnerNames 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailBaseSituationShowsOccupiedBaseRunnerNames() throws {
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: true, third: true),
            baseRunners: GameBaseRunners(first: "정수빈", second: "홍창기", third: "오스틴")
        )
        let presentation = GameDetailPresentation(
            game: game,
            payload: nil,
            boxscore: nil,
            baseRunnerDisplay: BaseRunnerDisplayResolution(
                runners: GameBaseRunners(first: "정수빈", second: "홍창기", third: "오스틴"),
                source: "snapshot"
            )
        )

        #expect(presentation.displayBaseRunners == [
            BaseRunnerDisplayItem(base: "1B", name: "정수빈"),
            BaseRunnerDisplayItem(base: "2B", name: "홍창기"),
            BaseRunnerDisplayItem(base: "3B", name: "오스틴")
        ])
    }

    // gameDetailBaseSituationKeepsEmptyBasesEmptyWhenNamesAreShown 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailBaseSituationKeepsEmptyBasesEmptyWhenNamesAreShown() throws {
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: false, second: true, third: false),
            baseRunners: GameBaseRunners(first: "정수빈", second: "홍창기", third: "오스틴")
        )
        let presentation = GameDetailPresentation(
            game: game,
            payload: nil,
            boxscore: nil,
            baseRunnerDisplay: BaseRunnerDisplayResolution(
                runners: GameBaseRunners(first: "정수빈", second: "홍창기", third: "오스틴"),
                source: "snapshot"
            )
        )

        #expect(presentation.displayBaseRunners == [BaseRunnerDisplayItem(base: "2B", name: "홍창기")])
    }

    // gameDetailBaseSituationRendersSnapshotRunnerNameInsteadOfOccupiedFallback 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailBaseSituationRendersSnapshotRunnerNameInsteadOfOccupiedFallback() throws {
        var resolver = BaseRunnerDisplayResolver()
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "이유찬", second: nil, third: nil)
        )
        let resolvedDisplay = resolver.resolve(gameIdentity: game.stableDetailIdentity, game: game)
        let presentation = GameDetailPresentation(
            game: game,
            payload: nil,
            boxscore: nil,
            baseRunnerDisplay: resolvedDisplay
        )

        #expect(presentation.displayBaseRunners == [BaseRunnerDisplayItem(base: "1B", name: "이유찬")])
    }

    // gameDetailBaseSituationAppliesOfficialMappedRunnerNamesAfterInitialFallback 메서드는 live 주자상황에서 official 이름을 차단하는지 검증합니다.
    @Test func gameDetailBaseSituationAppliesOfficialMappedRunnerNamesAfterInitialFallback() throws {
        var resolver = BaseRunnerDisplayResolver()
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: false, second: true, third: true),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )
        let fallbackDisplay = resolver.resolve(gameIdentity: game.stableDetailIdentity, game: game)
        let officialPayload = sampleGameCenterDetailPayload(
            game: game,
            baseRunners: GameCenterBaseRunners(first: nil, second: "김주원", third: "최정원")
        )

        let presentation = GameDetailPresentation(
            game: game,
            payload: officialPayload,
            boxscore: nil,
            baseRunnerDisplay: fallbackDisplay
        )

        #expect(fallbackDisplay.runners.second == "주자")
        #expect(fallbackDisplay.runners.third == "주자")
        #expect(presentation.displayBaseRunners == [
            BaseRunnerDisplayItem(base: "2B", name: "점유"),
            BaseRunnerDisplayItem(base: "3B", name: "점유")
        ])
        #expect(presentation.baseRunnerDisplay.source == "latestSnapshotOnly")
    }

    // gameDetailBaseSituationOfficialMappedAdvanceDoesNotReuseLowerBaseCache 메서드는 live 주자상황에서 cache/official 이름을 재사용하지 않는지 검증합니다.
    @Test func gameDetailBaseSituationOfficialMappedAdvanceDoesNotReuseLowerBaseCache() throws {
        var resolver = BaseRunnerDisplayResolver()
        let before = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: true, third: false),
            baseRunners: GameBaseRunners(first: "레이예스", second: "고승민", third: nil)
        )
        _ = resolver.resolve(gameIdentity: before.stableDetailIdentity, game: before)

        let after = try makeBaseRunnerDisplayGame(
            id: before.id,
            providerGameID: before.providerGameID ?? "20260506WOLT0",
            bases: RunnerState(first: false, second: true, third: true),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )
        let cachedDisplay = resolver.resolve(gameIdentity: after.stableDetailIdentity, game: after)
        let officialPayload = sampleGameCenterDetailPayload(
            game: after,
            baseRunners: GameCenterBaseRunners(first: nil, second: "레이예스", third: "고승민")
        )

        let presentation = GameDetailPresentation(
            game: after,
            payload: officialPayload,
            boxscore: nil,
            baseRunnerDisplay: cachedDisplay
        )

        #expect(presentation.displayBaseRunners == [
            BaseRunnerDisplayItem(base: "2B", name: "점유"),
            BaseRunnerDisplayItem(base: "3B", name: "점유")
        ])
        #expect(presentation.displayBaseRunners != [
            BaseRunnerDisplayItem(base: "2B", name: "고승민"),
            BaseRunnerDisplayItem(base: "3B", name: "고승민")
        ])
        #expect(presentation.baseRunnerDisplay.runners.first == nil)
        #expect(presentation.baseRunnerDisplay.runners.second == nil)
        #expect(presentation.baseRunnerDisplay.runners.third == nil)
        #expect(presentation.baseRunnerDisplay.source == "latestSnapshotOnly")
    }

    // gameDetailBaseSituationDoesNotHideCurrentBatterOrPitcher 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailBaseSituationDoesNotHideCurrentBatterOrPitcher() throws {
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: false, second: true, third: false),
            baseRunners: GameBaseRunners(first: nil, second: "홍창기", third: nil)
        )
        let presentation = GameDetailPresentation(
            game: game,
            payload: nil,
            boxscore: nil,
            baseRunnerDisplay: .empty
        )

        #expect(presentation.currentBatterName == "손성빈")
        #expect(presentation.currentPitcherName == "보쉴리")
    }

    // gameDetailRefreshClearsExistingRunnerNameWhenSnapshotNameMissing 메서드는 live snapshot에 이름이 없으면 기존 이름을 유지하지 않는지 검증합니다.
    @MainActor
    @Test func gameDetailRefreshClearsExistingRunnerNameWhenSnapshotNameMissing() async throws {
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

        #expect(refreshed?.baseRunners?.first == nil)
    }

    // gameDetailRefreshRecoversUnconfirmedFinalWhenIncomingLiveIsNewer 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    @Test func gameDetailRefreshRecoversUnconfirmedFinalWhenIncomingLiveIsNewer() async throws {
        let referenceDate = isoDate("2026-05-19T21:20:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "hanwha" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let existing = makeGameDetail(
            id: UUID(uuidString: "20260519-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-05-19T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 6,
            status: .final,
            seasonClassification: .regularSeason,
            inningText: "경기 종료",
            note: "public_game_id=20260519-HAN-LOT provider_game_id=20260519LTHH0 updated_at=2026-05-19T21:00:00+09:00",
            providerGameID: "20260519LTHH0"
        )
        let incoming = makeGameDetail(
            id: UUID(uuidString: "20260519-0000-0000-0000-000000000002")!,
            scheduledStart: existing.scheduledStart,
            venue: existing.venue,
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 6,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Bottom 9",
            note: "public_game_id=20260519-HAN-LOT provider_game_id=20260519LTHH0 live_last_checked_at=2026-05-19T21:10:00+09:00 updated_at=2026-05-19T21:10:00+09:00",
            providerGameID: "20260519LTHH0",
            balls: 1,
            strikes: 2,
            outs: 1,
            currentPitcherName: "최준용",
            currentBatterName: "황영묵"
        )
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [existing], notifications: [], settings: .default)
            }),
            fetchGameDetailSnapshot: { _, _, _ in incoming }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [existing], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        let refreshed = try #require(await model.refreshGameDetail(for: existing.canonicalGameIdentityValue, forceRefresh: true))

        #expect(refreshed.status == .live)
        #expect(refreshed.inningText == "Bottom 9")
        #expect(refreshed.currentPitcherName == "최준용")
        #expect(refreshed.currentBatterName == "황영묵")
    }

    // gameDetailRefreshRecoversUnconfirmedFinalFromLiveLikeSnapshotWithoutFreshness 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    @Test func gameDetailRefreshRecoversUnconfirmedFinalFromLiveLikeSnapshotWithoutFreshness() async throws {
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "hanwha" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let existing = makeGameDetail(
            id: UUID(uuidString: "20260519-0000-0000-0000-000000000003")!,
            scheduledStart: isoDate("2026-05-19T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 6,
            status: .final,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260519-HAN-LOT provider_game_id=20260519LTHH0",
            providerGameID: "20260519LTHH0"
        )
        let incoming = makeGameDetail(
            id: UUID(uuidString: "20260519-0000-0000-0000-000000000004")!,
            scheduledStart: existing.scheduledStart,
            venue: existing.venue,
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 6,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Bottom 9",
            note: "public_game_id=20260519-HAN-LOT provider_game_id=20260519LTHH0",
            providerGameID: "20260519LTHH0",
            balls: 0,
            strikes: 1,
            outs: 1,
            currentPitcherName: "최준용",
            currentBatterName: "황영묵"
        )
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [existing], notifications: [], settings: .default)
            }),
            fetchGameDetailSnapshot: { _, _, _ in incoming }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [existing], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let refreshed = try #require(await model.refreshGameDetail(for: existing.canonicalGameIdentityValue, forceRefresh: true))

        #expect(refreshed.status == .live)
        #expect(refreshed.inningText == "Bottom 9")
    }

    // gameDetailRefreshKeepsConfirmedFinalWhenIncomingLiveIsOlder 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    @Test func gameDetailRefreshKeepsConfirmedFinalWhenIncomingLiveIsOlder() async throws {
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "hanwha" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let existing = makeGameDetail(
            id: UUID(uuidString: "20260519-0000-0000-0000-000000000005")!,
            scheduledStart: isoDate("2026-05-19T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 6,
            status: .final,
            seasonClassification: .regularSeason,
            inningText: "경기 종료",
            note: "public_game_id=20260519-HAN-LOT provider_game_id=20260519LTHH0 updated_at=2026-05-19T21:10:00+09:00 final_confirmed_at=2026-05-19T21:10:00+09:00",
            providerGameID: "20260519LTHH0"
        )
        let incoming = makeGameDetail(
            id: UUID(uuidString: "20260519-0000-0000-0000-000000000006")!,
            scheduledStart: existing.scheduledStart,
            venue: existing.venue,
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 6,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Bottom 9",
            note: "public_game_id=20260519-HAN-LOT provider_game_id=20260519LTHH0 updated_at=2026-05-19T21:00:00+09:00",
            providerGameID: "20260519LTHH0",
            currentPitcherName: "최준용",
            currentBatterName: "황영묵"
        )
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [existing], notifications: [], settings: .default)
            }),
            fetchGameDetailSnapshot: { _, _, _ in incoming }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [existing], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let refreshed = try #require(await model.refreshGameDetail(for: existing.canonicalGameIdentityValue, forceRefresh: true))

        #expect(refreshed.status == .final)
        #expect(refreshed.inningText == "경기 종료")
    }

    // liveActivityAutoStartUsesRecoveredLiveStateAfterFalseFinalMerge 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    @Test func liveActivityAutoStartUsesRecoveredLiveStateAfterFalseFinalMerge() async throws {
        let controller = TestLiveActivityController(isSupported: true)
        let referenceDate = isoDate("2026-05-19T21:10:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "hanwha" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let existing = makeGameDetail(
            id: UUID(uuidString: "20260519-0000-0000-0000-000000000007")!,
            scheduledStart: isoDate("2026-05-19T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 6,
            status: .final,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260519-HAN-LOT provider_game_id=20260519LTHH0 updated_at=2026-05-19T21:00:00+09:00",
            providerGameID: "20260519LTHH0"
        )
        let incoming = makeGameDetail(
            id: UUID(uuidString: "20260519-0000-0000-0000-000000000008")!,
            scheduledStart: existing.scheduledStart,
            venue: existing.venue,
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 6,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Bottom 9",
            note: "public_game_id=20260519-HAN-LOT provider_game_id=20260519LTHH0 updated_at=2026-05-19T21:10:00+09:00",
            providerGameID: "20260519LTHH0",
            balls: 1,
            strikes: 2,
            outs: 1,
            currentPitcherName: "최준용",
            currentBatterName: "황영묵"
        )
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [existing], notifications: [], settings: .default)
            }),
            fetchGameDetailSnapshot: { _, _, _ in incoming }
        )
        let model = AppModel(
            repository: repository,
            liveActivityController: controller,
            bootstrap: KBOBootstrapData(teams: teams, games: [existing], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        model.settings.favoriteTeamID = "lotte"
        model.settings.liveActivitiesEnabled = true

        let refreshed = try #require(await model.refreshGameDetail(for: existing.canonicalGameIdentityValue, forceRefresh: true))
        await model.startOrUpdateLiveActivityIfNeeded(for: refreshed)

        #expect(refreshed.status == .live)
        #expect(controller.snapshots.count == 1)
        #expect(model.isLiveActivityOn(for: refreshed.id))
    }

    // gameLookupResolvesProviderStableIdentityAndPublicRawID 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameLookupResolvesOfficialAndScheduledProviderIdentities 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameLookupResolvesRawOfficialProviderIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameLookupKeepsKnownScheduledProviderStableIdentityWorking 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // scheduleMonthSnapshotMergesTransitiveProviderAliases 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleMonthSnapshotMergesTransitiveProviderAliases() throws {
        let teams = MockKBOData.makeBootstrap().teams
        let kt = try #require(teams.first(where: { $0.id == "kt" }))
        let hanwha = try #require(teams.first(where: { $0.id == "hanwha" }))
        let scheduledProviderID = "sched-202605101830-kt-hanwha"
        let officialProviderID = "20260510KTHH0"
        let scheduledStart = isoDate("2026-05-10T18:30:00+09:00")
        let finalStart = isoDate("2026-05-11T18:30:00+09:00")
        let scheduledShell = makeGameDetail(
            id: UUID(uuidString: "15151515-1515-1515-1515-151515151501")!,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            providerGameID: scheduledProviderID
        )
        let officialFinal = makeGameDetail(
            id: UUID(uuidString: "15151515-1515-1515-1515-151515151502")!,
            scheduledStart: finalStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: 6,
            homeScore: 4,
            status: .final,
            providerGameID: officialProviderID
        )
        let bridge = makeGameDetail(
            id: UUID(uuidString: "15151515-1515-1515-1515-151515151503")!,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: 2,
            homeScore: 1,
            status: .live,
            note: "official_provider_game_id=\(officialProviderID)",
            providerGameID: scheduledProviderID
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: teams, games: [scheduledShell, officialFinal, bridge], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let snapshot = model.currentScheduleMonthSnapshot(for: KBOMonthScheduleKey(date: scheduledStart))

        #expect(snapshot.count == 1)
        #expect(snapshot.first?.status == .final)
        #expect(snapshot.first?.awayScore == 6)
        #expect(snapshot.first?.homeScore == 4)
    }

    // gameLookupUsesTransitiveProviderAliasesForSelectedDetailMatch 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameLookupUsesTransitiveProviderAliasesForSelectedDetailMatch() throws {
        let teams = MockKBOData.makeBootstrap().teams
        let kt = try #require(teams.first(where: { $0.id == "kt" }))
        let hanwha = try #require(teams.first(where: { $0.id == "hanwha" }))
        let scheduledProviderID = "sched-202605101830-kt-hanwha"
        let officialProviderID = "20260510KTHH0"
        let scheduledStart = isoDate("2026-05-10T18:30:00+09:00")
        let finalStart = isoDate("2026-05-11T18:30:00+09:00")
        let scheduledShell = makeGameDetail(
            id: UUID(uuidString: "16161616-1616-1616-1616-161616161601")!,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            providerGameID: scheduledProviderID
        )
        let officialFinal = makeGameDetail(
            id: UUID(uuidString: "16161616-1616-1616-1616-161616161602")!,
            scheduledStart: finalStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: 6,
            homeScore: 4,
            status: .final,
            providerGameID: officialProviderID
        )
        let bridge = makeGameDetail(
            id: UUID(uuidString: "16161616-1616-1616-1616-161616161603")!,
            scheduledStart: scheduledStart,
            venue: "대전",
            awayTeam: kt,
            homeTeam: hanwha,
            awayScore: 2,
            homeScore: 1,
            status: .live,
            note: "official_provider_game_id=\(officialProviderID)",
            providerGameID: scheduledProviderID
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: teams, games: [scheduledShell, officialFinal, bridge], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let selected = try #require(model.game(withIdentity: "provider:\(scheduledProviderID)"))

        #expect(selected.status == .final)
        #expect(selected.awayScore == 6)
        #expect(selected.homeScore == 4)
        #expect(selected.providerGameID == officialProviderID)
    }

    // gameLookupDoesNotChooseAmbiguousSamePriorityProviderMatch 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailBoxscoreUsesPublicIDAfterOfficialProviderResolution 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailRefreshFallsBackToRepositoryWhenOfficialProviderMissingLocally 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailViewModelWithoutInitialGameUsesFallbackForRequestedIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailRefreshResolvesRouteInitialSnapshotWithoutGlobalGame 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailRefreshResolvesRouteInitialSnapshotWithoutGlobalGame() async throws {
        let game = try makeBoxscoreDetailGame()
        let emptyBootstrap = KBOBootstrapData(
            teams: MockKBOData.makeBootstrap().teams,
            games: [],
            notifications: [],
            settings: .default
        )
        let model = AppModel(
            repository: StubRepository(fetchBootstrapData: { emptyBootstrap }),
            bootstrap: emptyBootstrap,
            usePersistedSettings: false
        )

        #expect(model.game(withIdentity: game.stableDetailIdentity) == nil)

        let refreshed = await model.refreshGameDetailResult(
            for: game.stableDetailIdentity,
            initialGame: game,
            forceRefresh: false
        )

        #expect(refreshed?.game.id == game.id)
        #expect(refreshed?.game.publicGameID == game.publicGameID)
    }

    // upcomingGameDetailAppliesStartingPitchersFromSingleSupabaseRefresh 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    @Test func upcomingGameDetailAppliesStartingPitchersFromSingleSupabaseRefresh() async throws {
        let teams = MockKBOData.makeBootstrap().teams
        let initial = try makeLiveBoxscoreDetailGame(status: .upcoming)
        let refreshed = makeGameDetail(
            id: initial.id,
            scheduledStart: initial.scheduledStart,
            venue: initial.venue,
            awayTeam: initial.awayTeam,
            homeTeam: initial.homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: initial.note,
            providerGameID: initial.providerGameID,
            awayStartingPitcherName: "곽빈",
            homeStartingPitcherName: "김광현"
        )
        let detailFetchCounter = FetchCounter()
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [initial], notifications: [], settings: .default)
            }),
            fetchGameDetailSnapshot: { _, _, _ in
                await detailFetchCounter.increment()
                return refreshed
            }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [initial], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-10T10:00:00+09:00") }
        )
        let viewModel = GameDetailViewModel(gameIdentity: initial.stableDetailIdentity, initialGame: initial)

        let result = try #require(await viewModel.refreshIfNeeded(appModel: model, bypassAutomaticThrottle: true))
        let presentation = GameDetailPresentation(game: result, payload: nil, boxscore: nil)

        #expect(await detailFetchCounter.value == 1)
        #expect(viewModel.game?.awayStartingPitcherName == "곽빈")
        #expect(viewModel.game?.homeStartingPitcherName == "김광현")
        #expect(presentation.probableStarters?.away == "곽빈")
        #expect(presentation.probableStarters?.home == "김광현")
    }

    // gameDetailFallbackByOfficialProviderUsesPublicGameIDForBoxscore 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailRefreshKeepsExistingProviderFallbackBehavior 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailRefreshFallsBackToRepositoryByScheduledProviderID 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailRefreshUsesLocalCandidateWithoutIdentityFallback 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailRefreshKeepsNoSelectedGameWhenIdentityFallbackMisses 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameCenterReviewReportsDisplayableRecordsWhenBattingLinesExist 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseLatestSnapshotMapsKnownPlayerAliases 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseGamesSelectUsesOnlyCurrentGamesSchemaColumns 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseGameRowMapsStadiumIntoVenueWithoutStadiumCode 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseTodayRefreshSuppressesLocalFallbackWhenBypassingCache 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // todayFallbackUpcomingRowsDoNotOverwriteLiveTodayRows 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailSingleFetchByPublicGameIDReturnsOneRowWithoutDateFetch 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailScheduledRowUsesLatestSnapshotAsLiveState 메서드는 최신 스냅샷이 예정 row보다 우선되는지 검증합니다.
    @Test func gameDetailScheduledRowUsesLatestSnapshotAsLiveState() async throws {
        let referenceDate = isoDate("2026-06-24T18:30:00+09:00")
        let awayTeamID = UUID(uuidString: "61616161-6161-6161-6161-616161616161")!
        let homeTeamID = UUID(uuidString: "62626262-6262-6262-6262-626262626262")!
        let rowID = UUID(uuidString: "63636363-6363-6363-6363-636363636363")!
        let teams = [
            SupabaseTeamRow(id: awayTeamID, code: "nc", name: "NC 다이노스", shortName: "NC"),
            SupabaseTeamRow(id: homeTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데")
        ]
        let selected = makeGameDetail(
            id: UUID(uuidString: "64646464-6464-6464-6464-646464646464")!,
            scheduledStart: referenceDate,
            venue: "사직",
            awayTeam: SupabaseKBOMapper.mapTeam(teams[0]),
            homeTeam: SupabaseKBOMapper.mapTeam(teams[1]),
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260624-NC-LT provider_game_id=sched-202606241830-nc-lotte",
            providerGameID: "sched-202606241830-nc-lotte",
            awayStartingPitcherName: "NC선발",
            homeStartingPitcherName: "롯데선발"
        )
        let row = try makeSupabaseGameRow(
            id: rowID,
            publicGameID: "20260624-NC-LT",
            providerGameID: "20260624NCLT0",
            gameDate: "2026-06-24",
            scheduledAt: "2026-06-24T18:30:00+09:00",
            status: "scheduled",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 1,
            homeScore: 0,
            inningState: nil
        )
        let snapshot = try makeSupabaseLatestSnapshotRow(
            gameID: rowID,
            inningLabel: "1회 초",
            currentPitcherName: "롯데투수",
            currentBatterName: "NC타자"
        )
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(),
            source: TrackingSupabaseSource(teamRows: teams, gameRows: [row], tracker: tracker, latestSnapshotRows: [snapshot]),
            runtimeState: nil
        )

        let refreshed = try #require(await repository.fetchGameDetailSnapshot(
            for: selected,
            identity: selected.canonicalGameIdentityValue,
            cachedTeams: [selected.awayTeam, selected.homeTeam]
        ))

        #expect(refreshed.status == .live)
        #expect(refreshed.awayScore == 1)
        #expect(refreshed.homeScore == 0)
        #expect(refreshed.inningText == "1회 초")
        #expect(refreshed.currentPitcherName == "롯데투수")
        #expect(refreshed.currentBatterName == "NC타자")
        #expect(await tracker.latestSnapshotGameIDs == [rowID])
    }

    // gameDetailSingleFetchByProviderGameIDReturnsOneRow 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailSingleFetchFallsBackByDateAndTeams 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailRefreshUpdatesOnlySelectedEquivalentGame 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // repositoryCacheUpsertPreservesExistingPitchersWhenIncomingPitchersAreNil 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // myTeamNotificationFilterOnlyReturnsFavoriteTeamAlerts 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func myTeamNotificationFilterOnlyReturnsFavoriteTeamAlerts() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap())
        model.notificationFilter = .myTeam

        let notifications = model.filteredNotifications

        #expect(notifications.isEmpty == false)
        #expect(notifications.allSatisfy { $0.relatedTeamIDs.contains("lg") })
    }

    // unreadNotificationsCountDropsWhenItemIsMarkedRead 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func unreadNotificationsCountDropsWhenItemIsMarkedRead() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap())
        let unreadItem = try #require(model.notifications.first(where: { $0.isRead == false }))

        let before = model.unreadNotificationsCount
        model.markNotificationRead(unreadItem.id)

        #expect(model.unreadNotificationsCount == before - 1)
    }

    // scheduleFilterAllIncludesWholeMonthGames 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleFilterAllIncludesWholeMonthGames() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)
        let sampleDate = isoDate("2026-03-23T13:00:00+09:00")

        let games = model.scheduleGames(on: sampleDate, filter: .all)

        #expect(games.count == 4)
        #expect(games.contains { $0.awayTeam.id == "lotte" && $0.homeTeam.id == "ssg" })
        #expect(games.contains { $0.awayTeam.id == "kiwoom" && $0.homeTeam.id == "lg" })
    }

    // scheduleFilterMyTeamOnlyReturnsFavoriteTeamGames 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleFilterMyTeamOnlyReturnsFavoriteTeamGames() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)
        model.settings.favoriteTeamID = "lg"
        let sampleDate = isoDate("2026-03-23T13:00:00+09:00")

        let games = model.scheduleGames(on: sampleDate, filter: .myTeam)

        #expect(games.count == 1)
        #expect(games.allSatisfy { $0.involves(teamID: "lg") })
    }

    // scheduleMonthNavigationSkipsEmptyMonths 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // scheduleEntryUsesLocalScheduleWhenRemoteCountMatches 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // scheduleEntrySyncsMissingGamesOnceWhenCountsDiffer 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // scheduleEntryRefreshesTodayWithDateLimitedFetchOnly 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // scheduleScreenLoadUsesScheduleTabMonthlySourceOnly 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleScreenLoadUsesScheduleTabMonthlySourceOnly() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-01T09:00:00+09:00"))
        let game = try #require(base.games.first(where: {
            KBOMonthScheduleKey(date: $0.scheduledStart).yearMonthText == "202603"
        }))
        let tracker = ScheduleTabMonthTestTracker()
        let repository = ScheduleTabMonthTestRepository(
            bootstrap: base,
            scheduleTabGames: [game],
            tracker: tracker
        )
        let model = AppModel(
            repository: repository,
            bootstrap: base,
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-04-01T09:00:00+09:00") }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = isoDate("2026-03-01T09:00:00+09:00")
        viewModel.selectedDate = game.scheduledStart
        let standingsRevisionBeforeLoad = model.standingsRowsRevision

        await viewModel.loadDisplayedMonth(appModel: model)

        #expect(viewModel.selectedDateGames.map(\.id) == [game.id])
        #expect(model.standingsRowsRevision == standingsRevisionBeforeLoad)
        #expect(await tracker.scheduleTabMonthFetches == 1)
        #expect(await tracker.monthlyScheduleFetches == 0)
        #expect(await tracker.dailyScheduleFetches == 0)
    }

    // scheduleScreenMonthLoadDoesNotPopulateAppModelMonthSnapshot 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleScreenMonthLoadDoesNotPopulateAppModelMonthSnapshot() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-01T09:00:00+09:00"))
        let game = try #require(base.games.first(where: {
            KBOMonthScheduleKey(date: $0.scheduledStart).yearMonthText == "202603"
        }))
        let emptyBootstrap = KBOBootstrapData(
            teams: base.teams,
            games: [],
            notifications: [],
            settings: .default
        )
        let tracker = ScheduleTabMonthTestTracker()
        let repository = ScheduleTabMonthTestRepository(
            bootstrap: emptyBootstrap,
            scheduleTabGames: [game],
            tracker: tracker
        )
        let model = AppModel(
            repository: repository,
            bootstrap: emptyBootstrap,
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-04-01T09:00:00+09:00") }
        )
        let viewModel = ScheduleViewModel()
        let monthKey = KBOMonthScheduleKey(date: game.scheduledStart)
        viewModel.displayedMonth = game.scheduledStart
        viewModel.selectedDate = game.scheduledStart

        await viewModel.loadDisplayedMonth(appModel: model)

        #expect(viewModel.selectedDateGames.map(\.id) == [game.id])
        #expect(model.currentScheduleMonthSnapshot(for: monthKey).isEmpty)
        #expect(model.game(withIdentity: game.stableDetailIdentity) == nil)
        #expect(await tracker.scheduleTabMonthFetches == 1)
        #expect(await tracker.monthlyScheduleFetches == 0)
        #expect(await tracker.dailyScheduleFetches == 0)
    }

    // scheduleGameDetailRouteCarriesInitialGameSnapshot 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleGameDetailRouteCarriesInitialGameSnapshot() async throws {
        let game = try makeBoxscoreDetailGame()
        let route = ScheduleGameDetailRoute(game: game)

        #expect(route.stableIdentity == game.stableDetailIdentity)
        #expect(route.initialGame == game)
    }

    // todayLiveRefreshUpdatesScheduleMonthCacheStartingPitchers 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    @Test func todayLiveRefreshUpdatesScheduleMonthCacheStartingPitchers() async throws {
        let selectedDate = isoDate("2026-05-10T10:00:00+09:00")
        let monthKey = KBOMonthScheduleKey(date: selectedDate)
        let cachedGame = try makeLiveBoxscoreDetailGame(status: .upcoming)
        let refreshedGame = makeGameDetail(
            id: cachedGame.id,
            scheduledStart: cachedGame.scheduledStart,
            venue: cachedGame.venue,
            awayTeam: cachedGame.awayTeam,
            homeTeam: cachedGame.homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: cachedGame.note,
            providerGameID: cachedGame.providerGameID,
            awayStartingPitcherName: "곽빈",
            homeStartingPitcherName: "김광현"
        )
        let tracker = ScheduleTabMonthTestTracker()
        let bootstrap = KBOBootstrapData(
            teams: MockKBOData.makeBootstrap().teams,
            games: [refreshedGame],
            notifications: [],
            settings: .default
        )
        let repository = ScheduleTabMonthTestRepository(
            bootstrap: bootstrap,
            scheduleTabGames: [cachedGame],
            tracker: tracker
        )
        let appModel = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: bootstrap.teams, games: [], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { selectedDate }
        )
        let coordinator = ScheduleRefreshCoordinator()

        await coordinator.loadMonth(
            monthKey,
            forceRefresh: false,
            appModel: appModel,
            callSite: "test",
            reason: "initialLoad"
        )
        #expect(coordinator.cachedMonthEntries[monthKey.yearMonthText]?.games.first?.awayStartingPitcherName == nil)

        await coordinator.refreshTodayLiveIfNeeded(
            selectedDate: selectedDate,
            displayedMonthKey: monthKey,
            appModel: appModel,
            callSite: "test"
        )

        let cached = try #require(coordinator.cachedMonthEntries[monthKey.yearMonthText]?.games.first)
        #expect(cached.awayStartingPitcherName == "곽빈")
        #expect(cached.homeStartingPitcherName == "김광현")
        #expect(await tracker.scheduleTabMonthFetches == 1)
        #expect(await tracker.dailyScheduleFetches == 1)
    }

    // scheduleScreenDateSelectionDoesNotFetchNetworkData 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleScreenDateSelectionDoesNotFetchNetworkData() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-03-23T09:00:00+09:00"))
        let marchGames = base.games.filter {
            KBOMonthScheduleKey(date: $0.scheduledStart).yearMonthText == "202603"
        }
        let firstGame = try #require(marchGames.first)
        let secondGame = try #require(marchGames.dropFirst().first)
        let tracker = ScheduleTabMonthTestTracker()
        let repository = ScheduleTabMonthTestRepository(
            bootstrap: base,
            scheduleTabGames: marchGames,
            tracker: tracker
        )
        let model = AppModel(
            repository: repository,
            bootstrap: base,
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-03-23T09:00:00+09:00") }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = isoDate("2026-03-01T09:00:00+09:00")
        viewModel.selectedDate = firstGame.scheduledStart
        await viewModel.loadDisplayedMonth(appModel: model)

        let monthlyFetchesAfterLoad = await tracker.scheduleTabMonthFetches
        viewModel.selectDate(
            secondGame.scheduledStart,
            favoriteTeamID: nil,
            attendedGameKeys: []
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.selectedDateGames.contains { $0.id == secondGame.id })
        #expect(await tracker.scheduleTabMonthFetches == monthlyFetchesAfterLoad)
        #expect(await tracker.monthlyScheduleFetches == 0)
        #expect(await tracker.dailyScheduleFetches == 0)
    }

    // finalGameDerivesWinnerScoreAndTeamResult 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // scheduleCalendarDaysExposeFavoriteTeamFinalResult 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // lotteWinDayUsesBlueSemanticAppearance 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func lotteWinDayUsesBlueSemanticAppearance() {
        let appearance = ScheduleDayResultAppearance.from(dominantStatus: .final, favoriteTeamResult: .win)
        #expect(appearance == .win)
    }

    // lotteLossDayUsesRedSemanticAppearance 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func lotteLossDayUsesRedSemanticAppearance() {
        let appearance = ScheduleDayResultAppearance.from(dominantStatus: .final, favoriteTeamResult: .loss)
        #expect(appearance == .loss)
    }

    // drawDayUsesGraySemanticAppearance 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func drawDayUsesGraySemanticAppearance() {
        let appearance = ScheduleDayResultAppearance.from(dominantStatus: .final, favoriteTeamResult: .tie)
        #expect(appearance == .draw)
    }

    // noFavoriteTeamResultUsesNeutralSemanticAppearance 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func noFavoriteTeamResultUsesNeutralSemanticAppearance() {
        let appearance = ScheduleDayResultAppearance.from(dominantStatus: .final, favoriteTeamResult: nil)
        #expect(appearance == .neutral)
    }

    // attendanceSummaryCountsOnlyCompletedFavoriteTeamResults 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // attendanceDashboardAggregatesHomeAttendanceRecord 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func attendanceDashboardAggregatesHomeAttendanceRecord() throws {
        let teams = try attendanceFixtureTeams()
        let homeWin = makeAttendanceFixtureGame(index: 1, awayTeam: teams.doosan, homeTeam: teams.lg, awayScore: 2, homeScore: 5)
        let homeLoss = makeAttendanceFixtureGame(index: 2, awayTeam: teams.samsung, homeTeam: teams.lg, awayScore: 6, homeScore: 3)
        let homeDraw = makeAttendanceFixtureGame(index: 3, awayTeam: teams.lotte, homeTeam: teams.lg, awayScore: 4, homeScore: 4)

        let dashboard = AttendanceDashboardBuilder.build(attendedGames: [homeWin, homeLoss, homeDraw], favoriteTeamID: "lg")

        #expect(dashboard.home.games == 3)
        #expect(dashboard.home.wins == 1)
        #expect(dashboard.home.losses == 1)
        #expect(dashboard.home.draws == 1)
        #expect(dashboard.home.winPercentageText == "0.500")
        #expect(dashboard.away.games == 0)
    }

    // attendanceDashboardAggregatesAwayAttendanceRecord 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func attendanceDashboardAggregatesAwayAttendanceRecord() throws {
        let teams = try attendanceFixtureTeams()
        let awayWin = makeAttendanceFixtureGame(index: 4, awayTeam: teams.lg, homeTeam: teams.doosan, awayScore: 5, homeScore: 2)
        let awayLoss = makeAttendanceFixtureGame(index: 5, awayTeam: teams.lg, homeTeam: teams.samsung, awayScore: 3, homeScore: 6)
        let awayDraw = makeAttendanceFixtureGame(index: 6, awayTeam: teams.lg, homeTeam: teams.lotte, awayScore: 4, homeScore: 4)

        let dashboard = AttendanceDashboardBuilder.build(attendedGames: [awayWin, awayLoss, awayDraw], favoriteTeamID: "lg")

        #expect(dashboard.away.games == 3)
        #expect(dashboard.away.wins == 1)
        #expect(dashboard.away.losses == 1)
        #expect(dashboard.away.draws == 1)
        #expect(dashboard.away.winPercentageText == "0.500")
        #expect(dashboard.home.games == 0)
    }

    // attendanceDashboardAggregatesCombinedHomeAndAwayRecord 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func attendanceDashboardAggregatesCombinedHomeAndAwayRecord() throws {
        let teams = try attendanceFixtureTeams()
        let homeWin = makeAttendanceFixtureGame(index: 7, awayTeam: teams.doosan, homeTeam: teams.lg, awayScore: 2, homeScore: 5)
        let awayLoss = makeAttendanceFixtureGame(index: 8, awayTeam: teams.lg, homeTeam: teams.samsung, awayScore: 3, homeScore: 6)
        let awayDraw = makeAttendanceFixtureGame(index: 9, awayTeam: teams.lg, homeTeam: teams.lotte, awayScore: 4, homeScore: 4)

        let dashboard = AttendanceDashboardBuilder.build(attendedGames: [homeWin, awayLoss, awayDraw], favoriteTeamID: "lg")

        #expect(dashboard.overall.games == 3)
        #expect(dashboard.overall.wins == 1)
        #expect(dashboard.overall.losses == 1)
        #expect(dashboard.overall.draws == 1)
        #expect(dashboard.home.games == 1)
        #expect(dashboard.away.games == 2)
    }

    // attendanceDashboardExcludesDrawsFromWinningPercentage 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func attendanceDashboardExcludesDrawsFromWinningPercentage() throws {
        let teams = try attendanceFixtureTeams()
        let win = makeAttendanceFixtureGame(index: 10, awayTeam: teams.doosan, homeTeam: teams.lg, awayScore: 2, homeScore: 5)
        let draw = makeAttendanceFixtureGame(index: 11, awayTeam: teams.samsung, homeTeam: teams.lg, awayScore: 4, homeScore: 4)

        let dashboard = AttendanceDashboardBuilder.build(attendedGames: [win, draw], favoriteTeamID: "lg")
        let drawOnly = AttendanceDashboardBuilder.build(attendedGames: [draw], favoriteTeamID: "lg")

        #expect(dashboard.overall.games == 2)
        #expect(dashboard.overall.winPercentageText == "1.000")
        #expect(drawOnly.overall.winPercentage == nil)
        #expect(drawOnly.overall.winPercentageText == "---")
    }

    // attendanceDashboardExcludesGamesUnrelatedToFavoriteTeam 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func attendanceDashboardExcludesGamesUnrelatedToFavoriteTeam() throws {
        let teams = try attendanceFixtureTeams()
        let favoriteGame = makeAttendanceFixtureGame(index: 12, awayTeam: teams.doosan, homeTeam: teams.lg, awayScore: 2, homeScore: 5)
        let unrelatedGame = makeAttendanceFixtureGame(index: 13, awayTeam: teams.samsung, homeTeam: teams.lotte, awayScore: 3, homeScore: 1)

        let dashboard = AttendanceDashboardBuilder.build(attendedGames: [favoriteGame, unrelatedGame], favoriteTeamID: "lg")

        #expect(dashboard.overall.games == 1)
        #expect(dashboard.games.map(\.opponentName) == ["두산"])
    }

    // attendanceDashboardGameListIncludesOpponentStadiumAndScore 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func attendanceDashboardGameListIncludesOpponentStadiumAndScore() throws {
        let teams = try attendanceFixtureTeams()
        let game = makeAttendanceFixtureGame(
            index: 14,
            venue: "잠실",
            awayTeam: teams.doosan,
            homeTeam: teams.lg,
            awayScore: 2,
            homeScore: 5
        )

        let dashboard = AttendanceDashboardBuilder.build(attendedGames: [game], favoriteTeamID: "lg")
        let record = try #require(dashboard.games.first)

        #expect(record.opponentName == "두산")
        #expect(record.stadium == "잠실")
        #expect(record.scoreText == "두산 2 : 5 LG")
        #expect(record.gameDate == game.scheduledStart)
    }

    // attendanceDashboardShowsUpcomingAttendance 메서드는 경기 전 직관 기록이 목록에서 제외되지 않는지 검증합니다.
    @Test func attendanceDashboardShowsUpcomingAttendance() throws {
        let teams = try attendanceFixtureTeams()
        let upcoming = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000115")!,
            scheduledStart: isoDate("2026-07-07T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: teams.doosan,
            homeTeam: teams.lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )

        let dashboard = AttendanceDashboardBuilder.build(attendedGames: [upcoming], favoriteTeamID: "lg")

        #expect(dashboard.hasGames)
        #expect(dashboard.overall.games == 0)
        #expect(dashboard.upcomingGames.map(\.id) == [upcoming.attendanceStorageKey])
        #expect(dashboard.pastGames.isEmpty)
        #expect(dashboard.games.map(\.id) == [upcoming.attendanceStorageKey])
    }

    // attendanceDashboardSplitsUpcomingAndPastAttendance 메서드는 직관탭 섹션 분리와 정렬을 검증합니다.
    @Test func attendanceDashboardSplitsUpcomingAndPastAttendance() throws {
        let teams = try attendanceFixtureTeams()
        let earlierUpcoming = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000116")!,
            scheduledStart: isoDate("2026-07-07T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: teams.doosan,
            homeTeam: teams.lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )
        let laterUpcoming = makeGameDetail(
            id: UUID(uuidString: "95000000-0000-0000-0000-000000000117")!,
            scheduledStart: isoDate("2026-07-08T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: teams.samsung,
            homeTeam: teams.lg,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )
        let olderFinal = makeAttendanceFixtureGame(index: 16, awayTeam: teams.lotte, homeTeam: teams.lg, awayScore: 1, homeScore: 4)
        let newerFinal = makeAttendanceFixtureGame(index: 17, awayTeam: teams.doosan, homeTeam: teams.lg, awayScore: 5, homeScore: 2)

        let dashboard = AttendanceDashboardBuilder.build(
            attendedGames: [newerFinal, laterUpcoming, olderFinal, earlierUpcoming],
            favoriteTeamID: "lg"
        )

        #expect(dashboard.upcomingGames.map(\.id) == [earlierUpcoming.attendanceStorageKey, laterUpcoming.attendanceStorageKey])
        #expect(dashboard.pastGames.map(\.id) == [newerFinal.attendanceStorageKey, olderFinal.attendanceStorageKey])
        #expect(dashboard.overall.games == 2)
        #expect(dashboard.games.map(\.id) == [
            earlierUpcoming.attendanceStorageKey,
            laterUpcoming.attendanceStorageKey,
            newerFinal.attendanceStorageKey,
            olderFinal.attendanceStorageKey
        ])
    }

    // attendanceSummaryKeepsCompletedBootstrapGameWhenMonthlyDuplicateIsStale 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // scheduleCalendarDaysExposeAttendedGameMarker 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // scheduleCalendarMarkerUsesEquivalentAttendanceIdentityForMonthlyDuplicate 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // scheduleDetailLookupUsesProviderIdentityAcrossDifferentRawIDs 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // scheduleRainoutTransitionSchedulesLocalNotificationOnce 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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
                collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshSchedule(for: scheduledStart)
        await model.refreshSchedule(for: scheduledStart)

        #expect(collector.requests.count == 1)
        #expect(collector.requests.first?.content.body == "[LG] 금일 경기는 우천으로 인해 취소되었습니다.")
    }

    // scoringTransitionDoesNotScheduleLocalNotification 메서드는 이 타입의 주요 동작을 수행합니다.
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
                collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshSchedule(for: scheduledStart)

        #expect(collector.requests.isEmpty)
    }

    // inningOnlyLiveTransitionDoesNotScheduleNotification 메서드는 이 타입의 주요 동작을 수행합니다.
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
                collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshSchedule(for: scheduledStart)

        #expect(collector.requests.isEmpty)
    }

    // onBaseTransitionDoesNotScheduleLocalNotification 메서드는 이 타입의 주요 동작을 수행합니다.
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
                collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshSchedule(for: scheduledStart)

        #expect(collector.requests.isEmpty)
    }

    // homeRainoutTransitionSchedulesLocalNotificationOnce 메서드는 이 타입의 주요 동작을 수행합니다.
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
                collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshHome()
        await model.refreshHome()

        #expect(collector.requests.count == 1)
        #expect(collector.requests.first?.content.userInfo["kbo_live"] != nil)
    }

    // nonTodayCancelledGameDoesNotScheduleLocalNotification 메서드는 이 타입의 주요 동작을 수행합니다.
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
                collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshHome()

        #expect(collector.requests.isEmpty)
    }

    // finalizedGameDoesNotScheduleCancellationNotification 메서드는 이 타입의 주요 동작을 수행합니다.
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
                collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshHome()

        #expect(collector.requests.isEmpty)
    }

    // nonFavoriteCancelledGameDoesNotScheduleLocalNotification 메서드는 이 타입의 주요 동작을 수행합니다.
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
                collector.append(request)
            }
        )
        model.settings.favoriteTeamID = "lg"
        model.notificationAuthorizationStatus = .authorized

        await model.refreshHome()

        #expect(collector.requests.isEmpty)
    }

    // standingsExcludeExhibitionGamesAndRankByWinPercentage 메서드는 이 타입의 주요 동작을 수행합니다.
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

        let lgSnapshot = try requireStandingsSnapshot(in: standings, teamID: "lg")
        let doosanSnapshot = try requireStandingsSnapshot(in: standings, teamID: "doosan")

        #expect(lgSnapshot.rank == 1)
        #expect(lgSnapshot.recordText == "1승 0패 0무")
        #expect(lgSnapshot.winPercentageText == "1.000")
        #expect(doosanSnapshot.rank == 2)
        #expect(doosanSnapshot.recordText == "1승 1패 0무")
        #expect(doosanSnapshot.winPercentageText == "0.500")
        #expect(model.regularSeasonGames.count == 2)
    }

    // appModelBootstrapImmediatelyPublishesStandingsRows 메서드는 bootstrap 초기화 정책을 고정합니다.
    @Test func appModelBootstrapImmediatelyPublishesStandingsRows() throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-01T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let game = makeGameDetail(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            scheduledStart: isoDate("2026-03-28T14:00:00+09:00"),
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
                games: [game],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        #expect(model.standingsSnapshots.count == 2)
        let lgSnapshot = try requireStandingsSnapshot(in: model.standingsSnapshots, teamID: "lg")
        #expect(lgSnapshot.wins == 1)
    }

    // standingsSnapshotLookupReportsMissingTeamWithoutIndexingCrash 메서드는 빈 배열 guard 실패가 crash로 전파되지 않음을 검증합니다.
    @Test func standingsSnapshotLookupReportsMissingTeamWithoutIndexingCrash() {
        do {
            _ = try requireStandingsSnapshot(in: [], teamID: "lg")
            #expect(Bool(false))
        } catch let error as TestFixtureError {
            #expect(error.description.contains("teamID=lg"))
            #expect(error.description.contains("count=0"))
        } catch {
            #expect(Bool(false))
        }
    }

    // standingsRankMovementMovedUpShowsUpIndicator 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementMovedUpShowsUpIndicator() {
        let movement = StandingsRankMovementResolver.movement(currentRank: 4, preGameRank: 5)

        #expect(movement == .up(1))
        #expect(movement.indicator == "▲")
        #expect(movement.displayText == "▲1")
        #expect(movement.accessibilityText == "순위 1단계 상승")
    }

    // standingsRankMovementMovedDownShowsDownIndicator 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementMovedDownShowsDownIndicator() {
        let movement = StandingsRankMovementResolver.movement(currentRank: 5, preGameRank: 3)

        #expect(movement == .down(2))
        #expect(movement.indicator == "▼")
        #expect(movement.displayText == "▼2")
        #expect(movement.accessibilityText == "순위 2단계 하락")
    }

    // standingsRankMovementUnchangedShowsNoIndicator 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementUnchangedShowsNoIndicator() {
        let movement = StandingsRankMovementResolver.movement(currentRank: 4, preGameRank: 4)

        #expect(movement == .unchanged)
        #expect(movement.indicator == nil)
        #expect(movement.displayText == "-")
    }

    // standingsRankMovementMissingPreGameRankShowsNoIndicator 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementMissingPreGameRankShowsNoIndicator() {
        let movement = StandingsRankMovementResolver.movement(currentRank: 4, preGameRank: nil)

        #expect(movement == .unchanged)
        #expect(movement.indicator == nil)
        #expect(movement.displayText == "-")
    }

    // standingsRankMovementMissingCurrentRankShowsNoIndicator 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementMissingCurrentRankShowsNoIndicator() {
        let movement = StandingsRankMovementResolver.movement(currentRank: nil, preGameRank: 4)

        #expect(movement == .unchanged)
        #expect(movement.indicator == nil)
    }

    // standingsSnapshotCarriesPreGameRankForDisplayedMovement 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsSnapshotCarriesPreGameRankForDisplayedMovement() throws {
        let team = try #require(MockKBOData.makeBootstrap().teams.first(where: { $0.id == "lg" }))
        let snapshot = TeamStandingsSnapshot(
            team: team,
            rank: 4,
            wins: 10,
            losses: 8,
            ties: 1,
            remainingRegularSeasonGames: 125,
            recentResults: [],
            preGameRank: 6
        )

        #expect(snapshot.preGameRank == 6)
        #expect(StandingsRankMovementResolver.movement(currentRank: snapshot.rank, preGameRank: snapshot.preGameRank).displayText == "▲2")
    }

    // standingsRowRenderIdentityChangesWhenMovementChangesButKeepsTeamID 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRowRenderIdentityChangesWhenMovementChangesButKeepsTeamID() throws {
        let team = try #require(MockKBOData.makeBootstrap().teams.first(where: { $0.id == "doosan" }))
        let initial = TeamStandingsSnapshot(
            team: team,
            rank: 6,
            wins: 20,
            losses: 18,
            ties: 1,
            remainingRegularSeasonGames: 105,
            recentResults: []
        )
        let updated = initial.withPreGameRank(7)

        let initialIdentity = StandingsRowRenderIdentity(snapshot: initial)
        let updatedIdentity = StandingsRowRenderIdentity(snapshot: updated)

        #expect(initial.id == updated.id)
        #expect(initialIdentity.teamID == updatedIdentity.teamID)
        #expect(initialIdentity != updatedIdentity)
        #expect(initial.rankMovement.displayText == "-")
        #expect(updated.rankMovement.displayText == "▲1")
    }

    // standingsRankMovementUsesLatestCompletedDateInsteadOfCurrentDate 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementUsesLatestCompletedDateInsteadOfCurrentDate() throws {
        let fixture = try makeStandingsMovementFixture()
        let calendar = standingsMovementCalendar()

        let latestDay = try #require(StandingsRankMovementResolver.latestCompletedGameDay(
            games: fixture.games,
            calendar: calendar
        ))

        #expect(scheduleTestDayKey(for: latestDay) == "2026-05-24")
    }

    // standingsPreGameRanksUseGamesBeforeLatestCompletedDate 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsPreGameRanksUseGamesBeforeLatestCompletedDate() throws {
        let fixture = try makeStandingsMovementFixture()
        let ranks = StandingsRankMovementResolver.preGameRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRankProvider: { fixture.previousRanks[$0.id] }
        )

        #expect(ranks[fixture.leader.id] == 1)
        #expect(ranks[fixture.falling.id] == 2)
        #expect(ranks[fixture.rising.id] == 3)
    }

    // standingsPreGameRanksExcludeGamesOnLatestCompletedDate 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsPreGameRanksExcludeGamesOnLatestCompletedDate() throws {
        let fixture = try makeStandingsMovementFixture()
        let ranks = StandingsRankMovementResolver.preGameRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRankProvider: { fixture.previousRanks[$0.id] }
        )

        #expect(ranks[fixture.rising.id] == 3)
        #expect(ranks[fixture.falling.id] == 2)
    }

    // standingsRankMovementShowsUpAfterLatestCompletedDateBatch 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementShowsUpAfterLatestCompletedDateBatch() throws {
        let fixture = try makeStandingsMovementFixture()
        let currentRanks = currentStandingsRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRanks: fixture.previousRanks
        )
        let preGameRanks = StandingsRankMovementResolver.preGameRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRankProvider: { fixture.previousRanks[$0.id] }
        )

        let movement = StandingsRankMovementResolver.movement(
            currentRank: currentRanks[fixture.rising.id],
            preGameRank: preGameRanks[fixture.rising.id]
        )

        #expect(currentRanks[fixture.rising.id] == 2)
        #expect(preGameRanks[fixture.rising.id] == 3)
        #expect(movement.displayText == "▲1")
    }

    // standingsRankMovementShowsDownAfterLatestCompletedDateBatch 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementShowsDownAfterLatestCompletedDateBatch() throws {
        let fixture = try makeStandingsMovementFixture()
        let currentRanks = currentStandingsRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRanks: fixture.previousRanks
        )
        let preGameRanks = StandingsRankMovementResolver.preGameRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRankProvider: { fixture.previousRanks[$0.id] }
        )

        let movement = StandingsRankMovementResolver.movement(
            currentRank: currentRanks[fixture.falling.id],
            preGameRank: preGameRanks[fixture.falling.id]
        )

        #expect(currentRanks[fixture.falling.id] == 3)
        #expect(preGameRanks[fixture.falling.id] == 2)
        #expect(movement.displayText == "▼1")
    }

    // standingsRankMovementShowsUnchangedWhenRankIsSame 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementShowsUnchangedWhenRankIsSame() throws {
        let fixture = try makeStandingsMovementFixture()
        let currentRanks = currentStandingsRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRanks: fixture.previousRanks
        )
        let preGameRanks = StandingsRankMovementResolver.preGameRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRankProvider: { fixture.previousRanks[$0.id] }
        )

        let movement = StandingsRankMovementResolver.movement(
            currentRank: currentRanks[fixture.leader.id],
            preGameRank: preGameRanks[fixture.leader.id]
        )

        #expect(movement.displayText == "-")
    }

    // standingsRankMovementNoCompletedGamesReturnsNoPreGameRanks 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementNoCompletedGamesReturnsNoPreGameRanks() throws {
        let fixture = try makeStandingsMovementFixture()
        let upcomingOnly = fixture.games.map {
            makeGameDetail(
                id: $0.id,
                scheduledStart: $0.scheduledStart,
                venue: $0.venue,
                awayTeam: $0.awayTeam,
                homeTeam: $0.homeTeam,
                awayScore: nil,
                homeScore: nil,
                status: .upcoming,
                seasonClassification: .regularSeason
            )
        }

        let ranks = StandingsRankMovementResolver.preGameRanks(
            teams: fixture.teams,
            games: upcomingOnly,
            previousRankProvider: { fixture.previousRanks[$0.id] }
        )

        #expect(ranks.isEmpty)
    }

    // standingsRankMovementIgnoresCancelledAndNonFinalGamesForLatestCompletedDate 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementIgnoresCancelledAndNonFinalGamesForLatestCompletedDate() throws {
        var fixture = try makeStandingsMovementFixture()
        let cancelled = makeGameDetail(
            id: UUID(uuidString: "97000000-0000-0000-0000-000000000099")!,
            scheduledStart: isoDate("2026-05-25T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: fixture.leader,
            homeTeam: fixture.rising,
            awayScore: 0,
            homeScore: 0,
            status: .cancelled,
            seasonClassification: .regularSeason
        )
        fixture.games.append(cancelled)

        let latestDay = try #require(StandingsRankMovementResolver.latestCompletedGameDay(
            games: fixture.games,
            calendar: standingsMovementCalendar()
        ))

        #expect(scheduleTestDayKey(for: latestDay) == "2026-05-24")
    }

    // standingsRankMovementPersistsWhenCurrentDateIsAfterLatestCompletedDate 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsRankMovementPersistsWhenCurrentDateIsAfterLatestCompletedDate() throws {
        let fixture = try makeStandingsMovementFixture()
        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: fixture.teams,
                games: fixture.games,
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-25T09:00:00+09:00") }
        )

        let risingSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.rising.id })
        let movement = StandingsRankMovementResolver.movement(
            currentRank: risingSnapshot.rank,
            preGameRank: risingSnapshot.preGameRank
        )

        #expect(risingSnapshot.rank == 2)
        #expect(risingSnapshot.preGameRank == 3)
        #expect(movement.displayText == "▲1")
    }

    // latestFinalGameDateSplitProducesDifferentPreviousAndCurrentRanksAfterLatestResult 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func latestFinalGameDateSplitProducesDifferentPreviousAndCurrentRanksAfterLatestResult() throws {
        let fixture = try makeStandingsMovementFixture()
        let previousRanks = StandingsRankMovementResolver.preGameRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRankProvider: { fixture.previousRanks[$0.id] }
        )
        let currentRanks = currentStandingsRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRanks: fixture.previousRanks
        )

        #expect(previousRanks[fixture.rising.id] == 3)
        #expect(currentRanks[fixture.rising.id] == 2)
        #expect(previousRanks[fixture.falling.id] == 2)
        #expect(currentRanks[fixture.falling.id] == 3)
    }

    // appModelRowModelCarriesUpAndDownFromResolver 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func appModelRowModelCarriesUpAndDownFromResolver() throws {
        let fixture = try makeStandingsMovementFixture()
        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: fixture.teams,
                games: fixture.games,
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-25T09:00:00+09:00") }
        )

        let risingSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.rising.id })
        let fallingSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.falling.id })

        #expect(risingSnapshot.rankMovement == .up(1))
        #expect(fallingSnapshot.rankMovement == .down(1))
    }

    // standingsViewMovementDisplayTextUsesArrowCountAndDash 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsViewMovementDisplayTextUsesArrowCountAndDash() {
        #expect(RankingMovement.up(1).displayText == "▲1")
        #expect(RankingMovement.down(1).displayText == "▼1")
        #expect(RankingMovement.unchanged.displayText == "-")
    }

    // rowOrderingIsUnchangedByMovementDisplay 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func rowOrderingIsUnchangedByMovementDisplay() throws {
        let fixture = try makeStandingsMovementFixture()
        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: fixture.teams,
                games: fixture.games,
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-25T09:00:00+09:00") }
        )

        #expect(model.standingsSnapshots.map(\.team.id) == [
            fixture.leader.id,
            fixture.rising.id,
            fixture.falling.id
        ])
        #expect(model.standingsSnapshots.map(\.rankMovement) == [
            .unchanged,
            .up(1),
            .down(1)
        ])
    }

    // standingsRecentResultsAreLimitedToFiveMostRecentFinalGames 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // standingsStreakUsesAllCompletedLossesBeyondRecentFormLimit 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsStreakUsesAllCompletedLossesBeyondRecentFormLimit() throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-05-31T22:00:00+09:00"))
        let ssg = try #require(base.teams.first(where: { $0.id == "ssg" }))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let olderWin = makeGameDetail(
            id: UUID(uuidString: "51000000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-05-19T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: ssg,
            homeTeam: lg,
            awayScore: 6,
            homeScore: 2,
            status: .final,
            seasonClassification: .regularSeason
        )
        let losses = (0..<12).map { index in
            makeGameDetail(
                id: UUID(uuidString: String(format: "51000000-0000-0000-0000-%012d", index + 2))!,
                scheduledStart: isoDate(String(format: "2026-05-%02dT18:30:00+09:00", 31 - index)),
                venue: "문학",
                awayTeam: lg,
                homeTeam: ssg,
                awayScore: 5,
                homeScore: 1,
                status: .final,
                seasonClassification: .regularSeason
            )
        }

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [ssg, lg],
                games: Array(losses.reversed()) + [olderWin],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let ssgSnapshot = try #require(model.standingsSnapshots.first(where: { $0.team.id == "ssg" }))

        #expect(ssgSnapshot.currentStreakText == "12연패")
        #expect(ssgSnapshot.recentResults.count == 5)
        #expect(ssgSnapshot.recentResultsText == "패 패 패 패 패")
    }

    // standingsSnapshotDisplaysTwelveGameLosingStreakText 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsSnapshotDisplaysTwelveGameLosingStreakText() throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-05-31T22:00:00+09:00"))
        let ssg = try #require(base.teams.first(where: { $0.id == "ssg" }))
        let snapshot = TeamStandingsSnapshot(
            team: ssg,
            rank: 8,
            wins: 20,
            losses: 32,
            ties: 1,
            remainingRegularSeasonGames: 91,
            recentResults: Array(repeating: TeamGameResult.loss, count: 5),
            precomputedStreakText: "12연패"
        )

        #expect(snapshot.currentStreakText == "12연패")
    }

    // standingsStreakUsesAllCompletedWinsBeyondRecentFormLimit 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsStreakUsesAllCompletedWinsBeyondRecentFormLimit() throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-05-31T22:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let olderLoss = makeGameDetail(
            id: UUID(uuidString: "52000000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-05-24T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 7,
            homeScore: 2,
            status: .final,
            seasonClassification: .regularSeason
        )
        let wins = (0..<6).map { index in
            makeGameDetail(
                id: UUID(uuidString: String(format: "52000000-0000-0000-0000-%012d", index + 2))!,
                scheduledStart: isoDate(String(format: "2026-05-%02dT18:30:00+09:00", 31 - index)),
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
                games: [olderLoss] + wins,
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let lgSnapshot = try #require(model.standingsSnapshots.first(where: { $0.team.id == "lg" }))

        #expect(lgSnapshot.currentStreakText == "6연승")
        #expect(lgSnapshot.recentResults.count == 5)
        #expect(lgSnapshot.recentResultsText == "승 승 승 승 승")
    }

    // standingsStreakIgnoresIncompleteAndCancelledGames 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsStreakIgnoresIncompleteAndCancelledGames() throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-05-07T22:00:00+09:00"))
        let ssg = try #require(base.teams.first(where: { $0.id == "ssg" }))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let completedLosses = (1...3).map { day in
            makeGameDetail(
                id: UUID(uuidString: String(format: "53000000-0000-0000-0000-%012d", day))!,
                scheduledStart: isoDate(String(format: "2026-05-%02dT18:30:00+09:00", day)),
                venue: "문학",
                awayTeam: lg,
                homeTeam: ssg,
                awayScore: 5,
                homeScore: 1,
                status: .final,
                seasonClassification: .regularSeason
            )
        }
        let ignoredGames = [
            makeGameDetail(
                id: UUID(uuidString: "53000000-0000-0000-0000-000000000004")!,
                scheduledStart: isoDate("2026-05-04T18:30:00+09:00"),
                venue: "문학",
                awayTeam: lg,
                homeTeam: ssg,
                awayScore: nil,
                homeScore: nil,
                status: .cancelled,
                seasonClassification: .regularSeason
            ),
            makeGameDetail(
                id: UUID(uuidString: "53000000-0000-0000-0000-000000000005")!,
                scheduledStart: isoDate("2026-05-05T18:30:00+09:00"),
                venue: "문학",
                awayTeam: lg,
                homeTeam: ssg,
                awayScore: nil,
                homeScore: nil,
                status: .upcoming,
                seasonClassification: .regularSeason
            ),
            makeGameDetail(
                id: UUID(uuidString: "53000000-0000-0000-0000-000000000006")!,
                scheduledStart: isoDate("2026-05-06T18:30:00+09:00"),
                venue: "문학",
                awayTeam: lg,
                homeTeam: ssg,
                awayScore: 1,
                homeScore: 6,
                status: .live,
                seasonClassification: .regularSeason
            ),
            makeGameDetail(
                id: UUID(uuidString: "53000000-0000-0000-0000-000000000007")!,
                scheduledStart: isoDate("2026-05-07T18:30:00+09:00"),
                venue: "문학",
                awayTeam: lg,
                homeTeam: ssg,
                awayScore: 1,
                homeScore: 6,
                status: .rainDelay,
                seasonClassification: .regularSeason
            )
        ]

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [ssg, lg],
                games: completedLosses + ignoredGames,
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let ssgSnapshot = try #require(model.standingsSnapshots.first(where: { $0.team.id == "ssg" }))

        #expect(ssgSnapshot.currentStreakText == "3연패")
        #expect(ssgSnapshot.gamesPlayed == 3)
    }

    // standingsStreakSkipsTiesForContinuity 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsStreakSkipsTiesForContinuity() throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-05-05T22:00:00+09:00"))
        let ssg = try #require(base.teams.first(where: { $0.id == "ssg" }))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let games = [
            makeGameDetail(
                id: UUID(uuidString: "54000000-0000-0000-0000-000000000001")!,
                scheduledStart: isoDate("2026-05-01T18:30:00+09:00"),
                venue: "문학",
                awayTeam: lg,
                homeTeam: ssg,
                awayScore: 2,
                homeScore: 5,
                status: .final,
                seasonClassification: .regularSeason
            ),
            makeGameDetail(
                id: UUID(uuidString: "54000000-0000-0000-0000-000000000002")!,
                scheduledStart: isoDate("2026-05-02T18:30:00+09:00"),
                venue: "문학",
                awayTeam: lg,
                homeTeam: ssg,
                awayScore: 5,
                homeScore: 1,
                status: .final,
                seasonClassification: .regularSeason
            ),
            makeGameDetail(
                id: UUID(uuidString: "54000000-0000-0000-0000-000000000003")!,
                scheduledStart: isoDate("2026-05-03T18:30:00+09:00"),
                venue: "문학",
                awayTeam: lg,
                homeTeam: ssg,
                awayScore: 6,
                homeScore: 2,
                status: .final,
                seasonClassification: .regularSeason
            ),
            makeGameDetail(
                id: UUID(uuidString: "54000000-0000-0000-0000-000000000004")!,
                scheduledStart: isoDate("2026-05-04T18:30:00+09:00"),
                venue: "문학",
                awayTeam: lg,
                homeTeam: ssg,
                awayScore: 3,
                homeScore: 3,
                status: .final,
                seasonClassification: .regularSeason
            ),
            makeGameDetail(
                id: UUID(uuidString: "54000000-0000-0000-0000-000000000005")!,
                scheduledStart: isoDate("2026-05-05T18:30:00+09:00"),
                venue: "문학",
                awayTeam: lg,
                homeTeam: ssg,
                awayScore: 4,
                homeScore: 1,
                status: .final,
                seasonClassification: .regularSeason
            )
        ]

        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: [ssg, lg],
                games: games,
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false
        )

        let ssgSnapshot = try #require(model.standingsSnapshots.first(where: { $0.team.id == "ssg" }))

        #expect(ssgSnapshot.currentStreakText == "3연패")
        #expect(ssgSnapshot.recentResultsText == "패 무 패 패 승")
    }

    // homeFallbackWeeklyStandingsUseFiveActualPlayedGamesAfterRainout 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // homeFallbackWeeklyStandingsUseSixActualPlayedGamesWhenAvailable 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // homeFallbackUsesRecentCompletedGamesWhenTodayHasNoGames 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // homeFallbackRefreshLoadsStandingsSourceWhenTodayHasNoGames 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func homeFallbackRefreshLoadsStandingsSourceWhenTodayHasNoGames() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-04-27T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let completedGame = makeGameDetail(
            id: UUID(uuidString: "92500000-0000-0000-0000-000000000002")!,
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
        let state = TeamRankFlowState(
            localRanks: [],
            standingsGames: [completedGame]
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: [lg, doosan],
                games: [],
                notifications: [],
                settings: base.settings
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-04-27T09:00:00+09:00") }
        )

        #expect(model.todayGames.isEmpty)
        #expect(model.homeFallbackStandingsSnapshots.isEmpty)

        await model.refreshHome()

        let lgSnapshot = try #require(model.homeFallbackStandingsSnapshots.first(where: { $0.team.id == "lg" }))
        #expect(await state.standingsSourceFetchCount == 1)
        #expect(lgSnapshot.wins == 1)
        #expect(lgSnapshot.gamesPlayed == 1)
    }

    // homeFallbackCompletedResolverIncludesFinalGamesBeforeToday 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func homeFallbackCompletedResolverIncludesFinalGamesBeforeToday() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-05-25T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let finalGame = makeGameDetail(
            id: UUID(uuidString: "92510000-0000-0000-0000-000000000001")!,
            scheduledStart: isoDate("2026-05-24T17:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason
        )

        let completedGames = HomeFallbackStandingsResolver.completedRegularSeasonGamesBeforeToday(
            games: [finalGame],
            currentDate: isoDate("2026-05-25T09:00:00+09:00"),
            calendar: homeFallbackTestCalendar()
        )

        #expect(completedGames.map(\.id) == [finalGame.id])
    }

    // homeFallbackCompletedResolverExcludesCancelledGames 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func homeFallbackCompletedResolverExcludesCancelledGames() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-05-25T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let cancelledGame = makeGameDetail(
            id: UUID(uuidString: "92510000-0000-0000-0000-000000000002")!,
            scheduledStart: isoDate("2026-05-24T17:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: nil,
            homeScore: nil,
            status: .cancelled,
            seasonClassification: .regularSeason
        )

        let completedGames = HomeFallbackStandingsResolver.completedRegularSeasonGamesBeforeToday(
            games: [cancelledGame],
            currentDate: isoDate("2026-05-25T09:00:00+09:00"),
            calendar: homeFallbackTestCalendar()
        )

        #expect(completedGames.isEmpty)
    }

    // homeFallbackCompletedResolverExcludesTodayAndFutureGames 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func homeFallbackCompletedResolverExcludesTodayAndFutureGames() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-05-25T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let todayGame = makeGameDetail(
            id: UUID(uuidString: "92510000-0000-0000-0000-000000000003")!,
            scheduledStart: isoDate("2026-05-25T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason
        )
        let futureGame = makeGameDetail(
            id: UUID(uuidString: "92510000-0000-0000-0000-000000000004")!,
            scheduledStart: isoDate("2026-05-26T18:30:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason
        )

        let completedGames = HomeFallbackStandingsResolver.completedRegularSeasonGamesBeforeToday(
            games: [todayGame, futureGame],
            currentDate: isoDate("2026-05-25T09:00:00+09:00"),
            calendar: homeFallbackTestCalendar()
        )

        #expect(completedGames.isEmpty)
    }

    // homeFallbackWeeklyStandingsNotEmptyWhenValidFinalGamesExist 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func homeFallbackWeeklyStandingsNotEmptyWhenValidFinalGamesExist() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-05-25T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let doosan = try #require(base.teams.first(where: { $0.id == "doosan" }))
        let finalGame = makeGameDetail(
            id: UUID(uuidString: "92510000-0000-0000-0000-000000000005")!,
            scheduledStart: isoDate("2026-05-24T17:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason
        )
        let referenceGames = HomeFallbackStandingsResolver.referenceWeekCompletedGames(
            games: [finalGame],
            currentDate: isoDate("2026-05-25T09:00:00+09:00"),
            calendar: homeFallbackTestCalendar()
        )

        let snapshots = HomeFallbackStandingsBuilder.makeSnapshots(
            teams: [lg, doosan],
            referenceCompletedGames: referenceGames,
            seasonGames: [finalGame],
            previousRankProvider: { _ in nil }
        )

        #expect(snapshots.isEmpty == false)
        #expect(snapshots.first(where: { $0.team.id == "lg" })?.wins == 1)
    }

    // homeFallbackWeeklyStandingsUsesAllTeamsNotFavoriteOnly 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func homeFallbackWeeklyStandingsUsesAllTeamsNotFavoriteOnly() async throws {
        let base = MockKBOData.makeBootstrap(now: isoDate("2026-05-25T09:00:00+09:00"))
        let lg = try #require(base.teams.first(where: { $0.id == "lg" }))
        let samsung = try #require(base.teams.first(where: { $0.id == "samsung" }))
        let lotte = try #require(base.teams.first(where: { $0.id == "lotte" }))
        let nonFavoriteFinal = makeGameDetail(
            id: UUID(uuidString: "92510000-0000-0000-0000-000000000006")!,
            scheduledStart: isoDate("2026-05-24T17:00:00+09:00"),
            venue: "사직",
            awayTeam: samsung,
            homeTeam: lotte,
            awayScore: 7,
            homeScore: 3,
            status: .final,
            seasonClassification: .regularSeason
        )
        let referenceGames = HomeFallbackStandingsResolver.referenceWeekCompletedGames(
            games: [nonFavoriteFinal],
            currentDate: isoDate("2026-05-25T09:00:00+09:00"),
            calendar: homeFallbackTestCalendar()
        )

        let snapshots = HomeFallbackStandingsBuilder.makeSnapshots(
            teams: [lg, samsung, lotte],
            referenceCompletedGames: referenceGames,
            seasonGames: [nonFavoriteFinal],
            previousRankProvider: { team in team.id == "lg" ? 1 : nil }
        )

        #expect(referenceGames.map(\.id) == [nonFavoriteFinal.id])
        #expect(snapshots.first(where: { $0.team.id == "samsung" })?.wins == 1)
        #expect(snapshots.first(where: { $0.team.id == "lotte" })?.losses == 1)
    }

    // todayGamesUseKSTDateFiltering 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // standingsWinningStreakFireOnlyShowsForActiveThreeGameWinStreak 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // standingsDeriveRemainingRegularSeasonGamesFromStructuredClassification 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // standingsUseVirtualUnscheduledGamesWhenScheduleIsIncomplete 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // bundledBootstrapCompatibilityInfersRegularSeasonFromProviderGameIdentifier 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // uploadedLocalBootstrapProducesNonZeroStandingsRecords 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func uploadedLocalBootstrapProducesNonZeroStandingsRecords() async throws {
        let data = try localBootstrapFixtureData()
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

    // mapperHandlesExternalStatusesAndFallbacks 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    @Test func mapperHandlesExternalStatusesAndFallbacks() async throws {
        #expect(KBODataMapper.mapGameStatus(code: "LIVE", text: nil) == .live)
        #expect(KBODataMapper.mapGameStatus(code: "in_progress", text: nil) == .live)
        #expect(KBODataMapper.mapGameStatus(code: "running", text: nil) == .live)
        #expect(KBODataMapper.mapGameStatus(code: "finished", text: nil) == .final)
        #expect(KBODataMapper.mapGameStatus(code: "completed", text: nil) == .final)
        #expect(KBODataMapper.mapGameStatus(code: nil, text: "우천 중단") == .rainDelay)
        #expect(KBODataMapper.mapGameStatus(code: "suspended", text: nil) == .rainDelay)
        #expect(KBODataMapper.mapGameStatus(code: nil, text: "경기 종료") == .final)
        #expect(KBODataMapper.mapGameStatus(code: "UNKNOWN", text: "준비중") == .upcoming)
        #expect(KBODataMapper.mapGameStatus(code: "UNKNOWN", text: nil, inningText: "1회초") == .live)
        #expect(KBODataMapper.mapGameStatus(code: nil, text: "scheduled", inningText: "Top 1") == .upcoming)
    }

    // mapperBuildsStableDomainModelsFromDTOs 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    @Test func mapperBuildsStableDomainModelsFromDTOs() async throws {
        let bootstrap = MockKBOData.makeBootstrapDTO()
        let mapped = KBODataMapper.mapBootstrap(bootstrap)

        #expect(mapped.teams.count == 10)
        #expect(mapped.games.isEmpty == false)
        #expect(mapped.notifications.isEmpty == false)
        #expect(mapped.games.contains { $0.status == .rainDelay })
        #expect(mapped.games.contains { $0.status == .upcoming && $0.awayScore == nil && $0.homeScore == nil })
    }

    // gameDTOPrefersProviderGameIDForCanonicalIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // mapperUsesStructuredSeasonClassificationWhenAvailable 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
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

    // scoreNotificationPayloadDecodesFromJSON 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // scoreNotificationPayloadExtractorBuildsPayloadFromAPNSUserInfo 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // scoreNotificationPayloadExtractorBuildsPayloadFromBackendAPNsData 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // scoreNotificationPayloadExtractorAcceptsScoringPlayFields 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func scoreNotificationPayloadExtractorAcceptsScoringPlayFields() async throws {
        let payload = ScoreNotificationPayloadExtractor.payload(
            from: [
                "aps": [
                    "alert": [
                        "title": "롯데 득점",
                        "body": "7회초 레이예스 2루타, 2득점 · 롯데 4-2 한화"
                    ]
                ],
                "data": [
                    "gameId": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                    "publicGameId": "20260409LTHT0",
                    "eventType": "SCORE_CHANGED",
                    "awayTeamId": "lotte",
                    "homeTeamId": "hanwha",
                    "eventTeamId": "lotte",
                    "scoringBatterName": "레이예스",
                    "scoringResultText": "2루타",
                    "scoringHitBaseCount": 2,
                    "scoringRunsScored": "2",
                    "scoringRbi": 2,
                    "scoringInning": 7,
                    "scoringInningHalf": "top",
                    "scoringBattingTeamId": "lotte",
                    "scoringBattingTeamName": "롯데",
                    "scoringAwayScoreAfter": 4,
                    "scoringHomeScoreAfter": 2
                ]
            ]
        )

        #expect(payload?.title == "롯데 득점")
        #expect(payload?.scoringBatterName == "레이예스")
        #expect(payload?.scoringResultText == "2루타")
        #expect(payload?.scoringRunsScored == 2)
        #expect(payload?.scoringBattingTeamID == "lotte")
        #expect(payload?.preferredGameNavigationIdentity == "20260409LTHT0")
    }

    // notificationHistoryDecodesOldRecordsSafely 메서드는 이 타입의 주요 동작을 수행합니다.
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
        #expect(item.preferredGameNavigationIdentity == nil)
    }

    // receivedNotificationAppearsInNotificationListModel 메서드는 이 타입의 주요 동작을 수행합니다.
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
        #expect(item.gamePublicID == "20260409LTHT0")
        #expect(item.relatedGameID == nil)
        #expect(item.preferredGameNavigationIdentity == "20260409LTHT0")
        #expect(item.relatedTeamIDs == ["lotte", "hanwha"])
    }

    // notificationTapUsesPublicGameIDInsteadOfNotificationUUID 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    @Test func notificationTapUsesPublicGameIDInsteadOfNotificationUUID() async throws {
        let notificationID = UUID(uuidString: "937FEB4E-B0EF-45C2-9913-8C9543B13840")!
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kia" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let game = makeGameDetail(
            id: UUID(uuidString: "aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa")!,
            scheduledStart: isoDate("2026-06-02T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            note: "public_game_id=20260602-KIA-LOT",
            providerGameID: "sched-202606020930-17bc4f38-2589c61c"
        )
        let item = NotificationItem(
            id: notificationID,
            type: .scoreChange,
            title: "점수 변경",
            body: "KIA 득점",
            sentAt: isoDate("2026-06-02T19:30:00+09:00"),
            isRead: false,
            relatedGameID: nil,
            gamePublicID: "20260602-KIA-LOT",
            gameProviderID: "sched-202606020930-17bc4f38-2589c61c",
            relatedTeamIDs: ["kia", "lotte"]
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: teams, games: [game], notifications: [item], settings: .default),
            usePersistedSettings: false
        )

        let identity = try #require(model.notificationGameDetailNavigationIdentity(for: item))

        #expect(identity == "20260602-KIA-LOT")
        #expect(identity != notificationID.uuidString)
        #expect(model.game(withIdentity: identity)?.publicGameID == "20260602-KIA-LOT")
    }

    // notificationTapUsesProviderIdentityWhenOnlyProviderGameIDExists 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    @Test func notificationTapUsesProviderIdentityWhenOnlyProviderGameIDExists() async throws {
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kia" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lotte" }))
        let providerGameID = "sched-202606020930-17bc4f38-2589c61c"
        let game = makeGameDetail(
            id: UUID(uuidString: "bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb")!,
            scheduledStart: isoDate("2026-06-02T18:30:00+09:00"),
            venue: "사직",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            providerGameID: providerGameID
        )
        let item = NotificationItem(
            id: UUID(),
            type: .inningChange,
            title: "이닝 교체",
            body: "7회말",
            sentAt: isoDate("2026-06-02T20:00:00+09:00"),
            isRead: false,
            relatedGameID: nil,
            gameProviderID: providerGameID,
            relatedTeamIDs: ["kia", "lotte"]
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: teams, games: [game], notifications: [item], settings: .default),
            usePersistedSettings: false
        )

        let identity = try #require(model.notificationGameDetailNavigationIdentity(for: item))

        #expect(identity == "provider:\(providerGameID)")
        #expect(model.game(withIdentity: identity)?.providerGameID == providerGameID)
    }

    // notificationTapDoesNotNavigateWhenOnlyLocalNotificationUUIDExists 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    @Test func notificationTapDoesNotNavigateWhenOnlyLocalNotificationUUIDExists() async throws {
        let notificationID = UUID(uuidString: "cccccccc-3333-3333-3333-cccccccccccc")!
        let item = NotificationItem(
            id: notificationID,
            type: .scoreChange,
            title: "점수 변경",
            body: "로컬 알림",
            sentAt: isoDate("2026-06-02T20:05:00+09:00"),
            isRead: false,
            relatedGameID: notificationID,
            relatedTeamIDs: ["kia"]
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [], notifications: [item], settings: .default),
            usePersistedSettings: false
        )

        #expect(model.notificationGameDetailNavigationIdentity(for: item) == nil)
    }

    // scoreNotificationRouteKeepsOfficialGameIdentifierAsNavigationIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func scoreNotificationRouteKeepsOfficialGameIdentifierAsNavigationIdentity() async throws {
        let payload = ScoreNotificationPayload(
            gameID: "20260323WOLG0",
            eventType: .scoreChange,
            title: "득점",
            body: "키움이 득점했습니다.",
            teamIDs: ["kiwoom", "lg"],
            routeHint: .gameDetail
        )

        let route = ScoreNotificationPayloadExtractor.route(from: payload)

        #expect(route == .gameDetail("20260323WOLG0"))
    }

    // scoreNotificationRoutePrefersPublicGameIdentifier 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func scoreNotificationRoutePrefersPublicGameIdentifier() async throws {
        let payload = ScoreNotificationPayload(
            gameID: "937FEB4E-B0EF-45C2-9913-8C9543B13840",
            eventType: .scoreChange,
            title: "득점",
            body: "KIA가 득점했습니다.",
            publicGameID: "20260602-KIA-LOT",
            providerGameID: "sched-202606020930-17bc4f38-2589c61c",
            routeHint: .gameDetail
        )

        let route = ScoreNotificationPayloadExtractor.route(from: payload)

        #expect(route == .gameDetail("20260602-KIA-LOT"))
    }

    // notificationRouteCanTargetNotificationsScreenWithoutTabSelection 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // notificationRegistrationPayloadMapsFavoriteTeamAlertsAndQuietHours 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // notificationRegistrationPayloadSupportsDeniedAuthorizationState 메서드는 이 타입의 주요 동작을 수행합니다.
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

    @Test func notificationRegistrationPayloadForcesFavoriteTeamOnlyWhenFavoriteTeamExists() async throws {
        let settings = notificationRegistrationSettings(
            favoriteTeamID: "lotte",
            preferences: NotificationPreferences(favoriteTeamOnlyEnabled: false)
        )

        let payload = try #require(
            NotificationRegistrationPayload(
                deviceToken: "abc123",
                settings: settings,
                authorizationStatus: .authorized
            )
        )

        #expect(payload.favoriteTeamID == "lotte")
        #expect(payload.favoriteTeamOnlyEnabled == true)
    }

    @Test func notificationRegistrationEnvironmentNormalizesConfiguredValues() async throws {
        #expect(NotificationRegistrationEnvironment.normalize("sandbox") == "sandbox")
        #expect(NotificationRegistrationEnvironment.normalize(" Sandbox ") == "sandbox")
        #expect(NotificationRegistrationEnvironment.normalize("development") == "sandbox")
        #expect(NotificationRegistrationEnvironment.normalize("production") == "production")
        #expect(NotificationRegistrationEnvironment.normalize(" Production ") == "production")
        #expect(NotificationRegistrationEnvironment.normalize("prod") == "production")
        #expect(NotificationRegistrationEnvironment.normalize("invalid") == nil)
        #expect(NotificationRegistrationEnvironment.normalize(nil) == nil)
    }

    @Test func notificationRegistrationEnvironmentResolvesExplicitValuesBeforeFallback() async throws {
        #expect(NotificationRegistrationEnvironment.resolved(from: "sandbox") == "sandbox")
        #expect(NotificationRegistrationEnvironment.resolved(from: "production") == "production")
    }

    @Test func notificationRegistrationEnvironmentFallsBackWhenConfiguredValueIsInvalid() async throws {
        #if DEBUG
        let expectedFallback = "sandbox"
        #else
        let expectedFallback = "production"
        #endif

        #expect(NotificationRegistrationEnvironment.resolved(from: nil) == expectedFallback)
        #expect(NotificationRegistrationEnvironment.resolved(from: "invalid") == expectedFallback)
    }

    @Test func notificationRegistrationEnvironmentCurrentUsesInfoPlistConfiguration() async throws {
        #if DEBUG
        #expect(NotificationRegistrationEnvironment.current == "sandbox")
        #else
        #expect(NotificationRegistrationEnvironment.current == "production")
        #endif
    }

    @Test func liveActivityRegistrationURLPrefersExplicitURLAndDerivesDeviceEndpoint() async throws {
        let notificationURL = try #require(URL(string: "https://kboscore-back.onrender.com/devices/register"))
        let explicitURL = try #require(LiveActivityTokenRegistrationClientFactory.configuredLiveActivityRegistrationURL(
            processValue: nil,
            explicitBundleValue: "https://kboscore-back.onrender.com/live-activities/register",
            notificationURL: notificationURL
        ))
        let derivedURL = try #require(LiveActivityTokenRegistrationClientFactory.configuredLiveActivityRegistrationURL(
            processValue: nil,
            explicitBundleValue: nil,
            notificationURL: notificationURL
        ))

        #expect(explicitURL.absoluteString == "https://kboscore-back.onrender.com/live-activities/register")
        #expect(derivedURL.absoluteString == "https://kboscore-back.onrender.com/devices/live-activities/register")
    }

    @Test func liveActivityPushToStartRegistrationURLDerivesDeviceEndpoint() async throws {
        let notificationURL = try #require(URL(string: "https://kboscore-back.onrender.com/devices/register"))
        let derivedURL = try #require(LiveActivityPushToStartTokenRegistrationClientFactory.configuredPushToStartRegistrationURL(
            processValue: nil,
            explicitBundleValue: nil,
            notificationURL: notificationURL
        ))

        #expect(derivedURL.absoluteString == "https://kboscore-back.onrender.com/devices/live-activities/push-to-start/register")
    }

    @Test func liveActivityPushToStartPayloadCarriesAutoStartPreferences() async throws {
        let payload = LiveActivityPushToStartTokenRegistrationPayload(
            pushToStartToken: "start-token",
            settings: AppSettings(
                favoriteTeamID: "lg",
                notificationPreferences: NotificationPreferences(gameStart: true, favoriteTeamOnlyEnabled: true),
                quietHours: QuietHours(isEnabled: false, startHour: 23, endHour: 7),
                liveActivitiesEnabled: true,
                liveActivityAutoStartEnabled: false,
                appearance: .system,
                teamThemeMode: .favoriteTeam
            ),
            authorizationStatus: .authorized
        )
        let encoded = try JSONEncoder().encode(payload)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(json.contains("\"pushToStartToken\":\"start-token\""))
        #expect(json.contains("\"favoriteTeamID\":\"lg\""))
        #expect(json.contains("\"liveActivityAutoStartEnabled\":false"))
        #expect(json.contains("\"favoriteTeamOnlyEnabled\":true"))
    }

    // notificationPreferencesDefaultDetailedValuesMatchBackendDefaults 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // appSettingsPersistenceRoundTripPreservesDetailedNotificationPreferences 메서드는 이 타입의 주요 동작을 수행합니다.
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
                muteWhenLosingEnabled: true
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
        #expect(decoded.notificationPreferences.muteWhenLosingEnabled == true)
    }

    // notificationRegistrationKeyChangesWhenDetailedNotificationSettingsChange 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // notificationRegistrationDeduplicationSkipsDuplicateInFlightKey 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // notificationRegistrationDeduplicationSkipsAlreadyRegisteredKeyAfterSuccess 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // notificationRegistrationDeduplicationStartsWhenRegistrationKeyChanges 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // notificationRegistrationDeduplicationDoesNotCacheFailedOrSkippedRequestsAsSuccess 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // backendDeviceRegistrationSyncsDisabledNotificationPreferences 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func backendDeviceRegistrationSyncsDisabledNotificationPreferences() async throws {
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

        let didRegister = await eventually(timeout: 3.0) {
            await client.requestCount() == 1
        }
        let payload = try #require(await client.recordedPayloads().last)

        #expect(didRegister)
        #expect(payload.notificationsAuthorized == true)
        #expect(payload.gameStartEnabled == false)
        #expect(payload.scoreChangeEnabled == false)
        #expect(payload.leadChangeEnabled == false)
        #expect(payload.gameEndEnabled == false)
        #expect(payload.onBaseEnabled == false)
        #expect(payload.inningChangeEnabled == false)
        #expect(payload.favoriteTeamOnlyEnabled == true)
        #expect(model.notificationRegistrationSyncStatus == .synced)
    }

    // backendDeviceRegistrationSyncsDeniedAuthorizationState 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func backendDeviceRegistrationSyncsDeniedAuthorizationState() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .denied

        model.settings = notificationRegistrationSettings(favoriteTeamID: "lotte")

        let didRegister = await eventually(timeout: 1.0) {
            await client.requestCount() == 1
        }
        let payload = try #require(await client.recordedPayloads().last)

        #expect(didRegister)
        #expect(payload.notificationsAuthorized == false)
        #expect(payload.scoreChangeEnabled == true)
        #expect(model.notificationRegistrationSyncStatus == .synced)
    }

    // backendDeviceRegistrationSkipsWhenFavoriteTeamIsMissing 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // backendDeviceRegistrationRunsWhenEligible 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // backendDeviceRegistrationPayloadAndKeyIncludeFavoriteTeamOnlyPreference 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func backendDeviceRegistrationPayloadAndKeyIncludeFavoriteTeamOnlyPreference() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .authorized

        model.settings = notificationRegistrationSettings(
            favoriteTeamID: "lotte",
            preferences: NotificationPreferences(favoriteTeamOnlyEnabled: true)
        )

        let didRegister = await eventually(timeout: 1.0) {
            await client.requestCount() == 1
        }
        let payload = try #require(await client.recordedPayloads().last)
        let key = NotificationRegistrationKey(payload: payload, endpointDescription: client.debugEndpointDescription)

        #expect(didRegister)
        #expect(payload.favoriteTeamOnlyEnabled == true)
        #expect(key.favoriteTeamOnlyEnabled == true)
    }

    @Test func backendDeviceRegistrationPayloadSendsAllEnabledNotificationPreferences() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .authorized

        model.settings = notificationRegistrationSettings(
            favoriteTeamID: "lotte",
            preferences: NotificationPreferences(
                gameStart: true,
                scoreChange: true,
                leadChange: true,
                gameEnd: true,
                rainDelay: true,
                onBaseEnabled: true,
                inningChangeEnabled: true,
                favoriteTeamOnlyEnabled: true,
                muteWhenLosingEnabled: true
            )
        )

        let didRegister = await eventually(timeout: 1.0) {
            await client.requestCount() == 1
        }
        let payload = try #require(await client.recordedPayloads().last)

        #expect(didRegister)
        #expect(payload.notificationsAuthorized == true)
        #expect(payload.gameStartEnabled == true)
        #expect(payload.scoreChangeEnabled == true)
        #expect(payload.leadChangeEnabled == true)
        #expect(payload.gameEndEnabled == true)
        #expect(payload.onBaseEnabled == true)
        #expect(payload.inningChangeEnabled == true)
        #expect(payload.favoriteTeamOnlyEnabled == true)
        #expect(payload.muteWhenLosingEnabled == true)
    }

    @Test func backendDeviceRegistrationPayloadPreservesEnabledPreferencesWhenResyncing() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .authorized
        model.settings = notificationRegistrationSettings(
            favoriteTeamID: "lotte",
            preferences: NotificationPreferences(
                gameStart: true,
                scoreChange: true,
                leadChange: true,
                gameEnd: true,
                rainDelay: true,
                onBaseEnabled: true,
                inningChangeEnabled: true,
                favoriteTeamOnlyEnabled: true,
                muteWhenLosingEnabled: true
            )
        )

        let didRegisterInitialSettings = await eventually(timeout: 3.0) {
            await client.requestCount() == 1
        }

        var updatedSettings = model.settings
        updatedSettings.quietHours = QuietHours(isEnabled: true, startHour: 23, endHour: 7)
        model.settings = updatedSettings

        let didRegisterUpdatedSettings = await eventually(timeout: 3.0) {
            await client.requestCount() == 2
        }
        let payload = try #require(await client.recordedPayloads().last)

        #expect(didRegisterInitialSettings)
        #expect(didRegisterUpdatedSettings)
        #expect(payload.scoreChangeEnabled == true)
        #expect(payload.onBaseEnabled == true)
        #expect(payload.inningChangeEnabled == true)
        #expect(payload.favoriteTeamOnlyEnabled == true)
        #expect(payload.muteWhenLosingEnabled == true)
    }

    @Test func backendDeviceRegistrationPreservesFavoriteTeamOnlyWhenAPNsTokenReregisters() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        let delegate = AppNotificationDelegate()
        model.connectNotificationDelegate(delegate)
        model.notificationAuthorizationStatus = .authorized
        model.settings = notificationRegistrationSettings(
            favoriteTeamID: "lotte",
            preferences: NotificationPreferences(favoriteTeamOnlyEnabled: true)
        )

        delegate.onDeviceToken?("abc123")
        let didRegisterInitialToken = await eventually(timeout: 1.0) {
            await client.requestCount() == 1
        }

        delegate.onDeviceToken?("def456")
        let didRegisterUpdatedToken = await eventually(timeout: 1.0) {
            await client.requestCount() == 2
        }
        let payloads = await client.recordedPayloads()

        #expect(didRegisterInitialToken)
        #expect(didRegisterUpdatedToken)
        #expect(payloads.map(\.favoriteTeamOnlyEnabled) == [true, true])
        #expect(model.settings.notificationPreferences.favoriteTeamOnlyEnabled == true)
    }

    @Test func backendDeviceRegistrationPayloadSendsOnlyDisabledTogglesAsFalse() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .authorized

        model.settings = notificationRegistrationSettings(
            favoriteTeamID: "lotte",
            preferences: NotificationPreferences(
                gameStart: true,
                scoreChange: false,
                leadChange: true,
                gameEnd: true,
                rainDelay: true,
                onBaseEnabled: true,
                inningChangeEnabled: false,
                favoriteTeamOnlyEnabled: true,
                muteWhenLosingEnabled: false
            )
        )

        let didRegister = await eventually(timeout: 3.0) {
            await client.requestCount() == 1
        }
        let payload = try #require(await client.recordedPayloads().last)

        #expect(didRegister)
        #expect(payload.gameStartEnabled == true)
        #expect(payload.scoreChangeEnabled == false)
        #expect(payload.leadChangeEnabled == true)
        #expect(payload.gameEndEnabled == true)
        #expect(payload.onBaseEnabled == true)
        #expect(payload.inningChangeEnabled == false)
        #expect(payload.favoriteTeamOnlyEnabled == true)
        #expect(payload.muteWhenLosingEnabled == false)
    }

    @Test func notificationRegistrationDebugDescriptionsDoNotExposeDeviceToken() async throws {
        let payload = NotificationRegistrationPayload(
            platform: "ios",
            environment: "sandbox",
            deviceToken: "abcdef1234567890",
            installationId: "install-1",
            favoriteTeamID: "lotte",
            notificationsAuthorized: true,
            alertTypes: [.gameStart, .scoreChange],
            quietHours: nil,
            scoreChangeEnabled: true,
            onBaseEnabled: true,
            inningChangeEnabled: true,
            favoriteTeamOnlyEnabled: true
        )
        let key = NotificationRegistrationKey(payload: payload, endpointDescription: "https://example.com/devices/register")

        #expect(payload.debugRegistrationDescription.contains("abcdef1234567890") == false)
        #expect(payload.debugRegistrationDescription.contains("abcdef12") == false)
        #expect(key.description.contains("abcdef1234567890") == false)
        #expect(key.description.contains("abcdef12") == false)
        #expect(key.description.contains("tokenPrefix") == false)
        #expect(payload.debugRegistrationDescription.contains("environment=sandbox"))
        #expect(payload.debugRegistrationDescription.contains("favoriteTeamID=lotte"))
        #expect(payload.debugRegistrationDescription.contains("scoreChangeEnabled=true"))
        #expect(payload.debugRegistrationDescription.contains("onBaseEnabled=true"))
        #expect(payload.debugRegistrationDescription.contains("inningChangeEnabled=true"))
        #expect(payload.debugRegistrationDescription.contains("favoriteTeamOnlyEnabled=true"))
    }

    // backendDeviceRegistrationPayloadAndKeyIncludeMuteWhenLosingPreference 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func backendDeviceRegistrationPayloadAndKeyIncludeMuteWhenLosingPreference() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .authorized

        model.settings = notificationRegistrationSettings(
            favoriteTeamID: "lotte",
            preferences: NotificationPreferences(muteWhenLosingEnabled: true)
        )

        let didRegister = await eventually(timeout: 1.0) {
            await client.requestCount() == 1
        }
        let payload = try #require(await client.recordedPayloads().last)
        let key = NotificationRegistrationKey(payload: payload, endpointDescription: client.debugEndpointDescription)

        #expect(didRegister)
        #expect(payload.muteWhenLosingEnabled == true)
        #expect(key.muteWhenLosingEnabled == true)
    }

    // backendDeviceRegistrationKeepsTeamFilterPreferencesWhenOtherSettingChanges 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func backendDeviceRegistrationKeepsTeamFilterPreferencesWhenOtherSettingChanges() async throws {
        let client = RecordingNotificationRegistrationClient()
        let model = AppModel(
            notificationRegistrationClient: client,
            usePersistedSettings: false
        )
        model.apnsDeviceToken = "abc123"
        model.notificationAuthorizationStatus = .authorized

        model.settings = notificationRegistrationSettings(
            favoriteTeamID: "lotte",
            preferences: NotificationPreferences(
                favoriteTeamOnlyEnabled: true,
                muteWhenLosingEnabled: true
            )
        )

        let didRegisterInitialSettings = await eventually(timeout: 1.0) {
            await client.requestCount() == 1
        }

        var updatedSettings = model.settings
        updatedSettings.notificationPreferences.onBaseEnabled = true
        model.settings = updatedSettings

        let didRegisterUpdatedSettings = await eventually(timeout: 1.0) {
            await client.requestCount() == 2
        }
        let payload = try #require(await client.recordedPayloads().last)
        let key = NotificationRegistrationKey(payload: payload, endpointDescription: client.debugEndpointDescription)

        #expect(didRegisterInitialSettings)
        #expect(didRegisterUpdatedSettings)
        #expect(payload.onBaseEnabled == true)
        #expect(payload.favoriteTeamOnlyEnabled == true)
        #expect(payload.muteWhenLosingEnabled == true)
        #expect(key.favoriteTeamOnlyEnabled == true)
        #expect(key.muteWhenLosingEnabled == true)
    }

    // backendDeviceRegistrationRunsWhenAuthorizationIsProvisional 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // remoteNotificationRegistrationClientPostsJSONPayload 메서드는 이 타입의 주요 동작을 수행합니다.
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
            quietHours: NotificationRegistrationQuietHours(startHour: 23, endHour: 7),
            favoriteTeamOnlyEnabled: true
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
        let json = try #require(String(data: body, encoding: .utf8))
        let decoded = try JSONDecoder().decode(NotificationRegistrationPayload.self, from: body)

        #expect(status == .synced)
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 8)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(json.contains("\"favorite_team_only_enabled\":true"))
        #expect(json.contains("\"favoriteTeamOnlyEnabled\"") == false)
        #expect(decoded == payload)
        #expect(decoded.installationId == "install-1")
        #expect(decoded.gameStartEnabled == true)
        #expect(decoded.scoreChangeEnabled == true)
        #expect(decoded.leadChangeEnabled == true)
        #expect(decoded.gameEndEnabled == true)
        #expect(decoded.onBaseEnabled == false)
        #expect(decoded.inningChangeEnabled == false)
        #expect(decoded.favoriteTeamOnlyEnabled == true)
        #expect(decoded.muteWhenLosingEnabled == false)
    }

    @Test func notificationRegistrationPayloadDecodesLegacyCamelCaseFavoriteTeamOnlyPreference() throws {
        let payload = try JSONDecoder().decode(
            NotificationRegistrationPayload.self,
            from: Data("""
            {
              "platform": "ios",
              "environment": "sandbox",
              "deviceToken": "abc123",
              "installationId": "install-1",
              "favoriteTeamID": "lg",
              "notificationsAuthorized": true,
              "alertTypes": ["gameStart"],
              "favoriteTeamOnlyEnabled": true
            }
            """.utf8)
        )

        #expect(payload.favoriteTeamOnlyEnabled == true)
    }

    @Test func notificationInstallationIDMigratesLegacyUserDefaultsToKeychain() throws {
        let suiteName = "NotificationInstallationIDTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let service = "com.chogm.kboScore.tests.notification-installation-id.\(UUID().uuidString)"
        let account = "notification-installation-id"
        let legacyValue = "legacy-installation-id"
        defaults.set(legacyValue, forKey: NotificationInstallationID.legacyStorageKey)
        _ = NotificationInstallationID.deleteSavedValue(service: service, account: account)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            _ = NotificationInstallationID.deleteSavedValue(service: service, account: account)
        }

        let migrated = NotificationInstallationID.loadOrCreate(
            legacyDefaults: defaults,
            service: service,
            account: account
        )
        let reloaded = NotificationInstallationID.loadOrCreate(
            legacyDefaults: defaults,
            service: service,
            account: account
        )

        #expect(migrated == legacyValue)
        #expect(reloaded == legacyValue)
        #expect(defaults.string(forKey: NotificationInstallationID.legacyStorageKey) == nil)
        #expect(NotificationInstallationID.loadSavedValue(service: service, account: account) == legacyValue)
    }

    @Test func remoteLiveActivityTokenRegistrationClientSetsTimeout() async throws {
        let session = makeStubSession()
        let client = RemoteLiveActivityTokenRegistrationClient(
            endpointURL: URL(string: "https://example.com/devices/live-activities/register")!,
            session: session
        )
        let payload = LiveActivityTokenRegistrationPayload(
            activityId: "activity-1",
            environment: "sandbox",
            activityToken: "activity-token",
            installationId: "install-1",
            favoriteTeamID: "lg",
            publicGameID: "public-1",
            providerGameID: "provider-1",
            databaseID: UUID().uuidString,
            stableDetailIdentity: "stable-1"
        )

        URLProtocolStub.testResponses = [
            "https://example.com/devices/live-activities/register": StubResponse(statusCode: 200, data: Data())
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        let status = try await client.register(payload)
        let request = try #require(URLProtocolStub.lastRequest)

        #expect(status == .synced)
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 8)
    }

    @Test func remoteLiveActivityPushToStartRegistrationClientSetsTimeout() async throws {
        let session = makeStubSession()
        let client = RemoteLiveActivityPushToStartTokenRegistrationClient(
            endpointURL: URL(string: "https://example.com/devices/live-activities/push-to-start/register")!,
            session: session
        )
        let payload = LiveActivityPushToStartTokenRegistrationPayload(
            environment: "sandbox",
            pushToStartToken: "push-to-start-token",
            installationId: "install-1",
            favoriteTeamID: "lg",
            notificationsAuthorized: true,
            liveActivitiesEnabled: true,
            liveActivityAutoStartEnabled: true,
            gameStartEnabled: true,
            favoriteTeamOnlyEnabled: false
        )

        URLProtocolStub.testResponses = [
            "https://example.com/devices/live-activities/push-to-start/register": StubResponse(statusCode: 200, data: Data())
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        let status = try await client.register(payload)
        let request = try #require(URLProtocolStub.lastRequest)

        #expect(status == .synced)
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 8)
    }

    @Test func liveActivityRegistrationDebugDescriptionsDoNotExposeTokens() {
        let activityPayload = LiveActivityTokenRegistrationPayload(
            activityId: "activity-1",
            environment: "sandbox",
            activityToken: "sensitive-activity-token-value",
            installationId: "install-1",
            favoriteTeamID: "lg",
            publicGameID: "public-1",
            providerGameID: "provider-1",
            databaseID: UUID().uuidString,
            stableDetailIdentity: "stable-1"
        )
        let pushToStartPayload = LiveActivityPushToStartTokenRegistrationPayload(
            environment: "sandbox",
            pushToStartToken: "sensitive-push-to-start-token-value",
            installationId: "install-1",
            favoriteTeamID: "lg",
            notificationsAuthorized: true,
            liveActivitiesEnabled: true,
            liveActivityAutoStartEnabled: true,
            gameStartEnabled: true,
            favoriteTeamOnlyEnabled: false
        )

        let activityDescription = LiveActivityTokenRegistrationKey(
            payload: activityPayload,
            endpointDescription: "https://example.com/devices/live-activities/register"
        ).description
        let pushToStartDescription = LiveActivityPushToStartTokenRegistrationKey(
            payload: pushToStartPayload,
            endpointDescription: "https://example.com/devices/live-activities/push-to-start/register"
        ).description

        #expect(activityDescription.contains("sensitive-activity-token-value") == false)
        #expect(activityDescription.contains("sensitive") == false)
        #expect(pushToStartDescription.contains("sensitive-push-to-start-token-value") == false)
        #expect(pushToStartDescription.contains("sensitive") == false)
    }

    // teamIdentityCatalogKeepsTextAndThemeIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func teamIdentityCatalogKeepsTextAndThemeIdentity() async throws {
        let lgIdentity = TeamIdentity.catalog["lg"]
        let hanwhaIdentity = TeamIdentity.catalog["hanwha"]
        let doosanIdentity = TeamIdentity.catalog["doosan"]
        let kiwoomIdentity = TeamIdentity.catalog["kiwoom"]
        let lotteIdentity = TeamIdentity.catalog["lotte"]
        let samsungIdentity = TeamIdentity.catalog["samsung"]

        #expect(lgIdentity?.monogram == "LG")
        #expect(lgIdentity?.shortLabel == "LG")
        #expect(doosanIdentity?.monogram == "두산")
        #expect(hanwhaIdentity?.monogram == "한화")
        #expect(kiwoomIdentity?.monogram == "키움")
        #expect(lotteIdentity?.monogram == "롯데")
        #expect(samsungIdentity?.monogram == "삼성")
        #expect(hanwhaIdentity?.displayName == "한화 이글스")
        #expect(hanwhaIdentity?.themeID == .hanwha)
    }

    // teamIdentityCatalogKeepsHomeHeroWatermarkNicknames 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func teamIdentityCatalogKeepsHomeHeroWatermarkNicknames() async throws {
        let expectedNicknames = [
            "doosan": "Bears",
            "hanwha": "Eagles",
            "kia": "Tigers",
            "kiwoom": "Heroes",
            "kt": "Wiz",
            "lg": "Twins",
            "lotte": "Giants",
            "nc": "Dinos",
            "samsung": "Lions",
            "ssg": "Landers"
        ]

        for (teamID, expectedNickname) in expectedNicknames {
            #expect(TeamIdentity.catalog[teamID]?.homeHeroWatermarkLabel == expectedNickname)
        }
    }

    // unknownTeamIdentityUsesNeutralTheme 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func unknownTeamIdentityUsesNeutralTheme() async throws {
        let team = Team(id: "unknown", name: "Unknown Team", shortName: "UNK", englishName: "Unknown", markText: "UNK")

        #expect(team.identity.displayName == "Unknown Team")
        #expect(team.identity.monogram == "UNK")
        #expect(team.identity.homeHeroWatermarkLabel == "UNK")
        #expect(team.identity.themeID == .neutral)
    }

    // currentThemeFollowsFavoriteTeamPreference 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func currentThemeFollowsFavoriteTeamPreference() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)

        model.settings.favoriteTeamID = "ssg"
        model.settings.teamThemeMode = .favoriteTeam
        #expect(model.currentTheme.id == .ssg)

        model.settings.teamThemeMode = .systemDefault
        #expect(model.currentTheme.id == .neutral)
    }

    // favoriteTeamOnboardingCatalogContainsAllTenTeamsOffline 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func favoriteTeamOnboardingCatalogContainsAllTenTeamsOffline() throws {
        let teams = FavoriteTeamCatalog.teams
        let expectedIDs = Set(["kia", "samsung", "lg", "doosan", "kt", "ssg", "lotte", "hanwha", "nc", "kiwoom"])

        #expect(teams.count == 10)
        #expect(Set(teams.map(\.id)) == expectedIDs)
        #expect(teams.map(\.id) == FavoriteTeamCatalog.orderedTeamIDs)
    }

    // favoriteTeamOnboardingCatalogUsesUniqueIDs 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func favoriteTeamOnboardingCatalogUsesUniqueIDs() throws {
        let teams = FavoriteTeamCatalog.teams

        #expect(Set(teams.map(\.id)).count == teams.count)
    }

    // favoriteTeamOnboardingDoesNotDependOnRepositoryTeamsWhenSupabaseUnavailable 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // firstInstallPickerOpeningDoesNotCallFavoriteTeamRemoteRefresh 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func firstInstallPickerOpeningDoesNotCallFavoriteTeamRemoteRefresh() async throws {
        let recorder = FavoriteScheduleCallRecorder()
        let repository = FavoriteScheduleCountingRepository(recorder: recorder)
        let model = AppModel(repository: repository, usePersistedSettings: false)
        model.settings.favoriteTeamID = nil

        await model.loadIfNeeded()

        #expect(FavoriteTeamCatalog.teams.count == 10)
        #expect(await recorder.callCount() == 0)
    }

    // appStartupWithNoFavoriteTeamDoesNotCallHomeFavoriteGameRefresh 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func appStartupWithNoFavoriteTeamDoesNotCallHomeFavoriteGameRefresh() async throws {
        let recorder = FavoriteScheduleCallRecorder()
        let repository = FavoriteScheduleCountingRepository(recorder: recorder)
        let model = AppModel(repository: repository, usePersistedSettings: false)
        model.settings.favoriteTeamID = nil

        await model.loadIfNeeded()
        await model.refreshTodayOnForeground()

        #expect(await recorder.callCount() == 0)
    }

    // favoriteTeamOnboardingSelectingLottePersistsExistingID 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func favoriteTeamOnboardingSelectingLottePersistsExistingID() throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)

        model.completeFavoriteTeamOnboarding(with: "lotte")

        #expect(model.settings.favoriteTeamID == "lotte")
    }

    // favoriteTeamOnboardingSelectingHanwhaPersistsExistingID 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func favoriteTeamOnboardingSelectingHanwhaPersistsExistingID() throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)

        model.completeFavoriteTeamOnboarding(with: "hanwha")

        #expect(model.settings.favoriteTeamID == "hanwha")
    }

    // favoriteTeamDependentFlowsReadSelectedFavoriteTeamID 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func favoriteTeamDependentFlowsReadSelectedFavoriteTeamID() throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)

        model.completeFavoriteTeamOnboarding(with: "hanwha")

        #expect(model.settings.favoriteTeamID == "hanwha")
        #expect(model.currentTheme.id == .hanwha)
        #expect(model.favoriteTeam?.id == "hanwha")
    }

    // favoriteTeamSelectionStartsPostOnboardingFavoriteRefresh 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // favoriteTeamLiveGameFindsCurrentLiveMatch 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func favoriteTeamLiveGameFindsCurrentLiveMatch() async throws {
        let model = AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)
        model.settings.favoriteTeamID = "lg"

        let liveGame = try #require(model.favoriteTeamLiveGame)

        #expect(liveGame.status == .live)
        #expect(liveGame.involves(teamID: "lg"))
        #expect(model.shouldShowLiveActivityAction(for: liveGame))
    }

    // favoriteTeamLiveActivitySnapshotMapsFavoriteSideAndStatus 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveActivitySnapshotBuildsActivityAttributesAndContentState 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveActivityContentStateIncludesCurrentBatterAndPitcher 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveActivitySnapshotKeepsZeroZeroLiveScoreVisible 메서드는 이 타입의 주요 동작을 수행합니다.
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

    @Test func liveActivityOffenseResolverShowsIndicatorOnlyForLiveOffenseSide() {
        #expect(KBOLiveActivityOffenseResolver.offenseSide(isPreGame: false, summaryText: "LIVE", inningText: "5회 초") == .away)
        #expect(KBOLiveActivityOffenseResolver.offenseSide(isPreGame: false, summaryText: "LIVE", inningText: "Bottom 8") == .home)
        #expect(KBOLiveActivityOffenseResolver.offenseSide(isPreGame: true, summaryText: "18:30", inningText: "Top 1") == nil)
        #expect(KBOLiveActivityOffenseResolver.offenseSide(isPreGame: false, summaryText: "종료", inningText: "9회 말") == nil)
        #expect(KBOLiveActivityOffenseResolver.offenseSide(isPreGame: false, summaryText: "취소", inningText: "1회 초") == nil)
    }

    // liveActivitySnapshotUsesLatestSnapshotCountAndPlayers 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveActivityPregameStateShowsStartingPitchersOnly 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveActivityPregameSnapshotShowsProbableStartersWithoutLiveState 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveActivityAutoStartRejectsScheduledGameThirtyOneMinutesBeforeStart 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityAutoStartRejectsScheduledGameThirtyOneMinutesBeforeStart() async throws {
        let scheduledAt = isoDate("2026-04-28T18:30:00+09:00")
        let now = scheduledAt.addingTimeInterval(-31 * 60)

        let isEligible = LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
            status: .upcoming,
            scheduledAt: scheduledAt,
            now: now
        )

        #expect(isEligible == false)
    }

    // liveActivityAutoStartAllowsScheduledGameExactlyThirtyMinutesBeforeStart 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityAutoStartAllowsScheduledGameExactlyThirtyMinutesBeforeStart() async throws {
        let scheduledAt = isoDate("2026-04-28T18:30:00+09:00")
        let now = scheduledAt.addingTimeInterval(-30 * 60)

        let isEligible = LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
            status: .upcoming,
            scheduledAt: scheduledAt,
            now: now
        )

        #expect(isEligible)
    }

    // liveActivityAutoStartAllowsScheduledGameTenMinutesBeforeStart 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityAutoStartAllowsScheduledGameTenMinutesBeforeStart() async throws {
        let scheduledAt = isoDate("2026-04-28T18:30:00+09:00")
        let now = scheduledAt.addingTimeInterval(-10 * 60)

        let isEligible = LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
            status: .upcoming,
            scheduledAt: scheduledAt,
            now: now
        )

        #expect(isEligible)
    }

    // liveActivityAutoStartAllowsScheduledGameAfterStartWhenStillUpcoming 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityAutoStartAllowsScheduledGameAfterStartWhenStillUpcoming() async throws {
        let scheduledAt = isoDate("2026-04-28T18:30:00+09:00")
        let now = scheduledAt.addingTimeInterval(10 * 60)

        let isEligible = LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
            status: .upcoming,
            scheduledAt: scheduledAt,
            now: now
        )

        #expect(isEligible)
    }

    // liveActivityAutoStartAllowsLiveGameWithoutScheduledAt 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityAutoStartAllowsLiveGameWithoutScheduledAt() async throws {
        let isEligible = LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
            status: .live,
            scheduledAt: nil,
            now: isoDate("2026-04-28T18:30:00+09:00")
        )

        #expect(isEligible)
    }

    // liveActivityAutoStartRejectsScheduledGameWithoutScheduledAt 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityAutoStartRejectsScheduledGameWithoutScheduledAt() async throws {
        let decision = LiveActivityAutoStartEligibility.decision(
            status: .upcoming,
            scheduledAt: nil,
            now: isoDate("2026-04-28T18:30:00+09:00")
        )

        #expect(decision == .missingScheduledAt)
    }

    // liveActivityAutoStartRejectsFinalGame 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityAutoStartRejectsFinalGame() async throws {
        let isEligible = LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
            status: .final,
            scheduledAt: isoDate("2026-04-28T18:30:00+09:00"),
            now: isoDate("2026-04-28T18:30:00+09:00")
        )

        #expect(isEligible == false)
    }

    // liveActivityAutoStartRejectsCancelledGame 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityAutoStartRejectsCancelledGame() async throws {
        let isEligible = LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
            status: .cancelled,
            scheduledAt: isoDate("2026-04-28T18:30:00+09:00"),
            now: isoDate("2026-04-28T18:30:00+09:00")
        )

        #expect(isEligible == false)
    }

    // liveActivityAutoStartRejectsPostponedGameMappedAsCancelled 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityAutoStartRejectsPostponedGameMappedAsCancelled() async throws {
        let status = KBODataMapper.mapGameStatus(code: "postponed", text: nil)

        let isEligible = LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
            status: status,
            scheduledAt: isoDate("2026-04-28T18:30:00+09:00"),
            now: isoDate("2026-04-28T18:30:00+09:00")
        )

        #expect(status == .cancelled)
        #expect(isEligible == false)
    }

    // liveActivityAutoStartRejectsCompletedGameMappedAsFinal 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityAutoStartRejectsCompletedGameMappedAsFinal() async throws {
        let status = KBODataMapper.mapGameStatus(code: "completed", text: nil)

        let isEligible = LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
            status: status,
            scheduledAt: isoDate("2026-04-28T18:30:00+09:00"),
            now: isoDate("2026-04-28T18:30:00+09:00")
        )

        #expect(status == .final)
        #expect(isEligible == false)
    }

    // gameDetailAutoStartDoesNotCallLiveActivityControllerWhenEligibilityIsFalse 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailAutoStartDoesNotCallLiveActivityControllerWhenEligibilityIsFalse() async throws {
        let controller = TestLiveActivityController(isSupported: true)
        let scheduledAt = isoDate("2026-04-28T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let game = makeGameDetail(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1")!,
            scheduledStart: scheduledAt,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason
        )
        let model = AppModel(
            liveActivityController: controller,
            bootstrap: KBOBootstrapData(teams: teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { scheduledAt.addingTimeInterval(-31 * 60) }
        )
        model.settings.favoriteTeamID = "lg"
        model.settings.liveActivitiesEnabled = true

        await model.startOrUpdateLiveActivityIfNeeded(for: game)

        #expect(controller.snapshots.isEmpty)
        #expect(model.isLiveActivityOn(for: game.id) == false)
    }

    // gameDetailAutoStartCallsLiveActivityControllerWhenSettingsAndEligibilityAllow 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailAutoStartCallsLiveActivityControllerWhenSettingsAndEligibilityAllow() async throws {
        let controller = TestLiveActivityController(isSupported: true)
        let scheduledAt = isoDate("2026-04-28T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let game = makeGameDetail(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2")!,
            scheduledStart: scheduledAt,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            awayStartingPitcherName: "원정선발",
            homeStartingPitcherName: "홈선발"
        )
        let model = AppModel(
            liveActivityController: controller,
            bootstrap: KBOBootstrapData(teams: teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { scheduledAt.addingTimeInterval(-30 * 60) }
        )
        model.settings.favoriteTeamID = "lg"
        model.settings.liveActivitiesEnabled = true

        await model.startOrUpdateLiveActivityIfNeeded(for: game)

        #expect(controller.snapshots.count == 1)
        #expect(controller.activeGameID == game.id)
        #expect(model.isLiveActivityOn(for: game.id))
    }

    // liveActivityUpdateDeduperSkipsIdenticalPayloadsOnly 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityUpdateDeduperSkipsIdenticalPayloadsOnly() async throws {
        let gameID = UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!
        var deduper = FavoriteTeamLiveActivityUpdateDeduper()
        let firstKey = liveActivityContentStateKey()

        #expect(deduper.decision(gameID: gameID, contentStateKey: firstKey).shouldSkip == false)
        deduper.record(gameID: gameID, contentStateKey: firstKey)
        #expect(deduper.decision(gameID: gameID, contentStateKey: firstKey).shouldSkip)
    }

    // liveActivityUpdateDeduperUpdatesWhenScoreChanges 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityUpdateDeduperUpdatesWhenScoreChanges() async throws {
        let gameID = UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!
        var deduper = FavoriteTeamLiveActivityUpdateDeduper()
        let firstKey = liveActivityContentStateKey(favoriteScoreText: "4")
        let changedKey = liveActivityContentStateKey(favoriteScoreText: "5")
        deduper.record(gameID: gameID, contentStateKey: firstKey)

        let decision = deduper.decision(gameID: gameID, contentStateKey: changedKey)

        #expect(decision.shouldSkip == false)
        #expect(decision.changedFields == ["favoriteScoreText"])
    }

    // liveActivityUpdateDeduperUpdatesWhenCountChanges 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityUpdateDeduperUpdatesWhenCountChanges() async throws {
        let gameID = UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!
        var deduper = FavoriteTeamLiveActivityUpdateDeduper()
        let firstKey = liveActivityContentStateKey(balls: 1, strikes: 1, outs: 0)
        let changedKey = liveActivityContentStateKey(balls: 2, strikes: 2, outs: 1)
        deduper.record(gameID: gameID, contentStateKey: firstKey)

        let decision = deduper.decision(gameID: gameID, contentStateKey: changedKey)

        #expect(decision.shouldSkip == false)
        #expect(decision.changedFields == ["balls", "strikes", "outs"])
    }

    // liveActivityUpdateDeduperUpdatesWhenBasesChange 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityUpdateDeduperUpdatesWhenBasesChange() async throws {
        let gameID = UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!
        var deduper = FavoriteTeamLiveActivityUpdateDeduper()
        let firstKey = liveActivityContentStateKey(runnerOnFirst: false, runnerOnSecond: false, runnerOnThird: false)
        let changedKey = liveActivityContentStateKey(runnerOnFirst: true, runnerOnSecond: false, runnerOnThird: true)
        deduper.record(gameID: gameID, contentStateKey: firstKey)

        let decision = deduper.decision(gameID: gameID, contentStateKey: changedKey)

        #expect(decision.shouldSkip == false)
        #expect(decision.changedFields == ["runnerOnFirst", "runnerOnThird"])
    }

    // liveActivityUpdateDeduperUpdatesWhenBatterOrPitcherChanges 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityUpdateDeduperUpdatesWhenBatterOrPitcherChanges() async throws {
        let gameID = UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!
        var deduper = FavoriteTeamLiveActivityUpdateDeduper()
        let firstKey = liveActivityContentStateKey(currentBatterName: "홍길동", currentPitcherName: "김투수")
        let changedKey = liveActivityContentStateKey(currentBatterName: "박타자", currentPitcherName: "이투수")
        deduper.record(gameID: gameID, contentStateKey: firstKey)

        let decision = deduper.decision(gameID: gameID, contentStateKey: changedKey)

        #expect(decision.shouldSkip == false)
        #expect(decision.changedFields == ["currentBatterName", "currentPitcherName"])
    }

    // liveActivityUpdateDeduperUpdatesWhenRunnerStateChangesWithSameScoreAndInning 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveActivityUpdateDeduperUpdatesWhenRunnerStateChangesWithSameScoreAndInning() async throws {
        let gameID = UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!
        var deduper = FavoriteTeamLiveActivityUpdateDeduper()
        let firstKey = liveActivityContentStateKey(favoriteScoreText: "4", opponentScoreText: "3", inningText: "7회 말", runnerOnFirst: false)
        let changedKey = liveActivityContentStateKey(favoriteScoreText: "4", opponentScoreText: "3", inningText: "7회 말", runnerOnFirst: true)
        deduper.record(gameID: gameID, contentStateKey: firstKey)

        let decision = deduper.decision(gameID: gameID, contentStateKey: changedKey)

        #expect(decision.shouldSkip == false)
        #expect(decision.changedFields == ["runnerOnFirst"])
    }

    // liveActivityToggleUsesSupportedControllerForFavoriteLiveGame 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveActivityUpdateUsesMergedDetailAfterRefresh 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // backgroundLiveActivityRefreshReusesLocalUpdateController 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func backgroundLiveActivityRefreshReusesLocalUpdateController() async throws {
        let controller = TestLiveActivityController(isSupported: true)
        let referenceDate = isoDate("2026-04-28T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "kiwoom" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let gameID = UUID(uuidString: "cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd")!
        let selected = makeGameDetail(
            id: gameID,
            scheduledStart: referenceDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 0,
            homeScore: 1,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Top 1",
            note: "provider_game_id=20260428WOLG0"
        )
        let latest = makeGameDetail(
            id: gameID,
            scheduledStart: referenceDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 2,
            homeScore: 3,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Bottom 4",
            note: "provider_game_id=20260428WOLG0 updated_at=2026-04-28T19:42:00+09:00",
            bases: RunnerState(first: false, second: true, third: false),
            balls: 1,
            strikes: 2,
            outs: 1,
            currentPitcherName: "백그라운드투수",
            currentBatterName: "백그라운드타자"
        )
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(
                fetchBootstrapData: {
                    KBOBootstrapData(teams: teams, games: [selected], notifications: [], settings: .default)
                },
                fetchScheduleBypassingCache: { _, _ in
                    [latest]
                }
            ),
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

        await model.startOrUpdateLiveActivityIfNeeded(for: selected)
        let didAttempt = await model.refreshTodayForBackgroundLiveActivity(reason: "backgroundTask")

        let snapshot = try #require(controller.snapshots.last)
        #expect(didAttempt)
        #expect(controller.snapshots.count >= 2)
        #expect(snapshot.favoriteScoreText == "3")
        #expect(snapshot.opponentScoreText == "2")
        #expect(snapshot.inningText == "4회 말")
        #expect(snapshot.balls == 1)
        #expect(snapshot.strikes == 2)
        #expect(snapshot.outs == 1)
        #expect(snapshot.currentPitcherName == "백그라운드투수")
        #expect(snapshot.currentBatterName == "백그라운드타자")
    }

    // preseasonBootstrapFixtureDecodes 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveRepositoryFallsBackToBootstrapWhenCollectionEndpointsUseBootstrapShape 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // preseasonFixtureMapsIntoDomainModels 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func preseasonFixtureMapsIntoDomainModels() async throws {
        let data = try fixtureData(named: "2026-preseason-bootstrap")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let bootstrap = try decoder.decode(KBOBootstrapDTO.self, from: data)
        let mapped = KBODataMapper.mapBootstrap(bootstrap)
        let calendar = Calendar(identifier: .gregorian)
        let sampleDay = isoDate("2026-03-23T13:00:00+09:00")

        #expect(mapped.games.count == 7)
        #expect(mapped.games.filter { calendar.isDate($0.scheduledStart, inSameDayAs: sampleDay) }.count == 4)
        #expect(mapped.games.contains { $0.awayTeam.id == "lotte" && $0.homeTeam.id == "ssg" && $0.awayScore == 5 && $0.homeScore == 2 && $0.status == .final })
        #expect(mapped.games.contains { $0.awayTeam.id == "kia" && $0.homeTeam.id == "samsung" && $0.status == .rainDelay })
    }

    // externalResponseAdapterNormalizesPreseasonFixturePayload 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func externalResponseAdapterNormalizesPreseasonFixturePayload() async throws {
        let data = try fixtureData(named: "2026-preseason-external-response")
        let normalized = try KBOExternalResponseAdapter.normalize(data: data)

        #expect(normalized.games.count == 2)
        #expect(normalized.teams.count == 4)
        #expect(normalized.notifications.count == 1)
        #expect(normalized.games.contains { $0.awayTeamID == "lotte" && $0.homeTeamID == "ssg" && $0.awayScore == 5 && $0.homeScore == 2 })
        #expect(normalized.games.contains { $0.awayTeamID == "kia" && $0.homeTeamID == "samsung" && $0.statusText == "우천 중단" })
    }

    // officialGameListFixtureNormalizesIntoExistingDTOShape 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // officialOpeningDayGameListFixtureNormalizesUpcomingGames 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // officialScheduleFixtureNormalizesTableRowsIntoGames 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // externalResponseAdapterNormalizesStringValuesAndAlternateDates 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveRepositoryMapsOfficialGameListFixtureWithoutSeparateTeamsEndpoint 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // officialLivePayloadMapsStableIDsInningAndBases 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // testBaseRunnerBattingOrderNormalization 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func testBaseRunnerBattingOrderNormalization() {
        #expect(OfficialBaseRunnerLineupResolver.normalizedBattingOrderNumber("3") == 3)
        #expect(OfficialBaseRunnerLineupResolver.normalizedBattingOrderNumber("3번") == 3)
        #expect(OfficialBaseRunnerLineupResolver.normalizedBattingOrderNumber("03") == 3)
        #expect(OfficialBaseRunnerLineupResolver.normalizedBattingOrderNumber("") == nil)
        #expect(OfficialBaseRunnerLineupResolver.normalizedBattingOrderNumber(nil) == nil)
    }

    // testBaseRunnerOffenseSideFromTopInningUsesAwayLineup 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func testBaseRunnerOffenseSideFromTopInningUsesAwayLineup() throws {
        let battingSections = makeBaseRunnerLineupSections(
            away: [(2, "김민석")],
            home: [(2, "홈2번")]
        )

        for halfText in ["Top 1", "1회 초", "초"] {
            let runners = try #require(OfficialBaseRunnerLineupResolver.baseRunners(
                firstOrder: 2,
                secondOrder: nil,
                thirdOrder: nil,
                inningHalfText: halfText,
                battingSections: battingSections
            ))

            #expect(OfficialBaseRunnerLineupResolver.offenseSide(inningHalfText: halfText) == .away)
            #expect(runners.first == "김민석")
        }
    }

    // testBaseRunnerOffenseSideFromBottomInningUsesHomeLineup 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func testBaseRunnerOffenseSideFromBottomInningUsesHomeLineup() throws {
        let battingSections = makeBaseRunnerLineupSections(
            away: [(4, "원정4번")],
            home: [(4, "레이예스")]
        )

        for halfText in ["Bottom 1", "1회 말", "말"] {
            let runners = try #require(OfficialBaseRunnerLineupResolver.baseRunners(
                firstOrder: nil,
                secondOrder: 4,
                thirdOrder: nil,
                inningHalfText: halfText,
                battingSections: battingSections
            ))

            #expect(OfficialBaseRunnerLineupResolver.offenseSide(inningHalfText: halfText) == .home)
            #expect(runners.second == "레이예스")
        }
    }

    // testBaseRunnerMapsFirstSecondThirdRunnerNamesFromBattingOrders 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func testBaseRunnerMapsFirstSecondThirdRunnerNamesFromBattingOrders() throws {
        let battingSections = makeBaseRunnerLineupSections(
            away: [(2, "김민석"), (5, "전준우")],
            home: [(4, "레이예스")]
        )

        let runners = try #require(OfficialBaseRunnerLineupResolver.baseRunners(
            firstOrder: 2,
            secondOrder: 4,
            thirdOrder: 5,
            inningHalfText: nil,
            battingSections: battingSections
        ))

        #expect(runners.first == "김민석")
        #expect(runners.second == "레이예스")
        #expect(runners.third == "전준우")
    }

    // testBaseRunnerKeepsCachedNameWhenBaseStillOccupiedAndNewNameMissing 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func testBaseRunnerKeepsCachedNameWhenBaseStillOccupiedAndNewNameMissing() throws {
        var resolver = BaseRunnerDisplayResolver()
        let occupied = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "김민석", second: nil, third: nil)
        )
        _ = resolver.resolve(gameIdentity: occupied.stableDetailIdentity, game: occupied)
        let missingName = try makeBaseRunnerDisplayGame(
            id: occupied.id,
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )

        let display = resolver.resolve(gameIdentity: occupied.stableDetailIdentity, game: missingName)

        #expect(display.runners.first == "김민석")
        #expect(display.source == "carryForward")
    }

    // testBaseRunnerClearsCachedNameWhenBaseIsEmpty 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func testBaseRunnerClearsCachedNameWhenBaseIsEmpty() throws {
        var resolver = BaseRunnerDisplayResolver()
        let occupied = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "김민석", second: nil, third: nil)
        )
        _ = resolver.resolve(gameIdentity: occupied.stableDetailIdentity, game: occupied)
        let empty = try makeBaseRunnerDisplayGame(
            id: occupied.id,
            bases: RunnerState(first: false, second: false, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )

        let display = resolver.resolve(gameIdentity: occupied.stableDetailIdentity, game: empty)

        #expect(display.runners.first == nil)
        #expect(display.source == "empty")
    }

    // testBaseRunnerReplacesCachedNameWhenBattingOrderChanges 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func testBaseRunnerReplacesCachedNameWhenBattingOrderChanges() throws {
        let battingSections = makeBaseRunnerLineupSections(
            away: [(2, "김민석"), (5, "전준우")],
            home: []
        )
        var resolver = BaseRunnerDisplayResolver()
        let firstRunner = try #require(OfficialBaseRunnerLineupResolver.baseRunners(
            firstOrder: 2,
            secondOrder: nil,
            thirdOrder: nil,
            inningHalfText: "초",
            battingSections: battingSections
        ))
        let initial = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: firstRunner.first, second: nil, third: nil)
        )
        _ = resolver.resolve(gameIdentity: initial.stableDetailIdentity, game: initial)
        let changedRunner = try #require(OfficialBaseRunnerLineupResolver.baseRunners(
            firstOrder: 5,
            secondOrder: nil,
            thirdOrder: nil,
            inningHalfText: "초",
            battingSections: battingSections
        ))
        let changed = try makeBaseRunnerDisplayGame(
            id: initial.id,
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: changedRunner.first, second: nil, third: nil)
        )

        let display = resolver.resolve(gameIdentity: initial.stableDetailIdentity, game: changed)

        #expect(display.runners.first == "전준우")
        #expect(display.source == "snapshot")
    }

    // baseRunnerResolvedNamesFeedDisplayResolutionBeforeViewRendering 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func baseRunnerResolvedNamesFeedDisplayResolutionBeforeViewRendering() throws {
        let battingSections = makeBaseRunnerLineupSections(
            away: [(2, "김민석")],
            home: []
        )
        let runners = try #require(OfficialBaseRunnerLineupResolver.baseRunners(
            firstOrder: 2,
            secondOrder: nil,
            thirdOrder: nil,
            inningHalfText: "1회 초",
            battingSections: battingSections
        ))
        var resolver = BaseRunnerDisplayResolver()
        let game = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: runners.first, second: runners.second, third: runners.third)
        )

        let display = resolver.resolve(gameIdentity: game.stableDetailIdentity, game: game)

        #expect(display.runners.first == "김민석")
        #expect(display.runners.second == nil)
        #expect(display.runners.third == nil)
        #expect(display.source == "snapshot")
    }

    // liveRepositoryMapsOfficialMonthlyScheduleFixture 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveRepositoryMapsBackendFinishedMonthlyScheduleGame 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveRepositoryFallsBackToMonthlyScheduleWhenBootstrapEndpointIsMissing 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveRepositoryFallsBackToMonthlyScheduleWhenBootstrapEndpointIsMissing() async throws {
        let month = KBOMonthScheduleKey(year: 2026, month: 3)
        let backendMonthlyPayload = try makeBackendMonthPayloadJSON()
        let session = makeStubSession()
        let repository = LiveKBORepository(
            baseURL: URL(string: "https://example.com/api/")!,
            session: session,
            nowProvider: { isoDate("2026-03-27T12:00:00+09:00") }
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

    // liveRepositoryUsesVerifiedOfficialKBORequestShapeForMonthlySchedule 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveRepositoryUsesVerifiedOfficialKBORequestShapeForLiveGames 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveRepositoryUsesVerifiedOfficialKBORequestShapeForLiveGames() async throws {
        let officialGameList = try fixtureData(named: "2026-kbo-official-game-list-20260323")
        let fixedDate = isoDate("2026-03-23T10:00:00+09:00")
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

    // officialGameCenterClientUsesScheduledDateWhenProviderIDIsSchedulePlaceholder 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientUsesScheduledDateWhenProviderIDIsSchedulePlaceholder() async throws {
        let officialGameList = """
        {
          "game": [],
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
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        let game = try makeIdentityLookupGame(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131303")!,
            publicGameID: "20260513-KIW-HAN",
            providerGameID: "sched-202605130930-c5d5aa85-89747089",
            officialProviderGameID: nil,
            scheduledStart: isoDate("2026-05-13T18:30:00+09:00"),
            awayTeamID: "kiwoom",
            homeTeamID: "hanwha"
        )

        _ = await client.reconcileScheduledStartTimes(in: [game])

        let request = try #require(URLProtocolStub.lastRequest)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
        #expect(request.url?.absoluteString == "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList")
        #expect(body?.contains("date=20260513") == true)
        #expect(body?.contains("date=sched-20") == false)
    }

    // officialGameCenterClientReconcilesScheduleStartTimeFromOfficialGameList 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // officialGameCenterClientMapsLiveBaseRunnerNamesFromBattingOrderTable 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // officialGameCenterClientMapsLiveScoreboardLineScore 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientMapsLiveScoreboardLineScore() async throws {
        let inningTable = #"""
        {
          "headers": [
            { "row": [
              { "Text": "1" }, { "Text": "2" }, { "Text": "3" }, { "Text": "4" }, { "Text": "5" }, { "Text": "6" },
              { "Text": "7" }, { "Text": "8" }, { "Text": "9" }, { "Text": "10" }, { "Text": "11" }, { "Text": "12" }
            ] }
          ],
          "rows": [
            { "row": [
              { "Text": "0" }, { "Text": "1" }, { "Text": "0" }, { "Text": "2" }, { "Text": "-" }, { "Text": "-" },
              { "Text": "-" }, { "Text": "-" }, { "Text": "-" }, { "Text": "-" }, { "Text": "-" }, { "Text": "-" }
            ] },
            { "row": [
              { "Text": "1" }, { "Text": "0" }, { "Text": "0" }, { "Text": "1" }, { "Text": "-" }, { "Text": "-" },
              { "Text": "-" }, { "Text": "-" }, { "Text": "-" }, { "Text": "-" }, { "Text": "-" }, { "Text": "-" }
            ] }
          ],
          "tfoot": []
        }
        """#
        let totalsTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "3" }, { "Text": "7" }, { "Text": "0" }, { "Text": "4" }] },
            { "row": [{ "Text": "2" }, { "Text": "5" }, { "Text": "1" }, { "Text": "2" }] }
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
              "GAME_INN_NO": 4,
              "GAME_TB_SC_NM": "말",
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
          "table2": \(try jsonStringLiteral(inningTable)),
          "table3": \(try jsonStringLiteral(totalsTable))
        }
        """.data(using: .utf8)!
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: scoreboardPayload)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "fefefefe-fefe-fefe-fefe-fefefefefefe")!,
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

        let detail = try await client.fetchDetail(for: game, includeRecordFallback: false)

        #expect(detail?.lineScore?.inningLabels.count == 12)
        #expect(detail?.lineScore?.awayInnings.prefix(4) == ["0", "1", "0", "2"])
        #expect(detail?.lineScore?.homeTotals.runs == "2")
        #expect(detail?.lineScore?.awayTotals.hits == "7")
        #expect(detail?.lineScore?.homeTotals.walks == "2")
    }

    // officialGameCenterClientHandlesScoreboardOfficialErrorWithoutKeyNotFound 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientHandlesScoreboardOfficialErrorWithoutKeyNotFound() async throws {
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
              "GAME_INN_NO": 4,
              "GAME_TB_SC_NM": "말",
              "T_SCORE_CN": "3",
              "B_SCORE_CN": "2"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let officialError = """
        {
          "G_ID": "20260328KTLG0",
          "code": "200",
          "msg": "입력 문자열의 형식이 잘못되었습니다."
        }
        """.data(using: .utf8)!
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx?date=20260328": StubResponse(
                statusCode: 200,
                data: Data("<html></html>".utf8),
                headers: ["Content-Type": "text/html; charset=utf-8"]
            )
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "45454545-4545-4545-4545-454545454545")!,
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

        let detail = try await client.fetchDetail(for: game, includeRecordFallback: false)

        #expect(detail?.summary.officialGameID == "20260328KTLG0")
        #expect(detail?.lineScore == nil)
    }

    // officialGameCenterClientHandlesScoreboardResponseWithoutTables 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientHandlesScoreboardResponseWithoutTables() async throws {
        let payload = #"{"S_NM":"잠실","START_TM":"14:00","code":"100","msg":"성공"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(OfficialScoreboardResponse.self, from: payload)
        let client = OfficialKBOGameCenterClient()

        #expect(decoded.inningTable == nil)
        #expect(decoded.totalsTable == nil)
        #expect(client.makeLineScore(from: decoded) == nil)
    }

    // officialGameCenterClientFallsBackToScoreBoardPageLineScoreForLiveGame 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientFallsBackToScoreBoardPageLineScoreForLiveGame() async throws {
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
              "GAME_INN_NO": 4,
              "GAME_TB_SC_NM": "말",
              "T_SCORE_CN": "3",
              "B_SCORE_CN": "2"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let officialError = #"{"code":"200","msg":"입력 문자열의 형식이 잘못되었습니다."}"#.data(using: .utf8)!
        let scoreboardHTML = """
        <div class="smsScore">
          <strong class='teamT'>KT</strong>
          <strong class='teamT'>LG</strong>
          <table class="tScore">
            <thead><tr><th>TEAM</th><th>1</th><th>2</th><th>3</th><th>R</th><th>H</th><th>E</th><th>B</th></tr></thead>
            <tbody>
              <tr><th>KT</th><td>1</td><td>0</td><td>-</td><td>3</td><td>7</td><td>0</td><td>4</td></tr>
              <tr><th>LG</th><td>1</td><td>1</td><td>-</td><td>2</td><td>5</td><td>1</td><td>2</td></tr>
            </tbody>
          </table>
        </div>
        """.data(using: .utf8)!
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx?date=20260328": StubResponse(
                statusCode: 200,
                data: scoreboardHTML,
                headers: ["Content-Type": "text/html; charset=utf-8"]
            )
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "46464646-4646-4646-4646-464646464646")!,
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

        let detail = try await client.fetchDetail(for: game, includeRecordFallback: false)

        #expect(detail?.lineScore?.inningLabels == ["1", "2", "3"])
        #expect(detail?.lineScore?.awayTotals.runs == "3")
        #expect(detail?.lineScore?.homeTotals.hits == "5")
        #expect(detail?.review?.hasDisplayableRecords != true)
    }

    // officialGameCenterClientMapsLiveKeyPlayerRecordFallback 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientMapsLiveKeyPlayerRecordFallback() async throws {
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
              "GAME_INN_NO": 4,
              "GAME_TB_SC_NM": "말",
              "T_SCORE_CN": "3",
              "B_SCORE_CN": "2"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let officialError = #"{"code":"200","msg":"입력 문자열의 형식이 잘못되었습니다."}"#.data(using: .utf8)!
        let scoreboardHTML = """
        <div class="smsScore">
          <strong class='teamT'>KT</strong>
          <strong class='teamT'>LG</strong>
          <table class="tScore">
            <thead><tr><th>TEAM</th><th>1</th><th>2</th><th>R</th><th>H</th><th>E</th><th>B</th></tr></thead>
            <tbody>
              <tr><th>KT</th><td>1</td><td>0</td><td>3</td><td>7</td><td>0</td><td>4</td></tr>
              <tr><th>LG</th><td>1</td><td>1</td><td>2</td><td>5</td><td>1</td><td>2</td></tr>
            </tbody>
          </table>
        </div>
        """.data(using: .utf8)!
        let hitterPayload = """
        {
          "record": [
            { "RANK_NO": 1, "P_ID": 111, "P_NM": "강백호", "T_ID": "KT", "RECORD_IF": "12.5%</br>(3타수 1득점 2안타 2타점)" },
            { "RANK_NO": 2, "P_ID": 222, "P_NM": "홍창기", "T_ID": "LG", "RECORD_IF": "8.1%</br>(4타수 1득점 1안타 0타점 1볼넷)" }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let pitcherPayload = """
        {
          "record": [
            { "RANK_NO": 1, "P_ID": 333, "P_NM": "김불펜", "T_ID": "LG", "RECORD_IF": "6%</br>(2/3이닝 0실점 1삼진)" }
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
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx?date=20260328": StubResponse(
                statusCode: 200,
                data: scoreboardHTML,
                headers: ["Content-Type": "text/html; charset=utf-8"]
            ),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetBoxScoreScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerHitter": StubResponse(statusCode: 200, data: hitterPayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerPitcher": StubResponse(statusCode: 200, data: pitcherPayload)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "49494949-4949-4949-4949-494949494949")!,
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

        #expect(detail?.lineScore?.awayTotals.runs == "3")
        #expect(detail?.review?.hasDisplayableRecords == true)
        #expect(detail?.review?.summaryItems.count == 3)
        #expect(detail?.review?.awayBatting.lines.first?.name == "강백호")
        #expect(detail?.review?.awayBatting.lines.first?.atBats == "3")
        #expect(detail?.review?.awayBatting.lines.first?.hits == "2")
        #expect(detail?.review?.awayBatting.lines.first?.runsBattedIn == "2")
        #expect(detail?.review?.homeBatting.lines.first?.name == "홍창기")
        #expect(detail?.review?.homeBatting.lines.first?.walks == nil)
        #expect(detail?.review?.homePitching.lines.first?.name == "김불펜")
        #expect(detail?.review?.homePitching.lines.first?.innings == "2/3")
        #expect(detail?.review?.homePitching.lines.first?.runsAllowed == "0")
        #expect(detail?.review?.homePitching.lines.first?.strikeouts == "1")
    }

    // officialGameCenterClientBuildsLiveBatterRecordsFromLineupAndOverlaysKeyPlayerStats 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientBuildsLiveBatterRecordsFromLineupAndOverlaysKeyPlayerStats() async throws {
        let awayLineupTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "1" }, { "Text": "우익수" }, { "Text": "홍창기" }] },
            { "row": [{ "Text": "2" }, { "Text": "중견수" }, { "Text": "박해민" }] },
            { "row": [{ "Text": "3" }, { "Text": "1루수" }, { "Text": "오스틴" }] },
            { "row": [{ "Text": "4" }, { "Text": "좌익수" }, { "Text": "문성주" }] },
            { "row": [{ "Text": "5" }, { "Text": "지명타자" }, { "Text": "김현수" }] },
            { "row": [{ "Text": "6" }, { "Text": "3루수" }, { "Text": "문보경" }] },
            { "row": [{ "Text": "7" }, { "Text": "포수" }, { "Text": "박동원" }] },
            { "row": [{ "Text": "8" }, { "Text": "유격수" }, { "Text": "오지환" }] },
            { "row": [{ "Text": "9" }, { "Text": "2루수" }, { "Text": "신민재" }] }
          ],
          "tfoot": []
        }
        """#
        let homeLineupTable = #"""
        {
          "headers": [],
          "rows": [
            { "row": [{ "Text": "1" }, { "Text": "중견수" }, { "Text": "황성빈" }] },
            { "row": [{ "Text": "2" }, { "Text": "지명타자" }, { "Text": "고승민" }] },
            { "row": [{ "Text": "3" }, { "Text": "우익수" }, { "Text": "레이예스" }] },
            { "row": [{ "Text": "4" }, { "Text": "1루수" }, { "Text": "전준우" }] },
            { "row": [{ "Text": "5" }, { "Text": "좌익수" }, { "Text": "윤동희" }] },
            { "row": [{ "Text": "6" }, { "Text": "3루수" }, { "Text": "손호영" }] },
            { "row": [{ "Text": "7" }, { "Text": "포수" }, { "Text": "정보근" }] },
            { "row": [{ "Text": "8" }, { "Text": "유격수" }, { "Text": "박승욱" }] },
            { "row": [{ "Text": "9" }, { "Text": "2루수" }, { "Text": "정훈" }] }
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
              "G_DT": "20260527",
              "G_DT_TXT": "2026.05.27(수)",
              "G_ID": "20260527LGLT0",
              "G_TM": "18:30",
              "S_NM": "사직",
              "AWAY_ID": "LG",
              "HOME_ID": "LT",
              "AWAY_NM": "LG",
              "HOME_NM": "롯데",
              "GAME_STATE_SC": "2",
              "CANCEL_SC_NM": "정상경기",
              "GAME_INN_NO": 4,
              "GAME_TB_SC_NM": "초",
              "T_SCORE_CN": "1",
              "B_SCORE_CN": "0"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let officialError = #"{"code":"200","msg":"입력 문자열의 형식이 잘못되었습니다."}"#.data(using: .utf8)!
        let scoreboardHTML = """
        <div class="smsScore">
          <strong class='teamT'>LG</strong>
          <strong class='teamT'>롯데</strong>
          <table class="tScore">
            <thead><tr><th>TEAM</th><th>1</th><th>2</th><th>R</th><th>H</th><th>E</th><th>B</th></tr></thead>
            <tbody>
              <tr><th>LG</th><td>1</td><td>0</td><td>1</td><td>2</td><td>0</td><td>1</td></tr>
              <tr><th>롯데</th><td>0</td><td>0</td><td>0</td><td>1</td><td>0</td><td>0</td></tr>
            </tbody>
          </table>
        </div>
        """.data(using: .utf8)!
        let lineupPayload = """
        [
          [{ "LINEUP_CK": true }],
          [{ "T_ID": "LT" }],
          [{ "T_ID": "LG" }],
          [\(try jsonStringLiteral(homeLineupTable))],
          [\(try jsonStringLiteral(awayLineupTable))]
        ]
        """.data(using: .utf8)!
        let hitterPayload = """
        {
          "record": [
            {
              "RANK_NO": 1,
              "P_ID": 111,
              "P_NM": "홍창기",
              "T_ID": "LG",
              "RECORD_IF": "10.5%</br>(2타수 1득점 1안타 1타점)"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let emptySuccess = #"{"code":"100","msg":"성공"}"#.data(using: .utf8)!
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx?date=20260527": StubResponse(
                statusCode: 200,
                data: scoreboardHTML,
                headers: ["Content-Type": "text/html; charset=utf-8"]
            ),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetBoxScoreScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetLineUpAnalysis": StubResponse(statusCode: 200, data: lineupPayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerHitter": StubResponse(statusCode: 200, data: hitterPayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerPitcher": StubResponse(statusCode: 200, data: emptySuccess)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "51515151-5151-5151-5151-515151515151")!,
            scheduledStart: isoDate("2026-05-27T18:30:00+09:00"),
            venue: "사직",
            awayTeam: Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG"),
            homeTeam: Team(id: "lotte", name: "롯데 자이언츠", shortName: "롯데", englishName: "Lotte Giants", markText: "롯데"),
            awayScore: 1,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            providerGameID: "20260527LGLT0",
            events: [
                GameEvent(
                    id: UUID(uuidString: "51515151-5151-5151-5151-000000000001")!,
                    type: .keyPlay,
                    headline: "홍창기 홈런",
                    inningText: "1회 초",
                    timestamp: isoDate("2026-05-27T18:35:00+09:00")
                ),
                GameEvent(
                    id: UUID(uuidString: "51515151-5151-5151-5151-000000000002")!,
                    type: .keyPlay,
                    headline: "홍창기 볼넷",
                    inningText: "3회 초",
                    timestamp: isoDate("2026-05-27T19:05:00+09:00")
                ),
                GameEvent(
                    id: UUID(uuidString: "51515151-5151-5151-5151-000000000003")!,
                    type: .keyPlay,
                    headline: "박해민 삼진",
                    inningText: "2회 초",
                    timestamp: isoDate("2026-05-27T18:48:00+09:00")
                ),
                GameEvent(
                    id: UUID(uuidString: "51515151-5151-5151-5151-000000000004")!,
                    type: .keyPlay,
                    headline: "황성빈 볼넷",
                    inningText: "1회 말",
                    timestamp: isoDate("2026-05-27T18:55:00+09:00")
                )
            ]
        )

        let detail = try await client.fetchDetail(for: game)
        let awayBatters = try #require(detail?.review?.awayBatting.lines)
        let homeBatters = try #require(detail?.review?.homeBatting.lines)

        #expect(awayBatters.count == 9)
        #expect(homeBatters.count == 9)
        #expect(awayBatters.map(\.name).prefix(3) == ["홍창기", "박해민", "오스틴"])
        #expect(homeBatters.map(\.name).prefix(3) == ["황성빈", "고승민", "레이예스"])
        #expect(awayBatters.map(\.battingOrder) == ["1", "2", "3", "4", "5", "6", "7", "8", "9"])
        #expect(Set(awayBatters.map(\.name)).count == 9)
        #expect(GameRecordPositionFormatter.display(awayBatters[0].position) == "RF")
        #expect(GameRecordPositionFormatter.display(awayBatters[1].position) == "CF")
        #expect(GameRecordPositionFormatter.display(awayBatters[2].position) == "1B")
        #expect(GameRecordPositionFormatter.display(awayBatters[4].position) == "DH")
        #expect(awayBatters[0].atBats == "2")
        #expect(awayBatters[0].runs == "1")
        #expect(awayBatters[0].hits == "1")
        #expect(awayBatters[0].runsBattedIn == "1")
        #expect(awayBatters[0].homeRuns == "1")
        #expect(awayBatters[0].strikeouts == "0")
        #expect(awayBatters[0].walks == "1")
        #expect(awayBatters[0].average == nil)
        #expect(awayBatters[1].atBats == "0")
        #expect(awayBatters[1].runs == "0")
        #expect(awayBatters[1].hits == "0")
        #expect(awayBatters[1].runsBattedIn == "0")
        #expect(awayBatters[1].homeRuns == "0")
        #expect(awayBatters[1].strikeouts == "1")
        #expect(awayBatters[1].walks == "0")
        #expect(awayBatters[1].average == nil)
        #expect(awayBatters[2].homeRuns == "0")
        #expect(awayBatters[2].strikeouts == "0")
        #expect(awayBatters[2].walks == "0")
        #expect(homeBatters[0].homeRuns == "0")
        #expect(homeBatters[0].strikeouts == "0")
        #expect(homeBatters[0].walks == "1")
        #expect(GameDetailBattingTableColumns.headers(isLiveLike: true).contains("타율") == false)
        #expect(GameDetailBattingTableColumns.headers(isLiveLike: true) == ["타수", "득점", "안타", "타점", "홈런", "삼진", "볼넷"])
    }

    // officialGameCenterClientBuildsLivePitcherRowsFromStartersAndCurrentPitcherSide 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientBuildsLivePitcherRowsFromStartersAndCurrentPitcherSide() async throws {
        let officialGameList = """
        {
          "game": [
            {
              "LE_ID": 1,
              "SR_ID": 0,
              "SEASON_ID": 2026,
              "G_DT": "20260528",
              "G_DT_TXT": "2026.05.28(목)",
              "G_ID": "20260528LGLT0",
              "G_TM": "18:30",
              "S_NM": "사직",
              "AWAY_ID": "LG",
              "HOME_ID": "LT",
              "AWAY_NM": "LG",
              "HOME_NM": "롯데",
              "GAME_STATE_SC": "2",
              "CANCEL_SC_NM": "정상경기",
              "GAME_INN_NO": 4,
              "GAME_TB_SC_NM": "초",
              "T_SCORE_CN": "1",
              "B_SCORE_CN": "0"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let officialError = #"{"code":"200","msg":"입력 문자열의 형식이 잘못되었습니다."}"#.data(using: .utf8)!
        let scoreboardHTML = """
        <div class="smsScore">
          <strong class='teamT'>LG</strong>
          <strong class='teamT'>롯데</strong>
          <table class="tScore">
            <tbody>
              <tr><th>LG</th><td>1</td><td>1</td><td>2</td><td>0</td><td>1</td></tr>
              <tr><th>롯데</th><td>0</td><td>0</td><td>1</td><td>0</td><td>0</td></tr>
            </tbody>
          </table>
        </div>
        """.data(using: .utf8)!
        let emptySuccess = #"{"code":"100","msg":"성공"}"#.data(using: .utf8)!
        let pitcherPayload = """
        {
          "record": [
            { "RANK_NO": 1, "P_ID": 333, "P_NM": "김진욱", "T_ID": "LT", "RECORD_IF": "7.1%</br>(3이닝 1실점 4삼진)" }
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
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx?date=20260528": StubResponse(
                statusCode: 200,
                data: scoreboardHTML,
                headers: ["Content-Type": "text/html; charset=utf-8"]
            ),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetBoxScoreScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetLineUpAnalysis": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerHitter": StubResponse(statusCode: 200, data: emptySuccess),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerPitcher": StubResponse(statusCode: 200, data: pitcherPayload)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "53535353-5353-5353-5353-535353535353")!,
            scheduledStart: isoDate("2026-05-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG"),
            homeTeam: Team(id: "lotte", name: "롯데 자이언츠", shortName: "롯데", englishName: "Lotte Giants", markText: "롯데"),
            awayScore: 1,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "4회 초",
            providerGameID: "20260528LGLT0",
            awayStartingPitcherName: "임찬규",
            homeStartingPitcherName: "김진욱",
            events: [
                GameEvent(
                    id: UUID(uuidString: "53535353-5353-5353-5353-000000000001")!,
                    type: .pitching,
                    headline: "투수 김영우 등판",
                    inningText: "3회 말",
                    timestamp: isoDate("2026-05-28T19:40:00+09:00")
                )
            ],
            currentPitcherName: "김진욱"
        )

        let detail = try await client.fetchDetail(for: game)
        let awayPitchers = try #require(detail?.review?.awayPitching.lines)
        let homePitchers = try #require(detail?.review?.homePitching.lines)

        #expect(awayPitchers.map(\.name) == ["임찬규", "김영우"])
        #expect(awayPitchers.first?.role == "선발")
        #expect(awayPitchers[1].role == "구원")
        #expect(awayPitchers[1].innings == nil)
        #expect(awayPitchers[1].strikeouts == nil)
        #expect(homePitchers.map(\.name) == ["김진욱"])
        #expect(homePitchers.first?.role == "선발")
        #expect(homePitchers.first?.innings == "3")
        #expect(homePitchers.first?.runsAllowed == "1")
        #expect(homePitchers.first?.strikeouts == "4")
        #expect(homePitchers.filter { $0.name == "김진욱" }.count == 1)
        #expect(homePitchers.contains { $0.name == "김영우" } == false)
    }

    // officialGameCenterClientFallsBackToScoreboardHTMLBoxscoreBeforeKeyPlayerPartial 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientFallsBackToScoreboardHTMLBoxscoreBeforeKeyPlayerPartial() async throws {
        let officialGameList = """
        {
          "game": [
            {
              "LE_ID": 1,
              "SR_ID": 0,
              "SEASON_ID": 2026,
              "G_DT": "20260528",
              "G_DT_TXT": "2026.05.28(목)",
              "G_ID": "20260528LGLT0",
              "G_TM": "18:30",
              "S_NM": "사직",
              "AWAY_ID": "LG",
              "HOME_ID": "LT",
              "AWAY_NM": "LG",
              "HOME_NM": "롯데",
              "GAME_STATE_SC": "2",
              "CANCEL_SC_NM": "정상경기",
              "GAME_INN_NO": 4,
              "GAME_TB_SC_NM": "초",
              "T_SCORE_CN": "3",
              "B_SCORE_CN": "1"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let officialError = #"{"code":"200","msg":"입력 문자열의 형식이 잘못되었습니다."}"#.data(using: .utf8)!
        let htmlBoxscore = """
        <div class="smsScore">
          <strong class='teamT'>LG</strong>
          <strong class='teamT'>롯데</strong>
          <table class="tScore">
            <thead><tr><th>팀</th><th>1</th><th>2</th><th>R</th><th>H</th><th>E</th><th>B</th></tr></thead>
            <tbody>
              <tr><th>LG</th><td>1</td><td>2</td><td>3</td><td>6</td><td>0</td><td>4</td></tr>
              <tr><th>롯데</th><td>0</td><td>1</td><td>1</td><td>4</td><td>1</td><td>2</td></tr>
            </tbody>
          </table>
        </div>
        <table id="tblAwayHitter1"><thead><tr><th></th><th></th><th>선수명</th></tr></thead><tbody>
          <tr><td>1</td><td>우익수</td><td>홍창기</td></tr>
          <tr><td>2</td><td>중견수</td><td>박해민</td></tr>
        </tbody></table>
        <table id="tblAwayHitter3"><thead><tr><th>타수</th><th>안타</th><th>타점</th><th>득점</th><th>타율</th><th>홈런</th><th>볼넷</th><th>삼진</th></tr></thead><tbody>
          <tr><td>3</td><td>2</td><td>1</td><td>2</td><td>0.667</td><td>1</td><td>1</td><td>0</td></tr>
          <tr><td>4</td><td>1</td><td>2</td><td>1</td><td>0.250</td><td>0</td><td>2</td><td>1</td></tr>
        </tbody><tfoot><tr><td>7</td><td>3</td><td>3</td><td>3</td><td>0.429</td><td>1</td><td>3</td><td>1</td></tr></tfoot></table>
        <table id="tblHomeHitter1"><thead><tr><th></th><th></th><th>선수명</th></tr></thead><tbody>
          <tr><td>1</td><td>중견수</td><td>황성빈</td></tr>
        </tbody></table>
        <table id="tblHomeHitter3"><thead><tr><th>타수</th><th>안타</th><th>타점</th><th>득점</th><th>타율</th><th>홈런</th><th>볼넷</th><th>삼진</th></tr></thead><tbody>
          <tr><td>4</td><td>2</td><td>1</td><td>1</td><td>0.500</td><td>0</td><td>1</td><td>1</td></tr>
        </tbody><tfoot><tr><td>4</td><td>2</td><td>1</td><td>1</td><td>0.500</td><td>0</td><td>1</td><td>1</td></tr></tfoot></table>
        <table id="tblAwayPitcher"><thead><tr><th>선수명</th><th>등판</th><th>결과</th><th>승</th><th>패</th><th>세</th><th>이닝</th><th>타자</th><th>투구수</th><th>타수</th><th>피안타</th><th>홈런</th><th>4사구</th><th>삼진</th><th>실점</th><th>자책</th><th>평균자책점</th></tr></thead><tbody>
          <tr><td>이정용</td><td>선발</td><td>-</td><td>0</td><td>0</td><td>0</td><td>2</td><td>9</td><td>35</td><td>8</td><td>2</td><td>0</td><td>1</td><td>2</td><td>1</td><td>1</td><td>4.50</td></tr>
          <tr><td>김영우</td><td>구원</td><td>-</td><td>0</td><td>0</td><td>0</td><td>1</td><td>4</td><td>16</td><td>4</td><td>1</td><td>0</td><td>0</td><td>1</td><td>0</td><td>0</td><td>0.00</td></tr>
        </tbody></table>
        <table id="tblHomePitcher"><thead><tr><th>선수명</th><th>등판</th><th>결과</th><th>승</th><th>패</th><th>세</th><th>이닝</th><th>타자</th><th>투구수</th><th>타수</th><th>피안타</th><th>홈런</th><th>4사구</th><th>삼진</th><th>실점</th><th>자책</th><th>평균자책점</th></tr></thead><tbody>
          <tr><td>김진욱</td><td>선발</td><td>-</td><td>0</td><td>0</td><td>0</td><td>3</td><td>14</td><td>60</td><td>12</td><td>3</td><td>1</td><td>3</td><td>4</td><td>3</td><td>3</td><td>9.00</td></tr>
        </tbody></table>
        """.data(using: .utf8)!
        let keyplayerPayload = """
        {
          "record": [
            { "RANK_NO": 1, "P_ID": 1, "P_NM": "홍창기", "T_ID": "LG", "RECORD_IF": "99.9%</br>(1타수 0득점 0안타 0타점)" }
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
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx?date=20260528": StubResponse(
                statusCode: 200,
                data: htmlBoxscore,
                headers: ["Content-Type": "text/html; charset=utf-8"]
            ),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetBoxScoreScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetLineUpAnalysis": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerHitter": StubResponse(statusCode: 200, data: keyplayerPayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerPitcher": StubResponse(statusCode: 200, data: keyplayerPayload)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "54545454-5454-5454-5454-545454545454")!,
            scheduledStart: isoDate("2026-05-28T18:30:00+09:00"),
            venue: "사직",
            awayTeam: Team(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG"),
            homeTeam: Team(id: "lotte", name: "롯데 자이언츠", shortName: "롯데", englishName: "Lotte Giants", markText: "롯데"),
            awayScore: 3,
            homeScore: 1,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "4회 초",
            providerGameID: "20260528LGLT0",
            awayStartingPitcherName: "이정용",
            homeStartingPitcherName: "김진욱",
            currentPitcherName: "김진욱"
        )

        let detail = try await client.fetchDetail(for: game)
        let review = try #require(detail?.review)

        #expect(review.recordSource == .scoreboardHTMLBoxscore)
        #expect(review.awayBatting.lines.map(\.name) == ["홍창기", "박해민"])
        #expect(review.awayBatting.lines[0].atBats == "3")
        #expect(review.awayBatting.lines[0].homeRuns == "1")
        #expect(review.awayBatting.lines[0].walks == "1")
        #expect(review.awayBatting.lines[1].runsBattedIn == "2")
        #expect(review.awayBatting.totals?.atBats == "7")
        #expect(review.homeBatting.lines.map(\.name) == ["황성빈"])
        #expect(review.awayPitching.lines.map(\.name) == ["이정용", "김영우"])
        #expect(review.awayPitching.lines[1].role == "구원")
        #expect(review.awayPitching.lines[1].innings == "1")
        #expect(review.awayPitching.lines[1].strikeouts == "1")
        #expect(review.homePitching.lines.map(\.name) == ["김진욱"])
        #expect(review.homePitching.lines[0].runsAllowed == "3")
    }

    // officialGameCenterClientKeepsLineScoreWhenLiveKeyPlayerRecordsUnavailable 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientKeepsLineScoreWhenLiveKeyPlayerRecordsUnavailable() async throws {
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
              "GAME_INN_NO": 4,
              "GAME_TB_SC_NM": "말",
              "T_SCORE_CN": "3",
              "B_SCORE_CN": "2"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let officialError = #"{"code":"200","msg":"입력 문자열의 형식이 잘못되었습니다."}"#.data(using: .utf8)!
        let emptySuccess = #"{"code":"100","msg":"성공"}"#.data(using: .utf8)!
        let scoreboardHTML = """
        <div class="smsScore">
          <strong class='teamT'>KT</strong>
          <strong class='teamT'>LG</strong>
          <table class="tScore">
            <thead><tr><th>TEAM</th><th>1</th><th>2</th><th>R</th><th>H</th><th>E</th><th>B</th></tr></thead>
            <tbody>
              <tr><th>KT</th><td>1</td><td>0</td><td>3</td><td>7</td><td>0</td><td>4</td></tr>
              <tr><th>LG</th><td>1</td><td>1</td><td>2</td><td>5</td><td>1</td><td>2</td></tr>
            </tbody>
          </table>
        </div>
        """.data(using: .utf8)!
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx?date=20260328": StubResponse(
                statusCode: 200,
                data: scoreboardHTML,
                headers: ["Content-Type": "text/html; charset=utf-8"]
            ),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetBoxScoreScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerHitter": StubResponse(statusCode: 200, data: emptySuccess),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerPitcher": StubResponse(statusCode: 200, data: emptySuccess)
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "50505050-5050-5050-5050-505050505050")!,
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

        #expect(detail?.lineScore?.homeTotals.runs == "2")
        #expect(detail?.review?.hasDisplayableRecords != true)
    }

    // officialGameCenterClientRejectsScoreBoardPageWithoutTargetGame 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientRejectsScoreBoardPageWithoutTargetGame() async throws {
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
              "GAME_INN_NO": 4,
              "GAME_TB_SC_NM": "말",
              "T_SCORE_CN": "3",
              "B_SCORE_CN": "2"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let officialError = #"{"code":"200","msg":"입력 문자열의 형식이 잘못되었습니다."}"#.data(using: .utf8)!
        let scoreboardHTML = """
        <html><head><title>스코어보드 | 일정/결과 | KBO</title></head><body>
        <div class="smsScore">
          <strong class='teamT'>SSG</strong>
          <strong class='teamT'>두산</strong>
          <table class="tScore">
            <thead><tr><th>TEAM</th><th>1</th><th>R</th><th>H</th><th>E</th><th>B</th></tr></thead>
            <tbody>
              <tr><th>SSG</th><td>1</td><td>1</td><td>2</td><td>0</td><td>1</td></tr>
              <tr><th>두산</th><td>0</td><td>0</td><td>1</td><td>0</td><td>0</td></tr>
            </tbody>
          </table>
        </div>
        </body></html>
        """.data(using: .utf8)!
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx?date=20260328": StubResponse(
                statusCode: 200,
                data: scoreboardHTML,
                headers: ["Content-Type": "text/html; charset=utf-8"]
            )
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "47474747-4747-4747-4747-474747474747")!,
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

        let detail = try await client.fetchDetail(for: game, includeRecordFallback: false)

        #expect(detail?.summary.officialGameID == "20260328KTLG0")
        #expect(detail?.lineScore == nil)
    }

    // officialGameCenterClientRejectsScoreBoardPageObjectMovedHTML 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterClientRejectsScoreBoardPageObjectMovedHTML() async throws {
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
              "GAME_INN_NO": 4,
              "GAME_TB_SC_NM": "말",
              "T_SCORE_CN": "3",
              "B_SCORE_CN": "2"
            }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let officialError = #"{"code":"200","msg":"입력 문자열의 형식이 잘못되었습니다."}"#.data(using: .utf8)!
        let objectMovedHTML = Data("<html><body>Object moved to <a href='/Error'>here</a>.</body></html>".utf8)
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: officialError),
            "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx?date=20260328": StubResponse(
                statusCode: 200,
                data: objectMovedHTML,
                headers: ["Content-Type": "text/html; charset=utf-8"]
            )
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = makeGameDetail(
            id: UUID(uuidString: "48484848-4848-4848-4848-484848484848")!,
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

        let detail = try await client.fetchDetail(for: game, includeRecordFallback: false)

        #expect(detail?.summary.officialGameID == "20260328KTLG0")
        #expect(detail?.lineScore == nil)
    }

    // officialGameCenterClientFallsBackToLineupAnalysisForLiveBaseRunnerNames 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // officialGameCenterClientMapsLiveBoxScoreRecordSections 메서드는 이 타입의 주요 동작을 수행합니다.
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
        let keyPlayerHitterPayload = """
        {
          "record": [
            { "RANK_NO": 1, "P_ID": 999, "P_NM": "키플레이어타자", "T_ID": "KT", "RECORD_IF": "99.9%</br>(1타수 1안타)" }
          ],
          "code": "100",
          "msg": "성공"
        }
        """.data(using: .utf8)!
        let keyPlayerPitcherPayload = """
        {
          "record": [
            { "RANK_NO": 1, "P_ID": 998, "P_NM": "키플레이어투수", "T_ID": "LG", "RECORD_IF": "99.9%</br>(1이닝 0실점)" }
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
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(statusCode: 200, data: officialGameList),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetScoreBoardScroll": StubResponse(statusCode: 200, data: scoreboardPayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetBoxScoreScroll": StubResponse(statusCode: 200, data: boxScorePayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerHitter": StubResponse(statusCode: 200, data: keyPlayerHitterPayload),
            "https://www.koreabaseball.com/ws/Schedule.asmx/GetKeyPlayerPitcher": StubResponse(statusCode: 200, data: keyPlayerPitcherPayload)
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

        #expect(detail?.review?.hasDisplayableRecords == true)
        #expect(detail?.review?.summaryItems.contains { $0.value.contains("키플레이어") } != true)
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

    // officialGameCenterInvalidResponseCarriesLiveRequestDiagnostics 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialGameCenterInvalidResponseCarriesLiveRequestDiagnostics() async throws {
        let session = makeStubSession()
        let client = OfficialKBOGameCenterClient(
            baseURL: URL(string: "https://www.koreabaseball.com/")!,
            session: session
        )
        URLProtocolStub.testResponses = [
            "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList": StubResponse(
                statusCode: 200,
                data: #"{"code":"200","msg":"Object moved"}"#.data(using: .utf8)!,
                headers: ["Content-Type": "text/plain; charset=utf-8"]
            )
        ]
        defer { URLProtocolStub.testResponses = [:] }

        let game = try makeLiveBoxscoreDetailGame()

        do {
            _ = try await client.fetchDetail(for: game)
            Issue.record("Expected invalidResponse")
        } catch let OfficialKBOGameCenterError.officialError(message, diagnostic) {
            #expect(message == "Object moved")
            #expect(diagnostic.requestURL == "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList")
            #expect(diagnostic.providerGameID == "20260510SKOB0")
            #expect(diagnostic.publicGameID == "20260510-DOO-SSG")
            #expect(diagnostic.httpStatus == 200)
            #expect(diagnostic.contentType?.contains("text/plain") == true)
            #expect(diagnostic.bodyPreview.contains("Object moved"))
            #expect(diagnostic.parseFailureReason == "Official KBO error code 200: Object moved")
        } catch {
            Issue.record("Expected officialError, got \(error)")
        }
    }

    // officialGameCenterClientRejectsPlayResultsFromBattingAggregateStats 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameCenterKeyStatsDerivesHomeRunsAndStrikeoutsFromHitterRows 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameCenterKeyStatsUsesLineScoreAndBatterLinePrecedence 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameCenterKeyStatsUsesLineScoreAndBatterLinePrecedence() throws {
        let review = makeKeyStatsReview(
            summaryItems: [
                GameCenterSummaryItem(title: "홈런", value: "unused", values: ["0", "0"]),
                GameCenterSummaryItem(title: "도루", value: "unused", values: ["0", "0"]),
                GameCenterSummaryItem(title: "병살타", value: "unused", values: ["0", "0"]),
                GameCenterSummaryItem(title: "실책", value: "unused", values: ["9", "0"])
            ],
            awayLines: [
                makeKeyStatsBattingLine(name: "강백호", hits: "2", homeRuns: "3", stolenBases: "2", groundedIntoDoublePlay: "1", errors: "4"),
                makeKeyStatsBattingLine(name: "박병호", hits: "1", homeRuns: "1", stolenBases: "0", groundedIntoDoublePlay: "0", errors: "0")
            ],
            homeLines: [
                makeKeyStatsBattingLine(name: "홍창기", hits: "1", homeRuns: "2", stolenBases: "3", groundedIntoDoublePlay: "2", errors: "5"),
                makeKeyStatsBattingLine(name: "오지환", hits: "0", homeRuns: "0", stolenBases: "0", groundedIntoDoublePlay: "1", errors: "0")
            ]
        )
        let lineScore = GameCenterLineScore(
            inningLabels: [],
            awayInnings: [],
            homeInnings: [],
            awayTotals: GameCenterTeamLineTotals(runs: "8", hits: "9", errors: "1", walks: nil),
            homeTotals: GameCenterTeamLineTotals(runs: "3", hits: nil, errors: nil, walks: nil)
        )

        let stats = review.keyStats(awayTeam: keyStatsAwayTeam, homeTeam: keyStatsHomeTeam, lineScore: lineScore)

        #expect(stats.away.hits == 9)
        #expect(stats.home.hits == 1)
        #expect(stats.away.homeRuns == 4)
        #expect(stats.home.homeRuns == 2)
        #expect(stats.away.stolenBases == 2)
        #expect(stats.home.stolenBases == 3)
        #expect(stats.away.doublePlays == 1)
        #expect(stats.home.doublePlays == 3)
        #expect(stats.away.errors == 1)
        #expect(stats.home.errors == 5)
    }

    // gameCenterKeyStatsParsesStolenBasesAndDoublePlaysFromTableEtc 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameCenterKeyStatsSupportsMixedKoreanAndEnglishExtraLabels 메서드는 이 타입의 주요 동작을 수행합니다.
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
                makeKeyStatsBattingLine(name: "홍창기")
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

    // gameCenterKeyStatsDefaultsMissingFieldsSafelyToZero 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameCenterKeyStatsDefaultsMissingFieldsSafelyToZero() throws {
        let review = makeKeyStatsReview()

        let stats = review.keyStats(awayTeam: keyStatsAwayTeam, homeTeam: keyStatsHomeTeam, lineScore: nil)

        #expect(stats.away == GameCenterTeamKeyStats(hits: 0, homeRuns: 0, stolenBases: 0, strikeouts: 0, doublePlays: 0, errors: 0))
        #expect(stats.home == GameCenterTeamKeyStats(hits: 0, homeRuns: 0, stolenBases: 0, strikeouts: 0, doublePlays: 0, errors: 0))
    }

    // gameCenterKeyStatsKeepsAwayHomeValuesInOrder 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // makeKeyStatsReview 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // makeKeyStatsBattingLine 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    private func makeKeyStatsBattingLine(
        name: String,
        hits: String? = nil,
        homeRuns: String? = nil,
        stolenBases: String? = nil,
        strikeouts: String? = nil,
        groundedIntoDoublePlay: String? = nil,
        errors: String? = nil
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
            stolenBases: stolenBases,
            groundedIntoDoublePlay: groundedIntoDoublePlay,
            errors: errors,
            average: nil
        )
    }

    // makePositionBattingLine 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    private func makePositionBattingLine(order: String = "1", name: String, position: String) -> GameCenterBattingLine {
        GameCenterBattingLine(
            battingOrder: order,
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

    // liveRepositoryBuildsBootstrapFromOfficialLiveGamesPayload 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveRepositoryBuildsBootstrapFromOfficialLiveGamesPayload() async throws {
        let officialGameList = try fixtureData(named: "2026-kbo-official-game-list-20260323")
        let fixedDate = isoDate("2026-03-23T10:00:00+09:00")
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

    // liveRepositoryUsesDefaultNonMarchSeriesRuleForOfficialMonthlySchedule 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveRepositoryMapsBackendStandingsPayload 메서드는 이 타입의 주요 동작을 수행합니다.
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
        let snapshot = try #require(standings.first)
        #expect(snapshot.team.id == "lg")
        #expect(snapshot.rank == 1)
        #expect(snapshot.recentResults == [.win, .win, .loss])
        #expect(snapshot.runsScored == 31)
        #expect(snapshot.runsAllowed == 18)
        #expect(snapshot.pythagoreanWinningPercentage == StandingsMetrics.pythagoreanWinningPercentage(runsScored: 31, runsAllowed: 18))
        #expect(snapshot.rankingResolution == .resolved)
        #expect(snapshot.postseasonQualificationProbability == 0.84)
    }

    // liveRepositoryMapsBackendStandingsUnavailableProbabilityState 메서드는 이 타입의 주요 동작을 수행합니다.
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
        let snapshot = try #require(standings.first)
        #expect(snapshot.postseasonQualificationProbability == nil)
        #expect(snapshot.postseasonProbabilityUnavailableReason == .unknownClassificationGames)
        #expect(snapshot.postseasonQualificationText == "산출 불가")
    }

    // repositoryFactoryUsesBundledModeWhenBackendURLIsMissing 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // debugBuildSettingUsesDevelopmentSupabaseSchema 메서드는 Debug 빌드가 개발 schema를 사용하도록 고정합니다.
    @Test func debugBuildSettingUsesDevelopmentSupabaseSchema() throws {
        let xcconfig = try projectFileContents("kboScore/Config/Debug.xcconfig")
        let plist = try projectFileContents("Info-Debug.plist")

        #expect(xcconfig.contains("SUPABASE_DB_SCHEMA = kbo_crawler_api_dev"))
        #expect(plist.contains("<key>SupabaseDBSchema</key>"))
        #expect(plist.contains("<string>$(SUPABASE_DB_SCHEMA)</string>"))
    }

    // releaseBuildSettingUsesProductionSupabaseSchema 메서드는 Release/TestFlight/App Store 빌드가 운영 schema를 사용하도록 고정합니다.
    @Test func releaseBuildSettingUsesProductionSupabaseSchema() throws {
        let xcconfig = try projectFileContents("kboScore/Config/Release.xcconfig")
        let plist = try projectFileContents("Info-Release.plist")

        #expect(xcconfig.contains("SUPABASE_DB_SCHEMA = kbo_crawler_api"))
        #expect(xcconfig.contains("SUPABASE_DB_SCHEMA = kbo_crawler_api_dev") == false)
        #expect(plist.contains("<key>SupabaseDBSchema</key>"))
        #expect(plist.contains("<string>$(SUPABASE_DB_SCHEMA)</string>"))
    }

    // supabaseSchemaResolverUsesBuildConfigurationValues 메서드는 plist/env schema 값을 설정으로 해석합니다.
    @Test func supabaseSchemaResolverUsesBuildConfigurationValues() {
        #expect(AppRepositoryConfiguration.resolvedSupabaseSchema(
            environmentValue: nil,
            infoDictionaryValue: "kbo_crawler_api_dev",
            isDebugBuild: true
        ) == "kbo_crawler_api_dev")
        #expect(AppRepositoryConfiguration.resolvedSupabaseSchema(
            environmentValue: nil,
            infoDictionaryValue: "kbo_crawler_api",
            isDebugBuild: false
        ) == "kbo_crawler_api")
        #expect(AppRepositoryConfiguration.resolvedSupabaseSchema(
            environmentValue: nil,
            infoDictionaryValue: nil,
            isDebugBuild: false
        ) == "kbo_crawler_api")
    }

#if canImport(Supabase)
    // supabaseRepositoryUsesConfiguredSchema 메서드는 repository가 하드코딩 대신 configuration schema를 쓰도록 고정합니다.
    @Test func supabaseRepositoryUsesConfiguredSchema() throws {
        let configuration = SupabaseConfiguration(
            url: try #require(URL(string: "https://example.supabase.co")),
            publishableKey: "anon-key",
            schema: "custom_schema"
        )
        let repository = SupabaseKBORepository(configuration: configuration)

        #expect(repository.configuredSchemaName == "custom_schema")
    }
#endif

    // supabaseFailureFallsBackToLocalRepository 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseBootstrapUsesLocalBootstrapWhenGamesExist 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // bundledJSONRepositoryUsesDocumentsJSONWhenPresent 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // bundledJSONRepositoryFallsBackToBundledJSONWhenDocumentsJSONIsMissing 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // bundledJSONRepositoryFallsBackToBundledJSONWhenDocumentsJSONIsInvalid 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // externalDocumentsBootstrapStillDrivesStandingsAndProbabilityDerivation 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func externalDocumentsBootstrapStillDrivesStandingsAndProbabilityDerivation() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let bundledDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }

        let documentsURL = documentsDirectory.appendingPathComponent("LocalBootstrapData.json")
        let bundledURL = bundledDirectory.appendingPathComponent("LocalBootstrapData.json")
        let sourceData = try localBootstrapFixtureData()
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
        await model.loadStandingsIfNeeded()

        #expect(model.regularSeasonGames.isEmpty == false)
        #expect(model.standingsSnapshots.count == model.teams.count)
        #expect(model.standingsSnapshots.contains { $0.wins + $0.losses + $0.ties > 0 })
        #expect(model.debugLocalBootstrapSource == "문서 JSON")
    }

    // fixtureLoaderReportsMissingFixtureNameAndPath 메서드는 fixture 누락 실패 메시지를 명확히 유지합니다.
    @Test func fixtureLoaderReportsMissingFixtureNameAndPath() {
        do {
            _ = try fixtureData(named: "missing-bootstrap-fixture")
            #expect(Bool(false))
        } catch let error as TestFixtureError {
            #expect(error.description.contains("missing-bootstrap-fixture.json"))
            #expect(error.description.contains("Fixtures"))
        } catch {
            #expect(Bool(false))
        }
    }

    // testsDoNotReadProjectLocalBootstrapDataDirectly 메서드는 테스트가 fixture loader를 우회하지 않도록 고정합니다.
    @Test func testsDoNotReadProjectLocalBootstrapDataDirectly() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        let forbiddenPath = "kboScore/" + "LocalBootstrapData.json"

        #expect(source.contains(forbiddenPath) == false)
    }

    // appModelRefreshReReadsEditedDocumentsBootstrapJSON 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // appModelRefreshHomeReappliesEditedDocumentsBootstrapTeams 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // bundledJSONRepositoryRecoversAfterInvalidDocumentsJSONIsFixed 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // repositoryFactoryIgnoresLegacyBackendURLWhenBuildingRuntimeRepository 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // liveRepositoryBuildsLocalhostBackendRequestURLs 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameBoxscoreResponseDecodesFullBatterAndPitcherRecords 메서드는 이 타입의 주요 동작을 수행합니다.
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
        #expect(response.awayBatters[1].stolenBases == 1)
        #expect(response.awayBatters[1].groundedIntoDoublePlay == 1)
        #expect(response.homeBatters[0].errors == 1)
        #expect(response.awayPitchers[0].playerName == "잭로그")
        #expect(response.awayPitchers[0].appearance == "선발")
        #expect(response.awayPitchers[0].decisionResult == "승")
        #expect(response.awayPitchers[0].inningsPitched == "6 1/3")
        #expect(response.awayPitchers[0].battersFaced == 24)
        #expect(response.awayPitchers[0].pitchCount == 88)
        #expect(response.awayPitchers[0].walksOrHitByPitch == 1)
        #expect(response.awayPitchers[0].era == "3.19")
    }

    // gameBoxscoreResponseBuildsMajorRecordSummaryItemsFromLiveTextStats 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameBoxscoreResponseBuildsMajorRecordSummaryItemsFromLiveTextStats() throws {
        let response = try JSONDecoder().decode(GameBoxscoreResponse.self, from: sampleGameBoxscoreJSON()).sortedBySourceOrder
        let review = try #require(response.gameCenterReview)
        let stats = review.keyStats(awayTeam: Team(id: "doosan", name: "두산", shortName: "두산", englishName: "Doosan Bears", markText: "두산"), homeTeam: Team(id: "ssg", name: "SSG", shortName: "SSG", englishName: "SSG Landers", markText: "SSG"), lineScore: nil)

        #expect(review.summaryItems.contains { $0.title == "도루" && $0.values == ["1", "0"] })
        #expect(review.summaryItems.contains { $0.title == "병살타" && $0.values == ["1", "0"] })
        #expect(review.summaryItems.contains { $0.title == "실책" && $0.values == ["0", "1"] })
        #expect(stats.away.stolenBases == 1)
        #expect(stats.away.doublePlays == 1)
        #expect(stats.home.errors == 1)
    }

    // gameBoxscoreResponseKeepsNullableBatterFieldsNil 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameBoxscoreResponseKeepsNullableBatterFieldsNil() throws {
        let response = try JSONDecoder().decode(GameBoxscoreResponse.self, from: sampleGameBoxscoreJSON()).sortedBySourceOrder
        let batter = try #require(response.awayBatters.first)

        #expect(batter.homeRuns == nil)
        #expect(batter.walks == nil)
        #expect(batter.strikeouts == nil)
        #expect(batter.stolenBases == nil)
    }

    // gameDetailBatterStolenBaseDisplayDefaultsOnlyThatColumnToZero 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailBatterStolenBaseDisplayDefaultsOnlyThatColumnToZero() throws {
        let missingStat: String? = nil

        #expect(missingStat.displayStolenBaseStat == "0")
        #expect((missingStat ?? "-") == "-")
    }

    // gameRecordPositionFormatterDisplaysReadableBatterPositions 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameRecordPositionFormatterCoversObservedDetailedBatterRows 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameRecordPositionFormatterCoversObservedDetailedBatterRows() throws {
        #expect(GameRecordPositionFormatter.display("주우") == "PR·RF")
        #expect(GameRecordPositionFormatter.display("주二") == "PR·2B")
        #expect(GameRecordPositionFormatter.display("유三") == "SS·3B")
        #expect(GameRecordPositionFormatter.display("二유") == "2B·SS")
    }

    // gameRecordPositionEnrichmentUsesUnambiguousRicherSameTeamSource 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameRecordPositionEnrichmentUsesUnambiguousRicherSameTeamSource() throws {
        #if DEBUG
        GameRecordPositionFormatter.resetDebugLogCacheForTesting()
        #endif
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

    // gameRecordPositionEnrichmentFallsBackToBattingOrderForSubstitutes 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameRecordPositionEnrichmentFallsBackToBattingOrderForSubstitutes() throws {
        let current = GameCenterBattingSection(
            lines: [
                makePositionBattingLine(order: "8", name: "김지찬", position: ""),
                makePositionBattingLine(order: "9", name: "김도환", position: "")
            ],
            totals: nil
        )
        let source = GameCenterBattingSection(
            lines: [
                makePositionBattingLine(order: "8", name: "장승현", position: "포수"),
                makePositionBattingLine(order: "9", name: "김상준", position: "유격수")
            ],
            totals: nil
        )

        let enriched = current.enrichingPositions(from: source, sideLabel: "home")

        #expect(GameRecordPositionFormatter.display(enriched.lines[0].position) == "C")
        #expect(GameRecordPositionFormatter.display(enriched.lines[1].position) == "SS")
    }

    // gameRecordPositionEnrichmentInfersBlankSubstituteOrderFromAdjacentRows 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameRecordPositionEnrichmentInfersBlankSubstituteOrderFromAdjacentRows() throws {
        let current = GameCenterBattingSection(
            lines: [
                makePositionBattingLine(order: "7", name: "손호영", position: ""),
                makePositionBattingLine(order: "", name: "김세민", position: ""),
                makePositionBattingLine(order: "", name: "노진혁", position: ""),
                makePositionBattingLine(order: "8", name: "손성빈", position: "")
            ],
            totals: nil
        )
        let source = GameCenterBattingSection(
            lines: [
                makePositionBattingLine(order: "7", name: "손호영", position: "3루수"),
                makePositionBattingLine(order: "8", name: "손성빈", position: "포수")
            ],
            totals: nil
        )

        let enriched = current.enrichingPositions(from: source, sideLabel: "away")

        #expect(GameRecordPositionFormatter.display(enriched.lines[1].position) == "3B")
        #expect(GameRecordPositionFormatter.display(enriched.lines[2].position) == "3B")
    }

    // gameRecordPositionDebugLogsAreDedupedForSamePlayerAndGame 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameRecordPositionDebugLogsAreDedupedForSamePlayerAndGame() throws {
        #if DEBUG
        GameRecordPositionFormatter.resetDebugLogCacheForTesting()
        let current = GameCenterBattingSection(
            lines: [
                makePositionBattingLine(name: "정현창", position: "--")
            ],
            totals: nil
        )
        let source = GameCenterBattingSection(
            lines: [
                makePositionBattingLine(name: "정현창", position: "二유")
            ],
            totals: nil
        )

        _ = current.enrichingPositions(from: source, sideLabel: "away")
        _ = current.enrichingPositions(from: source, sideLabel: "away")

        #expect(GameRecordPositionFormatter.debugLoggedPositionCountForTesting == 1)
        #endif
    }

    // supabaseBatterRecordDTODecodesSnakeCaseColumns 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func supabaseBatterRecordDTODecodesSnakeCaseColumns() throws {
        let gameID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let teamID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let row = try JSONDecoder().decode(
            SupabaseGameBatterRecordRow.self,
            from: Data(
                """
                {
                  "id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
                  "game_id": "\(gameID.uuidString)",
                  "team_id": "\(teamID.uuidString)",
                  "source_order": 3,
                  "batting_order": 7,
                  "position": "一",
                  "player_name": "나승엽",
                  "at_bats": 2,
                  "runs": 1,
                  "hits": 1,
                  "rbi": 2,
                  "home_runs": 1,
                  "walks": 1,
                  "strikeouts": 0,
                  "stolen_bases": 0,
                  "batting_average": "0.500"
                }
                """.utf8
            )
        )

        #expect(row.gameID == gameID)
        #expect(row.teamID == teamID)
        #expect(row.sourceOrder == 3)
        #expect(row.battingOrder == 7)
        #expect(row.playerName == "나승엽")
        #expect(row.homeRuns == 1)
        #expect(row.walks == 1)
    }

    // supabasePitcherRecordDTODecodesSnakeCaseColumns 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func supabasePitcherRecordDTODecodesSnakeCaseColumns() throws {
        let gameID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let teamID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let row = try JSONDecoder().decode(
            SupabaseGamePitcherRecordRow.self,
            from: Data(
                """
                {
                  "id": "dddddddd-dddd-dddd-dddd-dddddddddddd",
                  "game_id": "\(gameID.uuidString)",
                  "team_id": "\(teamID.uuidString)",
                  "source_order": 0,
                  "pitching_order": 1,
                  "player_name": "나균안",
                  "appearance": "선발",
                  "decision_result": null,
                  "wins": null,
                  "losses": null,
                  "saves": null,
                  "innings_pitched": "2 1/3",
                  "batters_faced": 11,
                  "pitch_count": 45,
                  "at_bats": 10,
                  "hits": 3,
                  "home_runs": 1,
                  "walks_or_hit_by_pitch": 1,
                  "strikeouts": 2,
                  "runs": 1,
                  "earned_runs": 1,
                  "era": null
                }
                """.utf8
            )
        )

        #expect(row.gameID == gameID)
        #expect(row.teamID == teamID)
        #expect(row.pitchingOrder == 1)
        #expect(row.playerName == "나균안")
        #expect(row.inningsPitched == "2 1/3")
        #expect(row.pitchCount == 45)
        #expect(row.walksOrHitByPitch == 1)
    }

    // supabaseDetailedRecordsMapIntoGameCenterRowsAndSortBySourceOrder 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func supabaseDetailedRecordsMapIntoGameCenterRowsAndSortBySourceOrder() throws {
        let fixture = try makeSupabaseDetailedRecordFixture()

        let review = try #require(SupabaseKBOMapper.mapDetailedRecordReview(
            game: fixture.game,
            awayTeamDatabaseID: fixture.awayTeamID,
            homeTeamDatabaseID: fixture.homeTeamID,
            batterRows: [
                fixture.batter(name: "나승엽", teamID: fixture.awayTeamID, sourceOrder: 1, battingOrder: nil, walks: 1),
                fixture.batter(name: "황성빈", teamID: fixture.awayTeamID, sourceOrder: 0, battingOrder: nil, atBats: 2, strikeouts: 1),
                fixture.batter(name: "아데를린", teamID: fixture.homeTeamID, sourceOrder: 0, battingOrder: 4, rbi: 1, homeRuns: 1)
            ],
            pitcherRows: [
                fixture.pitcher(name: "네일", teamID: fixture.homeTeamID, sourceOrder: 0, pitchingOrder: 1, innings: "3", pitchCount: 42, hits: 2, strikeouts: 4),
                fixture.pitcher(name: "나균안", teamID: fixture.awayTeamID, sourceOrder: 0, pitchingOrder: 1, innings: "2 1/3", pitchCount: 45, hits: 3, homeRuns: 1, strikeouts: 2, runs: 1, earnedRuns: 1)
            ]
        ))

        #expect(review.recordSource == .dbLiveRecordsFresh)
        #expect(review.awayBatting.lines.map(\.name) == ["황성빈", "나승엽"])
        #expect(review.awayBatting.lines[0].atBats == "2")
        #expect(review.awayBatting.lines[0].strikeouts == "1")
        #expect(review.awayBatting.lines[1].walks == "1")
        #expect(review.homeBatting.lines[0].homeRuns == "1")
        #expect(review.homeBatting.lines[0].runsBattedIn == "1")
        #expect(review.awayBatting.lines[0].average == nil)
        #expect(review.awayPitching.lines.map(\.name) == ["나균안"])
        #expect(review.homePitching.lines.map(\.name) == ["네일"])
        #expect(review.awayPitching.lines[0].pitches == "45")
        #expect(review.awayPitching.lines[0].homeRunsAllowed == "1")
        #expect(review.awayPitching.lines[0].earnedRuns == "1")
    }

    // supabasePitcherRecordsSortByPitchingOrderBeforeSourceOrder 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func supabasePitcherRecordsSortByPitchingOrderBeforeSourceOrder() throws {
        let fixture = try makeSupabaseDetailedRecordFixture()

        let review = try #require(SupabaseKBOMapper.mapDetailedRecordReview(
            game: fixture.game,
            awayTeamDatabaseID: fixture.awayTeamID,
            homeTeamDatabaseID: fixture.homeTeamID,
            batterRows: [],
            pitcherRows: [
                fixture.pitcher(name: "두번째", teamID: fixture.awayTeamID, sourceOrder: 0, pitchingOrder: 2),
                fixture.pitcher(name: "첫번째", teamID: fixture.awayTeamID, sourceOrder: 9, pitchingOrder: 1)
            ]
        ))

        #expect(review.awayPitching.lines.map(\.name) == ["첫번째", "두번째"])
    }

    // gameDetailDatabaseRecordsUseResolvedSupabaseGameIDWhenLocalIDDiffers 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailDatabaseRecordsUseResolvedSupabaseGameIDWhenLocalIDDiffers() async throws {
        let inputLocalGameID = UUID(uuidString: "76E4CD75-1111-2222-3333-444444444444")!
        let resolvedSupabaseGameID = UUID(uuidString: "A9E90D0E-8BA7-404C-960A-DB7D01CA8AF3")!
        let awayTeamID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let homeTeamID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데"),
            SupabaseTeamRow(id: homeTeamID, code: "kia", name: "KIA 타이거즈", shortName: "KIA")
        ]
        let game = makeGameDetail(
            id: inputLocalGameID,
            scheduledStart: isoDate("2026-06-02T18:30:00+09:00"),
            venue: "광주",
            awayTeam: SupabaseKBOMapper.mapTeam(teamRows[0]),
            homeTeam: SupabaseKBOMapper.mapTeam(teamRows[1]),
            awayScore: 0,
            homeScore: 0,
            status: .final,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260602-KIA-LOT provider_game_id=20260602LTHT0",
            providerGameID: "20260602LTHT0"
        )
        let gameRow = try makeSupabaseGameRow(
            id: resolvedSupabaseGameID,
            publicGameID: "20260602-KIA-LOT",
            providerGameID: "20260602LTHT0",
            gameDate: "2026-06-02",
            scheduledAt: "2026-06-02T18:30:00+09:00",
            stadium: "광주",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 0,
            homeScore: 0,
            inningState: "Top 1"
        )
        let fixture = SupabaseDetailedRecordFixture(
            game: game,
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID
        )
        let batterRows = (0..<18).map { index in
            fixture.batter(
                name: "타자\(index + 1)",
                teamID: index < 9 ? awayTeamID : homeTeamID,
                sourceOrder: index < 9 ? index : index - 9,
                battingOrder: (index % 9) + 1,
                gameID: resolvedSupabaseGameID,
                atBats: 1
            )
        }
        let pitcherRows = [
            fixture.pitcher(
                name: "나균안",
                teamID: awayTeamID,
                sourceOrder: 0,
                pitchingOrder: 1,
                gameID: resolvedSupabaseGameID,
                innings: "1",
                pitchCount: 12
            ),
            fixture.pitcher(
                name: "네일",
                teamID: homeTeamID,
                sourceOrder: 0,
                pitchingOrder: 1,
                gameID: resolvedSupabaseGameID,
                innings: "1",
                pitchCount: 11
            )
        ]
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(),
            source: TrackingSupabaseSource(
                teamRows: teamRows,
                gameRows: [gameRow],
                tracker: tracker,
                batterRows: batterRows,
                pitcherRows: pitcherRows
            ),
            runtimeState: nil
        )

        let fetchedReview = try await repository.fetchGameDetailDatabaseReview(for: game)
        let review = try #require(fetchedReview)

        #expect(review.recordSource == .dbLiveRecordsFresh)
        #expect(review.awayBatting.lines.count + review.homeBatting.lines.count == 18)
        #expect(review.awayPitching.lines.count + review.homePitching.lines.count == 2)
        #expect(await tracker.batterRecordGameIDs == [resolvedSupabaseGameID])
        #expect(await tracker.pitcherRecordGameIDs == [resolvedSupabaseGameID])
        #expect(await tracker.eventRecordGameIDs == [resolvedSupabaseGameID])
        #expect(await tracker.batterRecordGameIDs.contains(inputLocalGameID) == false)
        #expect(await tracker.pitcherRecordGameIDs.contains(inputLocalGameID) == false)
    }

    // gameDetailSnapshotResultPreservesRawSupabaseGameIDSeparatelyFromMappedLocalID 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailSnapshotResultPreservesRawSupabaseGameIDSeparatelyFromMappedLocalID() async throws {
        let inputLocalGameID = UUID(uuidString: "86A920BA-5084-56F4-8F60-B1CB508C30E7")!
        let rawSupabaseGameID = UUID(uuidString: "1040A2AB-2E5D-4F20-9743-80C39C2C7345")!
        let awayTeamID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let homeTeamID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데"),
            SupabaseTeamRow(id: homeTeamID, code: "kia", name: "KIA 타이거즈", shortName: "KIA")
        ]
        let game = makeGameDetail(
            id: inputLocalGameID,
            scheduledStart: isoDate("2026-06-03T18:30:00+09:00"),
            venue: "광주",
            awayTeam: SupabaseKBOMapper.mapTeam(teamRows[0]),
            homeTeam: SupabaseKBOMapper.mapTeam(teamRows[1]),
            awayScore: 0,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260603-KIA-LOT provider_game_id=20260603LTHT0",
            providerGameID: "20260603LTHT0"
        )
        let gameRow = try makeSupabaseGameRow(
            id: rawSupabaseGameID,
            publicGameID: "20260603-KIA-LOT",
            providerGameID: "20260603LTHT0",
            gameDate: "2026-06-03",
            scheduledAt: "2026-06-03T18:30:00+09:00",
            stadium: "광주",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 0,
            homeScore: 0,
            inningState: "Top 1"
        )
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(),
            source: TrackingSupabaseSource(teamRows: teamRows, gameRows: [gameRow], tracker: tracker),
            runtimeState: nil
        )

        let result = try #require(await repository.fetchGameDetailSnapshotResult(
            for: game,
            identity: "provider:20260603LTHT0",
            cachedTeams: []
        ))

        #expect(result.rawSupabaseGameID == rawSupabaseGameID)
        #expect(result.providerGameID == "20260603LTHT0")
        #expect(result.publicGameID == "20260603-KIA-LOT")
        #expect(result.game.id != rawSupabaseGameID)
    }

    @Test func liveDatabaseRecordRefreshBypassesRawSupabaseIDCache() async throws {
        let localGameID = UUID(uuidString: "86A920BA-5084-56F4-8F60-B1CB508C30E7")!
        let rawSupabaseGameID = UUID(uuidString: "1040A2AB-2E5D-4F20-9743-80C39C2C7345")!
        let awayTeamID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let homeTeamID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "doosan", name: "두산 베어스", shortName: "두산"),
            SupabaseTeamRow(id: homeTeamID, code: "ssg", name: "SSG 랜더스", shortName: "SSG")
        ]
        let initialGame = try makeLiveBoxscoreDetailGame(status: .upcoming, id: localGameID)
        let gameRow = try makeSupabaseGameRow(
            id: rawSupabaseGameID,
            publicGameID: initialGame.publicGameID ?? "20260510-DOO-SSG",
            providerGameID: initialGame.providerGameID ?? "20260510SKOB0",
            gameDate: "2026-05-10",
            scheduledAt: "2026-05-10T14:00:00+09:00",
            stadium: "잠실",
            status: "live",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 3,
            homeScore: 1,
            inningState: "Top 3"
        )
        let snapshot = try makeSupabaseLatestSnapshotRow(
            gameID: rawSupabaseGameID,
            inningLabel: "Top 3",
            balls: 1,
            strikes: 2,
            outs: 1,
            awayScore: 3,
            homeScore: 1,
            runnerOnFirst: true,
            updatedAt: "2026-05-10T14:10:00+09:00"
        )
        let fixture = SupabaseDetailedRecordFixture(
            game: initialGame,
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID
        )
        var batter = fixture.batter(
            name: "최신타자",
            teamID: awayTeamID,
            sourceOrder: 0,
            battingOrder: 1,
            gameID: rawSupabaseGameID,
            atBats: 2
        )
        batter.updatedAt = "2026-05-10T14:10:00+09:00"
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(),
            source: TrackingSupabaseSource(
                teamRows: teamRows,
                gameRows: [gameRow],
                tracker: tracker,
                batterRows: [batter],
                latestSnapshotRows: [snapshot]
            ),
            runtimeState: nil
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [initialGame], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-10T14:11:00+09:00") }
        )

        let refreshed = try #require(await model.refreshGameDetailResult(for: initialGame.stableDetailIdentity)?.game)
        #expect(refreshed.status == .live)

        _ = await model.fetchGameDetailDatabaseReviewResult(for: refreshed)
        _ = await model.fetchGameDetailDatabaseReviewResult(for: refreshed)

        let finalGame = try makeLiveBoxscoreDetailGame(status: .final, id: localGameID)
        _ = await model.fetchGameDetailDatabaseReviewResult(for: finalGame)
        _ = await model.fetchGameDetailDatabaseReviewResult(for: finalGame, forceRefresh: true)

        #expect(await tracker.batterRecordGameIDs == [rawSupabaseGameID, rawSupabaseGameID, rawSupabaseGameID])
    }

    @Test func latestGameSnapshotResultUsesSingleSnapshotQueryForLiveSituation() async throws {
        let gameID = UUID(uuidString: "1040A2AB-2E5D-4F20-9743-80C39C2C7345")!
        let game = makeGameDetail(
            id: gameID,
            scheduledStart: isoDate("2026-07-07T18:30:00+09:00"),
            venue: "문학",
            awayTeam: Team(id: "doosan", name: "두산 베어스", shortName: "두산", englishName: "Doosan Bears", markText: "DOO"),
            homeTeam: Team(id: "ssg", name: "SSG 랜더스", shortName: "SSG", englishName: "SSG Landers", markText: "SSG"),
            awayScore: 3,
            homeScore: 4,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Bottom 8",
            note: "public_game_id=20260707-DOO-SSG provider_game_id=20260707OBSK0",
            providerGameID: "20260707OBSK0",
            bases: RunnerState(first: false, second: false, third: false),
            baseRunners: nil,
            balls: 0,
            strikes: 0,
            outs: 0,
            currentPitcherName: "문승원",
            currentBatterName: "양의지"
        )
        let snapshot = try makeSupabaseLatestSnapshotRow(
            gameID: gameID,
            inningLabel: "Bottom 8",
            currentPitcherName: "김민",
            currentBatterName: "안재석",
            balls: 2,
            strikes: 1,
            outs: 1,
            awayScore: 5,
            homeScore: 4,
            runnerOnFirst: false,
            runnerOnSecond: true,
            runnerOnThird: true,
            secondRunnerName: "허경민",
            thirdRunnerName: "정수빈",
            createdAt: "2026-07-07T12:30:10Z",
            updatedAt: "2026-07-07T12:30:11Z"
        )
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(),
            source: TrackingSupabaseSource(teamRows: [], gameRows: [], tracker: tracker, latestSnapshotRows: [snapshot]),
            runtimeState: nil
        )

        let result = try #require(await repository.fetchLatestGameSnapshotResult(gameID: gameID, fallbackGame: game))

        #expect(result.game.awayScore == 5)
        #expect(result.game.homeScore == 4)
        #expect(result.game.currentPitcherName == "김민")
        #expect(result.game.currentBatterName == "안재석")
        #expect(result.game.balls == 2)
        #expect(result.game.strikes == 1)
        #expect(result.game.outs == 1)
        #expect(result.game.bases == RunnerState(first: false, second: true, third: true))
        #expect(result.game.baseRunners?.second == "허경민")
        #expect(result.game.baseRunners?.third == "정수빈")
        #expect(result.snapshotCreatedAt != nil)
        #expect(result.snapshotUpdatedAt != nil)
        #expect(await tracker.latestSnapshotGameIDs == [gameID])
        #expect(await tracker.singleLookups.isEmpty)
    }

    // explicitSupabaseGameIDDatabaseReviewQueriesDetailedRecordsWithRawID 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func explicitSupabaseGameIDDatabaseReviewQueriesDetailedRecordsWithRawID() async throws {
        let localGameID = UUID(uuidString: "86A920BA-5084-56F4-8F60-B1CB508C30E7")!
        let rawSupabaseGameID = UUID(uuidString: "1040A2AB-2E5D-4F20-9743-80C39C2C7345")!
        let awayTeamID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let homeTeamID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데"),
            SupabaseTeamRow(id: homeTeamID, code: "kia", name: "KIA 타이거즈", shortName: "KIA")
        ]
        let mappedGame = makeGameDetail(
            id: localGameID,
            scheduledStart: isoDate("2026-06-03T18:30:00+09:00"),
            venue: "광주",
            awayTeam: SupabaseKBOMapper.mapTeam(teamRows[0]),
            homeTeam: SupabaseKBOMapper.mapTeam(teamRows[1]),
            awayScore: 0,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260603-KIA-LOT provider_game_id=20260603LTHT0",
            providerGameID: "20260603LTHT0"
        )
        let gameRow = try makeSupabaseGameRow(
            id: rawSupabaseGameID,
            publicGameID: "20260603-KIA-LOT",
            providerGameID: "20260603LTHT0",
            gameDate: "2026-06-03",
            scheduledAt: "2026-06-03T18:30:00+09:00",
            stadium: "광주",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 0,
            homeScore: 0,
            inningState: "Top 1"
        )
        let fixture = SupabaseDetailedRecordFixture(
            game: mappedGame,
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID
        )
        let batterRows = (0..<18).map { index in
            fixture.batter(
                name: "타자\(index + 1)",
                teamID: index < 9 ? awayTeamID : homeTeamID,
                sourceOrder: index < 9 ? index : index - 9,
                battingOrder: (index % 9) + 1,
                gameID: rawSupabaseGameID,
                atBats: 1
            )
        }
        let pitcherRows = [
            fixture.pitcher(name: "원정투수", teamID: awayTeamID, sourceOrder: 0, pitchingOrder: 1, gameID: rawSupabaseGameID, innings: "1", pitchCount: 12),
            fixture.pitcher(name: "홈투수", teamID: homeTeamID, sourceOrder: 0, pitchingOrder: 1, gameID: rawSupabaseGameID, innings: "1", pitchCount: 11)
        ]
        let eventRows = (0..<40).map { index in
            SupabaseGameEventRow(
                id: UUID(),
                gameID: rawSupabaseGameID,
                providerEventID: "event-\(index)",
                sequenceNumber: index,
                inning: 1,
                inningHalf: "top",
                eventType: "play",
                eventText: "event \(index)"
            )
        }
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(),
            source: TrackingSupabaseSource(
                teamRows: teamRows,
                gameRows: [gameRow],
                tracker: tracker,
                batterRows: batterRows,
                pitcherRows: pitcherRows,
                eventRows: eventRows
            ),
            runtimeState: nil
        )

        let result = try #require(await repository.fetchGameDetailDatabaseReview(
            supabaseGameId: rawSupabaseGameID,
            providerGameID: "20260603LTHT0",
            publicGameID: "20260603-KIA-LOT",
            invokedFrom: "afterFetchGameSingleRawSupabaseId"
        ))

        #expect(result.rawSupabaseGameID == rawSupabaseGameID)
        #expect(result.publicBatterRawRowCount == 18)
        #expect(result.publicPitcherRawRowCount == 2)
        #expect(result.eventRawRowCount == 40)
        #expect(result.mappedBatterCount == 18)
        #expect(result.mappedPitcherCount == 2)
        #expect(result.review?.recordSource == .dbLiveRecordsFresh)
        #expect(await tracker.batterRecordGameIDs == [rawSupabaseGameID])
        #expect(await tracker.pitcherRecordGameIDs == [rawSupabaseGameID])
        #expect(await tracker.eventRecordGameIDs == [rawSupabaseGameID])
        #expect(await tracker.batterRecordGameIDs.contains(localGameID) == false)
    }

    // providerResolvedDatabaseReviewQueriesDetailedRecordsWithRawSupabaseID 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func providerResolvedDatabaseReviewQueriesDetailedRecordsWithRawSupabaseID() async throws {
        let localGameID = UUID(uuidString: "86A920BA-5084-56F4-8F60-B1CB508C30E7")!
        let rawSupabaseGameID = UUID(uuidString: "1040A2AB-2E5D-4F20-9743-80C39C2C7345")!
        let awayTeamID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let homeTeamID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let teamRows = [
            SupabaseTeamRow(id: awayTeamID, code: "lotte", name: "롯데 자이언츠", shortName: "롯데"),
            SupabaseTeamRow(id: homeTeamID, code: "kia", name: "KIA 타이거즈", shortName: "KIA")
        ]
        let mappedGame = makeGameDetail(
            id: localGameID,
            scheduledStart: isoDate("2026-06-03T18:30:00+09:00"),
            venue: "광주",
            awayTeam: SupabaseKBOMapper.mapTeam(teamRows[0]),
            homeTeam: SupabaseKBOMapper.mapTeam(teamRows[1]),
            awayScore: 0,
            homeScore: 0,
            status: .live,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260603-KIA-LOT provider_game_id=20260603LTHT0",
            providerGameID: "20260603LTHT0"
        )
        let gameRow = try makeSupabaseGameRow(
            id: rawSupabaseGameID,
            publicGameID: "20260603-KIA-LOT",
            providerGameID: "20260603LTHT0",
            gameDate: "2026-06-03",
            scheduledAt: "2026-06-03T18:30:00+09:00",
            stadium: "광주",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 0,
            homeScore: 0,
            inningState: "Top 1"
        )
        let fixture = SupabaseDetailedRecordFixture(
            game: mappedGame,
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID
        )
        let batterRows = (0..<18).map { index in
            fixture.batter(
                name: "타자\(index + 1)",
                teamID: index < 9 ? awayTeamID : homeTeamID,
                sourceOrder: index < 9 ? index : index - 9,
                battingOrder: (index % 9) + 1,
                gameID: rawSupabaseGameID,
                atBats: 1
            )
        }
        let pitcherRows = [
            fixture.pitcher(name: "원정투수", teamID: awayTeamID, sourceOrder: 0, pitchingOrder: 1, gameID: rawSupabaseGameID, innings: "1", pitchCount: 12),
            fixture.pitcher(name: "홈투수", teamID: homeTeamID, sourceOrder: 0, pitchingOrder: 1, gameID: rawSupabaseGameID, innings: "1", pitchCount: 11)
        ]
        let eventRows = (0..<40).map { index in
            SupabaseGameEventRow(
                id: UUID(),
                gameID: rawSupabaseGameID,
                providerEventID: "event-\(index)",
                sequenceNumber: index,
                inning: 1,
                inningHalf: "top",
                eventType: "play",
                eventText: "event \(index)"
            )
        }
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(),
            source: TrackingSupabaseSource(
                teamRows: teamRows,
                gameRows: [gameRow],
                tracker: tracker,
                batterRows: batterRows,
                pitcherRows: pitcherRows,
                eventRows: eventRows
            ),
            runtimeState: nil
        )

        let result = try #require(await repository.fetchGameDetailDatabaseReview(
            providerGameID: "20260603LTHT0",
            publicGameID: "20260603-KIA-LOT",
            invokedFrom: "afterFetchGameSingleProviderResolved"
        ))

        #expect(result.inputLocalGameID != rawSupabaseGameID)
        #expect(result.rawSupabaseGameID == rawSupabaseGameID)
        #expect(result.resolvedSupabaseGameID == rawSupabaseGameID)
        #expect(result.providerGameID == "20260603LTHT0")
        #expect(result.publicGameID == "20260603-KIA-LOT")
        #expect(result.publicBatterRawRowCount == 18)
        #expect(result.publicPitcherRawRowCount == 2)
        #expect(result.eventRawRowCount == 40)
        #expect(result.mappedBatterCount == 18)
        #expect(result.mappedPitcherCount == 2)
        #expect(result.review?.recordSource == .dbLiveRecordsFresh)
        #expect(await tracker.singleLookups == [
            .providerGameID("20260603LTHT0"),
            .databaseID(rawSupabaseGameID)
        ])
        #expect(await tracker.batterRecordGameIDs == [rawSupabaseGameID])
        #expect(await tracker.pitcherRecordGameIDs == [rawSupabaseGameID])
        #expect(await tracker.eventRecordGameIDs == [rawSupabaseGameID])
        #expect(await tracker.batterRecordGameIDs.contains(localGameID) == false)

        let appRepository = AnyKBORepository(
            CachedKBORepository(
                base: AnyKBORepository(repository),
                configuration: .supabaseStartup,
                runtimeState: nil
            )
        )
        let cachedResult = try #require(await appRepository.fetchGameDetailDatabaseReview(
            providerGameID: "20260603LTHT0",
            publicGameID: "20260603-KIA-LOT",
            invokedFrom: "afterFetchGameSingleProviderResolved"
        ))
        #expect(cachedResult.rawSupabaseGameID == rawSupabaseGameID)
        #expect(cachedResult.publicBatterRawRowCount == 18)
        #expect(cachedResult.publicPitcherRawRowCount == 2)
        #expect(cachedResult.eventRawRowCount == 40)
        #expect(cachedResult.review?.recordSource == .dbLiveRecordsFresh)
        #expect(await tracker.singleLookups == [
            .providerGameID("20260603LTHT0"),
            .databaseID(rawSupabaseGameID),
            .providerGameID("20260603LTHT0"),
            .databaseID(rawSupabaseGameID)
        ])
    }

    // liveGameDetailUsesFreshDatabaseRecordsWhenBoxscoreUnavailable 메서드는 live 경기에서 최신 DB 기록을 우선 적용하는지 검증합니다.
    @Test func liveGameDetailUsesFreshDatabaseRecordsWhenBoxscoreUnavailable() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let game = try makeLiveBoxscoreDetailGame()
        let databaseReview = try makeSampleDatabaseRecordReview(game: game)
        let databaseFetcher = RecordingDatabaseReviewFetcher(review: databaseReview)
        let officialFallback = RecordingOfficialFallback(result: .success(sampleKeyplayerLimitedReview()))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game) },
            fetchDatabaseRecordReview: { game in await databaseFetcher.fetch(game: game) },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )

        await model.load(for: game)
        await model.waitForBoxscoreLoadForTesting()
        await model.waitForDatabaseRecordLoadForTesting()
        await model.waitForOfficialFallbackLoadForTesting()

        let presentation = GameDetailPresentation(
            game: game,
            payload: model.detail,
            boxscore: model.boxscore,
            databaseRecordReview: model.databaseRecordReview,
            officialFallbackReview: model.officialFallbackReview
        )
        #expect(model.databaseRecordReview?.recordSource == .dbLiveRecordsFresh)
        #expect(presentation.review?.recordSource == .dbLiveRecordsFresh)
        #expect(await databaseFetcher.fetchCount == 1)
    }

    // finalGameDetailChecksDatabaseRecordsBeforeOfficialFallback 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func finalGameDetailChecksDatabaseRecordsBeforeOfficialFallback() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let game = try makeBoxscoreDetailGame()
        let databaseReview = try makeSampleDatabaseRecordReview(game: game)
        let boxscoreState = RecordingBoxscoreState(result: .success(GameBoxscoreResponse.empty(gameId: "20260510-DOO-SSG")))
        let officialFallback = RecordingOfficialFallback(result: .success(sampleOfficialFallbackReview()))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: boxscoreState),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game) },
            fetchDatabaseRecordReview: { _ in
                try? await Task.sleep(nanoseconds: 150_000_000)
                return databaseReview
            },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )

        await model.load(for: game)
        await model.waitForBoxscoreLoadForTesting()
        await model.waitForOfficialFallbackLoadForTesting()
        #expect(await officialFallback.fetchCount == 0)

        await model.waitForDatabaseRecordLoadForTesting()
        await model.waitForOfficialFallbackLoadForTesting()

        #expect(model.databaseRecordReview?.recordSource == .dbLiveRecordsFresh)
        #expect(model.officialFallbackReview == nil)
        #expect(await officialFallback.fetchCount == 0)
    }

    // gameDetailScreenModelIgnoresKeyplayerFallbackWhenDatabaseRecordsAreEmpty 메서드는 제한 공식 기록을 기록 탭에 적용하지 않는지 검증합니다.
    @Test func gameDetailScreenModelIgnoresKeyplayerFallbackWhenDatabaseRecordsAreEmpty() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let officialFallback = RecordingOfficialFallback(result: .success(sampleKeyplayerLimitedReview()))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game) },
            fetchDatabaseRecordReview: { _ in nil },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )

        await model.load(for: try makeLiveBoxscoreDetailGame())
        await model.waitForOfficialFallbackLoadForTesting()

        #expect(model.databaseRecordReview == nil)
        #expect(model.officialFallbackReview == nil)
        #expect(await officialFallback.fetchCount == 1)
    }

    // gameDetailScreenModelPostFetchGameSingleDatabaseReviewOverridesEarlyEmptyLimitedRecords 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailScreenModelPostFetchGameSingleDatabaseReviewOverridesEarlyEmptyLimitedRecords() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let localGameID = UUID(uuidString: "86A920BA-5084-56F4-8F60-B1CB508C30E7")!
        let resolvedSupabaseGameID = UUID(uuidString: "1040A2AB-2E5D-4F20-9743-80C39C2C7345")!
        let game = try makeLiveBoxscoreDetailGame(status: .final, id: localGameID, providerGameID: "20260603LTHT0")
        let resolvedGame = try makeLiveBoxscoreDetailGame(status: .final, id: resolvedSupabaseGameID, providerGameID: "20260603LTHT0")
        let lineupReview = sampleLineupLimitedReview()
        let databaseReview = sampleDatabaseRecordReview(game: resolvedGame, batterCount: 18, pitcherCount: 2)
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game, review: lineupReview) },
            fetchDatabaseRecordReview: { _ in nil },
            fetchOfficialRecordFallback: { _ in nil }
        )

        await model.load(for: game)
        #expect(model.databaseRecordReview == nil)

        await model.mergeDatabaseRecordReviewAfterFetchGameSingle(
            inputLocalGameId: localGameID,
            resolvedGame: resolvedGame,
            rawSupabaseGameID: resolvedSupabaseGameID,
            rawSupabaseProviderGameID: "20260603LTHT0",
            rawSupabasePublicGameID: "20260603-LT-HT",
            fetchDatabaseRecordReviewResult: { game in
                GameDetailDatabaseReviewFetchResult(
                    review: databaseReview,
                    inputLocalGameID: game.id,
                    rawSupabaseGameID: resolvedSupabaseGameID,
                    resolvedSupabaseGameID: resolvedSupabaseGameID,
                    providerGameID: "20260603LTHT0",
                    publicGameID: "20260603-LT-HT",
                    publicBatterRawRowCount: 18,
                    publicPitcherRawRowCount: 2,
                    eventRawRowCount: 40
                )
            },
            fetchDatabaseRecordReviewResultByRawSupabaseID: { rawSupabaseGameID, providerGameID, publicGameID in
                GameDetailDatabaseReviewFetchResult(
                    review: databaseReview,
                    inputLocalGameID: localGameID,
                    rawSupabaseGameID: rawSupabaseGameID,
                    resolvedSupabaseGameID: rawSupabaseGameID,
                    providerGameID: providerGameID,
                    publicGameID: publicGameID,
                    publicBatterRawRowCount: 18,
                    publicPitcherRawRowCount: 2,
                    eventRawRowCount: 40
                )
            }
        )

        let presentation = GameDetailPresentation(
            game: resolvedGame,
            payload: model.detail,
            boxscore: nil,
            databaseRecordReview: model.databaseRecordReview,
            officialFallbackReview: model.officialFallbackReview
        )
        #expect(presentation.review?.recordSource == .dbLiveRecordsFresh)
        #expect((presentation.review?.awayBatting.lines.count ?? 0) + (presentation.review?.homeBatting.lines.count ?? 0) == 18)
        #expect((presentation.review?.awayPitching.lines.count ?? 0) + (presentation.review?.homePitching.lines.count ?? 0) == 2)

        await model.load(for: resolvedGame, forceRefresh: true)
        let refreshedPresentation = GameDetailPresentation(
            game: resolvedGame,
            payload: model.detail,
            boxscore: nil,
            databaseRecordReview: model.databaseRecordReview,
            officialFallbackReview: model.officialFallbackReview
        )
        #expect(refreshedPresentation.review?.recordSource == .dbLiveRecordsFresh)
    }

    // gameDetailScreenModelIgnoresLimitedFallbackThroughLiveLoad 메서드는 live 경기에서 제한 공식 기록을 표시하지 않는지 검증합니다.
    @Test func gameDetailScreenModelIgnoresLimitedFallbackThroughLiveLoad() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let localGameID = UUID(uuidString: "86A920BA-5084-56F4-8F60-B1CB508C30E7")!
        let rawSupabaseGameID = UUID(uuidString: "1040A2AB-2E5D-4F20-9743-80C39C2C7345")!
        let game = try makeLiveBoxscoreDetailGame(id: localGameID, providerGameID: "20260603LTHT0")
        let databaseReview = sampleDatabaseRecordReview(game: game, batterCount: 18, pitcherCount: 2)
        let officialFallback = RecordingOfficialFallback(result: .success(sampleKeyplayerLimitedReview()))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game) },
            fetchDatabaseRecordReview: { _ in nil },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )

        await model.mergeDatabaseRecordReviewAfterFetchGameSingle(
            inputLocalGameId: localGameID,
            resolvedGame: game,
            fetchDatabaseRecordReviewResult: { game in
                GameDetailDatabaseReviewFetchResult(
                    review: databaseReview,
                    inputLocalGameID: game.id,
                    rawSupabaseGameID: rawSupabaseGameID,
                    resolvedSupabaseGameID: rawSupabaseGameID,
                    providerGameID: "20260603LTHT0",
                    publicGameID: "20260603-KIA-LOT",
                    publicBatterRawRowCount: 18,
                    publicPitcherRawRowCount: 2,
                    eventRawRowCount: 40
                )
            },
            fetchDatabaseRecordReviewResultByRawSupabaseID: { _, _, _ in nil }
        )
        await model.load(for: game, forceRefresh: true)
        await model.waitForBoxscoreLoadForTesting()
        await model.waitForOfficialFallbackLoadForTesting()

        let presentation = GameDetailPresentation(
            game: game,
            payload: model.detail,
            boxscore: nil,
            databaseRecordReview: model.databaseRecordReview,
            officialFallbackReview: model.officialFallbackReview
        )
        #expect(model.databaseRecordReview == nil)
        #expect(presentation.review == nil)
        #expect(await officialFallback.fetchCount == 1)
    }

    // gameDetailScreenModelPostFetchGameSingleKeepsEmptyWhenDatabaseRowsAreEmpty 메서드는 DB와 full boxscore가 없으면 제한 기록을 표시하지 않는지 검증합니다.
    @Test func gameDetailScreenModelPostFetchGameSingleKeepsEmptyWhenDatabaseRowsAreEmpty() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let game = try makeLiveBoxscoreDetailGame()
        let officialFallback = RecordingOfficialFallback(result: .success(sampleKeyplayerLimitedReview()))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game) },
            fetchDatabaseRecordReview: { _ in nil },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )

        await model.load(for: game)
        await model.waitForOfficialFallbackLoadForTesting()
        await model.mergeDatabaseRecordReviewAfterFetchGameSingle(
            inputLocalGameId: game.id,
            resolvedGame: game,
            fetchDatabaseRecordReviewResult: { game in
                GameDetailDatabaseReviewFetchResult(
                    review: nil,
                    inputLocalGameID: game.id,
                    rawSupabaseGameID: game.id,
                    resolvedSupabaseGameID: game.id,
                    providerGameID: game.providerGameID,
                    publicGameID: game.publicGameID,
                    publicBatterRawRowCount: 0,
                    publicPitcherRawRowCount: 0,
                    eventRawRowCount: 0
                )
            },
            fetchDatabaseRecordReviewResultByRawSupabaseID: { rawSupabaseGameID, providerGameID, publicGameID in
                GameDetailDatabaseReviewFetchResult(
                    review: nil,
                    inputLocalGameID: game.id,
                    rawSupabaseGameID: rawSupabaseGameID,
                    resolvedSupabaseGameID: rawSupabaseGameID,
                    providerGameID: providerGameID,
                    publicGameID: publicGameID,
                    publicBatterRawRowCount: 0,
                    publicPitcherRawRowCount: 0,
                    eventRawRowCount: 0
                )
            }
        )

        let presentation = GameDetailPresentation(
            game: game,
            payload: model.detail,
            boxscore: nil,
            databaseRecordReview: model.databaseRecordReview,
            officialFallbackReview: model.officialFallbackReview
        )
        #expect(presentation.review == nil)
        #expect(model.databaseRecordReview == nil)
    }

    // gameBoxscoreResponseSortsRecordsBySourceOrder 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameBoxscoreResponseSortsRecordsBySourceOrder() throws {
        let response = try JSONDecoder().decode(GameBoxscoreResponse.self, from: sampleGameBoxscoreJSON()).sortedBySourceOrder

        #expect(response.awayBatters.map(\.sourceOrder) == [0, 1])
        #expect(response.awayBatters.map(\.playerName) == ["정수빈", "허경민"])
    }

    // backendGameBoxscoreClientFetchesExpectedEndpoint 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailScreenModelMergesBoxscoreWithoutClearingDetailState 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailScreenModelMergesBoxscoreWithoutClearingDetailState() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let state = RecordingBoxscoreState(result: .success(try JSONDecoder().decode(GameBoxscoreResponse.self, from: sampleGameBoxscoreJSON())))
        let officialFallback = RecordingOfficialFallback(result: .success(sampleOfficialFallbackReview()))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: state),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )
        let game = try makeBoxscoreDetailGame()

        await model.load(for: game)
        await model.waitForBoxscoreLoadForTesting()

        #expect(model.detail?.summary.officialGameID == "20260510SKOB0")
        #expect(model.boxscore?.awayBatters.count == 2)
        #expect(model.boxscore?.awayPitchers.first?.walksOrHitByPitch == 1)
        #expect(await state.fetchCount == 1)
        #expect(await state.requestedGameIDs == ["20260510-DOO-SSG"])
        #expect(await officialFallback.fetchCount == 0)
    }

    // gameDetailScreenModelAcceptsEmptyBoxscoreArrays 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailScreenModelAcceptsEmptyBoxscoreArrays() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let empty = GameBoxscoreResponse.empty(gameId: "20260510-DOO-SSG")
        let state = RecordingBoxscoreState(result: .success(empty))
        let officialFallback = RecordingOfficialFallback(result: .success(sampleOfficialFallbackReview()))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: state),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )

        await model.load(for: try makeBoxscoreDetailGame())
        await model.waitForBoxscoreLoadForTesting()
        await model.waitForOfficialFallbackLoadForTesting()

        #expect(model.boxscore?.awayBatters.isEmpty == true)
        #expect(model.boxscore?.homePitchers.isEmpty == true)
        #expect(model.officialFallbackReview?.awayBatting.lines.first?.name == "공식타자")
        #expect(await officialFallback.fetchCount == 1)
        #expect(model.errorMessage == nil)
    }

    // backendBoxscoreSuccessPreventsOfficialStatsFallback 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func backendBoxscoreSuccessPreventsOfficialStatsFallback() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let state = RecordingBoxscoreState(result: .success(try JSONDecoder().decode(GameBoxscoreResponse.self, from: sampleGameBoxscoreJSON())))
        let officialFallback = RecordingOfficialFallback(result: .success(sampleOfficialFallbackReview()))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: state),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game)
            },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )

        await model.load(for: try makeBoxscoreDetailGame())
        await model.waitForBoxscoreLoadForTesting()
        await model.waitForOfficialFallbackLoadForTesting()

        #expect(model.boxscore?.hasRecords == true)
        #expect(model.officialFallbackReview == nil)
        #expect(await officialFallback.fetchCount == 0)
    }

    // officialFallbackInFlightDedupePreventsDuplicateRequests 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialFallbackInFlightDedupePreventsDuplicateRequests() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let empty = GameBoxscoreResponse.empty(gameId: "20260510-DOO-SSG")
        let firstState = RecordingBoxscoreState(result: .success(empty))
        let secondState = RecordingBoxscoreState(result: .success(empty))
        let officialFallback = RecordingOfficialFallback(
            result: .success(sampleOfficialFallbackReview()),
            delayNanoseconds: 250_000_000
        )
        let firstModel = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: firstState, cacheIdentity: "first"),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game) },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )
        let secondModel = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: secondState, cacheIdentity: "second"),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game) },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )
        let game = try makeBoxscoreDetailGame()

        async let firstLoad: Void = firstModel.load(for: game)
        async let secondLoad: Void = secondModel.load(for: game)
        _ = await (firstLoad, secondLoad)
        await firstModel.waitForBoxscoreLoadForTesting()
        await secondModel.waitForBoxscoreLoadForTesting()
        await firstModel.waitForOfficialFallbackLoadForTesting()
        await secondModel.waitForOfficialFallbackLoadForTesting()

        #expect(await officialFallback.fetchCount == 1)
        #expect(firstModel.officialFallbackReview?.awayBatting.lines.first?.name == "공식타자")
        #expect(secondModel.officialFallbackReview?.awayBatting.lines.first?.name == "공식타자")
    }

    // officialFallbackFailureCooldownPreventsImmediateRetry 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func officialFallbackFailureCooldownPreventsImmediateRetry() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let empty = GameBoxscoreResponse.empty(gameId: "20260510-DOO-SSG")
        let officialFallback = RecordingOfficialFallback(result: .failure(TestRepositoryError.supabaseUnavailable))
        let firstModel = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: RecordingBoxscoreState(result: .success(empty)), cacheIdentity: "first"),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game) },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )
        let secondModel = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: RecordingBoxscoreState(result: .success(empty)), cacheIdentity: "second"),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game) },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )
        let game = try makeBoxscoreDetailGame()

        await firstModel.load(for: game)
        await firstModel.waitForBoxscoreLoadForTesting()
        await firstModel.waitForOfficialFallbackLoadForTesting()
        await secondModel.load(for: game)
        await secondModel.waitForBoxscoreLoadForTesting()
        await secondModel.waitForOfficialFallbackLoadForTesting()

        #expect(await officialFallback.fetchCount == 1)
        #expect(firstModel.officialFallbackReview == nil)
        #expect(secondModel.officialFallbackReview == nil)
    }

    // baseRunnerSnapshotNamesDisplayWithoutOfficialStatsFallback 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func baseRunnerSnapshotNamesDisplayWithoutOfficialStatsFallback() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let officialFallback = RecordingOfficialFallback(result: .success(sampleOfficialFallbackReview()))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game) },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )
        let liveGame = try makeBaseRunnerDisplayGame(
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "홍길동", second: nil, third: nil)
        )

        await model.load(for: liveGame)
        await model.waitForBoxscoreLoadForTesting()
        await model.waitForOfficialFallbackLoadForTesting()

        #expect(await officialFallback.fetchCount == 0)
    }

    // liveGameLoadsOfficialRecordFallbackWithoutBackendBoxscore 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveGameLoadsOfficialRecordFallbackWithoutBackendBoxscore() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let boxscoreState = RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))
        let officialFallback = RecordingOfficialFallback(result: .success(sampleOfficialFallbackReview()))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: boxscoreState),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game) },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )
        let game = try makeLiveBoxscoreDetailGame()

        await model.load(for: game)
        await model.waitForBoxscoreLoadForTesting()
        await model.waitForOfficialFallbackLoadForTesting()

        #expect(await boxscoreState.fetchCount == 1)
        #expect(await officialFallback.fetchCount == 1)
        #expect(model.officialFallbackReview?.awayBatting.lines.first?.name == "공식타자")
    }

    // officialFallbackSkipsWhenOfficialIdentityMissing 메서드는 public/provider 식별자가 없으면 공식 KBO 요청을 하지 않는지 검증합니다.
    @Test func officialFallbackSkipsWhenOfficialIdentityMissing() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let officialFallback = RecordingOfficialFallback(result: .success(sampleOfficialFallbackReview()))
        let baseGame = try makeLiveBoxscoreDetailGame(status: .live)
        let game = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "3초",
            note: nil,
            providerGameID: nil
        )
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))),
            fetchDetail: { _ in nil },
            fetchDatabaseRecordReview: { _ in nil },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )

        await model.load(for: game)
        await model.waitForBoxscoreLoadForTesting()
        await model.waitForDatabaseRecordLoadForTesting()
        await model.waitForOfficialFallbackLoadForTesting()

        #expect(await officialFallback.fetchCount == 0)
        #expect(model.officialFallbackReview == nil)
    }

    // liveGameDetailUsesOfficialRecordsFromDetailPayloadWithoutBackendBoxscore 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveGameDetailUsesOfficialRecordsFromDetailPayloadWithoutBackendBoxscore() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let boxscoreState = RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))
        let review = sampleOfficialFallbackReview()
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: boxscoreState),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game, review: review)
            },
            fetchOfficialRecordFallback: { _ in nil }
        )

        await model.load(for: try makeLiveBoxscoreDetailGame())
        await model.waitForOfficialFallbackLoadForTesting()

        await model.waitForBoxscoreLoadForTesting()

        #expect(await boxscoreState.fetchCount == 1)
        #expect(model.detail?.review?.hasDisplayableRecords == true)
        #expect(model.officialFallbackReview == nil)
    }

    // gameDetailPresentationShowsLiveDetailRecordsWhenPresent 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailPresentationShowsLiveDetailRecordsWhenPresent() async throws {
        let game = try makeLiveBoxscoreDetailGame()
        let review = sampleOfficialFallbackReview()
        let presentation = GameDetailPresentation(
            game: game,
            payload: sampleGameCenterDetailPayload(game: game, review: review),
            boxscore: nil
        )

        #expect(presentation.review?.hasDisplayableRecords == true)
        #expect(presentation.review?.awayBatting.lines.first?.name == "공식타자")
    }

    @Test func gameDetailPresentationIgnoresLimitedLiveRecordSources() throws {
        let game = try makeLiveBoxscoreDetailGame()
        let presentation = GameDetailPresentation(
            game: game,
            payload: sampleGameCenterDetailPayload(game: game, review: sampleLineupLimitedReview()),
            boxscore: nil,
            databaseRecordReview: nil,
            officialFallbackReview: sampleKeyplayerLimitedReview()
        )

        #expect(presentation.review == nil)
    }

    @Test func liveGameIgnoresStaleDatabaseRecords() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let game = try makeLiveBoxscoreDetailGame()
        let staleReview = sampleDatabaseRecordReview(game: game, batterCount: 18, pitcherCount: 2)
            .withRecordSource(.staleDbRecordsIgnored)
        let databaseFetcher = RecordingDatabaseReviewFetcher(review: staleReview)
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: RecordingBoxscoreState(result: .success(GameBoxscoreResponse.empty(gameId: game.publicGameID ?? "")))),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game, review: sampleLineupLimitedReview()) },
            fetchDatabaseRecordReview: { game in await databaseFetcher.fetch(game: game) },
            fetchOfficialRecordFallback: { _ in nil }
        )

        await model.load(for: game, forceRefresh: true)
        await model.waitForDatabaseRecordLoadForTesting()
        await model.waitForBoxscoreLoadForTesting()

        let presentation = GameDetailPresentation(
            game: game,
            payload: model.detail,
            boxscore: model.boxscore,
            databaseRecordReview: model.databaseRecordReview,
            officialFallbackReview: model.officialFallbackReview
        )
        #expect(await databaseFetcher.fetchCount == 1)
        #expect(model.databaseRecordReview == nil)
        #expect(presentation.review == nil)
    }

    @Test func liveGameLoadsFreshDatabaseRecordsBeforeBackendBoxscoreRecords() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let game = try makeLiveBoxscoreDetailGame()
        let boxscoreState = RecordingBoxscoreState(result: .success(sampleOfficialPriorityBoxscoreResponse()))
        let databaseReview = sampleDatabaseRecordReview(game: game, batterCount: 2, pitcherCount: 2)
        let databaseFetcher = RecordingDatabaseReviewFetcher(review: databaseReview)
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: boxscoreState),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game, review: sampleLineupLimitedReview()) },
            fetchDatabaseRecordReview: { game in await databaseFetcher.fetch(game: game) },
            fetchOfficialRecordFallback: { _ in nil }
        )

        await model.load(for: game)
        await model.waitForBoxscoreLoadForTesting()
        await model.waitForDatabaseRecordLoadForTesting()

        let presentation = GameDetailPresentation(
            game: game,
            payload: model.detail,
            boxscore: model.boxscore,
            databaseRecordReview: model.databaseRecordReview,
            officialFallbackReview: model.officialFallbackReview
        )

        #expect(await boxscoreState.fetchCount == 1)
        #expect(await databaseFetcher.fetchCount == 1)
        #expect(model.databaseRecordReview?.recordSource == .dbLiveRecordsFresh)
        #expect(presentation.review?.recordSource == .dbLiveRecordsFresh)
        #expect(presentation.review?.awayBatting.lines.first?.name == "원정타자1")
        #expect(presentation.review?.awayBatting.lines.first?.atBats == "1")
    }

    @Test func liveGamePrefersNewerBoxscoreOverOlderFreshDatabaseRecords() throws {
        let game = try makeLiveBoxscoreDetailGame()
        let databaseReview = sampleDatabaseRecordReview(game: game, batterCount: 2, pitcherCount: 1)
            .withRecordSource(
                .dbLiveRecordsFresh,
                recordUpdatedAt: isoDate("2026-05-10T16:10:00+09:00")
            )
        let presentation = GameDetailPresentation(
            game: game,
            payload: nil,
            boxscore: sampleOfficialPriorityBoxscoreResponse(),
            databaseRecordReview: databaseReview,
            officialFallbackReview: nil
        )

        #expect(presentation.review?.recordSource == .fullBoxscore)
        #expect(presentation.review?.awayBatting.lines.first?.name == "김공식")
    }

    @Test func liveDatabaseRecordRefreshQueuesLatestRequestWhilePreviousRequestIsInFlight() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let game = try makeLiveBoxscoreDetailGame()
        func review(playerName: String, atBats: String) -> GameCenterReview {
            GameCenterReview(
                summaryItems: [],
                awayBatting: GameCenterBattingSection(
                    lines: [
                        GameCenterBattingLine(
                            battingOrder: "1",
                            position: "중",
                            name: playerName,
                            atBats: atBats,
                            runs: "0",
                            hits: "1",
                            runsBattedIn: "0",
                            homeRuns: "0",
                            walks: "0",
                            strikeouts: "0",
                            average: nil
                        )
                    ],
                    totals: nil
                ),
                homeBatting: GameCenterBattingSection(lines: [], totals: nil),
                awayPitching: GameCenterPitchingSection(lines: []),
                homePitching: GameCenterPitchingSection(lines: []),
                recordSource: .dbLiveRecordsFresh
            )
        }
        let state = SequencedDatabaseReviewState(
            reviews: [
                review(playerName: "과거타자", atBats: "1"),
                review(playerName: "최신타자", atBats: "3")
            ],
            delays: [150_000_000, 0]
        )
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(
                state: RecordingBoxscoreState(result: .success(.empty(gameId: game.publicGameID ?? "")))
            ),
            fetchDetail: { _ in nil },
            fetchDatabaseRecordReview: { _ in await state.fetch() },
            fetchOfficialRecordFallback: { _ in nil }
        )

        await model.load(for: game, forceRefresh: true)
        await model.load(for: game, forceRefresh: true)
        await model.waitForDatabaseRecordLoadForTesting()

        #expect(await state.fetchCount == 2)
        #expect(model.databaseRecordReview?.awayBatting.lines.first?.name == "최신타자")
        #expect(model.databaseRecordReview?.awayBatting.lines.first?.atBats == "3")
    }

    @Test func officialBoxscoreRecordPreventsLineupOnlyStatsOverwrite() throws {
        let game = try makeLiveBoxscoreDetailGame()
        let lineupOnlyReview = GameCenterReview(
            summaryItems: [],
            awayBatting: GameCenterBattingSection(
                lines: [
                    GameCenterBattingLine(
                        battingOrder: "1",
                        position: "중",
                        name: "김공식",
                        atBats: nil,
                        runs: nil,
                        hits: nil,
                        runsBattedIn: nil,
                        homeRuns: nil,
                        walks: nil,
                        strikeouts: nil,
                        average: nil
                    )
                ],
                totals: nil
            ),
            homeBatting: GameCenterBattingSection(lines: [], totals: nil),
            awayPitching: GameCenterPitchingSection(lines: []),
            homePitching: GameCenterPitchingSection(lines: []),
            recordSource: .lineupLimited
        )
        let presentation = GameDetailPresentation(
            game: game,
            payload: sampleGameCenterDetailPayload(game: game, review: lineupOnlyReview),
            boxscore: sampleOfficialPriorityBoxscoreResponse(),
            databaseRecordReview: sampleDatabaseRecordReview(game: game, batterCount: 2, pitcherCount: 1),
            officialFallbackReview: nil
        )
        let firstLine = try #require(presentation.review?.awayBatting.lines.first)

        #expect(presentation.review?.recordSource == .fullBoxscore)
        #expect(firstLine.name == "김공식")
        #expect(firstLine.atBats == "25")
        #expect(firstLine.runs == "2")
        #expect(firstLine.hits == "6")
        #expect(firstLine.runsBattedIn == "2")
    }

    @Test func liveBatterTotalsDeriveFromDisplayedOfficialRows() throws {
        let game = try makeLiveBoxscoreDetailGame()
        let presentation = GameDetailPresentation(
            game: game,
            payload: sampleGameCenterDetailPayload(game: game, review: sampleLineupLimitedReview()),
            boxscore: sampleOfficialPriorityBoxscoreResponse(),
            databaseRecordReview: sampleDatabaseRecordReview(game: game, batterCount: 2, pitcherCount: 1),
            officialFallbackReview: nil
        )
        let totals = try #require(presentation.review?.awayBatting.displayedRecordTotals)

        #expect(totals.atBats == "28")
        #expect(totals.runs == "2")
        #expect(totals.hits == "7")
        #expect(totals.runsBattedIn == "2")
    }

    @Test func pitcherSnapshotDoesNotOverwriteOfficialPitcherRecord() throws {
        let game = try makeLiveBoxscoreDetailGame(currentPitcherName: "스냅샷투수")
        let snapshotPitcherFallback = GameCenterReview(
            summaryItems: [],
            awayBatting: GameCenterBattingSection(lines: [], totals: nil),
            homeBatting: GameCenterBattingSection(lines: [], totals: nil),
            awayPitching: GameCenterPitchingSection(
                lines: [
                    GameCenterPitchingLine(
                        name: "스냅샷투수",
                        role: "현재",
                        result: nil,
                        innings: "0 1/3",
                        pitches: nil,
                        hitsAllowed: nil,
                        walksAllowed: nil,
                        hitBatters: nil,
                        strikeouts: nil,
                        homeRunsAllowed: nil,
                        runsAllowed: nil,
                        earnedRuns: nil,
                        earnedRunAverage: nil
                    )
                ]
            ),
            homePitching: GameCenterPitchingSection(lines: []),
            recordSource: .lineupLimited
        )
        let presentation = GameDetailPresentation(
            game: game,
            payload: sampleGameCenterDetailPayload(game: game),
            boxscore: sampleOfficialPriorityBoxscoreResponse(),
            databaseRecordReview: nil,
            officialFallbackReview: snapshotPitcherFallback
        )

        #expect(presentation.review?.awayPitching.lines.map(\.name) == ["비슬리", "이이무라"])
        #expect(presentation.review?.awayPitching.lines.first?.innings == "6")
        #expect(presentation.review?.awayPitching.lines.dropFirst().first?.innings == "1")
    }

    @Test func substitutionPlayersFromOfficialBoxscoreRemainVisible() throws {
        let game = try makeLiveBoxscoreDetailGame()
        let presentation = GameDetailPresentation(
            game: game,
            payload: sampleGameCenterDetailPayload(game: game, review: sampleLineupLimitedReview()),
            boxscore: sampleOfficialPriorityBoxscoreResponse(),
            databaseRecordReview: nil,
            officialFallbackReview: nil
        )

        #expect(presentation.review?.awayBatting.lines.map(\.name).contains("대타자") == true)
        #expect(presentation.review?.awayBatting.lines.map(\.name).contains("대주자") == true)
    }

    @Test func liveBoxscoreRefreshReplacesPreviousBatterAndPitcherRows() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let game = try makeLiveBoxscoreDetailGame()
        let firstBoxscore = liveReplacementBoxscore(
            awayBatters: [
                ("선발타자", 0, 1, "중", 2),
                ("교체전타자", 1, 2, "一", 1)
            ],
            awayPitchers: [
                ("선발투수", 0, 1, "3"),
                ("교체전투수", 1, 2, "1")
            ]
        )
        let latestBoxscore = liveReplacementBoxscore(
            awayBatters: [
                ("선발타자", 0, 1, "중", 3),
                ("대타최신", 1, nil, "타", 1),
                ("대주자최신", 2, nil, "주", 0)
            ],
            awayPitchers: [
                ("선발투수", 0, 1, "3"),
                ("새투수", 1, 2, "1 1/3")
            ]
        )
        let sequenceState = SequencedBoxscoreState(results: [
            .success(firstBoxscore),
            .success(latestBoxscore)
        ])
        let model = GameDetailScreenModel(
            boxscoreClient: SequencedBoxscoreClient(state: sequenceState),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game, review: sampleLineupLimitedReview()) },
            fetchDatabaseRecordReview: { _ in nil },
            fetchOfficialRecordFallback: { _ in nil }
        )

        await model.load(for: game, forceRefresh: true)
        await model.waitForBoxscoreLoadForTesting()
        await model.load(for: game, forceRefresh: true)
        await model.waitForBoxscoreLoadForTesting()

        let presentation = GameDetailPresentation(
            game: game,
            payload: model.detail,
            boxscore: model.boxscore,
            databaseRecordReview: model.databaseRecordReview,
            officialFallbackReview: model.officialFallbackReview
        )

        #expect(await sequenceState.fetchCount == 2)
        #expect(model.databaseRecordReview == nil)
        #expect(presentation.review?.awayBatting.lines.map(\.name) == ["선발타자", "대타최신", "대주자최신"])
        #expect(presentation.review?.awayPitching.lines.map(\.name) == ["선발투수", "새투수"])
        #expect(presentation.review?.awayBatting.lines.map(\.name).contains("교체전타자") == false)
        #expect(presentation.review?.awayPitching.lines.map(\.name).contains("교체전투수") == false)
    }

    @Test func liveBoxscoreRefreshQueuesLatestRequestWhilePreviousRequestIsInFlight() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let game = try makeLiveBoxscoreDetailGame()
        let older = liveReplacementBoxscore(
            awayBatters: [("과거타자", 0, 1, "중", 1)],
            awayPitchers: [("과거투수", 0, 1, "1")]
        )
        let latest = liveReplacementBoxscore(
            awayBatters: [("최신타자", 0, 1, "중", 3)],
            awayPitchers: [("최신투수", 0, 1, "2")]
        )
        let state = SequencedBoxscoreState(
            results: [.success(older), .success(latest)],
            delays: [150_000_000, 0]
        )
        let model = GameDetailScreenModel(
            boxscoreClient: SequencedBoxscoreClient(state: state),
            fetchDetail: { _ in nil },
            fetchDatabaseRecordReview: { _ in nil },
            fetchOfficialRecordFallback: { _ in nil }
        )

        await model.load(for: game, forceRefresh: true)
        await model.load(for: game, forceRefresh: true)
        await model.waitForBoxscoreLoadForTesting()

        #expect(await state.fetchCount == 2)
        #expect(model.boxscore?.awayBatters.first?.playerName == "최신타자")
        #expect(model.boxscore?.awayPitchers.first?.playerName == "최신투수")
    }

    @Test func liveEmptyBoxscoreDoesNotOverwritePreviousFullBoxscoreRecords() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let game = try makeLiveBoxscoreDetailGame()
        let firstBoxscore = liveReplacementBoxscore(
            awayBatters: [("선발타자", 0, 1, "중", 2)],
            awayPitchers: [("선발투수", 0, 1, "3")]
        )
        let sequenceState = SequencedBoxscoreState(results: [
            .success(firstBoxscore),
            .success(GameBoxscoreResponse.empty(gameId: game.publicGameID ?? ""))
        ])
        let model = GameDetailScreenModel(
            boxscoreClient: SequencedBoxscoreClient(state: sequenceState),
            fetchDetail: { game in sampleGameCenterDetailPayload(game: game, review: sampleLineupLimitedReview()) },
            fetchDatabaseRecordReview: { _ in nil },
            fetchOfficialRecordFallback: { _ in nil }
        )

        await model.load(for: game, forceRefresh: true)
        await model.waitForBoxscoreLoadForTesting()
        await model.load(for: game, forceRefresh: true)
        await model.waitForBoxscoreLoadForTesting()

        let presentation = GameDetailPresentation(
            game: game,
            payload: model.detail,
            boxscore: model.boxscore,
            databaseRecordReview: model.databaseRecordReview,
            officialFallbackReview: model.officialFallbackReview
        )
        #expect(await sequenceState.fetchCount == 2)
        #expect(presentation.review?.recordSource == .fullBoxscore)
        #expect(presentation.review?.awayBatting.lines.map(\.name) == ["선발타자"])
        #expect(presentation.review?.awayPitching.lines.map(\.name) == ["선발투수"])
    }

    // gameDetailPresentationPrefersLatestSnapshotCountOverOfficialPayload 메서드는 latestSnapshot 카운트가 공식 상세 캐시를 이기는지 검증합니다.
    @Test func gameDetailPresentationPrefersLatestSnapshotCountOverOfficialPayload() throws {
        let snapshotGame = try makeLiveBoxscoreDetailGame(
            status: .live,
            id: UUID(uuidString: "24242424-2424-2424-2424-242424242401")!
        )
        let staleOfficialGame = makeGameDetail(
            id: snapshotGame.id,
            scheduledStart: snapshotGame.scheduledStart,
            venue: snapshotGame.venue,
            awayTeam: snapshotGame.awayTeam,
            homeTeam: snapshotGame.homeTeam,
            awayScore: snapshotGame.awayScore,
            homeScore: snapshotGame.homeScore,
            status: .live,
            inningText: snapshotGame.inningText,
            note: snapshotGame.note,
            providerGameID: snapshotGame.providerGameID,
            bases: snapshotGame.bases,
            balls: 0,
            strikes: 0,
            outs: 0
        )

        let presentation = GameDetailPresentation(
            game: snapshotGame,
            payload: sampleGameCenterDetailPayload(game: staleOfficialGame),
            boxscore: nil
        )

        #expect(presentation.balls == snapshotGame.balls)
        #expect(presentation.strikes == snapshotGame.strikes)
        #expect(presentation.outs == snapshotGame.outs)
    }

    // gameDetailPresentationPrefersLatestSnapshotBasesAndOfficialRunnerNames 메서드는 latestSnapshot 점유와 official 주자 이름을 병합하는지 검증합니다.
    @Test func gameDetailPresentationPrefersLatestSnapshotBasesAndOfficialRunnerNames() throws {
        let baseGame = try makeLiveBoxscoreDetailGame(
            status: .live,
            id: UUID(uuidString: "24242424-2424-2424-2424-242424242402")!
        )
        let snapshotGame = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "Bottom 3",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            bases: RunnerState(first: true, second: false, third: true),
            baseRunners: GameBaseRunners(first: "윤준호", second: nil, third: nil),
            balls: baseGame.balls,
            strikes: baseGame.strikes,
            outs: baseGame.outs
        )
        let officialPayload = sampleGameCenterDetailPayload(
            game: makeGameDetail(
                id: baseGame.id,
                scheduledStart: baseGame.scheduledStart,
                venue: baseGame.venue,
                awayTeam: baseGame.awayTeam,
                homeTeam: baseGame.homeTeam,
                awayScore: baseGame.awayScore,
                homeScore: baseGame.homeScore,
                status: .live,
                inningText: "Bottom 3",
                bases: RunnerState(first: false, second: true, third: false)
            ),
            baseRunners: GameCenterBaseRunners(first: "공식1루", second: "공식2루", third: "공식3루")
        )
        var resolver = BaseRunnerDisplayResolver()
        let display = resolver.resolve(gameIdentity: snapshotGame.stableDetailIdentity, game: snapshotGame)

        let presentation = GameDetailPresentation(
            game: snapshotGame,
            payload: officialPayload,
            boxscore: nil,
            baseRunnerDisplay: display
        )

        #expect(presentation.bases == RunnerState(first: true, second: false, third: true))
        #expect(presentation.baseRunners?.first == "윤준호")
        #expect(presentation.displayBaseRunners.map(\.base) == ["1B", "3B"])
        #expect(presentation.displayBaseRunners.first?.name == "윤준호")
        #expect(presentation.displayBaseRunners.last?.name == "공식3루")
    }

    // gameDetailPresentationShowsOccupiedFirstBaseWhenSnapshotRunnerNameMissing 메서드는 runner_on_first만 true여도 1루 점유가 표시되는지 검증합니다.
    @Test func gameDetailPresentationShowsOccupiedFirstBaseWhenSnapshotRunnerNameMissing() throws {
        let baseGame = try makeLiveBoxscoreDetailGame(status: .live)
        let snapshotGame = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "Top 4",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )

        let presentation = GameDetailPresentation(game: snapshotGame, payload: nil, boxscore: nil)

        #expect(presentation.bases?.first == true)
        #expect(presentation.displayBaseRunners.map(\.base) == ["1B"])
        #expect(presentation.displayBaseRunners.first?.name == "점유")
    }

    // gameDetailPresentationShowsOccupiedFirstAndSecondBases 메서드는 runner_on_first/second가 true이면 이름 없이도 1루/2루 점유를 표시하는지 검증합니다.
    @Test func gameDetailPresentationShowsOccupiedFirstAndSecondBases() throws {
        let baseGame = try makeLiveBoxscoreDetailGame(status: .live)
        let snapshotGame = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "Top 4",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            bases: RunnerState(first: true, second: true, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )

        let presentation = GameDetailPresentation(game: snapshotGame, payload: nil, boxscore: nil)

        #expect(presentation.bases == RunnerState(first: true, second: true, third: false))
        #expect(presentation.displayBaseRunners.map(\.base) == ["1B", "2B"])
        #expect(presentation.displayBaseRunners.map(\.name) == ["점유", "점유"])
    }

    // gameDetailPresentationPrefersLatestSnapshotBasesOverCachedEmptyBases 메서드는 cached display가 비어 있어도 latestSnapshot bases를 우선하는지 검증합니다.
    @Test func gameDetailPresentationPrefersLatestSnapshotBasesOverCachedEmptyBases() throws {
        let baseGame = try makeLiveBoxscoreDetailGame(status: .live)
        let snapshotGame = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "Top 4",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            bases: RunnerState(first: true, second: true, third: false),
            baseRunners: GameBaseRunners(first: "한동희", second: "레이예스", third: nil)
        )

        let presentation = GameDetailPresentation(
            game: snapshotGame,
            payload: nil,
            boxscore: nil,
            baseRunnerDisplay: .empty
        )

        #expect(presentation.bases == RunnerState(first: true, second: true, third: false))
        #expect(presentation.displayBaseRunners.map(\.name) == ["한동희", "레이예스"])
    }

    // gameDetailPresentationKeepsLatestSnapshotBasesWithDatabaseRecordReview 메서드는 DB record review 병합 후에도 latestSnapshot bases가 유지되는지 검증합니다.
    @Test func gameDetailPresentationKeepsLatestSnapshotBasesWithDatabaseRecordReview() throws {
        let baseGame = try makeLiveBoxscoreDetailGame(status: .live)
        let snapshotGame = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "Top 4",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            bases: RunnerState(first: true, second: true, third: false),
            baseRunners: GameBaseRunners(first: "한동희", second: "레이예스", third: nil)
        )
        let staleOfficialPayload = sampleGameCenterDetailPayload(
            game: makeGameDetail(
                id: baseGame.id,
                scheduledStart: baseGame.scheduledStart,
                venue: baseGame.venue,
                awayTeam: baseGame.awayTeam,
                homeTeam: baseGame.homeTeam,
                awayScore: baseGame.awayScore,
                homeScore: baseGame.homeScore,
                status: .live,
                inningText: "Top 4",
                bases: .empty
            )
        )

        let presentation = GameDetailPresentation(
            game: snapshotGame,
            payload: staleOfficialPayload,
            boxscore: nil,
            databaseRecordReview: sampleDatabaseRecordReview(game: snapshotGame, batterCount: 18, pitcherCount: 2)
        )

        #expect(presentation.bases == RunnerState(first: true, second: true, third: false))
        #expect(presentation.displayBaseRunners.map(\.name) == ["한동희", "레이예스"])
    }

    // gameDetailPresentationReplacesStaleSecondRunnerNameFromNextSnapshot 메서드는 이전 2루 주자 이름을 다음 snapshot 이름으로 교체하는지 검증합니다.
    @Test func gameDetailPresentationReplacesStaleSecondRunnerNameFromNextSnapshot() throws {
        let baseGame = try makeLiveBoxscoreDetailGame(status: .live)
        let nextSnapshot = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "Top 4",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            bases: RunnerState(first: false, second: true, third: false),
            baseRunners: GameBaseRunners(first: nil, second: "양의지", third: nil),
            balls: 1,
            strikes: 1,
            outs: 0,
            currentPitcherName: "나균안",
            currentBatterName: "안재석"
        )
        let staleDisplay = BaseRunnerDisplayResolution(
            runners: GameBaseRunners(first: nil, second: "정수빈", third: nil),
            source: "carryForward"
        )

        let presentation = GameDetailPresentation(
            game: nextSnapshot,
            payload: nil,
            boxscore: nil,
            baseRunnerDisplay: staleDisplay
        )

        #expect(presentation.liveSituation.secondRunnerName == "양의지")
        #expect(presentation.displayBaseRunners == [BaseRunnerDisplayItem(base: "2B", name: "양의지")])
    }

    // gameDetailPresentationClearsSecondRunnerWhenSnapshotBaseEmpty 메서드는 다음 snapshot에서 2루가 비면 이전 이름을 완전히 제거하는지 검증합니다.
    @Test func gameDetailPresentationClearsSecondRunnerWhenSnapshotBaseEmpty() throws {
        let baseGame = try makeLiveBoxscoreDetailGame(status: .live)
        let nextSnapshot = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "Top 4",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            bases: RunnerState(first: false, second: false, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil),
            balls: 1,
            strikes: 1,
            outs: 1,
            currentPitcherName: "나균안",
            currentBatterName: "안재석"
        )
        let staleDisplay = BaseRunnerDisplayResolution(
            runners: GameBaseRunners(first: nil, second: "정수빈", third: nil),
            source: "carryForward"
        )

        let presentation = GameDetailPresentation(
            game: nextSnapshot,
            payload: nil,
            boxscore: nil,
            baseRunnerDisplay: staleDisplay
        )

        #expect(presentation.liveSituation.runnerOnSecond == false)
        #expect(presentation.liveSituation.secondRunnerName == nil)
        #expect(presentation.displayBaseRunners.isEmpty)
    }

    // gameDetailPresentationDoesNotCarryPreviousNameWhenSnapshotRunnerNameNil 메서드는 2루 점유만 있고 이름이 없을 때 이전 이름을 유지하지 않는지 검증합니다.
    @Test func gameDetailPresentationDoesNotCarryPreviousNameWhenSnapshotRunnerNameNil() throws {
        let baseGame = try makeLiveBoxscoreDetailGame(status: .live)
        let nextSnapshot = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "Top 4",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            bases: RunnerState(first: false, second: true, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil),
            balls: 1,
            strikes: 1,
            outs: 2,
            currentPitcherName: "나균안",
            currentBatterName: "안재석"
        )
        let staleDisplay = BaseRunnerDisplayResolution(
            runners: GameBaseRunners(first: nil, second: "정수빈", third: nil),
            source: "carryForward"
        )

        let presentation = GameDetailPresentation(
            game: nextSnapshot,
            payload: nil,
            boxscore: nil,
            baseRunnerDisplay: staleDisplay
        )

        #expect(presentation.liveSituation.runnerOnSecond)
        #expect(presentation.liveSituation.secondRunnerName == nil)
        #expect(presentation.displayBaseRunners == [BaseRunnerDisplayItem(base: "2B", name: "점유")])
    }

    // gameDetailPresentationFillsMissingSnapshotRunnerNameFromOfficialPayload 메서드는 latestSnapshot 점유는 유지하면서 누락된 주자 이름만 official 값으로 보완하는지 검증합니다.
    @Test func gameDetailPresentationFillsMissingSnapshotRunnerNameFromOfficialPayload() throws {
        let baseGame = try makeLiveBoxscoreDetailGame(status: .live)
        let snapshot = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "Top 4",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            bases: RunnerState(first: false, second: true, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil),
            balls: 2,
            strikes: 1,
            outs: 2
        )
        let officialPayload = sampleGameCenterDetailPayload(
            game: makeGameDetail(
                id: baseGame.id,
                scheduledStart: baseGame.scheduledStart,
                venue: baseGame.venue,
                awayTeam: baseGame.awayTeam,
                homeTeam: baseGame.homeTeam,
                awayScore: baseGame.awayScore,
                homeScore: baseGame.homeScore,
                status: .live,
                inningText: "Top 4",
                bases: RunnerState(first: true, second: true, third: true),
                balls: 0,
                strikes: 0,
                outs: 0
            ),
            baseRunners: GameCenterBaseRunners(first: "공식1루", second: "정수빈", third: "공식3루")
        )

        let presentation = GameDetailPresentation(game: snapshot, payload: officialPayload, boxscore: nil)

        #expect(presentation.bases == RunnerState(first: false, second: true, third: false))
        #expect(presentation.balls == 2)
        #expect(presentation.strikes == 1)
        #expect(presentation.outs == 2)
        #expect(presentation.liveSituation.secondRunnerName == "정수빈")
        #expect(presentation.displayBaseRunners == [BaseRunnerDisplayItem(base: "2B", name: "정수빈")])
        #expect(presentation.baseRunnerDisplay.source == "latestSnapshotWithOfficialNames")
    }

    // gameDetailPresentationHidesOfficialRunnerNameWhenSnapshotBaseEmpty 메서드는 snapshot 기준 빈 베이스에는 official 이름을 표시하지 않는지 검증합니다.
    @Test func gameDetailPresentationHidesOfficialRunnerNameWhenSnapshotBaseEmpty() throws {
        let baseGame = try makeLiveBoxscoreDetailGame(status: .live)
        let snapshot = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "Top 4",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            bases: RunnerState(first: false, second: false, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil)
        )
        let officialPayload = sampleGameCenterDetailPayload(
            game: snapshot,
            baseRunners: GameCenterBaseRunners(first: nil, second: "정수빈", third: nil)
        )

        let presentation = GameDetailPresentation(game: snapshot, payload: officialPayload, boxscore: nil)

        #expect(presentation.liveSituation.runnerOnSecond == false)
        #expect(presentation.liveSituation.secondRunnerName == nil)
        #expect(presentation.displayBaseRunners.isEmpty)
    }

    // gameDetailPresentationKeepsCorrectedSnapshotRunnerNameOverStaleOfficialPayload 메서드는 보정된 latestSnapshot 주자 이름을 stale official 값으로 덮지 않는지 검증합니다.
    @Test func gameDetailPresentationKeepsCorrectedSnapshotRunnerNameOverStaleOfficialPayload() throws {
        let baseGame = try makeLiveBoxscoreDetailGame(status: .live)
        let nextSnapshot = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .live,
            inningText: "Top 4",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "노진혁", second: nil, third: nil),
            balls: 0,
            strikes: 0,
            outs: 0,
            currentPitcherName: "나균안",
            currentBatterName: "황성빈"
        )
        let officialPayload = sampleGameCenterDetailPayload(
            game: nextSnapshot,
            baseRunners: GameCenterBaseRunners(first: "손호영", second: nil, third: nil)
        )

        let presentation = GameDetailPresentation(
            game: nextSnapshot,
            payload: officialPayload,
            boxscore: nil,
            baseRunnerDisplay: BaseRunnerDisplayResolution(
                runners: GameBaseRunners(first: "노진혁", second: nil, third: nil),
                source: "carryForward"
            )
        )

        #expect(presentation.liveSituation.firstRunnerName == "노진혁")
        #expect(presentation.displayBaseRunners == [BaseRunnerDisplayItem(base: "1B", name: "노진혁")])
        #expect(presentation.baseRunnerDisplay.source == "latestSnapshotOnly")
    }

    // invalidLiveOfficialDetailKeepsRecordStateEmptyWithoutBackendBoxscore 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func invalidLiveOfficialDetailKeepsRecordStateEmptyWithoutBackendBoxscore() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let boxscoreState = RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: boxscoreState),
            fetchDetail: { _ in
                throw OfficialKBOGameCenterError.invalidResponse(
                    OfficialKBOResponseDiagnostic(
                        requestURL: "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList",
                        providerGameID: "20260510SKOB0",
                        officialProviderGameID: "20260510SKOB0",
                        publicGameID: "20260510-DOO-SSG",
                        officialGameID: "20260510SKOB0",
                        httpStatus: 500,
                        contentType: "text/html",
                        bodyPreview: "<html>error</html>",
                        parseFailureReason: "HTTP status 500"
                    )
                )
            },
            fetchOfficialRecordFallback: { _ in nil }
        )

        await model.load(for: try makeLiveBoxscoreDetailGame())
        await model.waitForBoxscoreLoadForTesting()
        await model.waitForOfficialFallbackLoadForTesting()

        #expect(await boxscoreState.fetchCount == 1)
        #expect(model.detail == nil)
        #expect(model.officialFallbackReview == nil)
        #expect(model.errorMessage != nil)
    }

    // liveLineScoreDoesNotRequireBackendBoxscore 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func liveLineScoreDoesNotRequireBackendBoxscore() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let boxscoreState = RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))
        let lineScore = sampleGameCenterLineScore()
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: boxscoreState),
            fetchDetail: { game in
                sampleGameCenterDetailPayload(game: game, lineScore: lineScore)
            },
            fetchOfficialRecordFallback: { _ in nil }
        )

        await model.load(for: try makeLiveBoxscoreDetailGame())
        await model.waitForBoxscoreLoadForTesting()

        #expect(await boxscoreState.fetchCount == 1)
        #expect(model.detail?.lineScore?.awayTotals.runs == "3")
        #expect(model.cachedLineScore?.homeTotals.walks == "2")
        #expect(model.boxscore == nil)
    }

    // repeatedLiveDetailLoadsDedupeConcurrentOfficialFetch 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func repeatedLiveDetailLoadsDedupeConcurrentOfficialFetch() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let fetcher = RecordingDetailPayloadFetcher(
            payload: sampleGameCenterDetailPayload(game: try makeLiveBoxscoreDetailGame(), lineScore: sampleGameCenterLineScore()),
            delayNanoseconds: 250_000_000
        )
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(state: RecordingBoxscoreState(result: .failure(TestRepositoryError.supabaseUnavailable))),
            fetchDetail: { game in try await fetcher.fetch(game: game) },
            fetchOfficialRecordFallback: { _ in nil }
        )
        let game = try makeLiveBoxscoreDetailGame()

        async let firstLoad: Void = model.load(for: game, forceRefresh: true)
        async let secondLoad: Void = model.load(for: game, forceRefresh: true)
        _ = await (firstLoad, secondLoad)

        #expect(await fetcher.fetchCount == 1)
        #expect(model.cachedLineScore?.awayTotals.hits == "7")
    }

    // gameDetailViewModelLiveRefreshTaskIDOnlyActivatesForPollingEligibleGames 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func gameDetailViewModelLiveRefreshTaskIDOnlyActivatesForPollingEligibleGames() throws {
        let live = GameDetailViewModel(gameIdentity: "live", initialGame: try makeLiveBoxscoreDetailGame(status: .live))
        let rainDelay = GameDetailViewModel(gameIdentity: "rain", initialGame: try makeLiveBoxscoreDetailGame(status: .rainDelay))
        let final = GameDetailViewModel(gameIdentity: "final", initialGame: try makeLiveBoxscoreDetailGame(status: .final))
        let cancelled = GameDetailViewModel(gameIdentity: "cancelled", initialGame: try makeLiveBoxscoreDetailGame(status: .cancelled))

        #expect(live.shouldAutoRefreshLiveGame)
        #expect(live.liveRefreshTaskID.hasPrefix("live:"))
        #expect(rainDelay.shouldAutoRefreshLiveGame)
        #expect(rainDelay.liveRefreshTaskID.hasPrefix("live:"))
        #expect(final.shouldAutoRefreshLiveGame == false)
        #expect(final.liveRefreshTaskID.hasPrefix("idle:"))
        #expect(cancelled.shouldAutoRefreshLiveGame == false)
        #expect(cancelled.liveRefreshTaskID.hasPrefix("idle:"))
    }

    // liveGameDetailEntryStartsPolling 메서드는 상세 화면 진입 시 live 경기 polling이 시작되는지 검증합니다.
    @Test func liveGameDetailEntryStartsPolling() async throws {
        let game = try makeLiveBoxscoreDetailGame(status: .live)
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)

        #expect(model.isGameDetailPollingActiveForTesting)
        #expect(model.activeGameDetailPollingIdentityForTesting == game.stableDetailIdentity)
        model.stopLiveGameDetailPolling()
    }

    // finalGameDetailEntryDoesNotStartPolling 메서드는 종료 경기에서 이닝 상태가 남아도 상세 polling을 시작하지 않는지 검증합니다.
    @Test func finalGameDetailEntryDoesNotStartPolling() async throws {
        let baseGame = try makeLiveBoxscoreDetailGame(status: .final)
        let game = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: baseGame.awayScore,
            homeScore: baseGame.homeScore,
            status: .final,
            inningText: "9말",
            note: baseGame.note,
            providerGameID: baseGame.providerGameID
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)

        #expect(model.isGameDetailPollingActiveForTesting == false)
        #expect(model.activeGameDetailPollingIdentityForTesting == nil)
    }

    // pastScheduledGameDetailEntryStartsPolling 메서드는 예정 시각이 지난 scheduled 경기 polling 시작을 검증합니다.
    @Test func pastScheduledGameDetailEntryStartsPolling() async throws {
        let game = try makeLiveBoxscoreDetailGame(status: .upcoming)
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { game.scheduledStart.addingTimeInterval(60) }
        )

        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)

        #expect(model.isGameDetailPollingActiveForTesting)
        model.stopLiveGameDetailPolling()
    }

    // providerIdentitySseSnapshotAppliesAndKeepsExistingStream 메서드는 provider identity 화면이 publicGameId SSE snapshot을 적용하는지 검증합니다.
    @Test func providerIdentitySseSnapshotAppliesAndKeepsExistingStream() async throws {
        let game = try makeLiveBoxscoreDetailGame(status: .upcoming, providerGameID: "20260707SKOB0")
        let state = RecordingGameLiveStreamState(events: [
            .heartbeat,
            .snapshot(GameLiveStateResponse(
                publicGameId: "20260510-DOO-SSG",
                status: "live",
                inning: 3,
                half: "bottom",
                awayScore: 4,
                homeScore: 2,
                balls: 2,
                strikes: 1,
                outs: 0,
                bases: .init(first: true, second: false, third: false),
                currentPitcherName: "김민준",
                currentBatterName: "강승호",
                rawHash: "stream-hash-1",
                updatedAtKst: "2026-07-07T19:04:54.441247+09:00"
            ))
        ])
        let model = AppModel(
            gameLiveStreamClient: RecordingGameLiveStreamClient(state: state),
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { game.scheduledStart.addingTimeInterval(60) }
        )

        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)
        let didApply = await eventually(timeout: 1.0, interval: 10_000_000) {
            guard let updated = model.game(withIdentity: game.stableDetailIdentity) else { return false }
            return updated.status == .live &&
                updated.inningText == "3회 말" &&
                updated.balls == 2 &&
                updated.strikes == 1 &&
                updated.outs == 0 &&
                updated.currentPitcherName == "김민준" &&
                updated.currentBatterName == "강승호"
        }

        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)

        #expect(didApply)
        #expect(await state.requestedGameIDs == ["20260510-DOO-SSG"])
        model.stopLiveGameDetailPolling()
    }

    @Test func sseRecordRefreshSignalDeduplicatesRawHashAndPublishesEachNewSnapshot() async throws {
        let game = try makeLiveBoxscoreDetailGame(status: .live)
        func liveState(rawHash: String) -> GameLiveStateResponse {
            GameLiveStateResponse(
                publicGameId: game.publicGameID ?? "20260510-DOO-SSG",
                status: "live",
                inning: nil,
                half: nil,
                awayScore: game.awayScore,
                homeScore: game.homeScore,
                balls: game.balls,
                strikes: game.strikes,
                outs: game.outs,
                bases: .init(first: true, second: false, third: false),
                currentPitcherName: game.currentPitcherName,
                currentBatterName: game.currentBatterName,
                rawHash: rawHash,
                updatedAtKst: "2026-05-10T14:10:00+09:00"
            )
        }
        let streamState = RecordingGameLiveStreamState(events: [
            .snapshot(liveState(rawHash: "records-hash-1")),
            .snapshot(liveState(rawHash: "records-hash-1")),
            .snapshot(liveState(rawHash: "records-hash-2"))
        ])
        let model = AppModel(
            repository: StubRepository(),
            gameLiveStreamClient: RecordingGameLiveStreamClient(state: streamState),
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { game.scheduledStart.addingTimeInterval(60) }
        )

        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)
        let didPublish = await eventually(timeout: 1.0, interval: 10_000_000) {
            model.gameDetailRecordRefreshSignal(for: game.stableDetailIdentity)?.sequence == 2
        }

        #expect(didPublish)
        #expect(model.gameDetailRecordRefreshSignal(for: game.stableDetailIdentity)?.rawHash == "records-hash-2")
        model.stopLiveGameDetailPolling()
    }

    // sseSnapshotRefetchesLatestSnapshotRunnerNames 메서드는 SSE payload에 없는 주자 이름을 latest snapshot 재조회로 반영하는지 검증합니다.
    @Test func sseSnapshotRefetchesLatestSnapshotRunnerNames() async throws {
        let game = try makeLiveBoxscoreDetailGame(status: .live)
        let snapshot = try makeSupabaseLatestSnapshotRow(
            gameID: game.id,
            inningLabel: "Bottom 4",
            currentPitcherName: "성영탁",
            currentBatterName: "손성빈",
            balls: 1,
            strikes: 1,
            outs: 2,
            awayScore: 0,
            homeScore: 9,
            runnerOnFirst: false,
            runnerOnSecond: true,
            runnerOnThird: false,
            secondRunnerName: "전민재"
        )
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default)
            }),
            source: TrackingSupabaseSource(teamRows: [], gameRows: [], tracker: tracker, latestSnapshotRows: [snapshot]),
            runtimeState: nil
        )
        let streamState = RecordingGameLiveStreamState(events: [
            .snapshot(GameLiveStateResponse(
                publicGameId: game.publicGameID ?? "20260510-DOO-SSG",
                status: "live",
                inning: 4,
                half: "bottom",
                awayScore: 0,
                homeScore: 9,
                balls: 1,
                strikes: 1,
                outs: 2,
                bases: .init(first: false, second: true, third: false),
                currentPitcherName: "성영탁",
                currentBatterName: "손성빈",
                rawHash: "stream-hash-runner-name",
                updatedAtKst: "2026-07-08T20:10:00+09:00"
            ))
        ])
        let model = AppModel(
            repository: repository,
            gameLiveStreamClient: RecordingGameLiveStreamClient(state: streamState),
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { game.scheduledStart.addingTimeInterval(60) }
        )

        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)
        let didApply = await eventually(timeout: 1.0, interval: 10_000_000) {
            model.game(withIdentity: game.stableDetailIdentity)?.baseRunners?.second == "전민재"
        }

        #expect(didApply)
        #expect(await tracker.latestSnapshotGameIDs == [game.id])
        #expect(model.game(withIdentity: game.stableDetailIdentity)?.homeScore == 9)
        #expect(model.game(withIdentity: game.stableDetailIdentity)?.currentBatterName == "손성빈")
        model.stopLiveGameDetailPolling()
    }

    // sseFallbackDoesNotPreserveRunnerNameAfterBatterChanged 메서드는 타자가 바뀐 fallback payload가 이전 주자 이름을 carry-forward하지 않는지 검증합니다.
    @Test func sseFallbackDoesNotPreserveRunnerNameAfterBatterChanged() async throws {
        let base = try makeLiveBoxscoreDetailGame(status: .live)
        let game = makeGameDetail(
            id: base.id,
            scheduledStart: base.scheduledStart,
            venue: base.venue,
            awayTeam: base.awayTeam,
            homeTeam: base.homeTeam,
            awayScore: 0,
            homeScore: 8,
            status: .live,
            seasonClassification: .regularSeason,
            inningText: "Bottom 4",
            note: base.note,
            providerGameID: base.providerGameID,
            bases: RunnerState(first: false, second: true, third: false),
            baseRunners: GameBaseRunners(first: nil, second: "김호령", third: nil),
            balls: 1,
            strikes: 1,
            outs: 2,
            currentPitcherName: "성영탁",
            currentBatterName: "손호영"
        )
        let streamState = RecordingGameLiveStreamState(events: [
            .snapshot(GameLiveStateResponse(
                publicGameId: game.publicGameID ?? "20260510-DOO-SSG",
                status: "live",
                inning: 4,
                half: "bottom",
                awayScore: 0,
                homeScore: 9,
                balls: 2,
                strikes: 1,
                outs: 2,
                bases: .init(first: false, second: true, third: false),
                currentPitcherName: "성영탁",
                currentBatterName: "손성빈",
                rawHash: "stream-hash-preserve-runner",
                updatedAtKst: "2026-07-08T20:10:00+09:00"
            ))
        ])
        let model = AppModel(
            repository: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default)
            }),
            gameLiveStreamClient: RecordingGameLiveStreamClient(state: streamState),
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { game.scheduledStart.addingTimeInterval(60) }
        )

        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)
        let didApply = await eventually(timeout: 1.0, interval: 10_000_000) {
            model.game(withIdentity: game.stableDetailIdentity)?.currentBatterName == "손성빈"
        }

        let updated = try #require(model.game(withIdentity: game.stableDetailIdentity))
        #expect(didApply)
        #expect(updated.bases == RunnerState(first: false, second: true, third: false))
        #expect(updated.baseRunners?.second == nil)
        model.stopLiveGameDetailPolling()
    }

    // delayedAndSuspendedGameDetailEntryStartsPolling 메서드는 delayed/suspended 정규화 상태의 polling 시작을 검증합니다.
    @Test func delayedAndSuspendedGameDetailEntryStartsPolling() async throws {
        let delayed = try makeLiveBoxscoreDetailGame(status: KBODataMapper.mapGameStatus(code: "delayed", text: nil))
        let suspended = try makeLiveBoxscoreDetailGame(
            status: KBODataMapper.mapGameStatus(code: "suspended", text: nil),
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        )
        let delayedModel = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [delayed], notifications: [], settings: .default),
            usePersistedSettings: false
        )
        let suspendedModel = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [suspended], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        await delayedModel.startLiveGameDetailPolling(gameIdentity: delayed.stableDetailIdentity)
        await suspendedModel.startLiveGameDetailPolling(gameIdentity: suspended.stableDetailIdentity)

        #expect(delayedModel.isGameDetailPollingActiveForTesting)
        #expect(suspendedModel.isGameDetailPollingActiveForTesting)
        delayedModel.stopLiveGameDetailPolling()
        suspendedModel.stopLiveGameDetailPolling()
    }

    // gameDetailDisappearStopsPolling 메서드는 상세 화면 disappear 시 polling 취소를 검증합니다.
    @Test func gameDetailDisappearStopsPolling() async throws {
        let game = try makeLiveBoxscoreDetailGame(status: .live)
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)
        model.stopLiveGameDetailPolling()

        #expect(model.isGameDetailPollingActiveForTesting == false)
        #expect(model.activeGameDetailPollingIdentityForTesting == nil)
    }

    // gameDetailForegroundRefreshesImmediately 메서드는 foreground 복귀 시 polling tick 대기 없이 1회 refresh하는지 검증합니다.
    @Test func gameDetailForegroundRefreshesImmediately() async throws {
        let game = try makeLiveBoxscoreDetailGame(status: .live)
        let state = RecordingGameDetailSnapshotState(result: .success(game))
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default)
            }),
            fetchGameDetailSnapshot: { game, identity, teams in
                try await state.fetch(game: game, identity: identity, teams: teams)
            }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false,
            gameDetailPollingIntervalNanoseconds: 5_000_000_000
        )

        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)
        await model.resumeLiveGameDetailPollingIfNeeded()

        #expect(await state.fetchCount == 1)
        model.stopLiveGameDetailPolling()
    }

    // gameDetailPollingContinuesAfterRefreshFailure 메서드는 refresh 실패 후에도 다음 polling tick이 유지되는지 검증합니다.
    @Test func gameDetailPollingContinuesAfterRefreshFailure() async throws {
        let game = try makeLiveBoxscoreDetailGame(status: .live)
        let state = RecordingGameDetailSnapshotState(result: .failure(TestRepositoryError.supabaseUnavailable))
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default)
            }),
            fetchGameDetailSnapshot: { game, identity, teams in
                try await state.fetch(game: game, identity: identity, teams: teams)
            }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false,
            gameDetailPollingIntervalNanoseconds: 10_000_000
        )

        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)
        let didKeepPolling = await eventually(timeout: 1.0, interval: 10_000_000) {
            await state.fetchCount >= 2
        }

        #expect(didKeepPolling)
        model.stopLiveGameDetailPolling()
    }

    // manualRefreshAndPollingUseSameGameDetailPresentationMergeResult 메서드는 수동 새로고침과 polling이 같은 상세 병합 결과를 만드는지 검증합니다.
    @Test func manualRefreshAndPollingUseSameGameDetailPresentationMergeResult() async throws {
        let game = try makeLiveBoxscoreDetailGame(status: .live)
        let latest = makeGameDetail(
            id: game.id,
            scheduledStart: game.scheduledStart,
            venue: game.venue,
            awayTeam: game.awayTeam,
            homeTeam: game.homeTeam,
            awayScore: game.awayScore,
            homeScore: game.homeScore,
            status: .live,
            inningText: "Bottom 3",
            note: game.note,
            providerGameID: game.providerGameID,
            bases: RunnerState(first: true, second: false, third: false),
            baseRunners: GameBaseRunners(first: "윤준호", second: nil, third: nil),
            balls: 1,
            strikes: 2,
            outs: 1,
            currentPitcherName: "나균안",
            currentBatterName: "정수빈"
        )
        let state = RecordingGameDetailSnapshotState(result: .success(latest))
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default)
            }),
            fetchGameDetailSnapshot: { game, identity, teams in
                try await state.fetch(game: game, identity: identity, teams: teams)
            }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false,
            gameDetailPollingIntervalNanoseconds: 10_000_000
        )

        let manual = try #require(await model.refreshGameDetailResult(for: game.stableDetailIdentity, forceRefresh: true)?.game)
        await model.startLiveGameDetailPolling(gameIdentity: game.stableDetailIdentity)
        let didPoll = await eventually(timeout: 1.0, interval: 10_000_000) {
            await state.fetchCount >= 2
        }
        let polled = try #require(model.game(withIdentity: game.stableDetailIdentity))

        #expect(didPoll)
        #expect(polled.balls == manual.balls)
        #expect(polled.strikes == manual.strikes)
        #expect(polled.outs == manual.outs)
        #expect(polled.bases == manual.bases)
        #expect(polled.baseRunners == manual.baseRunners)
        model.stopLiveGameDetailPolling()
    }

    // gameDetailRefreshPrefersLatestSnapshotBasesOverCachedEmptyBases 메서드는 AppModel refresh 후 저장소 캐시의 empty bases가 latestSnapshot bases를 덮지 못하는지 검증합니다.
    @Test func gameDetailRefreshPrefersLatestSnapshotBasesOverCachedEmptyBases() async throws {
        let cached = try makeLiveBoxscoreDetailGame(status: .live)
        let cachedEmpty = makeGameDetail(
            id: cached.id,
            scheduledStart: cached.scheduledStart,
            venue: cached.venue,
            awayTeam: cached.awayTeam,
            homeTeam: cached.homeTeam,
            awayScore: cached.awayScore,
            homeScore: cached.homeScore,
            status: .live,
            inningText: "Top 4",
            note: cached.note,
            providerGameID: cached.providerGameID,
            bases: .empty,
            baseRunners: nil,
            balls: cached.balls,
            strikes: cached.strikes,
            outs: cached.outs,
            currentPitcherName: cached.currentPitcherName,
            currentBatterName: cached.currentBatterName
        )
        let latest = makeGameDetail(
            id: cached.id,
            scheduledStart: cached.scheduledStart,
            venue: cached.venue,
            awayTeam: cached.awayTeam,
            homeTeam: cached.homeTeam,
            awayScore: cached.awayScore,
            homeScore: cached.homeScore,
            status: .live,
            inningText: "Top 4",
            note: cached.note,
            providerGameID: cached.providerGameID,
            bases: RunnerState(first: true, second: true, third: false),
            baseRunners: GameBaseRunners(first: nil, second: nil, third: nil),
            balls: 1,
            strikes: 2,
            outs: 1,
            currentPitcherName: cached.currentPitcherName,
            currentBatterName: cached.currentBatterName
        )
        let repository = DetailSnapshotStubRepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [cachedEmpty], notifications: [], settings: .default)
            }),
            fetchGameDetailSnapshot: { _, _, _ in latest }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [cachedEmpty], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let refreshed = try #require(await model.refreshGameDetailResult(for: cachedEmpty.stableDetailIdentity, forceRefresh: true)?.game)

        #expect(refreshed.bases == RunnerState(first: true, second: true, third: false))
        #expect(refreshed.baseRunners?.first == nil)
        #expect(refreshed.baseRunners?.second == nil)
        #expect(GameDetailPresentation(game: refreshed, payload: nil, boxscore: nil).displayBaseRunners.map(\.base) == ["1B", "2B"])
    }

    // upcomingGameDetailSkipsAutomaticOfficialPreviewLoad 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func upcomingGameDetailSkipsAutomaticOfficialPreviewLoad() async throws {
        GameDetailScreenModel.resetBoxscoreLoadingCacheForTesting()
        let baseGame = try makeLiveBoxscoreDetailGame(status: .upcoming)
        let game = makeGameDetail(
            id: baseGame.id,
            scheduledStart: baseGame.scheduledStart,
            venue: baseGame.venue,
            awayTeam: baseGame.awayTeam,
            homeTeam: baseGame.homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: baseGame.note,
            providerGameID: baseGame.providerGameID,
            awayStartingPitcherName: "곽빈",
            homeStartingPitcherName: "김광현"
        )
        let detailFetcher = RecordingDetailPayloadFetcher(
            payload: sampleGameCenterDetailPayload(game: game)
        )
        let officialFallback = RecordingOfficialFallback(
            result: .success(sampleOfficialFallbackReview())
        )
        let model = GameDetailScreenModel(
            boxscoreClient: RecordingBoxscoreClient(
                state: RecordingBoxscoreState(
                    result: .success(GameBoxscoreResponse.empty(gameId: "20260510-DOO-SSG"))
                )
            ),
            fetchDetail: { game in try await detailFetcher.fetch(game: game) },
            fetchDatabaseRecordReview: { _ in
                Issue.record("upcoming GameDetail should not fetch database records automatically")
                return nil
            },
            fetchOfficialRecordFallback: { game in try await officialFallback.fetch(game: game) }
        )

        await model.load(for: game)
        await model.waitForOfficialFallbackLoadForTesting()

        #expect(model.detail == nil)
        #expect(model.databaseRecordReview == nil)
        #expect(model.officialFallbackReview == nil)
        #expect(await detailFetcher.fetchCount == 0)
        #expect(await officialFallback.fetchCount == 0)
    }

    // upcomingGameDetailRefreshSkipsSupabaseSnapshotLookup 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func upcomingGameDetailRefreshSkipsSupabaseSnapshotLookup() async throws {
        let game = try makeLiveBoxscoreDetailGame(status: .upcoming)
        let awayTeamID = supabaseTeamUUID(for: "doosan")
        let homeTeamID = supabaseTeamUUID(for: "ssg")
        let row = try makeSupabaseGameRow(
            id: game.id,
            publicGameID: game.publicGameID ?? "20260510-DOO-SSG",
            providerGameID: game.providerGameID ?? "20260510SKOB0",
            gameDate: "2026-05-10",
            scheduledAt: "2026-05-10T14:00:00+09:00",
            status: "scheduled",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 0,
            homeScore: 0,
            inningState: "Scheduled"
        )
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default)
            }),
            source: TrackingSupabaseSource(
                teamRows: [
                    supabaseTeamRow(code: "doosan", id: awayTeamID),
                    supabaseTeamRow(code: "ssg", id: homeTeamID)
                ],
                gameRows: [row],
                tracker: tracker
            ),
            runtimeState: nil
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let refreshed = await model.refreshGameDetailResult(for: game.stableDetailIdentity, forceRefresh: false)

        #expect(refreshed?.game.id == game.id)
        #expect(await tracker.singleLookups.isEmpty)
        #expect(await tracker.latestSnapshotGameIDs.isEmpty)
    }

    // snapshotAtNilRawLiveWithInningProgressDoesNotDowngradeToUpcoming 메서드는 timestamp 없는 live snapshot도 진행 증거가 있으면 live로 유지되는지 검증합니다.
    @Test func snapshotAtNilRawLiveWithInningProgressDoesNotDowngradeToUpcoming() async throws {
        let game = try makeLiveBoxscoreDetailGame(status: .upcoming)
        let awayTeamID = supabaseTeamUUID(for: "doosan")
        let homeTeamID = supabaseTeamUUID(for: "ssg")
        let row = try makeSupabaseGameRow(
            id: game.id,
            publicGameID: game.publicGameID ?? "20260510-DOO-SSG",
            providerGameID: game.providerGameID ?? "20260510SKOB0",
            gameDate: "2026-05-10",
            scheduledAt: "2026-05-10T14:00:00+09:00",
            status: "live",
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: 0,
            homeScore: 0,
            inningState: "Bottom 3"
        )
        let snapshot = try makeSupabaseLatestSnapshotRow(
            gameID: game.id,
            inningLabel: "Bottom 3",
            currentPitcherName: nil,
            currentBatterName: nil,
            balls: 0,
            strikes: 0,
            outs: 0
        )
        let tracker = DetailFetchTracker()
        let repository = SupabaseBackedKBORepository(
            base: StubRepository(fetchBootstrapData: {
                KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default)
            }),
            source: TrackingSupabaseSource(
                teamRows: [
                    supabaseTeamRow(code: "doosan", id: awayTeamID),
                    supabaseTeamRow(code: "ssg", id: homeTeamID)
                ],
                gameRows: [row],
                tracker: tracker,
                latestSnapshotRows: [snapshot]
            ),
            runtimeState: nil
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        let refreshed = await model.refreshGameDetailResult(for: game.stableDetailIdentity, forceRefresh: true)

        #expect(refreshed?.game.status == .live)
        #expect(refreshed?.game.inningText == "Bottom 3")
    }

    // failedBoxscoreFetchDoesNotFailDetailLoad 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // slowBoxscoreFetchDoesNotBlockDetailPayloadRendering 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailScreenModelDoesNotRepeatBoxscoreFetchForSameGame 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameDetailScreenModelSkipsRepeatedFailedBoxscoreFetchDuringCooldown 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // bootstrapRefreshRepositoryWritesDocumentsJSONAndStoresETagOn200 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // bootstrapRefreshRepositorySendsStoredETagAndSkipsRewriteOn304 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // bootstrapRefreshFailurePreservesExistingDocumentsJSON 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // bootstrapRefreshFailureStillFallsBackToBundledJSONWithoutDocumentsFile 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // appModelRefreshHomeSkipsBootstrapReapplyWhenBootstrapIsNotModified 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // appModelRefreshHomeReappliesBootstrapAfterSuccessfulDownload 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // appModelMakesProbabilityAvailableBeforeThirtyPercentSeasonProgress 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // localProbabilityCalculatorMakesProbabilityAvailableAtThirtyPercentSeasonProgress 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // localProbabilityCalculatorMakesProbabilityAvailableAboveThirtyPercentSeasonProgress 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // localProbabilityCalculatorAddsVirtualGamesForOfficialPairDeficits 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // localProbabilityCalculatorReturnsDeterministicProbabilitiesForSameSnapshot 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // appModelDoesNotTreatEarlySevenAndOneLeaderAsClinched 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // appModelKeepsEarlyLowerRankedTeamsAboveNearZeroProbability 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // localProbabilityCalculatorReturnsCertainQualificationOutcomesWhenSeasonIsComplete 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // standingsRemainSortedByOfficialRecordWhenProbabilitiesExist 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // localProbabilityCalculatorFallsBackToNeutralPriorWithoutPreviousSeasonRanks 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // localProbabilityCalculatorUsesUnavailableReasonForUnknownClassificationGames 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // localProbabilityCalculatorDoesNotTreatMappedSupabaseRegularSeasonRowsAsUnknown 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // snapshotShowsUnavailablePostseasonProbabilityStateWhenReasonExists 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // snapshotKeepsUnavailablePostseasonStateVisibleAfterThresholdForRealDataIssues 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // snapshotFormatsPostseasonProbabilityAsOneDecimalPercent 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // snapshotClampsExtremeNonCertainPostseasonProbabilityDisplay 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // snapshotShowsExactPostseasonProbabilityForClinchedAndEliminatedTeams 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // snapshotCalculatesPythagoreanWinningPercentageFromRunsScoredAndAllowed 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // snapshotPythagoreanWinningPercentageReturnsNeutralForZeroRuns 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // snapshotPythagoreanWinningPercentageIsUnavailableWithoutRunData 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // standingsSnapshotUsesOnlyCompletedRegularSeasonGamesForRunTotalsAndPythagoreanWinningPercentage 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // fallbackRepositoryUsesMockWhenLiveRequestFails 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // fallbackRepositoryUsesMockMonthlyScheduleWhenLiveRequestFails 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // cachedRepositoryReusesFreshGameCache 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // cachedRepositoryFallsBackToStaleCacheAfterFailedRefresh 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // cachedRepositoryReusesFreshMonthlyScheduleCache 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // cachedRepositoryBypassesFreshMonthlyScheduleCacheWhenRequested 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // cachedRepositoryFallsBackToPersistedGamesCacheAcrossInstances 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // cachedRepositoryFallsBackToPersistedMonthlyScheduleAcrossInstances 메서드는 이 타입의 주요 동작을 수행합니다.
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

    @Test func cachedRepositoryPreservesMonthlyScheduleWhenRefreshReturnsEmpty() async throws {
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 5)
        let fullMonthGames = try makeScheduleMonthGames()
        let fetchSequence = ScheduleMonthFetchSequence(responses: [fullMonthGames, []])
        let repository = CachedKBORepository(
            base: StubRepository(fetchMonthlySchedule: { _ in
                await fetchSequence.next()
            }),
            configuration: RepositoryCacheConfiguration(bootstrapTTL: 1, gamesTTL: 1, notificationsTTL: 1, monthlyScheduleTTL: 60),
            runtimeState: nil
        )

        let seeded = try await repository.fetchMonthlySchedule(for: monthKey)
        let refreshed = try await repository.fetchMonthlySchedule(for: monthKey, bypassingCache: true)
        let cachedAfterRefresh = try await repository.fetchMonthlySchedule(for: monthKey)

        #expect(seeded.count == fullMonthGames.count)
        #expect(refreshed.count == fullMonthGames.count)
        #expect(cachedAfterRefresh.count == fullMonthGames.count)
    }

    // appModelKeepsExistingGamesWhenRefreshFails 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // myTeamCalendarDerivesMonthGridFromExistingGames 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func myTeamCalendarDerivesMonthGridFromExistingGames() async throws {
        let referenceDate = isoDate("2026-03-23T12:00:00+09:00")
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

    // myTeamCalendarUsesLoadedOfficialMonthSchedule 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func myTeamCalendarUsesLoadedOfficialMonthSchedule() async throws {
        let referenceDate = isoDate("2026-03-12T09:00:00+09:00")
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

    @Test func favoriteTeamScheduleWidgetSnapshotUsesFullLoadedMonth() async throws {
        let referenceDate = isoDate("2026-06-20T09:00:00+09:00")
        let schedule = try makeScheduleMonthGames(count: 135, year: 2026, month: 6)
        let repository = StubRepository(fetchMonthlySchedule: { _ in schedule })
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let lotte = try #require(model.teams.first(where: { $0.id == "lotte" }))

        model.settings.favoriteTeamID = "lotte"
        await model.loadMyTeamScheduleIfNeeded(for: referenceDate)

        let days = model.myTeamCalendarDays(for: referenceDate)
        let expectedCount = schedule.filter { $0.involves(teamID: "lotte") }.count
        let snapshot = FavoriteTeamWidgetSnapshotBuilder.makeSnapshot(
            teamID: lotte.id,
            teamName: lotte.displayName,
            teamShortName: lotte.displayName,
            displayedMonth: model.startOfMonth(for: referenceDate),
            monthTitle: model.calendarMonthTitle(for: referenceDate),
            days: days,
            referenceDate: referenceDate,
            calendar: scheduleTestCalendar()
        )
        let snapshotCount = snapshot.days.reduce(0) { partialResult, day in
            partialResult + (day.isInDisplayedMonth ? day.gameCount : 0)
        }

        #expect(expectedCount > 1)
        #expect(snapshotCount == expectedCount)
        #expect(snapshot.monthSummaryText == "이달 경기 \(expectedCount)")
    }

    @Test func scheduleTabMonthLoadPublishesFullMonthToFavoriteTeamWidget() async throws {
        let referenceDate = isoDate("2026-06-20T09:00:00+09:00")
        let monthKey = KBOMonthScheduleKey(date: referenceDate)
        let schedule = try makeScheduleMonthGames(count: 135, year: 2026, month: 6)
        let bootstrap = MockKBOData.makeBootstrap(now: referenceDate)
        let emptyBootstrap = KBOBootstrapData(
            teams: bootstrap.teams,
            games: [],
            notifications: [],
            settings: bootstrap.settings
        )
        let repository = StubRepository(fetchMonthlySchedule: { _ in schedule })
        let model = AppModel(
            repository: repository,
            bootstrap: emptyBootstrap,
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = referenceDate

        model.settings.favoriteTeamID = "lotte"
        await viewModel.loadDisplayedMonth(appModel: model)

        let snapshot = try #require(model.favoriteTeamScheduleWidgetSnapshotForTesting())
        let expectedCount = schedule.filter { $0.involves(teamID: "lotte") }.count
        let snapshotCount = snapshot.days.reduce(0) { partialResult, day in
            partialResult + (day.isInDisplayedMonth ? day.gameCount : 0)
        }

        #expect(model.currentScheduleMonthSnapshot(for: monthKey).isEmpty)
        #expect(model.favoriteTeamScheduleWidgetSourceMonthlyCountForTesting(monthKey: monthKey) == schedule.count)
        #expect(expectedCount > 1)
        #expect(snapshot.teamID == "lotte")
        #expect(snapshotCount == expectedCount)
        #expect(snapshot.monthSummaryText == "이달 경기 \(expectedCount)")
    }

    @Test func scheduleTabNonCurrentMonthDoesNotOverwriteFavoriteTeamWidgetSnapshot() async throws {
        let referenceDate = isoDate("2026-06-21T09:00:00+09:00")
        let currentMonthKey = KBOMonthScheduleKey(year: 2026, month: 6)
        let nonCurrentMonthKey = KBOMonthScheduleKey(year: 2026, month: 5)
        let juneSchedule = try makeScheduleMonthGames(count: 135, year: 2026, month: 6)
        let maySchedule = try makeScheduleMonthGames(count: 135, year: 2026, month: 5)
        let bootstrap = MockKBOData.makeBootstrap(now: referenceDate)
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: bootstrap.teams, games: [], notifications: [], settings: bootstrap.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        model.settings.favoriteTeamID = "lotte"
        await model.updateFavoriteTeamScheduleWidgetSnapshot(
            fromScheduleTabMonthGames: juneSchedule,
            monthKey: currentMonthKey,
            reason: "scheduleTabMonth"
        )
        let currentSnapshot = try #require(model.favoriteTeamScheduleWidgetSnapshotForTesting())

        await model.updateFavoriteTeamScheduleWidgetSnapshot(
            fromScheduleTabMonthGames: maySchedule,
            monthKey: nonCurrentMonthKey,
            reason: "scheduleTabMonth"
        )
        let afterMaySnapshot = try #require(model.favoriteTeamScheduleWidgetSnapshotForTesting())

        #expect(KBOMonthScheduleKey(date: currentSnapshot.displayedMonth) == currentMonthKey)
        #expect(KBOMonthScheduleKey(date: afterMaySnapshot.displayedMonth) == currentMonthKey)
        #expect(afterMaySnapshot.monthSummaryText == currentSnapshot.monthSummaryText)
        #expect(model.favoriteTeamScheduleWidgetSourceMonthlyCountForTesting(monthKey: nonCurrentMonthKey) == nil)
    }

    @Test func scheduleTabCurrentMonthUpdatesFavoriteTeamWidgetSnapshot() async throws {
        let referenceDate = isoDate("2026-06-21T09:00:00+09:00")
        let currentMonthKey = KBOMonthScheduleKey(year: 2026, month: 6)
        let juneSchedule = try makeScheduleMonthGames(count: 135, year: 2026, month: 6)
        let bootstrap = MockKBOData.makeBootstrap(now: referenceDate)
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: bootstrap.teams, games: [], notifications: [], settings: bootstrap.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        model.settings.favoriteTeamID = "lotte"
        await model.updateFavoriteTeamScheduleWidgetSnapshot(
            fromScheduleTabMonthGames: juneSchedule,
            monthKey: currentMonthKey,
            reason: "scheduleTabMonth"
        )

        let snapshot = try #require(model.favoriteTeamScheduleWidgetSnapshotForTesting())
        let expectedCount = juneSchedule.filter { $0.involves(teamID: "lotte") }.count
        let snapshotCount = snapshot.days.reduce(0) { partialResult, day in
            partialResult + (day.isInDisplayedMonth ? day.gameCount : 0)
        }

        #expect(KBOMonthScheduleKey(date: snapshot.displayedMonth) == currentMonthKey)
        #expect(model.favoriteTeamScheduleWidgetSourceMonthlyCountForTesting(monthKey: currentMonthKey) == juneSchedule.count)
        #expect(snapshotCount == expectedCount)
        #expect(snapshot.monthSummaryText == "이달 경기 \(expectedCount)")
    }

    @Test func favoriteTeamChangeUsesCurrentMonthForWidgetSnapshot() async throws {
        let referenceDate = isoDate("2026-06-21T09:00:00+09:00")
        let currentMonthKey = KBOMonthScheduleKey(year: 2026, month: 6)
        let displayedMonthKey = KBOMonthScheduleKey(year: 2026, month: 5)
        let juneSchedule = try makeScheduleMonthGames(count: 135, year: 2026, month: 6)
        let maySchedule = try makeScheduleMonthGames(count: 135, year: 2026, month: 5)
        let bootstrap = MockKBOData.makeBootstrap(now: referenceDate)
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: bootstrap.teams, games: [], notifications: [], settings: bootstrap.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        model.settings.favoriteTeamID = "lotte"
        await model.updateFavoriteTeamScheduleWidgetSnapshot(
            fromScheduleTabMonthGames: juneSchedule,
            monthKey: currentMonthKey,
            reason: "scheduleTabMonth"
        )
        model.settings.favoriteTeamID = "kt"

        await model.updateFavoriteTeamScheduleWidgetSnapshot(
            fromScheduleTabMonthGames: maySchedule,
            monthKey: displayedMonthKey,
            reason: "scheduleTabMonth"
        )
        await model.updateFavoriteTeamScheduleWidgetSnapshot(
            fromScheduleTabMonthGames: juneSchedule,
            monthKey: currentMonthKey,
            reason: "scheduleTabMonth"
        )

        let snapshot = try #require(model.favoriteTeamScheduleWidgetSnapshotForTesting())
        let expectedCount = juneSchedule.filter { $0.involves(teamID: "kt") }.count
        let snapshotCount = snapshot.days.reduce(0) { partialResult, day in
            partialResult + (day.isInDisplayedMonth ? day.gameCount : 0)
        }

        #expect(snapshot.teamID == "kt")
        #expect(KBOMonthScheduleKey(date: snapshot.displayedMonth) == currentMonthKey)
        #expect(snapshotCount == expectedCount)
    }

    @Test func widgetProviderIgnoresStaleMonthSnapshot() async throws {
        let currentDate = isoDate("2026-06-21T09:00:00+09:00")
        let staleMonth = isoDate("2026-05-01T09:00:00+09:00")
        let currentMonth = isoDate("2026-06-01T09:00:00+09:00")
        let staleSnapshot = FavoriteTeamScheduleWidgetSnapshot(
            generatedAt: staleMonth,
            refreshAfter: staleMonth.addingTimeInterval(60 * 60),
            teamID: "lotte",
            teamName: "롯데",
            teamShortName: "롯데",
            displayedMonth: staleMonth,
            monthTitle: "2026년 5월",
            monthSummaryText: "이달 경기 1",
            state: .ready,
            days: []
        )
        let currentSnapshot = FavoriteTeamScheduleWidgetSnapshot(
            generatedAt: currentDate,
            refreshAfter: currentDate.addingTimeInterval(60 * 60),
            teamID: "lotte",
            teamName: "롯데",
            teamShortName: "롯데",
            displayedMonth: currentMonth,
            monthTitle: "2026년 6월",
            monthSummaryText: "이달 경기 20",
            state: .ready,
            days: []
        )

        #expect(FavoriteTeamScheduleWidgetSnapshotMonthPolicy.isCurrentMonth(snapshot: staleSnapshot, now: currentDate) == false)
        #expect(FavoriteTeamScheduleWidgetSnapshotMonthPolicy.isCurrentMonth(snapshot: currentSnapshot, now: currentDate) == true)
    }

    @Test func todayRefreshDoesNotOverwriteFullMonthFavoriteTeamWidgetSnapshot() async throws {
        let referenceDate = isoDate("2026-06-20T09:00:00+09:00")
        let monthKey = KBOMonthScheduleKey(date: referenceDate)
        let schedule = try makeScheduleMonthGames(count: 135, year: 2026, month: 6)
        let todayGames = schedule.filter {
            ScheduleDateKeyFormatter.dayKey(for: $0.scheduledStart) == "2026-06-20"
        }
        let bootstrap = MockKBOData.makeBootstrap(now: referenceDate)
        let emptyBootstrap = KBOBootstrapData(
            teams: bootstrap.teams,
            games: [],
            notifications: [],
            settings: bootstrap.settings
        )
        let repository = StubRepository(
            fetchMonthlySchedule: { _ in schedule },
            fetchScheduleBypassingCache: { _, _ in todayGames }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: emptyBootstrap,
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = referenceDate

        model.settings.favoriteTeamID = "lotte"
        await viewModel.loadDisplayedMonth(appModel: model)
        let fullSnapshot = try #require(model.favoriteTeamScheduleWidgetSnapshotForTesting())
        let fullSnapshotCount = fullSnapshot.days.reduce(0) { partialResult, day in
            partialResult + (day.isInDisplayedMonth ? day.gameCount : 0)
        }

        _ = await model.refreshTodayScheduleGamesForScheduleCache(
            selectedDate: referenceDate,
            reason: "scheduleTodayLiveRefresh"
        )

        let afterTodaySnapshot = try #require(model.favoriteTeamScheduleWidgetSnapshotForTesting())
        let afterTodaySnapshotCount = afterTodaySnapshot.days.reduce(0) { partialResult, day in
            partialResult + (day.isInDisplayedMonth ? day.gameCount : 0)
        }

        #expect(todayGames.count < schedule.count)
        #expect(model.favoriteTeamScheduleWidgetSourceMonthlyCountForTesting(monthKey: monthKey) == schedule.count)
        #expect(afterTodaySnapshotCount == fullSnapshotCount)
        #expect(afterTodaySnapshot.monthSummaryText == fullSnapshot.monthSummaryText)
    }

    @Test func homeFavoritePartialSnapshotDoesNotOverwriteFullMonthWidgetSnapshot() async throws {
        FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: nil, snapshot: nil)
        defer { FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: nil, snapshot: nil) }
        let referenceDate = isoDate("2026-06-21T09:00:00+09:00")
        let currentMonthKey = KBOMonthScheduleKey(year: 2026, month: 6)
        let juneSchedule = try makeScheduleMonthGames(count: 110, year: 2026, month: 6)
        let partialGame = try #require(juneSchedule.first { $0.involves(teamID: "lotte") })
        let bootstrap = MockKBOData.makeBootstrap(now: referenceDate)
        let fullMonthModel = AppModel(
            bootstrap: KBOBootstrapData(teams: bootstrap.teams, games: [], notifications: [], settings: bootstrap.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        fullMonthModel.settings.favoriteTeamID = "lotte"
        await fullMonthModel.updateFavoriteTeamScheduleWidgetSnapshot(
            fromScheduleTabMonthGames: juneSchedule,
            monthKey: currentMonthKey,
            reason: "scheduleTabMonth"
        )
        let fullSnapshot = try #require(FavoriteTeamScheduleWidgetShared.loadSnapshot())
        #expect(FavoriteTeamScheduleWidgetShared.loadSnapshotSourceMonthlyCount() == juneSchedule.count)

        let partialModel = AppModel(
            repository: FavoriteScheduleStubRepository(
                base: StubRepository(fetchMonthlySchedule: { _ in juneSchedule }),
                fetchFavoriteTeamSchedule: { _, _, _ in [partialGame] }
            ),
            bootstrap: KBOBootstrapData(teams: bootstrap.teams, games: [], notifications: [], settings: bootstrap.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        partialModel.settings.favoriteTeamID = "lotte"
        await partialModel.refreshHome()
        let afterHomeSnapshot = try #require(FavoriteTeamScheduleWidgetShared.loadSnapshot())

        #expect(fullSnapshot.monthSummaryText == afterHomeSnapshot.monthSummaryText)
        #expect(afterHomeSnapshot.state == .ready)
        #expect(FavoriteTeamScheduleWidgetShared.loadSnapshotSourceMonthlyCount() == juneSchedule.count)
    }

    @Test func homeFavoritePartialSnapshotDoesNotOverwriteExistingWidgetSnapshotWithoutSourceCount() async throws {
        FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: nil, snapshot: nil)
        defer { FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: nil, snapshot: nil) }
        let referenceDate = isoDate("2026-06-21T09:00:00+09:00")
        let currentMonthKey = KBOMonthScheduleKey(year: 2026, month: 6)
        let juneSchedule = try makeScheduleMonthGames(count: 110, year: 2026, month: 6)
        let partialGame = try #require(juneSchedule.first { $0.involves(teamID: "lotte") })
        let bootstrap = MockKBOData.makeBootstrap(now: referenceDate)
        let fullMonthModel = AppModel(
            bootstrap: KBOBootstrapData(teams: bootstrap.teams, games: [], notifications: [], settings: bootstrap.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        fullMonthModel.settings.favoriteTeamID = "lotte"
        await fullMonthModel.updateFavoriteTeamScheduleWidgetSnapshot(
            fromScheduleTabMonthGames: juneSchedule,
            monthKey: currentMonthKey,
            reason: "scheduleTabMonth"
        )
        let fullSnapshot = try #require(FavoriteTeamScheduleWidgetShared.loadSnapshot())
        FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: nil, snapshot: nil)
        FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: "lotte", snapshot: fullSnapshot)
        #expect(FavoriteTeamScheduleWidgetShared.loadSnapshotSourceMonthlyCount() == nil)

        let partialModel = AppModel(
            repository: FavoriteScheduleStubRepository(
                base: StubRepository(fetchMonthlySchedule: { _ in juneSchedule }),
                fetchFavoriteTeamSchedule: { _, _, _ in [partialGame] }
            ),
            bootstrap: KBOBootstrapData(teams: bootstrap.teams, games: [], notifications: [], settings: bootstrap.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        partialModel.settings.favoriteTeamID = "lotte"
        await partialModel.refreshHome()
        let afterHomeSnapshot = try #require(FavoriteTeamScheduleWidgetShared.loadSnapshot())

        #expect(fullSnapshot.monthSummaryText == afterHomeSnapshot.monthSummaryText)
        #expect(afterHomeSnapshot.state == .ready)
        #expect(FavoriteTeamScheduleWidgetShared.loadSnapshotSourceMonthlyCount() == nil)
    }

    @Test func homeFavoritePartialSnapshotAllowedWhenNoExistingWidgetSnapshot() async throws {
        FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: nil, snapshot: nil)
        defer { FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: nil, snapshot: nil) }
        let referenceDate = isoDate("2026-06-21T09:00:00+09:00")
        let juneSchedule = try makeScheduleMonthGames(count: 110, year: 2026, month: 6)
        let partialGame = try #require(juneSchedule.first { $0.involves(teamID: "lotte") })
        let bootstrap = MockKBOData.makeBootstrap(now: referenceDate)
        let model = AppModel(
            repository: FavoriteScheduleStubRepository(
                base: StubRepository(fetchMonthlySchedule: { _ in [] }),
                fetchFavoriteTeamSchedule: { _, _, _ in [partialGame] }
            ),
            bootstrap: KBOBootstrapData(teams: bootstrap.teams, games: [], notifications: [], settings: bootstrap.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        model.settings.favoriteTeamID = "lotte"
        await model.refreshHome()
        let snapshot = try #require(model.favoriteTeamScheduleWidgetSnapshotForTesting())
        let snapshotCount = snapshot.days.reduce(0) { partialResult, day in
            partialResult + (day.isInDisplayedMonth ? day.gameCount : 0)
        }

        #expect(snapshotCount == 1)
        #expect(snapshot.state == .ready)
        #expect(FavoriteTeamScheduleWidgetShared.loadSnapshotSourceMonthlyCount() == 1)
    }

    @Test func scheduleTabCurrentMonthFullSnapshotStoresSourceMonthlyCount() async throws {
        FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: nil, snapshot: nil)
        defer { FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: nil, snapshot: nil) }
        let referenceDate = isoDate("2026-06-21T09:00:00+09:00")
        let currentMonthKey = KBOMonthScheduleKey(year: 2026, month: 6)
        let juneSchedule = try makeScheduleMonthGames(count: 110, year: 2026, month: 6)
        let bootstrap = MockKBOData.makeBootstrap(now: referenceDate)
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: bootstrap.teams, games: [], notifications: [], settings: bootstrap.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        model.settings.favoriteTeamID = "lotte"
        await model.updateFavoriteTeamScheduleWidgetSnapshot(
            fromScheduleTabMonthGames: juneSchedule,
            monthKey: currentMonthKey,
            reason: "scheduleTabMonth"
        )
        let snapshot = try #require(FavoriteTeamScheduleWidgetShared.loadSnapshot())

        #expect(snapshot.state == .ready)
        #expect(FavoriteTeamScheduleWidgetShared.loadSnapshotSourceMonthlyCount() == juneSchedule.count)
    }

    @Test func emptyScheduleTabMonthDoesNotOverwriteFavoriteTeamWidgetSnapshot() async throws {
        let referenceDate = isoDate("2026-06-21T09:00:00+09:00")
        let currentMonthKey = KBOMonthScheduleKey(year: 2026, month: 6)
        let juneSchedule = try makeScheduleMonthGames(count: 135, year: 2026, month: 6)
        let bootstrap = MockKBOData.makeBootstrap(now: referenceDate)
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: bootstrap.teams, games: [], notifications: [], settings: bootstrap.settings),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )

        model.settings.favoriteTeamID = "lotte"
        await model.updateFavoriteTeamScheduleWidgetSnapshot(
            fromScheduleTabMonthGames: juneSchedule,
            monthKey: currentMonthKey,
            reason: "scheduleTabMonth"
        )
        let fullSnapshot = try #require(model.favoriteTeamScheduleWidgetSnapshotForTesting())

        await model.updateFavoriteTeamScheduleWidgetSnapshot(
            fromScheduleTabMonthGames: [],
            monthKey: currentMonthKey,
            reason: "scheduleTabMonth"
        )
        let afterEmptySnapshot = try #require(model.favoriteTeamScheduleWidgetSnapshotForTesting())

        #expect(fullSnapshot.monthSummaryText != "등록 경기 없음")
        #expect(afterEmptySnapshot.monthSummaryText == fullSnapshot.monthSummaryText)
        #expect(afterEmptySnapshot.state == .ready)
    }

    // scheduleLoadFetchesMonthlyDataWithoutFavoriteTeamSelection 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleLoadFetchesMonthlyDataWithoutFavoriteTeamSelection() async throws {
        let counter = FetchCounter()
        let referenceDate = isoDate("2026-03-12T09:00:00+09:00")
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

    // scheduleInitialMonthLoadShowsLoadingBeforeEmptyState 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleInitialMonthLoadShowsLoadingBeforeEmptyState() async throws {
        let gate = ScheduleFetchGate()
        let referenceDate = isoDate("2026-03-12T09:00:00+09:00")
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            await gate.wait()
            return []
        })
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = referenceDate

        let loadTask = Task { await viewModel.loadDisplayedMonth(appModel: model) }
        await gate.waitUntilStarted()

        #expect(viewModel.isLoadingDisplayedMonth)
        #expect(viewModel.selectedGamesContentState == .initialLoading)

        await gate.release()
        await loadTask.value

        #expect(viewModel.isLoadingDisplayedMonth == false)
        #expect(viewModel.selectedGamesContentState == .loadedEmpty)
    }

    // scheduleInitialMonthLoadWithGamesShowsLoadedState 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleInitialMonthLoadWithGamesShowsLoadedState() async throws {
        let referenceDate = isoDate("2026-03-12T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let game = makeGameDetail(
            id: UUID(),
            scheduledStart: referenceDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let repository = StubRepository(fetchMonthlySchedule: { _ in [game] })
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = referenceDate

        await viewModel.loadDisplayedMonth(appModel: model)

        #expect(viewModel.isLoadingDisplayedMonth == false)
        #expect(viewModel.selectedDateGames.map(\.id) == [game.id])
        #expect(viewModel.selectedGamesContentState == .loaded)
    }

    // scheduleRefreshWithDisplayedGamesDoesNotShowInitialLoadingState 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleRefreshWithDisplayedGamesDoesNotShowInitialLoadingState() async throws {
        let gate = ScheduleFetchGate()
        let referenceDate = isoDate("2026-03-12T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let game = makeGameDetail(
            id: UUID(),
            scheduledStart: referenceDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let fetchSequence = ScheduleMonthFetchSequence(responses: [[game], [game]])
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            let count = await fetchSequence.count
            if count > 0 {
                await gate.wait()
            }
            return await fetchSequence.next()
        })
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = referenceDate
        await viewModel.loadDisplayedMonth(appModel: model)

        let refreshTask = Task { await viewModel.refreshDisplayedMonth(appModel: model) }
        await gate.waitUntilStarted()

        #expect(viewModel.selectedDateGames.isEmpty == false)
        #expect(viewModel.selectedGamesContentState == .loaded)

        await gate.release()
        await refreshTask.value
    }

    @Test func scheduleForceRefreshKeepsExistingMonthPresentationWhileFetchIsInFlight() async throws {
        let gate = ScheduleFetchGate()
        let referenceDate = isoDate("2026-07-21T09:00:00+09:00")
        let fullMonthGames = try makeScheduleMonthGames(count: 110, year: 2026, month: 7)
        let fetchSequence = ScheduleMonthFetchSequence(responses: [fullMonthGames, fullMonthGames])
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            let count = await fetchSequence.count
            if count > 0 {
                await gate.wait()
            }
            return await fetchSequence.next()
        })
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: MockKBOData.makeBootstrap().teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = referenceDate
        await viewModel.loadDisplayedMonth(appModel: model)

        let refreshTask = Task { await viewModel.loadDisplayedMonth(appModel: model) }
        await gate.waitUntilStarted()

        #expect(viewModel.monthGameCount == fullMonthGames.count)
        #expect(viewModel.selectedGamesContentState == .loaded)

        await gate.release()
        await refreshTask.value
    }

    @Test func scheduleReentryUsesRepositoryMonthCacheBeforeForceRefreshCompletes() async throws {
        let gate = ScheduleFetchGate()
        let referenceDate = isoDate("2026-07-21T09:00:00+09:00")
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 7)
        let fullMonthGames = try makeScheduleMonthGames(count: 110, year: 2026, month: 7)
        let fetchSequence = ScheduleMonthFetchSequence(responses: [fullMonthGames, fullMonthGames])
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let configuration = RepositoryCacheConfiguration(
            bootstrapTTL: 1,
            gamesTTL: 1,
            notificationsTTL: 1,
            monthlyScheduleTTL: 60,
            diskCacheDirectory: cacheDirectory
        )
        let repository = CachedKBORepository(
            base: StubRepository(fetchMonthlySchedule: { _ in
                let count = await fetchSequence.count
                if count > 0 {
                    await gate.wait()
                }
                return await fetchSequence.next()
            }),
            configuration: configuration,
            runtimeState: nil
        )
        _ = try await repository.fetchScheduleTabMonth(for: monthKey, bypassingCache: true)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: MockKBOData.makeBootstrap().teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = referenceDate

        let loadTask = Task { await viewModel.loadDisplayedMonth(appModel: model) }
        await gate.waitUntilStarted()

        #expect(viewModel.monthGameCount == fullMonthGames.count)
        #expect(viewModel.selectedGamesContentState == .loaded)

        await gate.release()
        await loadTask.value
    }

    @Test func scheduleMonthRefreshEmptyResponsePreservesDisplayedMonthCache() async throws {
        let referenceDate = isoDate("2026-05-26T09:00:00+09:00")
        let fullMonthGames = try makeScheduleMonthGames()
        let fetchSequence = ScheduleMonthFetchSequence(responses: [fullMonthGames, []])
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            await fetchSequence.next()
        })
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: MockKBOData.makeBootstrap().teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = referenceDate

        await viewModel.loadDisplayedMonth(appModel: model)
        await viewModel.loadDisplayedMonth(appModel: model)

        #expect(viewModel.monthGameCount == fullMonthGames.count)
        #expect(viewModel.selectedDateGames.count == 5)
        #expect(await fetchSequence.count == 2)
    }

    @Test func scheduleTodayLiveRecentEmptyResultDoesNotClearMonthPresentation() async throws {
        let referenceDate = isoDate("2026-05-26T09:00:00+09:00")
        let fullMonthGames = try makeScheduleMonthGames()
        let repository = StubRepository(
            fetchMonthlySchedule: { _ in fullMonthGames },
            fetchScheduleBypassingCache: { _, _ in [] }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: MockKBOData.makeBootstrap().teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = referenceDate

        await viewModel.loadDisplayedMonth(appModel: model)
        await viewModel.refreshLiveScoresIfNeeded(appModel: model)
        await viewModel.refreshLiveScoresIfNeeded(appModel: model)

        #expect(viewModel.monthGameCount == fullMonthGames.count)
        #expect(viewModel.selectedDateGames.count == 5)
    }

    // failedScheduleInitialLoadDoesNotStayLoading 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func failedScheduleInitialLoadDoesNotStayLoading() async throws {
        let gate = ScheduleFetchGate()
        let referenceDate = isoDate("2026-03-12T09:00:00+09:00")
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            await gate.wait()
            throw URLError(.timedOut)
        })
        let model = AppModel(
            repository: repository,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = referenceDate

        let loadTask = Task { await viewModel.loadDisplayedMonth(appModel: model) }
        await gate.waitUntilStarted()
        #expect(viewModel.selectedGamesContentState == .initialLoading)

        await gate.release()
        await loadTask.value

        #expect(viewModel.isLoadingDisplayedMonth == false)
        #expect(viewModel.selectedGamesContentState == .loadedEmpty)
    }

    // scheduleDayLoadUsesLocalCacheForPastCompletedDate 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleDayLoadUsesLocalCacheForPastCompletedDate() async throws {
        let dayFetchCounter = FetchCounter()
        let referenceDate = isoDate("2026-03-12T18:30:00+09:00")
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
                isoDate("2026-03-13T09:00:00+09:00")
            }
        )

        await model.loadScheduleIfNeeded(for: referenceDate)
        await model.loadScheduleDayIfNeeded(for: referenceDate)

        #expect(await dayFetchCounter.value == 0)
    }

    // scheduleDayLoadFetchesTodayOnly 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleDayLoadFetchesTodayOnly() async throws {
        let dayFetchCounter = FetchCounter()
        let referenceDate = isoDate("2026-03-12T18:30:00+09:00")
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

    // staleScheduleResolverTreatsPastScheduledGameAsStale 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func staleScheduleResolverTreatsPastScheduledGameAsStale() throws {
        let fixture = try makeStaleScheduleFixture(status: .upcoming, day: "2026-03-12")

        #expect(ScheduleStaleGameReconciliationResolver.isStalePastGame(
            fixture.game,
            today: fixture.today,
            calendar: fixture.calendar
        ))
    }

    // staleScheduleResolverTreatsPastUnknownMappedGameAsStale 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func staleScheduleResolverTreatsPastUnknownMappedGameAsStale() throws {
        let status = KBODataMapper.mapGameStatus(code: "unknown", text: nil)
        let fixture = try makeStaleScheduleFixture(status: status, day: "2026-03-12")

        #expect(status == .upcoming)
        #expect(ScheduleStaleGameReconciliationResolver.isStalePastGame(
            fixture.game,
            today: fixture.today,
            calendar: fixture.calendar
        ))
    }

    // staleScheduleResolverTreatsPastLiveGameAsStale 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func staleScheduleResolverTreatsPastLiveGameAsStale() throws {
        let fixture = try makeStaleScheduleFixture(status: .live, day: "2026-03-12")

        #expect(ScheduleStaleGameReconciliationResolver.isStalePastGame(
            fixture.game,
            today: fixture.today,
            calendar: fixture.calendar
        ))
    }

    // staleScheduleResolverDoesNotTreatPastFinalGameAsStale 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func staleScheduleResolverDoesNotTreatPastFinalGameAsStale() throws {
        let fixture = try makeStaleScheduleFixture(status: .final, day: "2026-03-12")

        #expect(ScheduleStaleGameReconciliationResolver.isStalePastGame(
            fixture.game,
            today: fixture.today,
            calendar: fixture.calendar
        ) == false)
    }

    // staleScheduleResolverDoesNotTreatPastCancelledOrPostponedGameAsStale 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func staleScheduleResolverDoesNotTreatPastCancelledOrPostponedGameAsStale() throws {
        let cancelled = try makeStaleScheduleFixture(status: .cancelled, day: "2026-03-12")
        let postponedStatus = KBODataMapper.mapGameStatus(code: "postponed", text: nil)
        let postponed = try makeStaleScheduleFixture(status: postponedStatus, day: "2026-03-12")

        #expect(postponedStatus == .cancelled)
        #expect(ScheduleStaleGameReconciliationResolver.isStalePastGame(
            cancelled.game,
            today: cancelled.today,
            calendar: cancelled.calendar
        ) == false)
        #expect(ScheduleStaleGameReconciliationResolver.isStalePastGame(
            postponed.game,
            today: postponed.today,
            calendar: postponed.calendar
        ) == false)
    }

    // staleScheduleResolverDoesNotTreatTodayOrFutureGamesAsStale 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func staleScheduleResolverDoesNotTreatTodayOrFutureGamesAsStale() throws {
        let todayScheduled = try makeStaleScheduleFixture(status: .upcoming, day: "2026-03-13")
        let todayLive = try makeStaleScheduleFixture(status: .live, day: "2026-03-13")
        let futureScheduled = try makeStaleScheduleFixture(status: .upcoming, day: "2026-03-14")

        #expect(ScheduleStaleGameReconciliationResolver.isStalePastGame(
            todayScheduled.game,
            today: todayScheduled.today,
            calendar: todayScheduled.calendar
        ) == false)
        #expect(ScheduleStaleGameReconciliationResolver.isStalePastGame(
            todayLive.game,
            today: todayLive.today,
            calendar: todayLive.calendar
        ) == false)
        #expect(ScheduleStaleGameReconciliationResolver.isStalePastGame(
            futureScheduled.game,
            today: futureScheduled.today,
            calendar: futureScheduled.calendar
        ) == false)
    }

    // staleScheduleResolverDeduplicatesMultipleGamesOnSameDate 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func staleScheduleResolverDeduplicatesMultipleGamesOnSameDate() throws {
        let first = try makeStaleScheduleFixture(status: .upcoming, day: "2026-03-12")
        let second = try makeStaleScheduleFixture(status: .live, day: "2026-03-12", id: UUID())

        let dates = ScheduleStaleGameReconciliationResolver.staleGameDates(
            in: [first.game, second.game],
            today: first.today,
            calendar: first.calendar
        )

        #expect(dates == ["2026-03-12"])
    }

    // staleScheduleResolverSortsDatesNewestFirst 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func staleScheduleResolverSortsDatesNewestFirst() throws {
        let oldest = try makeStaleScheduleFixture(status: .upcoming, day: "2026-03-09")
        let newest = try makeStaleScheduleFixture(status: .live, day: "2026-03-12")
        let middle = try makeStaleScheduleFixture(status: .upcoming, day: "2026-03-10")

        let dates = ScheduleStaleGameReconciliationResolver.staleGameDates(
            in: [oldest.game, newest.game, middle.game],
            today: newest.today,
            calendar: newest.calendar
        )

        #expect(dates == ["2026-03-12", "2026-03-10", "2026-03-09"])
    }

    // schedulePullToRefreshPreflightFreshDataSkipsBackendReconciliation 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshPreflightFreshDataSkipsBackendReconciliation() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let pastDate = isoDate("2026-03-12T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let staleGame = makeGameDetail(
            id: UUID(),
            scheduledStart: pastDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let finalGame = makeGameDetail(
            id: staleGame.id,
            scheduledStart: pastDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 2,
            status: .final
        )
        let fetchSequence = ScheduleMonthFetchSequence(responses: [[staleGame]])
        let dateFetchRecorder = ScheduleDateFetchRecorder(responses: [scheduleTestDayKey(for: pastDate): [finalGame]])
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            await fetchSequence.next()
        }, fetchScheduleBypassingCache: { date, bypassingCache in
            await dateFetchRecorder.fetch(date: date, bypassingCache: bypassingCache)
        })
        let reconciliationClient = RecordingScheduleStaleGameReconciliationClient()
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: reconciliationClient,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = pastDate
        viewModel.selectedDate = pastDate

        await viewModel.refreshDisplayedMonth(appModel: model)
        await model.waitForSchedulePostReconciliationRefreshIfNeeded()
        await viewModel.loadDisplayedMonth(appModel: model)

        #expect(await reconciliationClient.calls.isEmpty)
        #expect(await fetchSequence.count == 1)
        #expect(await dateFetchRecorder.calls.map { $0.dayKey } == ["2026-03-12"])
        #expect(await dateFetchRecorder.calls.map { $0.bypassingCache } == [true])
        #expect(viewModel.selectedDateGames.first?.status == .final)
        #expect(model.currentScheduleMonthSnapshot(for: KBOMonthScheduleKey(date: pastDate)).first?.status == .final)
    }

    // schedulePullToRefreshCallsBackendOnlyForDatesStillStaleAfterPreflight 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshCallsBackendOnlyForDatesStillStaleAfterPreflight() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let staleDate = isoDate("2026-03-12T18:30:00+09:00")
        let resolvedDate = isoDate("2026-03-11T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let stillStaleGame = makeGameDetail(id: UUID(), scheduledStart: staleDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: nil, homeScore: nil, status: .upcoming)
        let locallyStaleResolvedGame = makeGameDetail(id: UUID(), scheduledStart: resolvedDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: nil, homeScore: nil, status: .upcoming)
        let freshResolvedGame = makeGameDetail(id: locallyStaleResolvedGame.id, scheduledStart: resolvedDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: 3, homeScore: 2, status: .final)
        let dateFetchRecorder = ScheduleDateFetchRecorder(responses: [
            "2026-03-12": [stillStaleGame],
            "2026-03-11": [freshResolvedGame]
        ])
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            [stillStaleGame, locallyStaleResolvedGame]
        }, fetchScheduleBypassingCache: { date, bypassingCache in
            await dateFetchRecorder.fetch(date: date, bypassingCache: bypassingCache)
        })
        let reconciliationClient = RecordingScheduleStaleGameReconciliationClient()
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: reconciliationClient,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = resolvedDate

        await viewModel.refreshDisplayedMonth(appModel: model)
        await model.waitForSchedulePostReconciliationRefreshIfNeeded()

        #expect(await Array(dateFetchRecorder.calls.map { $0.dayKey }.prefix(2)) == ["2026-03-12", "2026-03-11"])
        #expect(await reconciliationClient.calls == [["2026-03-12"]])
        #expect(viewModel.selectedDateGames.first?.status == .final)
    }

    // schedulePullToRefreshPreflightOverlayPreservesFullMonthGameCount 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshPreflightOverlayPreservesFullMonthGameCount() async throws {
        let referenceDate = isoDate("2026-05-22T09:00:00+09:00")
        let staleDate = isoDate("2026-05-21T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let staleGames = (0..<5).map { index in
            makeGameDetail(
                id: UUID(),
                scheduledStart: staleDate.addingTimeInterval(TimeInterval(index * 60)),
                venue: "잠실",
                awayTeam: awayTeam,
                homeTeam: homeTeam,
                awayScore: nil,
                homeScore: nil,
                status: .upcoming
            )
        }
        let unrelatedGames = (0..<267).map { index in
            makeGameDetail(
                id: UUID(),
                scheduledStart: isoDate("2026-05-01T12:00:00+09:00").addingTimeInterval(TimeInterval(index * 60)),
                venue: "고척",
                awayTeam: awayTeam,
                homeTeam: homeTeam,
                awayScore: 1,
                homeScore: 0,
                status: .final
            )
        }
        let refreshedGames = staleGames.map {
            makeGameDetail(
                id: $0.id,
                scheduledStart: $0.scheduledStart,
                venue: $0.venue,
                awayTeam: awayTeam,
                homeTeam: homeTeam,
                awayScore: 4,
                homeScore: 2,
                status: .final
            )
        }
        let monthGames = unrelatedGames + staleGames
        let dateFetchRecorder = ScheduleDateFetchRecorder(responses: ["2026-05-21": refreshedGames])
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            monthGames
        }, fetchScheduleBypassingCache: { date, bypassingCache in
            await dateFetchRecorder.fetch(date: date, bypassingCache: bypassingCache)
        })
        let reconciliationClient = RecordingScheduleStaleGameReconciliationClient()
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: reconciliationClient,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = staleDate
        viewModel.selectedDate = staleDate

        await viewModel.refreshDisplayedMonth(appModel: model)
        await viewModel.loadDisplayedMonth(appModel: model)

        let monthSnapshot = model.currentScheduleMonthSnapshot(for: KBOMonthScheduleKey(date: staleDate))
        #expect(await reconciliationClient.calls.isEmpty)
        #expect(monthSnapshot.count == 272)
        #expect(viewModel.monthGameCount == 272)
        #expect(viewModel.selectedDateGames.count == 5)
        #expect(viewModel.selectedDateGames.allSatisfy { $0.status == .final })
    }

    // schedulePullToRefreshPreflightOverlayUpdatesMatchesAndInsertsMissingGames 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshPreflightOverlayUpdatesMatchesAndInsertsMissingGames() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let pastDate = isoDate("2026-03-12T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let staleGame = makeGameDetail(id: UUID(), scheduledStart: pastDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: nil, homeScore: nil, status: .upcoming)
        let unrelatedGame = makeGameDetail(id: UUID(), scheduledStart: isoDate("2026-03-10T18:30:00+09:00"), venue: "고척", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: 1, homeScore: 0, status: .final)
        let refreshedExisting = makeGameDetail(id: staleGame.id, scheduledStart: pastDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: 4, homeScore: 2, status: .final)
        let insertedGame = makeGameDetail(id: UUID(), scheduledStart: pastDate.addingTimeInterval(3600), venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: 5, homeScore: 3, status: .final)
        let dateFetchRecorder = ScheduleDateFetchRecorder(responses: ["2026-03-12": [refreshedExisting, insertedGame]])
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            [unrelatedGame, staleGame]
        }, fetchScheduleBypassingCache: { date, bypassingCache in
            await dateFetchRecorder.fetch(date: date, bypassingCache: bypassingCache)
        })
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: RecordingScheduleStaleGameReconciliationClient(),
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = pastDate
        viewModel.selectedDate = pastDate

        await viewModel.refreshDisplayedMonth(appModel: model)
        await viewModel.loadDisplayedMonth(appModel: model)

        let monthSnapshot = model.currentScheduleMonthSnapshot(for: KBOMonthScheduleKey(date: pastDate))
        #expect(monthSnapshot.count == 3)
        #expect(monthSnapshot.filter { $0.id == staleGame.id }.count == 1)
        #expect(monthSnapshot.contains { $0.id == staleGame.id && $0.status == .final })
        #expect(monthSnapshot.contains { $0.id == insertedGame.id })
        #expect(monthSnapshot.contains { $0.id == unrelatedGame.id })
    }

    // schedulePullToRefreshPreflightRecomputesStaleFromOverlaidDateGames 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshPreflightRecomputesStaleFromOverlaidDateGames() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let pastDate = isoDate("2026-03-12T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let resolvedGame = makeGameDetail(id: UUID(), scheduledStart: pastDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: nil, homeScore: nil, status: .upcoming)
        let stillStaleGame = makeGameDetail(id: UUID(), scheduledStart: pastDate.addingTimeInterval(3600), venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: nil, homeScore: nil, status: .upcoming)
        let refreshedResolvedGame = makeGameDetail(id: resolvedGame.id, scheduledStart: pastDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: 4, homeScore: 2, status: .final)
        let dateFetchRecorder = ScheduleDateFetchRecorder(responses: ["2026-03-12": [refreshedResolvedGame]])
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            [resolvedGame, stillStaleGame]
        }, fetchScheduleBypassingCache: { date, bypassingCache in
            await dateFetchRecorder.fetch(date: date, bypassingCache: bypassingCache)
        })
        let reconciliationClient = RecordingScheduleStaleGameReconciliationClient()
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: reconciliationClient,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = pastDate
        viewModel.selectedDate = pastDate

        await viewModel.refreshDisplayedMonth(appModel: model)
        await model.waitForSchedulePostReconciliationRefreshIfNeeded()

        #expect(await reconciliationClient.calls == [["2026-03-12"]])
        #expect(model.currentScheduleMonthSnapshot(for: KBOMonthScheduleKey(date: pastDate)).count == 2)
    }

    // schedulePullToRefreshSendsOnlyNewestThreeStaleDates 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshSendsOnlyNewestThreeStaleDates() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let staleGames = try ["2026-03-09", "2026-03-10", "2026-03-11", "2026-03-12"].map { day in
            makeGameDetail(
                id: UUID(),
                scheduledStart: try #require(ISO8601DateFormatter().date(from: "\(day)T18:30:00+09:00")),
                venue: "잠실",
                awayTeam: awayTeam,
                homeTeam: homeTeam,
                awayScore: nil,
                homeScore: nil,
                status: .upcoming
            )
        }
        let fetchSequence = ScheduleMonthFetchSequence(responses: [staleGames])
        let dateFetchRecorder = ScheduleDateFetchRecorder(responses: Dictionary(
            uniqueKeysWithValues: staleGames.map { (scheduleTestDayKey(for: $0.scheduledStart), [$0]) }
        ))
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            await fetchSequence.next()
        }, fetchScheduleBypassingCache: { date, bypassingCache in
            await dateFetchRecorder.fetch(date: date, bypassingCache: bypassingCache)
        })
        let reconciliationClient = RecordingScheduleStaleGameReconciliationClient()
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: reconciliationClient,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = referenceDate
        viewModel.selectedDate = referenceDate

        await viewModel.refreshDisplayedMonth(appModel: model)
        await model.waitForSchedulePostReconciliationRefreshIfNeeded()

        #expect(await reconciliationClient.calls == [["2026-03-12", "2026-03-11", "2026-03-10"]])
        #expect(await reconciliationClient.calls.first?.contains("2026-03-09") == false)
        #expect(await Array(dateFetchRecorder.calls.map { $0.dayKey }.prefix(3)) == ["2026-03-12", "2026-03-11", "2026-03-10"])
    }

    // schedulePullToRefreshPreservesUnrelatedDatesAfterPostReconciliationRefresh 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshPreservesUnrelatedDatesAfterPostReconciliationRefresh() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let staleDate = isoDate("2026-03-12T18:30:00+09:00")
        let unrelatedDate = isoDate("2026-03-11T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let staleGame = makeGameDetail(id: UUID(), scheduledStart: staleDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: nil, homeScore: nil, status: .upcoming)
        let freshGame = makeGameDetail(id: staleGame.id, scheduledStart: staleDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: 4, homeScore: 2, status: .final)
        let unrelatedGame = makeGameDetail(id: UUID(), scheduledStart: unrelatedDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: 1, homeScore: 0, status: .final)
        let dateFetchRecorder = ScheduleDateFetchRecorder(responses: ["2026-03-12": [freshGame]])
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            [staleGame, unrelatedGame]
        }, fetchScheduleBypassingCache: { date, bypassingCache in
            await dateFetchRecorder.fetch(date: date, bypassingCache: bypassingCache)
        })
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: RecordingScheduleStaleGameReconciliationClient(),
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = staleDate
        viewModel.selectedDate = unrelatedDate

        await viewModel.refreshDisplayedMonth(appModel: model)
        await model.waitForSchedulePostReconciliationRefreshIfNeeded()
        await viewModel.loadDisplayedMonth(appModel: model)

        let selectedGame = try #require(viewModel.selectedDateGames.first)
        #expect(selectedGame.id == unrelatedGame.id)
        #expect(selectedGame.status == .final)
        let monthSnapshot = model.currentScheduleMonthSnapshot(for: KBOMonthScheduleKey(date: staleDate))
        #expect(monthSnapshot.contains { $0.id == freshGame.id && $0.status == .final })
    }

    // schedulePullToRefreshDoesNotCallReconciliationWhenNoStalePastGamesExist 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshDoesNotCallReconciliationWhenNoStalePastGamesExist() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let pastDate = isoDate("2026-03-12T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let finalGame = makeGameDetail(
            id: UUID(),
            scheduledStart: pastDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 4,
            homeScore: 2,
            status: .final
        )
        let fetchSequence = ScheduleMonthFetchSequence(responses: [[finalGame]])
        let repository = StubRepository(fetchMonthlySchedule: { _ in
            await fetchSequence.next()
        })
        let reconciliationClient = RecordingScheduleStaleGameReconciliationClient()
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: reconciliationClient,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = pastDate
        viewModel.selectedDate = pastDate

        await viewModel.refreshDisplayedMonth(appModel: model)

        #expect(await reconciliationClient.calls.isEmpty)
        #expect(await fetchSequence.count == 1)
    }

    // schedulePullToRefreshKeepsExistingDataWhenReconciliationFailsAfterPreflight 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshKeepsExistingDataWhenReconciliationFailsAfterPreflight() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let pastDate = isoDate("2026-03-12T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let staleGame = makeGameDetail(id: UUID(), scheduledStart: pastDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: nil, homeScore: nil, status: .upcoming)
        let dateFetchRecorder = ScheduleDateFetchRecorder(responses: [:])
        let repository = StubRepository(fetchMonthlySchedule: { _ in [staleGame] }, fetchScheduleBypassingCache: { date, bypassingCache in
            await dateFetchRecorder.fetch(date: date, bypassingCache: bypassingCache)
        })
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: RecordingScheduleStaleGameReconciliationClient(error: URLError(.badServerResponse)),
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = pastDate
        viewModel.selectedDate = pastDate

        await viewModel.refreshDisplayedMonth(appModel: model)

        #expect(await dateFetchRecorder.calls.map { $0.dayKey } == ["2026-03-12"])
        #expect(viewModel.selectedDateGames.first?.status == .upcoming)
        #expect(viewModel.selectedGamesContentState == .loaded)
        #expect(viewModel.statusMessage == nil)
        #expect(viewModel.monthGameCount == 1)
    }

    // schedulePullToRefreshKeepsExistingDataWhenBackendReconciliationReturnsUnauthorized 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshKeepsExistingDataWhenBackendReconciliationReturnsUnauthorized() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let pastDate = isoDate("2026-03-12T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let staleGame = makeGameDetail(id: UUID(), scheduledStart: pastDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: nil, homeScore: nil, status: .upcoming)
        let dateFetchRecorder = ScheduleDateFetchRecorder(responses: ["2026-03-12": [staleGame]])
        let repository = StubRepository(fetchMonthlySchedule: { _ in [staleGame] }, fetchScheduleBypassingCache: { date, bypassingCache in
            await dateFetchRecorder.fetch(date: date, bypassingCache: bypassingCache)
        })
        let session = makeStubSession()
        let reconciliationClient = BackendScheduleStaleGameReconciliationClient(baseURL: URL(string: "http://192.168.45.140:8088")!, session: session)
        URLProtocolStub.testResponses = [
            "http://192.168.45.140:8088/api/v1/games/reconcile-stale": StubResponse(
                statusCode: 401,
                data: Data(#"{"error":"unauthorized"}"#.utf8)
            )
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: reconciliationClient,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = pastDate
        viewModel.selectedDate = pastDate

        await viewModel.refreshDisplayedMonth(appModel: model)
        let request = try #require(URLProtocolStub.lastRequest)

        #expect(request.url?.absoluteString == "http://192.168.45.140:8088/api/v1/games/reconcile-stale")
        #expect(await dateFetchRecorder.calls.map { $0.dayKey } == ["2026-03-12"])
        #expect(viewModel.selectedDateGames.first?.status == .upcoming)
        #expect(viewModel.selectedGamesContentState == .loaded)
        #expect(viewModel.statusMessage == nil)
        #expect(viewModel.monthGameCount == 1)
    }

    // schedulePullToRefreshKeepsExistingDataWhenPostReconciliationDateFetchFails 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshKeepsExistingDataWhenPostReconciliationDateFetchFails() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let pastDate = isoDate("2026-03-12T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let staleGame = makeGameDetail(id: UUID(), scheduledStart: pastDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: nil, homeScore: nil, status: .upcoming)
        let repository = StubRepository(fetchMonthlySchedule: { _ in [staleGame] }, fetchScheduleBypassingCache: { _, _ in
            throw URLError(.timedOut)
        })
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: RecordingScheduleStaleGameReconciliationClient(),
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = pastDate
        viewModel.selectedDate = pastDate

        await viewModel.refreshDisplayedMonth(appModel: model)
        await model.waitForSchedulePostReconciliationRefreshIfNeeded()

        #expect(viewModel.selectedDateGames.first?.status == .upcoming)
    }

    // schedulePullToRefreshSkipsRecentlyReconciledDatesWhileForceRefreshIsRunning 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshSkipsRecentlyReconciledDatesWhileForceRefreshIsRunning() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let pastDate = isoDate("2026-03-12T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let staleGame = makeGameDetail(id: UUID(), scheduledStart: pastDate, venue: "잠실", awayTeam: awayTeam, homeTeam: homeTeam, awayScore: nil, homeScore: nil, status: .upcoming)
        let dateFetchRecorder = ScheduleDateFetchRecorder(responses: ["2026-03-12": [staleGame]], delayNanoseconds: 200_000_000)
        let repository = StubRepository(fetchMonthlySchedule: { _ in [staleGame] }, fetchScheduleBypassingCache: { date, bypassingCache in
            await dateFetchRecorder.fetch(date: date, bypassingCache: bypassingCache)
        })
        let reconciliationClient = RecordingScheduleStaleGameReconciliationClient()
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: reconciliationClient,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = pastDate
        viewModel.selectedDate = pastDate

        await viewModel.refreshDisplayedMonth(appModel: model)
        await viewModel.refreshDisplayedMonth(appModel: model)
        await model.waitForSchedulePostReconciliationRefreshIfNeeded()

        #expect(await reconciliationClient.calls == [["2026-03-12"]])
    }

    // schedulePullToRefreshDoesNotStartDuplicateReconciliationWhileInFlight 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func schedulePullToRefreshDoesNotStartDuplicateReconciliationWhileInFlight() async throws {
        let referenceDate = isoDate("2026-03-13T09:00:00+09:00")
        let pastDate = isoDate("2026-03-12T18:30:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
        let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
        let staleGame = makeGameDetail(
            id: UUID(),
            scheduledStart: pastDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let repository = StubRepository(fetchMonthlySchedule: { _ in [staleGame] }, fetchScheduleBypassingCache: { _, _ in
            [staleGame]
        })
        let reconciliationClient = RecordingScheduleStaleGameReconciliationClient(delayNanoseconds: 200_000_000)
        let model = AppModel(
            repository: repository,
            scheduleStaleGameReconciliationClient: reconciliationClient,
            bootstrap: MockKBOData.makeBootstrap(now: referenceDate),
            usePersistedSettings: false,
            currentDateProvider: { referenceDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = pastDate
        viewModel.selectedDate = pastDate

        async let first: Void = viewModel.refreshDisplayedMonth(appModel: model)
        async let second: Void = viewModel.refreshDisplayedMonth(appModel: model)
        _ = await (first, second)

        #expect(await reconciliationClient.calls == [["2026-03-12"]])
    }

    // scheduleMonthOverlayKeepsFullMonthWhenMergingTodayRefresh 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleMonthOverlayKeepsFullMonthWhenMergingTodayRefresh() async throws {
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 5)
        let fullMonthGames = try makeScheduleMonthGames()
        let todayRefreshGames = makeScheduleTodayRefreshGames(from: fullMonthGames)

        let mergedGames = ScheduleMonthOverlayResolver.merge(
            existingMonthGames: fullMonthGames,
            incomingGames: todayRefreshGames,
            monthKey: monthKey,
            calendar: scheduleTestCalendar()
        )

        #expect(fullMonthGames.count == 135)
        #expect(todayRefreshGames.count == 5)
        #expect(mergedGames.count == 135)
        #expect(Set(mergedGames.map(\.id)).count == 135)
    }

    // scheduleMonthOverlayUpdatesMatchingGamesWithoutDroppingOtherDates 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleMonthOverlayUpdatesMatchingGamesWithoutDroppingOtherDates() async throws {
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 5)
        let fullMonthGames = try makeScheduleMonthGames()
        let todayRefreshGames = makeScheduleTodayRefreshGames(from: fullMonthGames)
        let untouchedGame = try #require(fullMonthGames.first {
            scheduleTestDayKey(for: $0.scheduledStart) == "2026-05-01"
        })
        let updatedGameID = try #require(todayRefreshGames.first?.id)

        let mergedGames = ScheduleMonthOverlayResolver.merge(
            existingMonthGames: fullMonthGames,
            incomingGames: todayRefreshGames,
            monthKey: monthKey,
            calendar: scheduleTestCalendar()
        )

        let updatedGame = try #require(mergedGames.first { $0.id == updatedGameID })
        #expect(mergedGames.count == 135)
        #expect(updatedGame.status == .final)
        #expect(updatedGame.awayScore == 4)
        #expect(updatedGame.homeScore == 2)
        #expect(mergedGames.contains { $0.id == untouchedGame.id })
    }

    // scheduleTodayLiveRefreshMergesAllFiveLatestSnapshots 메서드는 오늘 전체 경기 live overlay 병합을 검증합니다.
    @Test func scheduleTodayLiveRefreshMergesAllFiveLatestSnapshots() async throws {
        let selectedDate = isoDate("2026-05-26T18:40:00+09:00")
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 5)
        let teams = MockKBOData.makeBootstrap().teams
        let pairs = [("samsung", "lg"), ("nc", "lotte"), ("kia", "ssg"), ("kiwoom", "hanwha"), ("doosan", "kt")]
        let scheduledGames = try pairs.enumerated().map { index, pair in
            makeGameDetail(
                id: UUID(uuidString: String(format: "97000000-0000-0000-0000-%012d", index + 1))!,
                scheduledStart: selectedDate.addingTimeInterval(TimeInterval(index * 60)),
                venue: "구장\(index)",
                awayTeam: try #require(teams.first { $0.id == pair.0 }),
                homeTeam: try #require(teams.first { $0.id == pair.1 }),
                awayScore: nil,
                homeScore: nil,
                status: .upcoming,
                seasonClassification: .regularSeason,
                inningText: nil,
                note: "public_game_id=live-overlay-\(index)",
                providerGameID: index == 1 ? "sched-202605261830-\(pair.0)-\(pair.1)" : "provider-\(index)"
            )
        }
        let liveGames = scheduledGames.enumerated().map { index, game in
            makeGameDetail(
                id: UUID(uuidString: String(format: "98000000-0000-0000-0000-%012d", index + 1))!,
                scheduledStart: game.scheduledStart,
                venue: game.venue,
                awayTeam: game.awayTeam,
                homeTeam: game.homeTeam,
                awayScore: index,
                homeScore: index == 0 ? 0 : index - 1,
                status: .live,
                seasonClassification: .regularSeason,
                inningText: index % 2 == 0 ? "\(index + 1)회 초" : "\(index + 1)회 말",
                note: "public_game_id=live-overlay-\(index)",
                providerGameID: "provider-\(index)",
                currentPitcherName: "투수\(index)",
                currentBatterName: "타자\(index)"
            )
        }
        let repository = StubRepository(
            fetchMonthlySchedule: { key in key == monthKey ? scheduledGames : [] },
            fetchScheduleBypassingCache: { _, _ in liveGames }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { selectedDate }
        )
        let coordinator = ScheduleRefreshCoordinator()

        await coordinator.loadMonth(monthKey, forceRefresh: false, appModel: model, callSite: "test", reason: "initialLoad")
        await coordinator.refreshTodayLiveIfNeeded(selectedDate: selectedDate, displayedMonthKey: monthKey, appModel: model, callSite: "test")

        let cachedGames = try #require(coordinator.cachedMonthEntries[monthKey.yearMonthText]?.games)
        let selectedDayGames = cachedGames.filter {
            ScheduleDateKeyFormatter.dayKey(for: $0.scheduledStart) == "2026-05-26"
        }
        #expect(selectedDayGames.count == 5)
        #expect(selectedDayGames.allSatisfy { $0.status == .live })
        #expect(selectedDayGames.map(\.inningText).contains("1회 초"))
        #expect(selectedDayGames.map(\.inningText).contains("2회 말"))
        #expect(selectedDayGames.map(\.currentPitcherName).allSatisfy { $0?.hasPrefix("투수") == true })
    }

    // remoteCancelledStatusWinsOverCachedScheduledMonthGame 메서드는 Supabase 취소 상태가 로컬 예정 캐시를 덮는지 검증합니다.
    @Test func remoteCancelledStatusWinsOverCachedScheduledMonthGame() async throws {
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first { $0.id == "hanwha" })
        let homeTeam = try #require(teams.first { $0.id == "lg" })
        let cached = makeGameDetail(
            id: UUID(uuidString: "97000000-0000-0000-0000-000000070501")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260705-LG-HAN provider_game_id=20260705LGHH0 updated_at=2026-07-05T10:00:00+09:00"
        )
        let remote = makeGameDetail(
            id: UUID(uuidString: "97000000-0000-0000-0000-000000070502")!,
            scheduledStart: cached.scheduledStart,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .cancelled,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260705-LG-HAN provider_game_id=20260705LGHH0 updated_at=2026-07-05T16:00:00+09:00 status_reason=우천취소"
        )

        let merged = GameMergeResolver.preferredGame(existing: cached, candidate: remote)

        #expect(merged.status == .cancelled)
        #expect(merged.note?.contains("status_reason=우천취소") == true)
    }

    // cancelledMappingDoesNotRequireCancelledFlag 메서드는 status 문자열만 cancelled여도 UI 상태가 취소인지 검증합니다.
    @Test func cancelledMappingDoesNotRequireCancelledFlag() throws {
        let homeTeamID = UUID(uuidString: "97000000-0000-0000-0000-000000070511")!
        let awayTeamID = UUID(uuidString: "97000000-0000-0000-0000-000000070512")!
        let teamRows = try JSONDecoder().decode(
            [SupabaseTeamRow].self,
            from: """
            [
              { "id": "\(homeTeamID.uuidString)", "team_code": "lg", "name": "LG Twins", "short_name": "LG" },
              { "id": "\(awayTeamID.uuidString)", "team_code": "hanwha", "name": "Hanwha Eagles", "short_name": "한화" }
            ]
            """.data(using: .utf8)!
        )
        let gameRows = try JSONDecoder().decode(
            [SupabaseGameRow].self,
            from: """
            [
              {
                "id": "97000000-0000-0000-0000-000000070513",
                "public_game_id": "20260705-LG-HAN",
                "provider": "kbo",
                "provider_game_id": "20260705LGHH0",
                "game_date": "2026-07-05",
                "scheduled_at": "2026-07-05T18:00:00+09:00",
                "stadium": "잠실",
                "status": "cancelled",
                "home_team_id": "\(homeTeamID.uuidString)",
                "away_team_id": "\(awayTeamID.uuidString)",
                "home_score": null,
                "away_score": null,
                "inning_state": null,
                "is_cancelled": false,
                "is_postponed": false,
                "status_reason": "우천취소"
              }
            ]
            """.data(using: .utf8)!
        )

        let games = SupabaseKBOMapper.mapGames(gameRows: gameRows, teamRows: teamRows)

        #expect(games.first?.status == .cancelled)
    }

    // cancelledFlagOverridesScheduledStatus 메서드는 is_cancelled=true가 status 문자열보다 우선인지 검증합니다.
    @Test func cancelledFlagOverridesScheduledStatus() throws {
        let homeTeamID = UUID(uuidString: "97000000-0000-0000-0000-000000070521")!
        let awayTeamID = UUID(uuidString: "97000000-0000-0000-0000-000000070522")!
        let teamRows = try JSONDecoder().decode(
            [SupabaseTeamRow].self,
            from: """
            [
              { "id": "\(homeTeamID.uuidString)", "team_code": "kia", "name": "KIA Tigers", "short_name": "KIA" },
              { "id": "\(awayTeamID.uuidString)", "team_code": "nc", "name": "NC Dinos", "short_name": "NC" }
            ]
            """.data(using: .utf8)!
        )
        let gameRows = try JSONDecoder().decode(
            [SupabaseGameRow].self,
            from: """
            [
              {
                "id": "97000000-0000-0000-0000-000000070523",
                "public_game_id": "20260705-KIA-NC",
                "provider": "kbo",
                "provider_game_id": "20260705NCHT0",
                "game_date": "2026-07-05",
                "scheduled_at": "2026-07-05T18:00:00+09:00",
                "stadium": "광주",
                "status": "scheduled",
                "home_team_id": "\(homeTeamID.uuidString)",
                "away_team_id": "\(awayTeamID.uuidString)",
                "home_score": null,
                "away_score": null,
                "inning_state": null,
                "is_cancelled": true,
                "is_postponed": false,
                "status_reason": "우천취소"
              }
            ]
            """.data(using: .utf8)!
        )

        let games = SupabaseKBOMapper.mapGames(gameRows: gameRows, teamRows: teamRows)

        #expect(games.first?.status == .cancelled)
    }

    // todayLiveRefreshEmptyDoesNotClearMonthCache 메서드는 0건 daily refresh가 월간 캐시와 위젯 월 소스를 비우지 않는지 검증합니다.
    @Test func todayLiveRefreshEmptyDoesNotClearMonthCache() async throws {
        let selectedDate = isoDate("2026-07-05T12:00:00+09:00")
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 7)
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first { $0.id == "hanwha" })
        let homeTeam = try #require(teams.first { $0.id == "lg" })
        let monthGame = makeGameDetail(
            id: UUID(uuidString: "97000000-0000-0000-0000-000000070531")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .cancelled,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260705-LG-HAN provider_game_id=20260705LGHH0 updated_at=2026-07-05T16:00:00+09:00 status_reason=우천취소"
        )
        let repository = StubRepository(
            fetchBootstrapData: {
                KBOBootstrapData(teams: teams, games: [], notifications: [], settings: .default)
            },
            fetchGames: { [] },
            fetchMonthlySchedule: { key in key == monthKey ? [monthGame] : [] },
            fetchScheduleBypassingCache: { _, _ in [] }
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { selectedDate }
        )
        model.settings.favoriteTeamID = "lg"
        let coordinator = ScheduleRefreshCoordinator()

        await coordinator.loadMonth(monthKey, forceRefresh: true, appModel: model, callSite: "test", reason: "initialLoad")
        await coordinator.refreshTodayLiveIfNeeded(selectedDate: selectedDate, displayedMonthKey: monthKey, appModel: model, callSite: "test")

        #expect(coordinator.cachedMonthEntries[monthKey.yearMonthText]?.games.count == 1)
        #expect(coordinator.cachedMonthEntries[monthKey.yearMonthText]?.games.first?.status == .cancelled)
        #expect(model.favoriteTeamScheduleWidgetSourceMonthlyCountForTesting(monthKey: monthKey) == 1)
    }

    // scheduleTabMonthEntryForcesSupabaseFetchEvenWhenLocalCacheExists 메서드는 월 진입 시 캐시 hit여도 remote를 다시 확인하는지 검증합니다.
    @Test func scheduleTabMonthEntryForcesSupabaseFetchEvenWhenLocalCacheExists() async throws {
        let selectedDate = isoDate("2026-07-05T12:00:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first { $0.id == "hanwha" })
        let homeTeam = try #require(teams.first { $0.id == "lg" })
        let game = makeGameDetail(
            id: UUID(uuidString: "97000000-0000-0000-0000-000000070541")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .cancelled,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260705-LG-HAN provider_game_id=20260705LGHH0 updated_at=2026-07-05T16:00:00+09:00 status_reason=우천취소"
        )
        let tracker = ScheduleTabMonthTestTracker()
        let repository = ScheduleTabMonthTestRepository(
            bootstrap: KBOBootstrapData(teams: teams, games: [], notifications: [], settings: .default),
            scheduleTabGames: [game],
            tracker: tracker
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { selectedDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = selectedDate
        viewModel.selectedDate = selectedDate

        await viewModel.loadDisplayedMonth(appModel: model)
        await viewModel.loadDisplayedMonth(appModel: model)

        #expect(await tracker.scheduleTabMonthFetches == 2)
        #expect(await tracker.scheduleTabBypassingCacheValues == [true, true])
        #expect(viewModel.selectedDateGames.first?.status == .cancelled)
    }

    // julyFifthRainoutsAppearCancelledInMonthlySchedule 메서드는 2026-07-05 취소 2건이 월간 일정에 표시되는지 검증합니다.
    @Test func julyFifthRainoutsAppearCancelledInMonthlySchedule() async throws {
        let selectedDate = isoDate("2026-07-05T12:00:00+09:00")
        let teams = MockKBOData.makeBootstrap().teams
        let hanwha = try #require(teams.first { $0.id == "hanwha" })
        let lg = try #require(teams.first { $0.id == "lg" })
        let nc = try #require(teams.first { $0.id == "nc" })
        let kia = try #require(teams.first { $0.id == "kia" })
        let rainouts = [
            makeGameDetail(
                id: UUID(uuidString: "97000000-0000-0000-0000-000000070551")!,
                scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
                venue: "잠실",
                awayTeam: hanwha,
                homeTeam: lg,
                awayScore: nil,
                homeScore: nil,
                status: .cancelled,
                seasonClassification: .regularSeason,
                note: "public_game_id=20260705-LG-HAN provider_game_id=20260705LGHH0 updated_at=2026-07-05T16:00:00+09:00 status_reason=우천취소"
            ),
            makeGameDetail(
                id: UUID(uuidString: "97000000-0000-0000-0000-000000070552")!,
                scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
                venue: "광주",
                awayTeam: nc,
                homeTeam: kia,
                awayScore: nil,
                homeScore: nil,
                status: .cancelled,
                seasonClassification: .regularSeason,
                note: "public_game_id=20260705-KIA-NC provider_game_id=20260705NCHT0 updated_at=2026-07-05T16:00:00+09:00 status_reason=우천취소"
            )
        ]
        let repository = ScheduleTabMonthTestRepository(
            bootstrap: KBOBootstrapData(teams: teams, games: [], notifications: [], settings: .default),
            scheduleTabGames: rainouts,
            tracker: ScheduleTabMonthTestTracker()
        )
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(teams: teams, games: [], notifications: [], settings: .default),
            usePersistedSettings: false,
            currentDateProvider: { selectedDate }
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = selectedDate
        viewModel.selectedDate = selectedDate

        await viewModel.loadDisplayedMonth(appModel: model)

        #expect(viewModel.selectedDateGames.count == 2)
        #expect(viewModel.selectedDateGames.allSatisfy { $0.status == .cancelled })
        #expect(Set(viewModel.selectedDateGames.compactMap(\.publicGameID)) == ["20260705-LG-HAN", "20260705-KIA-NC"])
    }

    // scheduleAppModelSyncSmallerSnapshotDoesNotReplaceFullRepositoryMonth 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleAppModelSyncSmallerSnapshotDoesNotReplaceFullRepositoryMonth() async throws {
        let selectedDate = isoDate("2026-05-26T09:00:00+09:00")
        let mayKey = KBOMonthScheduleKey(year: 2026, month: 5)
        let fullMonthGames = try makeScheduleMonthGames()
        let todayRefreshGames = makeScheduleTodayRefreshGames(from: fullMonthGames)
        let model = try makeSchedulePartialSyncModel(
            fullMonthGames: fullMonthGames,
            todayRefreshGames: todayRefreshGames,
            currentDate: selectedDate
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = isoDate("2026-05-01T09:00:00+09:00")
        viewModel.selectedDate = selectedDate

        await viewModel.loadDisplayedMonth(appModel: model)
        await model.refreshScheduleDay(for: selectedDate)
        await viewModel.loadDisplayedMonth(appModel: model)

        #expect(model.currentScheduleMonthSnapshot(for: mayKey).count == 5)
        #expect(viewModel.monthGameCount == 135)
    }

    // scheduleMonthCachePreservesMayWhenSwitchingAwayAndBackAfterPartialSync 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleMonthCachePreservesMayWhenSwitchingAwayAndBackAfterPartialSync() async throws {
        let selectedDate = isoDate("2026-05-26T09:00:00+09:00")
        let fullMayGames = try makeScheduleMonthGames()
        let todayRefreshGames = makeScheduleTodayRefreshGames(from: fullMayGames)
        let juneGames = try makeScheduleMonthGames(count: 20, year: 2026, month: 6)
        let model = try makeSchedulePartialSyncModel(
            fullMonthGames: fullMayGames,
            todayRefreshGames: todayRefreshGames,
            currentDate: selectedDate,
            otherMonthGames: juneGames
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = isoDate("2026-05-01T09:00:00+09:00")
        viewModel.selectedDate = selectedDate

        await viewModel.loadDisplayedMonth(appModel: model)
        await model.refreshScheduleDay(for: selectedDate)
        viewModel.changeDisplayedMonth(
            to: isoDate("2026-06-01T09:00:00+09:00"),
            favoriteTeamID: nil,
            attendedGameKeys: []
        )
        await viewModel.loadDisplayedMonth(appModel: model)
        #expect(viewModel.monthGameCount == 20)

        viewModel.changeDisplayedMonth(
            to: isoDate("2026-05-01T09:00:00+09:00"),
            favoriteTeamID: nil,
            attendedGameKeys: []
        )
        viewModel.selectedDate = selectedDate
        await viewModel.loadDisplayedMonth(appModel: model)

        #expect(viewModel.monthGameCount == 135)
        #expect(viewModel.selectedDateGames.count == 5)
    }

    // scheduleSelectedDateGamesUseFullMonthAfterPartialRefresh 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleSelectedDateGamesUseFullMonthAfterPartialRefresh() async throws {
        let selectedDate = isoDate("2026-05-26T09:00:00+09:00")
        let fullMonthGames = try makeScheduleMonthGames()
        let todayRefreshGames = makeScheduleTodayRefreshGames(from: fullMonthGames)
        let model = try makeSchedulePartialSyncModel(
            fullMonthGames: fullMonthGames,
            todayRefreshGames: todayRefreshGames,
            currentDate: selectedDate
        )
        let viewModel = ScheduleViewModel()
        viewModel.displayedMonth = isoDate("2026-05-01T09:00:00+09:00")
        viewModel.selectedDate = selectedDate

        await viewModel.loadDisplayedMonth(appModel: model)
        await model.refreshScheduleDay(for: selectedDate)
        await viewModel.loadDisplayedMonth(appModel: model)

        #expect(viewModel.monthGameCount == 135)
        #expect(viewModel.selectedDateGames.count == 5)
        #expect(viewModel.selectedDateGames.allSatisfy { $0.status == .final })
    }

    // scheduleMonthOverlayIgnoresIncomingGamesOutsideSelectedMonth 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleMonthOverlayIgnoresIncomingGamesOutsideSelectedMonth() async throws {
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 5)
        let fullMonthGames = try makeScheduleMonthGames()
        let juneGame = try #require(makeScheduleMonthGames(count: 1, year: 2026, month: 6).first)

        let mergedGames = ScheduleMonthOverlayResolver.merge(
            existingMonthGames: fullMonthGames,
            incomingGames: [juneGame],
            monthKey: monthKey,
            calendar: scheduleTestCalendar()
        )

        #expect(mergedGames.count == 135)
        #expect(mergedGames.contains { $0.id == juneGame.id } == false)
    }

    // backendScheduleStaleGameReconciliationClientPostsExpectedEndpoint 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func backendScheduleStaleGameReconciliationClientPostsExpectedEndpoint() async throws {
        let session = makeStubSession()
        let client = BackendScheduleStaleGameReconciliationClient(baseURL: URL(string: "http://192.168.45.140:8088")!, session: session)
        URLProtocolStub.testResponses = [
            "http://192.168.45.140:8088/api/v1/games/reconcile-stale": StubResponse(
                statusCode: 200,
                data: Data(#"{"dates":["2026-03-12"],"processedDateCount":1,"failedCount":0,"summaries":[]}"#.utf8)
            )
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        try await client.reconcileStaleGames(dates: ["2026-03-12"])
        let request = try #require(URLProtocolStub.lastRequest)
        let body = try #require(httpBodyData(from: request))
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]

        #expect(request.url?.absoluteString == "http://192.168.45.140:8088/api/v1/games/reconcile-stale")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(payload?["dates"] as? [String] == ["2026-03-12"])
    }

    // backendAttendanceClientUsesExpectedEndpoints 메서드는 직관 API 계약을 검증합니다.
    @Test func backendAttendanceClientUsesExpectedEndpoints() async throws {
        let session = makeStubSession()
        let client = BackendAttendanceClient(baseURL: URL(string: "http://192.168.45.140:8088")!, session: session)
        let installationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let gameID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        URLProtocolStub.testResponses = [
            "http://192.168.45.140:8088/api/v1/attendance": StubResponse(statusCode: 200, data: Data()),
            "http://192.168.45.140:8088/api/v1/attendance?installationId=11111111-1111-1111-1111-111111111111": StubResponse(
                statusCode: 200,
                data: Data(#"{"gameIds":["22222222-2222-2222-2222-222222222222"]}"#.utf8)
            )
        ]
        URLProtocolStub.lastRequest = nil
        defer {
            URLProtocolStub.testResponses = [:]
            URLProtocolStub.lastRequest = nil
        }

        try await client.setAttendance(
            true,
            installationID: installationID,
            gameID: gameID,
            publicGameID: "20260705-SSG-SAM",
            providerGameID: "20260705SSHT0"
        )
        var request = try #require(URLProtocolStub.lastRequest)
        var payload = try JSONSerialization.jsonObject(with: try #require(httpBodyData(from: request))) as? [String: String]
        #expect(request.url?.absoluteString == "http://192.168.45.140:8088/api/v1/attendance")
        #expect(request.httpMethod == "POST")
        #expect(payload?["installationId"] == installationID.uuidString)
        #expect(payload?["gameId"] == gameID.uuidString)

        try await client.setAttendance(
            false,
            installationID: installationID,
            gameID: gameID,
            publicGameID: "20260705-SSG-SAM",
            providerGameID: "20260705SSHT0"
        )
        request = try #require(URLProtocolStub.lastRequest)
        payload = try JSONSerialization.jsonObject(with: try #require(httpBodyData(from: request))) as? [String: String]
        #expect(request.httpMethod == "DELETE")
        #expect(payload?["installationId"] == installationID.uuidString)
        #expect(payload?["gameId"] == gameID.uuidString)

        let gameIDs = try await client.fetchAttendedGameIDs(installationID: installationID)
        request = try #require(URLProtocolStub.lastRequest)
        #expect(request.url?.absoluteString == "http://192.168.45.140:8088/api/v1/attendance?installationId=11111111-1111-1111-1111-111111111111")
        #expect(request.httpMethod == "GET")
        #expect(gameIDs == Set([gameID]))
    }

    // attendanceClientBaseURLPrefersDebugAttendancePlistOverBackendEnvironment 메서드는 Debug 직관 API 기본값이 로컬 백엔드를 향하는지 검증합니다.
    @Test func attendanceClientBaseURLPrefersDebugAttendancePlistOverBackendEnvironment() throws {
        let resolved = try #require(AttendanceClientFactory.resolveBaseURL(
            attendanceEnvironmentValue: nil,
            attendanceBundleValue: "http://localhost:8088",
            backendEnvironmentValue: "https://kboscore-back.onrender.com",
            backendBundleValue: "http://localhost:8088",
            notificationEnvironmentValue: nil,
            notificationBundleValue: nil,
            buildConfiguration: "Debug"
        ))

        #expect(resolved.source == "attendancePlist")
        #expect(resolved.url.absoluteString == "http://localhost:8088")
    }

    // attendanceClientBaseURLUsesDebugBackendPlistWhenAttendanceKeyMissing 메서드는 Attendance 전용 키가 없을 때 Debug 공통 backend 로컬 URL을 재사용하는지 검증합니다.
    @Test func attendanceClientBaseURLUsesDebugBackendPlistWhenAttendanceKeyMissing() throws {
        let resolved = try #require(AttendanceClientFactory.resolveBaseURL(
            attendanceEnvironmentValue: nil,
            attendanceBundleValue: nil,
            backendEnvironmentValue: nil,
            backendBundleValue: "http://localhost:8088",
            notificationEnvironmentValue: nil,
            notificationBundleValue: nil,
            buildConfiguration: "Debug"
        ))

        #expect(resolved.source == "backendPlist")
        #expect(resolved.url.absoluteString == "http://localhost:8088")
    }

    // attendanceClientBaseURLDoesNotUseRenderFallbackInDebug 메서드는 Debug 직관 API가 운영 backend 설정으로 떨어지지 않도록 검증합니다.
    @Test func attendanceClientBaseURLDoesNotUseRenderFallbackInDebug() throws {
        let resolved = try #require(AttendanceClientFactory.resolveBaseURL(
            attendanceEnvironmentValue: nil,
            attendanceBundleValue: nil,
            backendEnvironmentValue: "https://kboscore-back.onrender.com",
            backendBundleValue: "https://kboscore-back.onrender.com",
            notificationEnvironmentValue: "https://kboscore-back.onrender.com/devices/register",
            notificationBundleValue: "https://kboscore-back.onrender.com/devices/register",
            buildConfiguration: "Debug"
        ))

        #expect(resolved.source == "developmentFallback")
        #expect(resolved.url.absoluteString == "http://localhost:8088")
    }

    // attendanceClientBaseURLKeepsReleaseRenderURL 메서드는 Release 직관 API가 운영 Render URL을 유지하는지 검증합니다.
    @Test func attendanceClientBaseURLKeepsReleaseRenderURL() throws {
        let resolved = try #require(AttendanceClientFactory.resolveBaseURL(
            attendanceEnvironmentValue: nil,
            attendanceBundleValue: "https://kboscore-back.onrender.com",
            backendEnvironmentValue: "http://localhost:8088",
            backendBundleValue: "https://kboscore-back.onrender.com",
            notificationEnvironmentValue: nil,
            notificationBundleValue: nil,
            buildConfiguration: "Release"
        ))

        #expect(resolved.source == "attendancePlist")
        #expect(resolved.url.absoluteString == "https://kboscore-back.onrender.com")
    }

    // attendanceButtonAvailabilityStartsEnabledWithConfiguredClient 메서드는 baseURL이 있는 client 경로에서는 버튼 차단 상태가 아니어야 함을 검증합니다.
    @Test func attendanceButtonAvailabilityStartsEnabledWithConfiguredClient() {
        let model = AppModel(
            attendanceClient: RecordingAttendanceClient(),
            bootstrap: MockKBOData.makeBootstrap(),
            usePersistedSettings: false
        )

        #expect(model.isAttendanceSyncAvailable)
    }

    // attendanceList404DoesNotMarkEveryGame 메서드는 목록 조회 실패가 전체 직관 상태로 번지지 않도록 검증합니다.
    @Test func attendanceList404DoesNotMarkEveryGame() async throws {
        let client = RecordingAttendanceClient(fetchError: .httpStatus(404))
        let model = AppModel(
            attendanceClient: client,
            bootstrap: MockKBOData.makeBootstrap(),
            usePersistedSettings: false
        )

        await model.refreshAttendanceRecordsFromServer()

        #expect(model.attendedGameIDs.isEmpty)
        #expect(model.games.allSatisfy { model.isGameAttended($0) == false })
    }

    // attendanceToggleSuccessAddsOnlySelectedDatabaseGameID 메서드는 체크 성공 시 해당 DB UUID만 직관 상태가 되는지 검증합니다.
    @Test func attendanceToggleSuccessAddsOnlySelectedDatabaseGameID() async throws {
        let client = RecordingAttendanceClient()
        let teams = try attendanceFixtureTeams()
        let selected = makeGameDetail(
            id: UUID(uuidString: "F6EE5DCB-0912-47CA-BD8A-737EA4CEA3F9")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: teams.lg,
            homeTeam: teams.doosan,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let other = makeGameDetail(
            id: UUID(uuidString: "2BB85FB1-EE5F-4748-93C0-17D38BC3F492")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "대구",
            awayTeam: teams.samsung,
            homeTeam: teams.lotte,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let games = [selected, other]
        let model = AppModel(
            attendanceClient: client,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: games, notifications: [], settings: .default),
            usePersistedSettings: false
        )

        model.toggleGameAttendance(for: selected)
        #expect(model.isGameAttended(selected) == false)
        #expect(model.isGameAttended(other) == false)

        let confirmed = await eventually(timeout: 1) {
            let requests = await client.setRequests()
            return requests.isEmpty == false && model.isGameAttended(selected)
        }
        #expect(confirmed)
        #expect(model.attendedGameIDs == [selected.id])
        let requests = await client.setRequests()
        let request = try #require(requests.first)
        #expect(request.isAttended)
        #expect(request.gameID == selected.id)
    }

    // attendanceToggleFailureRollsBackOnlySelectedDatabaseGameID 메서드는 체크 실패 시 선택 경기만 롤백되는지 검증합니다.
    @Test func attendanceToggleFailureRollsBackOnlySelectedDatabaseGameID() async throws {
        let client = RecordingAttendanceClient(setError: AttendanceClientError.httpStatus(404))
        let teams = try attendanceFixtureTeams()
        let selected = makeGameDetail(
            id: UUID(uuidString: "F6EE5DCB-0912-47CA-BD8A-737EA4CEA3F9")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: teams.lg,
            homeTeam: teams.doosan,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let other = makeGameDetail(
            id: UUID(uuidString: "2BB85FB1-EE5F-4748-93C0-17D38BC3F492")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "대구",
            awayTeam: teams.samsung,
            homeTeam: teams.lotte,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let games = [selected, other]
        let model = AppModel(
            attendanceClient: client,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: games, notifications: [], settings: .default),
            usePersistedSettings: false
        )

        model.replaceAttendedGameIDsForTesting([other.id])
        model.toggleGameAttendance(for: selected)
        #expect(model.isGameAttended(selected) == false)
        #expect(model.isGameAttended(other))

        let rolledBack = await eventually(timeout: 1) {
            model.isGameAttended(selected) == false && model.isGameAttended(other)
        }
        #expect(rolledBack)
        #expect(model.attendedGameIDs == [other.id])
    }

    // gameDetailAttendanceButtonUsesSharedAttendanceState 메서드는 상세 버튼 selected 상태가 shared DB UUID 상태를 보는지 검증합니다.
    @Test func gameDetailAttendanceButtonUsesSharedAttendanceState() throws {
        let teams = try attendanceFixtureTeams()
        let game = makeGameDetail(
            id: UUID(uuidString: "F6EE5DCB-0912-47CA-BD8A-737EA4CEA3F9")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: teams.lg,
            homeTeam: teams.doosan,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let bootstrap = KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default)
        let model = AppModel(
            bootstrap: bootstrap,
            usePersistedSettings: false
        )

        model.replaceAttendedGameIDsForTesting([game.id])

        #expect(model.isGameDetailAttended(game))
    }

    // gameDetailAttendanceStateSurvivesDetailReentry 메서드는 상세 재생성 후에도 shared state 기준 selected가 유지되는지 검증합니다.
    @Test func gameDetailAttendanceStateSurvivesDetailReentry() async throws {
        let client = RecordingAttendanceClient()
        let teams = try attendanceFixtureTeams()
        let game = makeGameDetail(
            id: UUID(uuidString: "F6EE5DCB-0912-47CA-BD8A-737EA4CEA3F9")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: teams.lg,
            homeTeam: teams.doosan,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let recreatedDetailGame = game
        let bootstrap = KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default)
        let model = AppModel(
            attendanceClient: client,
            bootstrap: bootstrap,
            usePersistedSettings: false
        )

        model.toggleGameDetailAttendance(for: game)
        let confirmed = await eventually(timeout: 1) {
            model.isGameDetailAttended(recreatedDetailGame)
        }

        #expect(confirmed)
        #expect(model.isGameDetailAttended(recreatedDetailGame))
        #expect(model.attendedGameIDs == [game.id])
    }

    // attendanceNoOpSetDoesNotConfirmLocalDetailState 메서드는 서버 sync skip이 로컬 직관 상태를 확정하지 않도록 검증합니다.
    @Test func attendanceNoOpSetDoesNotConfirmLocalDetailState() async throws {
        let teams = try attendanceFixtureTeams()
        let game = makeGameDetail(
            id: UUID(uuidString: "F6EE5DCB-0912-47CA-BD8A-737EA4CEA3F9")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: teams.lg,
            homeTeam: teams.doosan,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let bootstrap = KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default)
        let model = AppModel(
            attendanceClient: NoOpAttendanceClient(),
            bootstrap: bootstrap,
            usePersistedSettings: false
        )

        model.toggleGameDetailAttendance(for: game)
        await model.refreshAttendanceRecordsFromServer()

        #expect(model.isGameDetailAttended(game) == false)
        #expect(model.attendedGameIDs.isEmpty)
        #expect(model.isAttendanceSyncAvailable == false)
    }

    // attendanceUnconfiguredDisablesRepeatedListSync 메서드는 baseURL 누락 시 목록 sync가 반복 요청되지 않도록 검증합니다.
    @Test func attendanceUnconfiguredDisablesRepeatedListSync() async throws {
        let client = RecordingAttendanceClient(fetchError: .unconfigured)
        let model = AppModel(
            attendanceClient: client,
            bootstrap: MockKBOData.makeBootstrap(),
            usePersistedSettings: false
        )

        await model.refreshAttendanceRecordsFromServer()
        await model.refreshAttendanceRecordsFromServer()

        #expect(await client.fetchCount() == 1)
        #expect(model.attendedGameIDs.isEmpty)
    }

    // attendanceServerListReplacesConfirmedIDsWithCanonicalKeys 메서드는 서버 4건 응답이 canonical key 4건으로 반영되는지 검증합니다.
    @Test func attendanceServerListReplacesConfirmedIDsWithCanonicalKeys() async throws {
        let gameIDs: Set<UUID> = [
            UUID(uuidString: "384cc6a7-af84-4658-b054-afea45637922")!,
            UUID(uuidString: "f6ee5dcb-0912-47ca-bd8a-737ea4cea3f9")!,
            UUID(uuidString: "2bb85fb1-ee5f-4748-93c0-17d38bc3f492")!,
            UUID(uuidString: "6b1ef981-021c-4f41-9e65-31e25f7095ee")!
        ]
        let client = RecordingAttendanceClient(fetchedGameIDs: gameIDs)
        let model = AppModel(
            attendanceClient: client,
            bootstrap: MockKBOData.makeBootstrap(),
            usePersistedSettings: false
        )

        await model.refreshAttendanceRecordsFromServer()

        #expect(await client.fetchCount() == 1)
        #expect(model.attendedGameIDs == gameIDs)
        #expect(model.attendedGameKeys == Set(gameIDs.map { "id:\($0.uuidString.lowercased())" }))
    }

    // attendanceUnconfiguredDisablesRepeatedMarkRequests 메서드는 저장 설정 오류 후 같은 action 요청을 반복하지 않는지 검증합니다.
    @Test func attendanceUnconfiguredDisablesRepeatedMarkRequests() async throws {
        let client = RecordingAttendanceClient(setError: .unconfigured)
        let teams = try attendanceFixtureTeams()
        let game = makeGameDetail(
            id: UUID(uuidString: "F6EE5DCB-0912-47CA-BD8A-737EA4CEA3F9")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: teams.lg,
            homeTeam: teams.doosan,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming
        )
        let model = AppModel(
            attendanceClient: client,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [game], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        model.toggleGameDetailAttendance(for: game)
        _ = await eventually(timeout: 1) {
            await client.setRequests().count == 1
        }
        model.toggleGameDetailAttendance(for: game)

        #expect(await client.setRequests().count == 1)
        #expect(model.attendedGameIDs.isEmpty)
    }

    // gameDetailAttendanceResolvesKnownDatabaseID 메서드는 detail snapshot id가 달라도 public/provider identity로 DB UUID를 API에 전달하는지 검증합니다.
    @Test func gameDetailAttendanceResolvesKnownDatabaseID() async throws {
        let client = RecordingAttendanceClient()
        let teams = try attendanceFixtureTeams()
        let databaseGameID = UUID(uuidString: "F6EE5DCB-0912-47CA-BD8A-737EA4CEA3F9")!
        let providerGeneratedID = UUID(uuidString: "B59894BF-49CD-5BCB-9367-580C974982C7")!
        let storedGame = makeGameDetail(
            id: providerGeneratedID,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: teams.lg,
            homeTeam: teams.doosan,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            note: "supabase_game_id=\(databaseGameID.uuidString) public_game_id=20260705-LG-DOO provider_game_id=20260705LGDO0",
            providerGameID: "20260705LGDO0"
        )
        let detailSnapshot = makeGameDetail(
            id: providerGeneratedID,
            scheduledStart: storedGame.scheduledStart,
            venue: storedGame.venue,
            awayTeam: storedGame.awayTeam,
            homeTeam: storedGame.homeTeam,
            awayScore: storedGame.awayScore,
            homeScore: storedGame.homeScore,
            status: storedGame.status,
            seasonClassification: storedGame.seasonClassification,
            note: "public_game_id=20260705-LG-DOO provider_game_id=20260705LGDO0",
            providerGameID: storedGame.providerGameID
        )
        let model = AppModel(
            attendanceClient: client,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [storedGame], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        model.toggleGameDetailAttendance(for: detailSnapshot)
        let recorded = await eventually(timeout: 1) {
            let requests = await client.setRequests()
            return requests.isEmpty == false
        }

        #expect(recorded)
        #expect(model.attendanceGameID(for: detailSnapshot) == databaseGameID)
        let request = try #require(await client.setRequests().first)
        #expect(request.gameID == databaseGameID)
        #expect(request.gameID != providerGeneratedID)
        #expect(model.attendedGameIDs == [databaseGameID])
        #expect(model.isGameDetailAttended(detailSnapshot))
    }

    // attendanceGeneratedUUIDIsNotSentToAPI 메서드는 provider/generated UUID만 있는 경우 Attendance API 요청을 차단하는지 검증합니다.
    @Test func attendanceGeneratedUUIDIsNotSentToAPI() async throws {
        let client = RecordingAttendanceClient()
        let teams = try attendanceFixtureTeams()
        let generatedGame = makeGameDetail(
            id: UUID(uuidString: "B59894BF-49CD-5BCB-9367-580C974982C7")!,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: teams.lg,
            homeTeam: teams.doosan,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            providerGameID: "20260705LGDO0"
        )
        let model = AppModel(
            attendanceClient: client,
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [generatedGame], notifications: [], settings: .default),
            usePersistedSettings: false
        )

        model.toggleGameAttendance(for: generatedGame)

        let noRequest = await eventually(timeout: 0.3) {
            await client.setRequests().isEmpty
        }
        #expect(noRequest)
        #expect(model.attendedGameIDs.isEmpty)
    }

    // schedulePresentationShowsAttendanceMarkerForServerGameId 메서드는 서버 UUID 직관 키가 일정 마커에 반영되는지 검증합니다.
    @Test func schedulePresentationShowsAttendanceMarkerForServerGameId() async throws {
        let selectedDate = isoDate("2026-07-05T18:00:00+09:00")
        let gameID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first { $0.id == "hanwha" })
        let homeTeam = try #require(teams.first { $0.id == "lg" })
        let game = makeGameDetail(
            id: gameID,
            scheduledStart: selectedDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260705-LG-HAN"
        )
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 7)
        let entry = await ScheduleMonthCacheEntry.build(key: monthKey, games: [game])

        let presentation = await SchedulePresentation.build(
            displayedMonth: selectedDate,
            selectedDate: selectedDate,
            filter: .all,
            favoriteTeamID: nil,
            attendedGameKeys: [GameIdentifier.idKey(gameID)],
            cachedMonthEntries: [monthKey.yearMonthText: entry],
            failedMonthKeys: [],
            currentDate: selectedDate
        )

        let attendedDay = try #require(presentation.calendarDays.first {
            SchedulePresentation.dayKey(for: $0.date) == "2026-07-05"
        })
        #expect(attendedDay.hasAttendedGame)
        #expect(presentation.selectedDateGames.first?.id == gameID)
    }

    // attendanceCanonicalKeyMatchesLowercaseServerAndUppercaseAppUUIDs 메서드는 UUID 대소문자 차이를 제거합니다.
    @Test func attendanceCanonicalKeyMatchesLowercaseServerAndUppercaseAppUUIDs() throws {
        let lowercaseServerID = "384cc6a7-af84-4658-b054-afea45637922"
        let uppercaseAppID = "384CC6A7-AF84-4658-B054-AFEA45637922"

        #expect(GameIdentifier.attendanceCanonicalKey(from: lowercaseServerID) == "id:\(lowercaseServerID)")
        #expect(GameIdentifier.attendanceCanonicalKey(from: uppercaseAppID) == "id:\(lowercaseServerID)")
        #expect(GameIdentifier.attendanceCanonicalKey(from: "id:\(uppercaseAppID)") == "id:\(lowercaseServerID)")
    }

    // schedulePresentationMatchesFourLowercaseAttendanceIDsAgainstSupabaseGameNotes 메서드는 월간 일정 110건 중 서버 직관 4건이 모두 마커로 잡히는지 검증합니다.
    @Test func schedulePresentationMatchesFourLowercaseAttendanceIDsAgainstSupabaseGameNotes() async throws {
        let teams = try attendanceFixtureTeams()
        let attendedDatabaseIDs = [
            UUID(uuidString: "384cc6a7-af84-4658-b054-afea45637922")!,
            UUID(uuidString: "f6ee5dcb-0912-47ca-bd8a-737ea4cea3f9")!,
            UUID(uuidString: "2bb85fb1-ee5f-4748-93c0-17d38bc3f492")!,
            UUID(uuidString: "6b1ef981-021c-4f41-9e65-31e25f7095ee")!
        ]
        let games = (0..<110).map { index in
            let isAttendedFixture = index < attendedDatabaseIDs.count
            let localID = UUID(uuidString: String(format: "11111111-1111-4111-8111-%012d", index + 1))!
            let databaseID = isAttendedFixture ? attendedDatabaseIDs[index] : localID
            return makeGameDetail(
                id: localID,
                scheduledStart: isoDate(String(format: "2026-07-%02dT18:30:00+09:00", (index % 28) + 1)),
                venue: "잠실",
                awayTeam: index.isMultiple(of: 2) ? teams.doosan : teams.samsung,
                homeTeam: teams.lg,
                awayScore: nil,
                homeScore: nil,
                status: .upcoming,
                seasonClassification: .regularSeason,
                note: "supabase_game_id=\(databaseID.uuidString) public_game_id=202607\(String(format: "%02d", (index % 28) + 1))-LG-\(index)"
            )
        }
        let selectedDate = isoDate("2026-07-01T18:30:00+09:00")
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 7)
        let entry = await ScheduleMonthCacheEntry.build(key: monthKey, games: games)
        let lowercaseServerKeys = Set(attendedDatabaseIDs.map { $0.uuidString.lowercased() })

        let presentation = await SchedulePresentation.build(
            displayedMonth: selectedDate,
            selectedDate: selectedDate,
            filter: .all,
            favoriteTeamID: nil,
            attendedGameKeys: lowercaseServerKeys,
            cachedMonthEntries: [monthKey.yearMonthText: entry],
            failedMonthKeys: [],
            currentDate: selectedDate
        )

        let markedDays = presentation.calendarDays.filter(\.hasAttendedGame)
        #expect(entry.games.count == 110)
        #expect(markedDays.count == 4)
    }

    // scheduleRowsMarkOnlyGamesWhoseDatabaseIDIsAttended 메서드는 일정 row 직관 마커 조건이 DB UUID 하나에만 켜지는지 검증합니다.
    @Test func scheduleRowsMarkOnlyGamesWhoseDatabaseIDIsAttended() throws {
        let bootstrap = MockKBOData.makeBootstrap()
        let games = Array(bootstrap.games.prefix(5))
        #expect(games.count == 5)
        let attendedGame = try #require(games.dropFirst(2).first)
        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: bootstrap.teams,
                games: games,
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false
        )

        model.replaceAttendedGameIDsForTesting([attendedGame.id])
        #expect(games.filter { model.isGameAttended($0) }.map(\.id) == [attendedGame.id])

        model.replaceAttendedGameIDsForTesting([])
        #expect(games.allSatisfy { model.isGameAttended($0) == false })

        model.replaceAttendedGameIDsForTesting([UUID()])
        #expect(games.allSatisfy { model.isGameAttended($0) == false })
    }

    // schedulePresentationIgnoresProviderAttendanceAliasForServerMarkers 메서드는 UUID가 아닌 alias가 마커를 켜지 않도록 검증합니다.
    @Test func schedulePresentationIgnoresProviderAttendanceAliasForServerMarkers() async throws {
        let selectedDate = isoDate("2026-07-05T18:00:00+09:00")
        let gameID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let teams = MockKBOData.makeBootstrap().teams
        let awayTeam = try #require(teams.first { $0.id == "hanwha" })
        let homeTeam = try #require(teams.first { $0.id == "lg" })
        let game = makeGameDetail(
            id: gameID,
            scheduledStart: selectedDate,
            venue: "잠실",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: nil,
            homeScore: nil,
            status: .upcoming,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260705-LG-HAN",
            providerGameID: "20260705LGHH0"
        )
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 7)
        let entry = await ScheduleMonthCacheEntry.build(key: monthKey, games: [game])

        let presentation = await SchedulePresentation.build(
            displayedMonth: selectedDate,
            selectedDate: selectedDate,
            filter: .all,
            favoriteTeamID: nil,
            attendedGameKeys: ["provider:20260705LGHH0"],
            cachedMonthEntries: [monthKey.yearMonthText: entry],
            failedMonthKeys: [],
            currentDate: selectedDate
        )

        let day = try #require(presentation.calendarDays.first {
            SchedulePresentation.dayKey(for: $0.date) == "2026-07-05"
        })
        #expect(day.hasAttendedGame == false)
    }

    // attendanceDashboardUsesServerGameIDs 메서드는 직관탭 목록이 서버 UUID 상태 기준으로 구성되는지 검증합니다.
    @Test func attendanceDashboardUsesServerGameIDs() throws {
        let teams = MockKBOData.makeBootstrap().teams
        let lg = try #require(teams.first { $0.id == "lg" })
        let doosan = try #require(teams.first { $0.id == "doosan" })
        let selectedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let otherID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let selected = makeGameDetail(
            id: selectedID,
            scheduledStart: isoDate("2026-07-05T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 2,
            homeScore: 5,
            status: .final,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260705-LG-DOO"
        )
        let other = makeGameDetail(
            id: otherID,
            scheduledStart: isoDate("2026-07-06T18:00:00+09:00"),
            venue: "잠실",
            awayTeam: doosan,
            homeTeam: lg,
            awayScore: 4,
            homeScore: 1,
            status: .final,
            seasonClassification: .regularSeason,
            note: "public_game_id=20260706-LG-DOO"
        )
        let model = AppModel(
            bootstrap: KBOBootstrapData(
                teams: teams,
                games: [selected, other],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false
        )

        model.replaceAttendedGameIDsForTesting([selectedID])

        #expect(model.attendanceDashboard.games.map(\.gameIdentity) == [selected.stableDetailIdentity])
    }

    // attendanceDashboardShowsAllServerConfirmedGamesBySupabaseGameID 메서드는 로컬 generated id 대신 DB UUID key로 직관탭을 구성합니다.
    @Test func attendanceDashboardShowsAllServerConfirmedGamesBySupabaseGameID() throws {
        let teams = try attendanceFixtureTeams()
        let databaseIDs = [
            UUID(uuidString: "384cc6a7-af84-4658-b054-afea45637922")!,
            UUID(uuidString: "f6ee5dcb-0912-47ca-bd8a-737ea4cea3f9")!,
            UUID(uuidString: "2bb85fb1-ee5f-4748-93c0-17d38bc3f492")!,
            UUID(uuidString: "6b1ef981-021c-4f41-9e65-31e25f7095ee")!
        ]
        let games = databaseIDs.enumerated().map { index, databaseID in
            makeGameDetail(
                id: UUID(uuidString: String(format: "22222222-2222-4222-8222-%012d", index + 1))!,
                scheduledStart: isoDate(String(format: "2026-07-%02dT18:30:00+09:00", index + 1)),
                venue: "잠실",
                awayTeam: teams.doosan,
                homeTeam: teams.lg,
                awayScore: nil,
                homeScore: nil,
                status: .upcoming,
                seasonClassification: .regularSeason,
                note: "supabase_game_id=\(databaseID.uuidString) public_game_id=2026070\(index + 1)-LG-DOO"
            )
        }
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: games, notifications: [], settings: .default),
            usePersistedSettings: false
        )
        model.settings.favoriteTeamID = "lg"

        model.replaceAttendedGameIDsForTesting(Set(databaseIDs))

        #expect(model.attendedGameKeys.count == 4)
        #expect(model.attendanceDashboard.games.count == 4)
        #expect(model.attendanceDashboard.upcomingGames.count == 4)
    }

    // attendanceDashboardUsesScheduleTabMonthCacheForAllConfirmedGames 메서드는 직관탭이 일정탭 월간 캐시 110건에서 4건을 모두 찾는지 검증합니다.
    @Test func attendanceDashboardUsesScheduleTabMonthCacheForAllConfirmedGames() throws {
        let teams = try attendanceFixtureTeams()
        let databaseIDs = [
            UUID(uuidString: "6e352a5f-f0a4-452e-8b62-a97b53aecef1")!,
            UUID(uuidString: "d8be45a1-1517-4686-b9a6-40d61d05d685")!,
            UUID(uuidString: "f6ee5dcb-0912-47ca-bd8a-737ea4cea3f9")!,
            UUID(uuidString: "384cc6a7-af84-4658-b054-afea45637922")!
        ]
        let monthGames = (0..<110).map { index in
            let localID = UUID(uuidString: String(format: "33333333-3333-4333-8333-%012d", index + 1))!
            let databaseID = index < databaseIDs.count ? databaseIDs[index] : localID
            let status: GameStatus = index < 2 ? .upcoming : .final
            let awayScore: Int? = status == .final ? (index == 2 ? 2 : 6) : nil
            let homeScore: Int? = status == .final ? (index == 2 ? 5 : 3) : nil
            return makeGameDetail(
                id: localID,
                scheduledStart: isoDate(String(format: "2026-07-%02dT18:30:00+09:00", (index % 28) + 1)),
                venue: "잠실",
                awayTeam: index.isMultiple(of: 2) ? teams.doosan : teams.samsung,
                homeTeam: teams.lg,
                awayScore: awayScore,
                homeScore: homeScore,
                status: status,
                seasonClassification: .regularSeason,
                note: "supabase_game_id=\(databaseID.uuidString) public_game_id=202607\(String(format: "%02d", (index % 28) + 1))-LG-\(index)"
            )
        }
        let monthKey = KBOMonthScheduleKey(year: 2026, month: 7)
        let model = AppModel(
            bootstrap: KBOBootstrapData(teams: MockKBOData.makeBootstrap().teams, games: [monthGames[0]], notifications: [], settings: .default),
            usePersistedSettings: false
        )
        model.settings.favoriteTeamID = "lg"
        model.replaceAttendedGameIDsForTesting(Set(databaseIDs))

        #expect(model.attendanceDashboard.games.count == 1)

        model.mergeScheduleTabMonthGamesForAttendance(
            monthGames,
            monthKey: monthKey,
            reason: "testScheduleTabMonth"
        )

        let dashboard = model.attendanceDashboard
        #expect(dashboard.games.count == 4)
        #expect(dashboard.upcomingGames.count == 2)
        #expect(dashboard.pastGames.count == 2)
        #expect(dashboard.overall.games == 2)
        #expect(dashboard.overall.wins == 1)
        #expect(dashboard.overall.losses == 1)
        #expect(dashboard.overall.draws == 0)
    }

    // scheduleStaleReconciliationAppFactoryUsesNoOpClient 메서드는 실행 환경에 맞는 구현체 생성을 검증합니다.
    @Test func scheduleStaleReconciliationAppFactoryUsesNoOpClient() {
        let client = ScheduleStaleGameReconciliationClientFactory.makeAppClient()

        #expect(client is NoOpScheduleStaleGameReconciliationClient)
    }

    // scheduleStaleReconciliationResolverPrefersConfiguredLANBackendURL 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleStaleReconciliationResolverPrefersConfiguredLANBackendURL() throws {
        let resolved = try #require(ScheduleStaleGameReconciliationClientFactory.resolveBaseURL(
            backendEnvironmentValue: "http://192.168.45.140:8088",
            backendBundleValue: "http://localhost:8088",
            notificationEnvironmentValue: nil,
            notificationBundleValue: nil
        ))

        #expect(resolved.source == "environment")
        #expect(resolved.url.absoluteString == "http://192.168.45.140:8088")
    }

    // scheduleStaleReconciliationResolverDerivesBackendURLFromNotificationEndpoint 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleStaleReconciliationResolverDerivesBackendURLFromNotificationEndpoint() throws {
        let resolved = try #require(ScheduleStaleGameReconciliationClientFactory.resolveBaseURL(
            backendEnvironmentValue: nil,
            backendBundleValue: "http://localhost:8088",
            notificationEnvironmentValue: "http://192.168.45.140:8088/devices/register",
            notificationBundleValue: nil
        ))

        #expect(resolved.source == "notificationEnvironment")
        #expect(resolved.url.absoluteString == "http://192.168.45.140:8088/")
    }

    // scheduleStaleReconciliationResolverUsesLocalhostFallbackOnlyWithoutConfiguration 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleStaleReconciliationResolverUsesLocalhostFallbackOnlyWithoutConfiguration() throws {
        let resolved = try #require(ScheduleStaleGameReconciliationClientFactory.resolveBaseURL(
            backendEnvironmentValue: nil,
            backendBundleValue: nil,
            notificationEnvironmentValue: nil,
            notificationBundleValue: nil
        ))

        #expect(resolved.source == "developmentFallback")
        #expect(resolved.url.absoluteString == "http://localhost:8088")
    }

    // scheduleStatusMessageExplicitlyShowsMissingLiveConfiguration 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleStatusMessageExplicitlyShowsMissingLiveConfiguration() async throws {
        let referenceDate = isoDate("2026-03-12T09:00:00+09:00")
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

    // scheduleDebugSummaryReflectsLiveMonthlyScheduleSource 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    @Test func scheduleDebugSummaryReflectsLiveMonthlyScheduleSource() async throws {
        let referenceDate = isoDate("2026-03-12T09:00:00+09:00")
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

    // scheduleCalendarUsesBackendMonthResponseShapeAndProducesDayMarkers 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

        let referenceDate = isoDate("2026-03-01T00:00:00+09:00")
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

    // repositoryFactoryWithoutSupabaseConfigKeepsExistingRuntimeDefaults 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseMapperDecodesRowsIntoExistingGameModels 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseMapperTreatsValidKBOGameDateAsRegularSeasonWithoutNumericProviderGameID 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseMapperPreservesExplicitPreseasonMarker 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseMapperPreservesExplicitPostseasonMarker 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseTeamRowDecodesLegacyTeamCodeColumn 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // standingsContentStateSelectsExpectedDisplayBranch 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsContentStateSelectsExpectedDisplayBranch() throws {
        let team = try #require(MockKBOData.makeBootstrap().teams.first)
        let snapshot = TeamStandingsSnapshot(
            team: team,
            rank: 1,
            wins: 1,
            losses: 0,
            ties: 0,
            remainingRegularSeasonGames: 143,
            recentResults: [.win]
        )

        if case .empty = StandingsContentState.make(
            rows: [],
            isLoading: false,
            revision: 7,
            favoriteTeamID: "lg"
        ) {
        } else {
            Issue.record("Expected empty standings content state")
        }

        if case .loading = StandingsContentState.make(
            rows: [],
            isLoading: true,
            revision: 7,
            favoriteTeamID: "lg"
        ) {
        } else {
            Issue.record("Expected loading standings content state")
        }

        if case let .table(rows, revision, favoriteTeamID) = StandingsContentState.make(
            rows: [snapshot],
            isLoading: true,
            revision: 7,
            favoriteTeamID: "lg"
        ) {
            #expect(rows == [snapshot])
            #expect(revision == 7)
            #expect(favoriteTeamID == "lg")
        } else {
            Issue.record("Expected table standings content state")
        }
    }

    // standingsTabRendersLocalTeamRankRowsImmediately 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // standingsTabUsesCachedRankRowsWithoutStandingsSourceFetch 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsTabUsesCachedRankRowsWithoutStandingsSourceFetch() async throws {
        let fixture = try makeStandingsMovementFixture()
        let staleRankRows = sampleTeamRankRows(
            teams: fixture.teams,
            ranks: [
                fixture.leader.id: 1,
                fixture.falling.id: 2,
                fixture.rising.id: 3
            ]
        )
        let state = TeamRankFlowState(localRanks: staleRankRows, standingsGames: fixture.games)
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: fixture.teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-25T09:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()

        let risingSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.rising.id })
        let fallingSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.falling.id })

        #expect(await state.standingsSourceFetchCount == 0)
        #expect(model.standingsSnapshots.map(\.team.id) == [
            fixture.leader.id,
            fixture.falling.id,
            fixture.rising.id
        ])
        #expect(risingSnapshot.rankMovement == .unchanged)
        #expect(risingSnapshot.rankMovement.displayText == "-")
        #expect(fallingSnapshot.rankMovement == .unchanged)
        #expect(fallingSnapshot.rankMovement.displayText == "-")
    }

    // cachedRankRowsDoNotStartBackgroundStandingsSourceLoad 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func cachedRankRowsDoNotStartBackgroundStandingsSourceLoad() async throws {
        let fixture = try makeDoosanSSGStandingsMovementFixture()
        let currentRanks = currentStandingsRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRanks: fixture.previousRanks
        )
        let state = TeamRankFlowState(
            localRanks: sampleTeamRankRows(teams: fixture.teams, ranks: currentRanks),
            standingsGames: fixture.games
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: fixture.teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-28T09:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()

        let doosanSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.rising.id })
        let ssgSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.falling.id })
        #expect(fixture.games.count == 245)
        #expect(await state.standingsSourceFetchCount == 0)
        #expect(doosanSnapshot.rankMovement == RankingMovement.unchanged)
        #expect(doosanSnapshot.rankMovement.displayText == "-")
        #expect(ssgSnapshot.rankMovement == RankingMovement.unchanged)
    }

    // cachedRankRowsDoNotChangeRevisionFromBackgroundSourceArrival 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func cachedRankRowsDoNotChangeRevisionFromBackgroundSourceArrival() async throws {
        let fixture = try makeDoosanSSGStandingsMovementFixture()
        let currentRanks = currentStandingsRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRanks: fixture.previousRanks
        )
        let state = TeamRankFlowState(
            localRanks: sampleTeamRankRows(teams: fixture.teams, ranks: currentRanks),
            standingsGames: fixture.games
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: fixture.teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-28T09:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()
        let revisionAfterLoad = model.standingsRowsRevision
        await model.prefetchStandingsSourceIfNeeded()

        let doosanSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.rising.id })
        let ssgSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.falling.id })
        #expect(await state.standingsSourceFetchCount == 0)
        #expect(model.standingsRowsRevision == revisionAfterLoad)
        #expect(model.standingsSnapshots.filter { $0.rankMovement != .unchanged }.isEmpty)
        #expect(doosanSnapshot.rankMovement.displayText == "-")
        #expect(ssgSnapshot.rankMovement.displayText == "-")
    }

    // repeatedStandingsAppearDoesNotStartStandingsSourceFetch 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func repeatedStandingsAppearDoesNotStartStandingsSourceFetch() async throws {
        let fixture = try makeDoosanSSGStandingsMovementFixture()
        let currentRanks = currentStandingsRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRanks: fixture.previousRanks
        )
        let state = TeamRankFlowState(
            localRanks: sampleTeamRankRows(teams: fixture.teams, ranks: currentRanks),
            standingsGames: fixture.games
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: fixture.teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-28T09:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()
        let revisionAfterFirstLoad = model.standingsRowsRevision
        await model.loadStandingsIfNeeded()

        let doosanSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.rising.id })
        #expect(await state.standingsSourceFetchCount == 0)
        #expect(model.standingsRowsRevision == revisionAfterFirstLoad)
        #expect(doosanSnapshot.rankMovement == RankingMovement.unchanged)
    }

    // manualStandingsRefreshUsesRemoteRankRowsWithoutSourceGames 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func manualStandingsRefreshUsesRemoteRankRowsWithoutSourceGames() async throws {
        let fixture = try makeDoosanSSGStandingsMovementFixture()
        let currentRanks = currentStandingsRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRanks: fixture.previousRanks
        )
        let rankRows = sampleTeamRankRows(teams: fixture.teams, ranks: currentRanks)
        let state = TeamRankFlowState(
            localRanks: rankRows,
            remoteRanks: rankRows,
            standingsGames: fixture.games
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: fixture.teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-28T09:00:00+09:00") }
        )

        await model.loadStandingsIfNeeded()
        await model.refreshStandings()

        let doosanSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.rising.id })
        let ssgSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.falling.id })
        #expect(await state.remoteFetchCount == 1)
        #expect(await state.standingsSourceFetchCount == 0)
        #expect(doosanSnapshot.rankMovement == RankingMovement.unchanged)
        #expect(ssgSnapshot.rankMovement == RankingMovement.unchanged)
    }

    // launchDoesNotPrefetchStandingsSourceWhenRankRowsExist 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func launchDoesNotPrefetchStandingsSourceWhenRankRowsExist() async throws {
        let fixture = try makeDoosanSSGStandingsMovementFixture()
        let state = TeamRankFlowState(
            localRanks: sampleTeamRankRows(
                teams: fixture.teams,
                ranks: currentStandingsRanks(
                    teams: fixture.teams,
                    games: fixture.games,
                    previousRanks: fixture.previousRanks
                )
            ),
            standingsGames: fixture.games
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: fixture.teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-28T09:00:00+09:00") }
        )

        await model.loadIfNeeded()
        await model.loadStandingsIfNeeded()

        let revisionAfterRankRows = model.standingsRowsRevision
        let doosanRankRow = try #require(model.standingsSnapshots.first { $0.team.id == fixture.rising.id })
        let ssgRankRow = try #require(model.standingsSnapshots.first { $0.team.id == fixture.falling.id })
        #expect(await state.standingsSourceFetchCount == 0)
        #expect(doosanRankRow.rankMovement == RankingMovement.unchanged)
        #expect(ssgRankRow.rankMovement == RankingMovement.unchanged)

        await model.loadStandingsIfNeeded()

        let doosanAfterAppear = try #require(model.standingsSnapshots.first { $0.team.id == fixture.rising.id })
        #expect(await state.standingsSourceFetchCount == 0)
        #expect(model.standingsRowsRevision == revisionAfterRankRows)
        #expect(doosanAfterAppear.rankMovement.displayText == "-")
    }

    // standingsAppearDoesNotJoinLaunchStandingsSourcePrefetch 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func standingsAppearDoesNotJoinLaunchStandingsSourcePrefetch() async throws {
        let fixture = try makeDoosanSSGStandingsMovementFixture()
        let currentRanks = currentStandingsRanks(
            teams: fixture.teams,
            games: fixture.games,
            previousRanks: fixture.previousRanks
        )
        let state = TeamRankFlowState(
            localRanks: sampleTeamRankRows(teams: fixture.teams, ranks: currentRanks),
            standingsGames: fixture.games
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: fixture.teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-28T09:00:00+09:00") }
        )

        await model.loadIfNeeded()
        await model.loadStandingsIfNeeded()

        let doosanSnapshot = try #require(model.standingsSnapshots.first { $0.team.id == fixture.rising.id })
        #expect(await state.standingsSourceFetchCount == 0)
        #expect(doosanSnapshot.rankMovement == RankingMovement.unchanged)
    }

    // rankRowsDoNotUseStandingsSourceOrGeneralGamesFallback 메서드는 이 타입의 주요 동작을 수행합니다.
    @Test func rankRowsDoNotUseStandingsSourceOrGeneralGamesFallback() async throws {
        let fixture = try makeDoosanSSGStandingsMovementFixture()
        let state = TeamRankFlowState(
            localRanks: sampleTeamRankRows(
                teams: fixture.teams,
                ranks: currentStandingsRanks(
                    teams: fixture.teams,
                    games: fixture.games,
                    previousRanks: fixture.previousRanks
                )
            ),
            standingsGames: fixture.games
        )
        let repository = TeamRankFlowRepository(state: state)
        let model = AppModel(
            repository: repository,
            bootstrap: KBOBootstrapData(
                teams: fixture.teams,
                games: [],
                notifications: [],
                settings: .default
            ),
            usePersistedSettings: false,
            currentDateProvider: { isoDate("2026-05-28T09:00:00+09:00") }
        )

        await model.loadIfNeeded()
        await model.loadStandingsIfNeeded()

        #expect(await state.standingsSourceFetchCount == 0)
        #expect(await state.generalGamesFetchCount == 0)
    }

    // standingsTabAutoFetchesTeamRankViewWhenLocalRankCacheIsEmpty 메서드는 이 타입의 주요 동작을 수행합니다.
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
        #expect(await state.standingsSourceFetchCount == 0)
        #expect(await state.cachedRanksCount == 2)
        #expect(model.standingsSnapshots.map(\.rank).prefix(2) == [1, 2])
    }

    // simultaneousStandingsBootstrapCoalescesTeamRankRemoteFetch 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // manualStandingsRefreshFetchesTeamRankViewAndUpdatesLocalCache 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // standingsAreNotClearedWhileTeamRankRefreshIsRunning 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // emptyTeamRankViewFallsBackToGamesBasedStandingsCalculation 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // teamRankFetchFailureWithEmptyLocalCacheFallsBackToGamesBasedStandingsCalculation 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // teamRankFetchFailureKeepsExistingLocalRanksVisible 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseSnakeCaseColumnsDecodeIntoTeamRankRow 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // teamRankRowsRenderSortedByRankAscending 메서드는 이 타입의 주요 동작을 수행합니다.
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

// sampleTeamRankRows 메서드는 이 타입의 주요 동작을 수행합니다.
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

// sampleTeamRankRows 메서드는 이 타입의 주요 동작을 수행합니다.
private func sampleTeamRankRows(teams: [Team], ranks: [String: Int]) -> [TeamRankRow] {
    teams
        .compactMap { team -> TeamRankRow? in
            guard let rank = ranks[team.id] else { return nil }
            return TeamRankRow(
                season: 2026,
                teamID: UUID(uuidString: String(format: "11111111-1111-1111-1111-%012d", rank))!,
                teamCode: team.id,
                rank: rank,
                teamName: team.name,
                gamesPlayed: 40,
                wins: max(0, 30 - rank),
                losses: 10 + rank,
                draws: 0,
                winningPercentage: Double(30 - rank) / 40.0,
                gamesBehind: Double(rank - 1),
                streakType: "WIN",
                streakCount: 1,
                streakText: "1승"
            )
        }
        .sorted { $0.rank < $1.rank }
}

private actor RankFetchGate {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var didRelease = false

    // wait 메서드는 이 타입의 주요 동작을 수행합니다.
    func wait() async {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil
        guard didRelease == false else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    // waitUntilStarted 메서드는 이 타입의 주요 동작을 수행합니다.
    func waitUntilStarted() async {
        guard didStart == false else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    // release 메서드는 이 타입의 주요 동작을 수행합니다.
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
    private let standingsSourceGate: RankFetchGate?
    private let standingsGames: [GameDetail]
    private(set) var remoteFetchCount = 0
    private(set) var localReplaceCount = 0
    private(set) var standingsSourceFetchCount = 0
    private(set) var generalGamesFetchCount = 0

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        localRanks: [TeamRankRow],
        remoteRanks: [TeamRankRow] = [],
        remoteError: (any Error)? = nil,
        gate: RankFetchGate? = nil,
        standingsSourceGate: RankFetchGate? = nil,
        standingsGames: [GameDetail] = []
    ) {
        self.localRanks = localRanks
        self.remoteRanks = remoteRanks
        self.remoteError = remoteError
        self.gate = gate
        self.standingsSourceGate = standingsSourceGate
        self.standingsGames = standingsGames
    }

    var cachedRanksCount: Int {
        localRanks.count
    }

    // fetchLocalRanks 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetchLocalRanks(season: Int) -> [TeamRankRow] {
        localRanks.filter { $0.season == season }.sorted { $0.rank < $1.rank }
    }

    // replaceLocalRanks 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func replaceLocalRanks(_ ranks: [TeamRankRow], season: Int) -> Int {
        localRanks.removeAll { $0.season == season }
        localRanks.append(contentsOf: ranks)
        localReplaceCount += 1
        return ranks.count
    }

    // fetchRemoteRanks 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // fetchStandingsSource 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetchStandingsSource(season: Int) async -> [GameDetail] {
        standingsSourceFetchCount += 1
        if let standingsSourceGate {
            await standingsSourceGate.wait()
        }
        return standingsGames
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetchGames() -> [GameDetail] {
        generalGamesFetchCount += 1
        return []
    }
}

// TeamRankFlowRepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
private struct TeamRankFlowRepository: KBORepository, KBOTeamRankDataSource, KBOLocalTeamRankCacheDataSource, KBOLocalTeamRankCacheUpserting, KBOStandingsGameDataSource, Sendable {
    let state: TeamRankFlowState

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        MockKBOData.makeBootstrap()
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        await state.fetchGames()
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        []
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        []
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        []
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        []
    }

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        []
    }

    // fetchTeamRanks 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeamRanks(season: Int) async throws -> [TeamRankRow] {
        try await state.fetchRemoteRanks(season: season)
    }

    // fetchLocalTeamRanks 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLocalTeamRanks(season: Int) async -> [TeamRankRow] {
        await state.fetchLocalRanks(season: season)
    }

    // replaceLocalTeamRanks 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated func replaceLocalTeamRanks(_ ranks: [TeamRankRow], season: Int) async -> Int {
        await state.replaceLocalRanks(ranks, season: season)
    }

    // fetchStandingsSource 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandingsSource(season: Int) async throws -> [GameDetail] {
        await state.fetchStandingsSource(season: season)
    }
}

private actor RepositoryCallTracker {
    private(set) var bootstrapFetchCount = 0
    private(set) var monthlyScheduleFetchCount = 0

    // recordBootstrapFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordBootstrapFetch() {
        bootstrapFetchCount += 1
    }

    // recordMonthlyScheduleFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordMonthlyScheduleFetch() {
        monthlyScheduleFetchCount += 1
    }
}

// TrackingKBORepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
private struct TrackingKBORepository<Base: KBORepository>: KBORepository, Sendable {
    let base: Base
    let tracker: RepositoryCallTracker

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        await tracker.recordBootstrapFetch()
        return try await base.fetchBootstrapData()
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await base.fetchGames()
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await base.fetchNotifications()
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        await tracker.recordMonthlyScheduleFetch()
        return try await base.fetchMonthlySchedule(for: month)
    }

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }
}

// StaticSupabaseSource 구조체는 StaticSupabaseSource 타입의 역할과 값을 정의합니다.
private struct StaticSupabaseSource: SupabaseKBOReading, Sendable {
    let teamRows: [SupabaseTeamRow]
    let gameRows: [SupabaseGameRow]

    // fetchTeams 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow] {
        teamRows
    }

    // fetchGameCount 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameCount() async throws -> Int {
        gameRows.count
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [SupabaseGameRow] {
        gameRows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(excludingProviderGameIDs providerGameIDs: Set<String>) async throws -> [SupabaseGameRow] {
        gameRows.filter { row in
            guard let providerGameID = row.providerGameID else { return true }
            return providerGameIDs.contains(providerGameID) == false
        }
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow] {
        gameRows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow] {
        gameRows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(date: Date, favoriteTeamID: String) async throws -> [SupabaseGameRow] {
        gameRows
    }

    // fetchGamesForStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGamesForStandings(season: Int) async throws -> [SupabaseGameRow] {
        gameRows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow] {
        gameRows
    }

    // fetchGame 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // fetchLatestSnapshots 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLatestSnapshots(gameIDs: [UUID]) async throws -> [SupabaseLatestGameSnapshotRow] {
        []
    }

    // fetchLatestSnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLatestSnapshot(gameID: UUID) async throws -> SupabaseLatestGameSnapshotRow? {
        nil
    }
}

private actor DetailFetchTracker {
    private(set) var singleLookups: [SupabaseGameLookup] = []
    private(set) var dateFetches = 0
    private(set) var teamFetches = 0
    private(set) var latestSnapshotGameIDs: [UUID] = []
    private(set) var batterRecordGameIDs: [UUID] = []
    private(set) var pitcherRecordGameIDs: [UUID] = []
    private(set) var eventRecordGameIDs: [UUID] = []

    // recordSingleLookup 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordSingleLookup(_ lookup: SupabaseGameLookup) {
        singleLookups.append(lookup)
    }

    // recordDateFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordDateFetch() {
        dateFetches += 1
    }

    // recordTeamFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordTeamFetch() {
        teamFetches += 1
    }

    // recordLatestSnapshotFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordLatestSnapshotFetch(gameID: UUID) {
        latestSnapshotGameIDs.append(gameID)
    }

    // recordBatterRecordFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordBatterRecordFetch(gameID: UUID) {
        batterRecordGameIDs.append(gameID)
    }

    // recordPitcherRecordFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordPitcherRecordFetch(gameID: UUID) {
        pitcherRecordGameIDs.append(gameID)
    }

    // recordEventRecordFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordEventRecordFetch(gameID: UUID) {
        eventRecordGameIDs.append(gameID)
    }
}

// TrackingSupabaseSource 구조체는 TrackingSupabaseSource 타입의 역할과 값을 정의합니다.
private struct TrackingSupabaseSource: SupabaseKBOReading, Sendable {
    let teamRows: [SupabaseTeamRow]
    let gameRows: [SupabaseGameRow]
    let tracker: DetailFetchTracker
    let batterRows: [SupabaseGameBatterRecordRow]
    let pitcherRows: [SupabaseGamePitcherRecordRow]
    let eventRows: [SupabaseGameEventRow]
    let latestSnapshotRows: [SupabaseLatestGameSnapshotRow]

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        teamRows: [SupabaseTeamRow],
        gameRows: [SupabaseGameRow],
        tracker: DetailFetchTracker,
        batterRows: [SupabaseGameBatterRecordRow] = [],
        pitcherRows: [SupabaseGamePitcherRecordRow] = [],
        eventRows: [SupabaseGameEventRow] = [],
        latestSnapshotRows: [SupabaseLatestGameSnapshotRow] = []
    ) {
        self.teamRows = teamRows
        self.gameRows = gameRows
        self.tracker = tracker
        self.batterRows = batterRows
        self.pitcherRows = pitcherRows
        self.eventRows = eventRows
        self.latestSnapshotRows = latestSnapshotRows
    }

    // fetchTeams 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow] {
        await tracker.recordTeamFetch()
        return teamRows
    }

    // fetchGameCount 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameCount() async throws -> Int {
        gameRows.count
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [SupabaseGameRow] {
        gameRows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(excludingProviderGameIDs providerGameIDs: Set<String>) async throws -> [SupabaseGameRow] {
        gameRows.filter { row in
            guard let providerGameID = row.providerGameID else { return true }
            return providerGameIDs.contains(providerGameID) == false
        }
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow] {
        gameRows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow] {
        await tracker.recordDateFetch()
        return gameRows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(date: Date, favoriteTeamID: String) async throws -> [SupabaseGameRow] {
        await tracker.recordDateFetch()
        return gameRows
    }

    // fetchGamesForStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGamesForStandings(season: Int) async throws -> [SupabaseGameRow] {
        gameRows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow] {
        gameRows
    }

    // fetchGame 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // fetchLatestSnapshots 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLatestSnapshots(gameIDs: [UUID]) async throws -> [SupabaseLatestGameSnapshotRow] {
        await MainActor.run {
            latestSnapshotRows.filter { gameIDs.contains($0.gameID) }
        }
    }

    // fetchLatestSnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLatestSnapshot(gameID: UUID) async throws -> SupabaseLatestGameSnapshotRow? {
        await tracker.recordLatestSnapshotFetch(gameID: gameID)
        return await MainActor.run {
            latestSnapshotRows.first { $0.gameID == gameID }
        }
    }

    // fetchGameBatterRecords 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameBatterRecords(gameID: UUID) async throws -> [SupabaseGameBatterRecordRow] {
        await tracker.recordBatterRecordFetch(gameID: gameID)
        return await MainActor.run {
            batterRows.filter { $0.gameID == gameID }
        }
    }

    // fetchGamePitcherRecords 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGamePitcherRecords(gameID: UUID) async throws -> [SupabaseGamePitcherRecordRow] {
        await tracker.recordPitcherRecordFetch(gameID: gameID)
        return await MainActor.run {
            pitcherRows.filter { $0.gameID == gameID }
        }
    }

    // fetchGameEvents 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameEvents(gameID: UUID) async throws -> [SupabaseGameEventRow] {
        await tracker.recordEventRecordFetch(gameID: gameID)
        return await MainActor.run {
            eventRows.filter { $0.gameID == gameID }
        }
    }
}

private actor ScheduleSyncTestTracker {
    private(set) var remoteCountChecks = 0
    private(set) var missingFetches = 0
    private(set) var monthlyScheduleFetches = 0
    private(set) var dailyScheduleFetches = 0

    // recordRemoteCountCheck 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordRemoteCountCheck() {
        remoteCountChecks += 1
    }

    // recordMissingFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordMissingFetch() {
        missingFetches += 1
    }

    // recordMonthlyScheduleFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordMonthlyScheduleFetch() {
        monthlyScheduleFetches += 1
    }

    // recordDailyScheduleFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordDailyScheduleFetch() {
        dailyScheduleFetches += 1
    }
}

private actor ScheduleTabMonthTestTracker {
    private(set) var scheduleTabMonthFetches = 0
    private(set) var monthlyScheduleFetches = 0
    private(set) var dailyScheduleFetches = 0
    private(set) var scheduleTabBypassingCacheValues: [Bool] = []

    // recordScheduleTabMonthFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordScheduleTabMonthFetch(bypassingCache: Bool) {
        scheduleTabMonthFetches += 1
        scheduleTabBypassingCacheValues.append(bypassingCache)
    }

    // recordMonthlyScheduleFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordMonthlyScheduleFetch() {
        monthlyScheduleFetches += 1
    }

    // recordDailyScheduleFetch 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordDailyScheduleFetch() {
        dailyScheduleFetches += 1
    }
}

// ScheduleTabMonthTestRepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
private struct ScheduleTabMonthTestRepository: KBORepository, KBOScheduleTabMonthDataSource, Sendable {
    let bootstrap: KBOBootstrapData
    let scheduleTabGames: [GameDetail]
    let tracker: ScheduleTabMonthTestTracker

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        bootstrap
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        bootstrap.games
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        bootstrap.notifications
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        await tracker.recordMonthlyScheduleFetch()
        return bootstrap.games.filter {
            KBOMonthScheduleKey(date: $0.scheduledStart) == month
        }
    }

    // fetchScheduleTabMonth 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchScheduleTabMonth(
        for month: KBOMonthScheduleKey,
        bypassingCache: Bool
    ) async throws -> [GameDetail] {
        await tracker.recordScheduleTabMonthFetch(bypassingCache: bypassingCache)
        return scheduleTabGames.filter {
            KBOMonthScheduleKey(date: $0.scheduledStart) == month
        }
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        await tracker.recordDailyScheduleFetch()
        let calendar = Calendar(identifier: .gregorian)
        return bootstrap.games.filter { calendar.isDate($0.scheduledStart, inSameDayAs: date) }
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache _: Bool) async throws -> [GameDetail] {
        try await fetchSchedule(for: date)
    }

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        []
    }
}

// ScheduleSyncTestRepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
private struct ScheduleSyncTestRepository: KBORepository, KBOScheduleRemoteSyncDataSource, Sendable {
    let bootstrap: KBOBootstrapData
    let remoteCount: Int
    let missingGames: [GameDetail]
    let todayGames: [GameDetail]
    let tracker: ScheduleSyncTestTracker

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        bootstrap
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        bootstrap.games
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        bootstrap.notifications
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        await tracker.recordMonthlyScheduleFetch()
        return bootstrap.games.filter { game in
            KBOMonthScheduleKey(date: game.scheduledStart) == month
        }
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        await tracker.recordDailyScheduleFetch()
        let calendar = Calendar(identifier: .gregorian)
        return todayGames.filter { calendar.isDate($0.scheduledStart, inSameDayAs: date) }
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await fetchSchedule(for: date)
    }

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        []
    }

    // fetchRemoteGameCount 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchRemoteGameCount() async throws -> Int {
        await tracker.recordRemoteCountCheck()
        return remoteCount
    }

    // fetchMissingScheduleGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMissingScheduleGames(excludingKnownGames knownGames: [GameDetail]) async throws -> KBOScheduleMissingGamesResult {
        await tracker.recordMissingFetch()
        let knownAliases = Set(knownGames.flatMap(\.gameIdentityAliases))
        let missing = missingGames.filter { game in
            game.gameIdentityAliases.isDisjoint(with: knownAliases)
        }
        return KBOScheduleMissingGamesResult(remoteCount: remoteCount, games: missing)
    }
}

// FailingSupabaseSource 구조체는 FailingSupabaseSource 타입의 역할과 값을 정의합니다.
private struct FailingSupabaseSource: SupabaseKBOReading, Sendable {
    private let error = TestRepositoryError.supabaseUnavailable

    // fetchTeams 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow] {
        throw error
    }

    // fetchGameCount 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameCount() async throws -> Int {
        throw error
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [SupabaseGameRow] {
        throw error
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(excludingProviderGameIDs providerGameIDs: Set<String>) async throws -> [SupabaseGameRow] {
        throw error
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow] {
        throw error
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow] {
        throw error
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(date: Date, favoriteTeamID: String) async throws -> [SupabaseGameRow] {
        throw error
    }

    // fetchGamesForStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGamesForStandings(season: Int) async throws -> [SupabaseGameRow] {
        throw error
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow] {
        throw error
    }

    // fetchGame 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGame(lookup: SupabaseGameLookup) async throws -> [SupabaseGameRow] {
        throw error
    }

    // fetchLatestSnapshots 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLatestSnapshots(gameIDs: [UUID]) async throws -> [SupabaseLatestGameSnapshotRow] {
        throw error
    }

    // fetchLatestSnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLatestSnapshot(gameID: UUID) async throws -> SupabaseLatestGameSnapshotRow? {
        throw error
    }
}

// TestRepositoryError 열거형는 실패 상황을 구분하고 호출자에게 전달합니다.
private enum TestRepositoryError: Error, Sendable {
    case supabaseUnavailable
}

private actor RecordingGameDetailSnapshotState {
    private let result: Result<GameDetail?, Error>
    private(set) var fetchCount = 0

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(result: Result<GameDetail?, Error>) {
        self.result = result
    }

    // fetch 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetch(game _: GameDetail, identity _: String, teams _: [Team]) async throws -> GameDetail? {
        fetchCount += 1
        return try result.get()
    }
}

private actor RecordingBoxscoreState {
    private let result: Result<GameBoxscoreResponse, Error>
    private(set) var fetchCount = 0
    private(set) var requestedGameIDs: [String] = []

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(result: Result<GameBoxscoreResponse, Error>) {
        self.result = result
    }

    // fetch 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetch(gameId: String) throws -> GameBoxscoreResponse {
        fetchCount += 1
        requestedGameIDs.append(gameId)
        return try result.get()
    }
}

private actor SequencedBoxscoreState {
    private var results: [Result<GameBoxscoreResponse, Error>]
    private var delays: [UInt64]
    private(set) var fetchCount = 0
    private(set) var requestedGameIDs: [String] = []

    init(results: [Result<GameBoxscoreResponse, Error>], delays: [UInt64] = []) {
        self.results = results
        self.delays = delays
    }

    func fetch(gameId: String) async throws -> GameBoxscoreResponse {
        fetchCount += 1
        requestedGameIDs.append(gameId)
        let delay = delays.isEmpty ? 0 : delays.removeFirst()
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        let result = results.isEmpty ? .failure(TestRepositoryError.supabaseUnavailable) : results.removeFirst()
        return try result.get()
    }
}

private actor RecordingGameLiveStreamState {
    let events: [GameLiveStreamEvent]
    private(set) var requestedGameIDs: [String] = []

    init(events: [GameLiveStreamEvent]) {
        self.events = events
    }

    func record(gameID: String) {
        requestedGameIDs.append(gameID)
    }
}

private struct RecordingGameLiveStreamClient: GameLiveStreaming {
    let state: RecordingGameLiveStreamState
    var cacheIdentity: String { "recording-stream" }

    nonisolated func streamGame(gameId: String) -> AsyncThrowingStream<GameLiveStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await state.record(gameID: gameId)
                for event in state.events {
                    continuation.yield(event)
                }
                while Task.isCancelled == false {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                continuation.finish(throwing: CancellationError())
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private actor RecordingOfficialFallback {
    private let result: Result<GameCenterReview?, Error>
    private let delayNanoseconds: UInt64
    private(set) var fetchCount = 0
    private(set) var requestedGameIDs: [String] = []

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(result: Result<GameCenterReview?, Error>, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    // fetch 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetch(game: GameDetail) async throws -> GameCenterReview? {
        fetchCount += 1
        requestedGameIDs.append(game.publicGameID ?? game.officialGameCenterID ?? game.id.uuidString)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }
}

private actor RecordingDetailPayloadFetcher {
    private let payload: GameCenterDetailPayload?
    private let delayNanoseconds: UInt64
    private(set) var fetchCount = 0

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(payload: GameCenterDetailPayload?, delayNanoseconds: UInt64 = 0) {
        self.payload = payload
        self.delayNanoseconds = delayNanoseconds
    }

    // fetch 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetch(game: GameDetail) async throws -> GameCenterDetailPayload? {
        fetchCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return payload
    }
}

// RecordingBoxscoreClient 구조체는 외부 서비스나 시스템 기능 호출을 캡슐화합니다.
private struct RecordingBoxscoreClient: GameBoxscoreFetching {
    let state: RecordingBoxscoreState
    var delayNanoseconds: UInt64 = 0
    var cacheIdentity: String = "recording"

    // fetchGameBoxscore 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameBoxscore(gameId: String) async throws -> GameBoxscoreResponse {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try await state.fetch(gameId: gameId)
    }
}

private struct SequencedBoxscoreClient: GameBoxscoreFetching {
    let state: SequencedBoxscoreState
    var cacheIdentity: String = "sequenced"

    nonisolated func fetchGameBoxscore(gameId: String) async throws -> GameBoxscoreResponse {
        try await state.fetch(gameId: gameId)
    }
}

private actor RecordingDatabaseReviewFetcher {
    private let review: GameCenterReview?
    private(set) var fetchCount = 0

    init(review: GameCenterReview?) {
        self.review = review
    }

    func fetch(game _: GameDetail) -> GameCenterReview? {
        fetchCount += 1
        return review
    }
}

private actor SequencedDatabaseReviewState {
    private var reviews: [GameCenterReview?]
    private var delays: [UInt64]
    private(set) var fetchCount = 0

    init(reviews: [GameCenterReview?], delays: [UInt64] = []) {
        self.reviews = reviews
        self.delays = delays
    }

    func fetch() async -> GameCenterReview? {
        fetchCount += 1
        let delay = delays.isEmpty ? 0 : delays.removeFirst()
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return reviews.isEmpty ? nil : reviews.removeFirst()
    }
}

private final class BoxscoreURLProtocolStub: URLProtocol, @unchecked Sendable {
    static var testResponses: [String: StubResponse] = [:]
    static var lastRequest: URLRequest?

    // canInit 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.port == 8088 && request.url?.path.hasSuffix("/boxscore") == true
    }

    // canonicalRequest 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    // startLoading 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // stopLoading 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    override func stopLoading() {}
}

// makeBoxscoreStubSession 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeBoxscoreStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BoxscoreURLProtocolStub.self]
    return URLSession(configuration: configuration)
}

// sampleGameBoxscoreJSON 메서드는 이 타입의 주요 동작을 수행합니다.
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
              "groundedIntoDoublePlay": 1,
              "errors": 0,
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
              "groundedIntoDoublePlay": null,
              "errors": null,
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
              "groundedIntoDoublePlay": 0,
              "errors": 1,
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

private func sampleOfficialPriorityBoxscoreResponse() -> GameBoxscoreResponse {
    GameBoxscoreResponse(
        gameId: "20260510-DOO-SSG",
        awayBatters: [
            GameBatterRecord(
                sourceOrder: 0,
                battingOrder: 1,
                position: "좌",
                playerName: "김공식",
                atBats: 25,
                runs: 2,
                hits: 6,
                rbi: 2,
                homeRuns: 0,
                walks: 1,
                strikeouts: 3,
                stolenBases: 0,
                groundedIntoDoublePlay: 0,
                errors: 0,
                battingAverage: "0.240"
            ),
            GameBatterRecord(
                sourceOrder: 1,
                battingOrder: 2,
                position: "一",
                playerName: "박기록",
                atBats: 3,
                runs: 0,
                hits: 1,
                rbi: 0,
                homeRuns: 0,
                walks: 0,
                strikeouts: 1,
                stolenBases: 0,
                groundedIntoDoublePlay: 0,
                errors: 0,
                battingAverage: "0.333"
            ),
            GameBatterRecord(
                sourceOrder: 2,
                battingOrder: nil,
                position: "타",
                playerName: "대타자",
                atBats: 0,
                runs: 0,
                hits: 0,
                rbi: 0,
                homeRuns: 0,
                walks: 0,
                strikeouts: 0,
                stolenBases: 0,
                groundedIntoDoublePlay: 0,
                errors: 0,
                battingAverage: nil
            ),
            GameBatterRecord(
                sourceOrder: 3,
                battingOrder: nil,
                position: "주",
                playerName: "대주자",
                atBats: 0,
                runs: 0,
                hits: 0,
                rbi: 0,
                homeRuns: 0,
                walks: 0,
                strikeouts: 0,
                stolenBases: 0,
                groundedIntoDoublePlay: 0,
                errors: 0,
                battingAverage: nil
            )
        ],
        homeBatters: [],
        awayPitchers: [
            GamePitcherRecord(
                sourceOrder: 0,
                pitchingOrder: 1,
                playerName: "비슬리",
                appearance: "선발",
                decisionResult: nil,
                wins: nil,
                losses: nil,
                saves: nil,
                inningsPitched: "6",
                battersFaced: 22,
                pitchCount: 81,
                atBats: 21,
                hits: 4,
                homeRuns: 0,
                walksOrHitByPitch: 1,
                strikeouts: 5,
                runs: 1,
                earnedRuns: 1,
                era: "3.00"
            ),
            GamePitcherRecord(
                sourceOrder: 1,
                pitchingOrder: 2,
                playerName: "이이무라",
                appearance: "구원",
                decisionResult: nil,
                wins: nil,
                losses: nil,
                saves: nil,
                inningsPitched: "1",
                battersFaced: 4,
                pitchCount: 14,
                atBats: 4,
                hits: 1,
                homeRuns: 0,
                walksOrHitByPitch: 0,
                strikeouts: 1,
                runs: 0,
                earnedRuns: 0,
                era: "0.00"
            )
        ],
        homePitchers: [],
        updatedAt: "2026-05-10T16:15:00+09:00",
        isStale: false
    )
}

private func liveReplacementBoxscore(
    awayBatters: [(name: String, sourceOrder: Int, battingOrder: Int?, position: String, atBats: Int)],
    awayPitchers: [(name: String, sourceOrder: Int, pitchingOrder: Int?, innings: String)]
) -> GameBoxscoreResponse {
    GameBoxscoreResponse(
        gameId: "20260510-DOO-SSG",
        awayBatters: awayBatters.map { value in
            GameBatterRecord(
                sourceOrder: value.sourceOrder,
                battingOrder: value.battingOrder,
                position: value.position,
                playerName: value.name,
                atBats: value.atBats,
                runs: 0,
                hits: value.atBats > 0 ? 1 : 0,
                rbi: 0,
                homeRuns: 0,
                walks: 0,
                strikeouts: 0,
                stolenBases: 0,
                groundedIntoDoublePlay: 0,
                errors: 0,
                battingAverage: nil
            )
        },
        homeBatters: [],
        awayPitchers: awayPitchers.map { value in
            GamePitcherRecord(
                sourceOrder: value.sourceOrder,
                pitchingOrder: value.pitchingOrder,
                playerName: value.name,
                appearance: value.pitchingOrder == 1 ? "선발" : "구원",
                decisionResult: nil,
                wins: nil,
                losses: nil,
                saves: nil,
                inningsPitched: value.innings,
                battersFaced: nil,
                pitchCount: nil,
                atBats: nil,
                hits: nil,
                homeRuns: nil,
                walksOrHitByPitch: nil,
                strikeouts: nil,
                runs: nil,
                earnedRuns: nil,
                era: nil
            )
        },
        homePitchers: [],
        updatedAt: "2026-05-10T16:20:00+09:00",
        isStale: false
    )
}

// makeBoxscoreDetailGame 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// makeLiveBoxscoreDetailGame 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeLiveBoxscoreDetailGame(
    status: GameStatus = .live,
    id: UUID = UUID(uuidString: "11111111-2222-3333-4444-555555555556")!,
    providerGameID: String = "20260510SKOB0",
    currentPitcherName: String? = nil
) throws -> GameDetail {
    let teams = MockKBOData.makeBootstrap().teams
    let doosan = try #require(teams.first(where: { $0.id == "doosan" }))
    let ssg = try #require(teams.first(where: { $0.id == "ssg" }))
    return makeGameDetail(
        id: id,
        scheduledStart: isoDate("2026-05-10T14:00:00+09:00"),
        venue: "잠실",
        awayTeam: doosan,
        homeTeam: ssg,
        awayScore: status == .upcoming || status == .cancelled ? nil : 3,
        homeScore: status == .upcoming || status == .cancelled ? nil : 1,
        status: status,
        note: "public_game_id=20260510-DOO-SSG provider_game_id=\(providerGameID)",
        providerGameID: providerGameID,
        bases: RunnerState(first: true, second: false, third: false),
        balls: 1,
        strikes: 2,
        outs: 1,
        currentPitcherName: currentPitcherName
    )
}

// SupabaseDetailedRecordFixture 구조체는 SupabaseDetailedRecordFixture 타입의 역할과 값을 정의합니다.
private struct SupabaseDetailedRecordFixture {
    let game: GameDetail
    let awayTeamID: UUID
    let homeTeamID: UUID

    // batter 메서드는 이 타입의 주요 동작을 수행합니다.
    func batter(
        name: String,
        teamID: UUID,
        sourceOrder: Int?,
        battingOrder: Int?,
        gameID: UUID? = nil,
        atBats: Int? = nil,
        runs: Int? = nil,
        hits: Int? = nil,
        rbi: Int? = nil,
        homeRuns: Int? = nil,
        walks: Int? = nil,
        strikeouts: Int? = nil,
        stolenBases: Int? = nil,
        groundedIntoDoublePlay: Int? = nil,
        errors: Int? = nil
    ) -> SupabaseGameBatterRecordRow {
        SupabaseGameBatterRecordRow(
            id: UUID(),
            gameID: gameID ?? game.id,
            teamID: teamID,
            sourceOrder: sourceOrder,
            battingOrder: battingOrder,
            position: nil,
            playerName: name,
            atBats: atBats,
            runs: runs,
            hits: hits,
            rbi: rbi,
            homeRuns: homeRuns,
            walks: walks,
            strikeouts: strikeouts,
            stolenBases: stolenBases,
            groundedIntoDoublePlay: groundedIntoDoublePlay,
            errors: errors,
            battingAverage: "0.999"
        )
    }

    // pitcher 메서드는 이 타입의 주요 동작을 수행합니다.
    func pitcher(
        name: String,
        teamID: UUID,
        sourceOrder: Int?,
        pitchingOrder: Int?,
        gameID: UUID? = nil,
        innings: String? = nil,
        pitchCount: Int? = nil,
        hits: Int? = nil,
        homeRuns: Int? = nil,
        strikeouts: Int? = nil,
        runs: Int? = nil,
        earnedRuns: Int? = nil
    ) -> SupabaseGamePitcherRecordRow {
        SupabaseGamePitcherRecordRow(
            id: UUID(),
            gameID: gameID ?? game.id,
            teamID: teamID,
            sourceOrder: sourceOrder,
            pitchingOrder: pitchingOrder,
            playerName: name,
            appearance: "선발",
            decisionResult: nil,
            wins: nil,
            losses: nil,
            saves: nil,
            inningsPitched: innings,
            battersFaced: nil,
            pitchCount: pitchCount,
            atBats: nil,
            hits: hits,
            homeRuns: homeRuns,
            walksOrHitByPitch: nil,
            strikeouts: strikeouts,
            runs: runs,
            earnedRuns: earnedRuns,
            era: "0.00"
        )
    }
}

// makeSupabaseDetailedRecordFixture 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeSupabaseDetailedRecordFixture() throws -> SupabaseDetailedRecordFixture {
    SupabaseDetailedRecordFixture(
        game: try makeLiveBoxscoreDetailGame(),
        awayTeamID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        homeTeamID: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    )
}

// makeSampleDatabaseRecordReview 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
@MainActor
private func makeSampleDatabaseRecordReview(game: GameDetail) throws -> GameCenterReview {
    let fixture = SupabaseDetailedRecordFixture(
        game: game,
        awayTeamID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        homeTeamID: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    )
    return try #require(SupabaseKBOMapper.mapDetailedRecordReview(
        game: game,
        awayTeamDatabaseID: fixture.awayTeamID,
        homeTeamDatabaseID: fixture.homeTeamID,
        batterRows: [
            fixture.batter(name: "황성빈", teamID: fixture.awayTeamID, sourceOrder: 0, battingOrder: 1, atBats: 2, strikeouts: 1),
            fixture.batter(name: "나승엽", teamID: fixture.awayTeamID, sourceOrder: 1, battingOrder: 2, walks: 1)
        ],
        pitcherRows: [
            fixture.pitcher(name: "나균안", teamID: fixture.awayTeamID, sourceOrder: 0, pitchingOrder: 1, innings: "2 1/3", pitchCount: 45, hits: 3, strikeouts: 2)
        ]
    ))
}

// makeIdentityLookupGame 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// IdentityFallbackSupabaseFixture 구조체는 IdentityFallbackSupabaseFixture 타입의 역할과 값을 정의합니다.
private struct IdentityFallbackSupabaseFixture {
    let tracker: DetailFetchTracker
    let supabaseSource: TrackingSupabaseSource
}

// makeIdentityFallbackSupabaseSource 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// supabaseTeamUUID 메서드는 이 타입의 주요 동작을 수행합니다.
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

// supabaseTeamRow 메서드는 이 타입의 주요 동작을 수행합니다.
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

// supabaseGameDate 메서드는 이 타입의 주요 동작을 수행합니다.
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

// sampleGameCenterDetailPayload 메서드는 이 타입의 주요 동작을 수행합니다.
private func sampleGameCenterDetailPayload(
    game: GameDetail,
    lineScore: GameCenterLineScore? = nil,
    review: GameCenterReview? = nil,
    baseRunners: GameCenterBaseRunners? = nil
) -> GameCenterDetailPayload {
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
            baseRunners: baseRunners,
            probableStarters: nil,
            winningPitcher: nil,
            losingPitcher: nil,
            savePitcher: nil
        ),
        lineScore: lineScore,
        review: review,
        preview: nil
    )
}

// sampleGameCenterLineScore 메서드는 이 타입의 주요 동작을 수행합니다.
private func sampleGameCenterLineScore() -> GameCenterLineScore {
    GameCenterLineScore(
        inningLabels: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"],
        awayInnings: ["0", "1", "0", "2", "-", "-", "-", "-", "-", "-", "-", "-"],
        homeInnings: ["1", "0", "0", "0", "-", "-", "-", "-", "-", "-", "-", "-"],
        awayTotals: GameCenterTeamLineTotals(runs: "3", hits: "7", errors: "0", walks: "4"),
        homeTotals: GameCenterTeamLineTotals(runs: "1", hits: "5", errors: "1", walks: "2")
    )
}

// sampleOfficialFallbackReview 메서드는 이 타입의 주요 동작을 수행합니다.
private func sampleOfficialFallbackReview() -> GameCenterReview {
    GameCenterReview(
        summaryItems: [],
        awayBatting: GameCenterBattingSection(
            lines: [
                GameCenterBattingLine(
                    battingOrder: "1",
                    position: "좌",
                    name: "공식타자",
                    atBats: "4",
                    runs: "1",
                    hits: "2",
                    runsBattedIn: "1",
                    homeRuns: nil,
                    walks: nil,
                    strikeouts: nil,
                    average: nil
                )
            ],
            totals: nil
        ),
        homeBatting: GameCenterBattingSection(lines: [], totals: nil),
        awayPitching: GameCenterPitchingSection(lines: []),
        homePitching: GameCenterPitchingSection(lines: []),
        recordSource: .fullBoxscore
    )
}

// sampleKeyplayerLimitedReview 메서드는 이 타입의 주요 동작을 수행합니다.
private func sampleKeyplayerLimitedReview() -> GameCenterReview {
    GameCenterReview(
        summaryItems: [],
        awayBatting: GameCenterBattingSection(
            lines: [
                GameCenterBattingLine(
                    battingOrder: "",
                    position: "",
                    name: "키플레이어",
                    atBats: nil,
                    runs: nil,
                    hits: "1",
                    runsBattedIn: nil,
                    homeRuns: nil,
                    walks: nil,
                    strikeouts: nil,
                    average: nil
                )
            ],
            totals: nil
        ),
        homeBatting: GameCenterBattingSection(lines: [], totals: nil),
        awayPitching: GameCenterPitchingSection(lines: []),
        homePitching: GameCenterPitchingSection(lines: []),
        recordSource: .keyplayerPartialLimited
    )
}

// sampleLineupLimitedReview 메서드는 이 타입의 주요 동작을 수행합니다.
private func sampleLineupLimitedReview() -> GameCenterReview {
    GameCenterReview(
        summaryItems: [],
        awayBatting: GameCenterBattingSection(
            lines: [
                GameCenterBattingLine(
                    battingOrder: "1",
                    position: "중",
                    name: "라인업타자",
                    atBats: nil,
                    runs: nil,
                    hits: nil,
                    runsBattedIn: nil,
                    homeRuns: nil,
                    walks: nil,
                    strikeouts: nil,
                    average: nil
                )
            ],
            totals: nil
        ),
        homeBatting: GameCenterBattingSection(lines: [], totals: nil),
        awayPitching: GameCenterPitchingSection(lines: []),
        homePitching: GameCenterPitchingSection(lines: []),
        recordSource: .lineupLimited
    )
}

// sampleDatabaseRecordReview 메서드는 이 타입의 주요 동작을 수행합니다.
private func sampleDatabaseRecordReview(
    game: GameDetail,
    batterCount: Int,
    pitcherCount: Int
) -> GameCenterReview {
    let awayBatters = (0..<(batterCount / 2)).map { index in
        GameCenterBattingLine(
            battingOrder: "\(index + 1)",
            position: "타",
            name: "원정타자\(index + 1)",
            atBats: "1",
            runs: "0",
            hits: "1",
            runsBattedIn: "0",
            homeRuns: "0",
            walks: "0",
            strikeouts: "0",
            average: "0.999"
        )
    }
    let homeBatters = (0..<(batterCount - awayBatters.count)).map { index in
        GameCenterBattingLine(
            battingOrder: "\(index + 1)",
            position: "타",
            name: "홈타자\(index + 1)",
            atBats: "1",
            runs: "0",
            hits: "1",
            runsBattedIn: "0",
            homeRuns: "0",
            walks: "0",
            strikeouts: "0",
            average: "0.999"
        )
    }
    let awayPitchers = (0..<(pitcherCount / 2)).map { index in
        GameCenterPitchingLine(
            name: "원정투수\(index + 1)",
            role: "선발",
            result: nil,
            innings: "1",
            pitches: "12",
            hitsAllowed: "0",
            walksAllowed: "0",
            hitBatters: "0",
            strikeouts: "1",
            homeRunsAllowed: "0",
            runsAllowed: "0",
            earnedRuns: "0",
            earnedRunAverage: "0.00"
        )
    }
    let homePitchers = (0..<(pitcherCount - awayPitchers.count)).map { index in
        GameCenterPitchingLine(
            name: "홈투수\(index + 1)",
            role: "선발",
            result: nil,
            innings: "1",
            pitches: "11",
            hitsAllowed: "0",
            walksAllowed: "0",
            hitBatters: "0",
            strikeouts: "1",
            homeRunsAllowed: "0",
            runsAllowed: "0",
            earnedRuns: "0",
            earnedRunAverage: "0.00"
        )
    }
    return GameCenterReview(
        summaryItems: [],
        awayBatting: GameCenterBattingSection(lines: awayBatters, totals: nil),
        homeBatting: GameCenterBattingSection(lines: homeBatters, totals: nil),
        awayPitching: GameCenterPitchingSection(lines: awayPitchers),
        homePitching: GameCenterPitchingSection(lines: homePitchers),
        recordSource: .dbLiveRecordsFresh
    )
}

private actor RecordingNotificationRegistrationClient: NotificationRegistrationClient {
    private var payloads: [NotificationRegistrationPayload] = []

    nonisolated var debugEndpointDescription: String? {
        "https://example.com/devices/register"
    }

    // syncRegistration 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    nonisolated func syncRegistration(_ payload: NotificationRegistrationPayload) async throws -> NotificationRegistrationSyncStatus {
        await record(payload)
        return .synced
    }

    // record 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func record(_ payload: NotificationRegistrationPayload) {
        payloads.append(payload)
    }

    // requestCount 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func requestCount() -> Int {
        payloads.count
    }

    // favoriteTeamIDs 메서드는 이 타입의 주요 동작을 수행합니다.
    func favoriteTeamIDs() -> [String?] {
        payloads.map(\.favoriteTeamID)
    }

    // recordedPayloads 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordedPayloads() -> [NotificationRegistrationPayload] {
        payloads
    }
}

private struct RecordedAttendanceRequest: Sendable {
    let isAttended: Bool
    let gameID: UUID
    let publicGameID: String?
    let providerGameID: String?
}

private actor RecordingAttendanceClient: AttendanceClient {
    private let fetchedGameIDs: Set<UUID>
    private let fetchError: AttendanceClientError?
    private let setError: AttendanceClientError?
    private var recordedFetchCount = 0
    private var recordedSetRequests: [RecordedAttendanceRequest] = []

    init(
        fetchedGameIDs: Set<UUID> = [],
        fetchError: AttendanceClientError? = nil,
        setError: AttendanceClientError? = nil
    ) {
        self.fetchedGameIDs = fetchedGameIDs
        self.fetchError = fetchError
        self.setError = setError
    }

    nonisolated func fetchAttendedGameIDs(installationID _: UUID) async throws -> Set<UUID> {
        try await fetch()
    }

    private func fetch() throws -> Set<UUID> {
        recordedFetchCount += 1
        if let fetchError {
            throw fetchError
        }
        return fetchedGameIDs
    }

    nonisolated func setAttendance(
        _ isAttended: Bool,
        installationID _: UUID,
        gameID: UUID,
        publicGameID: String?,
        providerGameID: String?
    ) async throws {
        try await recordSet(
            RecordedAttendanceRequest(
                isAttended: isAttended,
                gameID: gameID,
                publicGameID: publicGameID,
                providerGameID: providerGameID
            )
        )
    }

    private func recordSet(_ request: RecordedAttendanceRequest) throws {
        recordedSetRequests.append(request)
        if let setError {
            throw setError
        }
    }

    func setRequests() -> [RecordedAttendanceRequest] {
        recordedSetRequests
    }

    func fetchCount() -> Int {
        recordedFetchCount
    }
}

// notificationRegistrationSettings 메서드는 이 타입의 주요 동작을 수행합니다.
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

// disabledNotificationPreferences 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // record 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func record(favoriteTeamID: String) {
        recordedFavoriteTeamIDs.append(favoriteTeamID)
    }

    // callCount 메서드는 이 타입의 주요 동작을 수행합니다.
    func callCount() -> Int {
        recordedFavoriteTeamIDs.count
    }

    // favoriteTeamIDs 메서드는 이 타입의 주요 동작을 수행합니다.
    func favoriteTeamIDs() -> [String] {
        recordedFavoriteTeamIDs
    }
}

// FavoriteScheduleCountingRepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
private struct FavoriteScheduleCountingRepository: KBORepository, KBOFavoriteTeamScheduleDataSource {
    let recorder: FavoriteScheduleCallRecorder
    let base: StubRepository

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        recorder: FavoriteScheduleCallRecorder,
        base: StubRepository = StubRepository()
    ) {
        self.recorder = recorder
        self.base = base
    }

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        try await base.fetchBootstrapData()
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await base.fetchGames()
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await base.fetchNotifications()
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await base.fetchMonthlySchedule(for: month)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
    }

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

    // fetchFavoriteTeamSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchFavoriteTeamSchedule(
        date _: Date,
        favoriteTeamId: Team.ID,
        bypassingCache _: Bool
    ) async throws -> [GameDetail] {
        await recorder.record(favoriteTeamID: favoriteTeamId)
        return []
    }
}

// FavoriteScheduleStubRepository 구조체는 테스트에서 응원팀 일정 조회 capability만 선택적으로 추가합니다.
private struct FavoriteScheduleStubRepository: KBORepository, KBOFavoriteTeamScheduleDataSource {
    let base: StubRepository
    let fetchFavoriteTeamScheduleHandler: @Sendable (Date, Team.ID, Bool) async throws -> [GameDetail]

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        base: StubRepository,
        fetchFavoriteTeamSchedule: @escaping @Sendable (Date, Team.ID, Bool) async throws -> [GameDetail]
    ) {
        self.base = base
        self.fetchFavoriteTeamScheduleHandler = fetchFavoriteTeamSchedule
    }

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        try await base.fetchBootstrapData()
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await base.fetchGames()
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await base.fetchNotifications()
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await base.fetchMonthlySchedule(for: month)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
    }

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

    // fetchFavoriteTeamSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchFavoriteTeamSchedule(
        date: Date,
        favoriteTeamId: Team.ID,
        bypassingCache: Bool
    ) async throws -> [GameDetail] {
        try await fetchFavoriteTeamScheduleHandler(date, favoriteTeamId, bypassingCache)
    }
}

// eventually 메서드는 이 타입의 주요 동작을 수행합니다.
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

// StubResponse 구조체는 StubResponse 타입의 역할과 값을 정의합니다.
private struct StubResponse {
    let statusCode: Int
    let data: Data
    let headers: [String: String]

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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

    // canInit 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host == "example.com"
            || host == "www.koreabaseball.com"
            || host == "localhost"
            || host == "192.168.45.140"
    }

    // canonicalRequest 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    // startLoading 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // stopLoading 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    override func stopLoading() {}
}

// makeStubSession 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
}

// jsonStringLiteral 메서드는 이 타입의 주요 동작을 수행합니다.
private func jsonStringLiteral(_ value: String) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    return String(data: data, encoding: .utf8) ?? "\"\""
}

// httpBodyData 메서드는 이 타입의 주요 동작을 수행합니다.
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

private enum TestFixtureError: Error, CustomStringConvertible {
    case missingFixture(name: String, searchedPath: String)
    case unreadableFixture(name: String, searchedPath: String, underlying: Error)
    case missingStandingsSnapshot(teamID: String, availableTeamIDs: [String], count: Int)

    nonisolated var description: String {
        switch self {
        case .missingFixture(let name, let searchedPath):
            return "Missing test fixture name=\(name) searchedPath=\(searchedPath)"
        case .unreadableFixture(let name, let searchedPath, let underlying):
            return "Unreadable test fixture name=\(name) searchedPath=\(searchedPath) error=\(underlying)"
        case .missingStandingsSnapshot(let teamID, let availableTeamIDs, let count):
            return "Missing standings snapshot teamID=\(teamID) count=\(count) availableTeamIDs=\(availableTeamIDs.joined(separator: ","))"
        }
    }
}

// requireStandingsSnapshot 메서드는 standings 테스트가 배열 인덱싱으로 프로세스를 중단하지 않게 합니다.
private func requireStandingsSnapshot(
    in standings: [TeamStandingsSnapshot],
    teamID: String
) throws -> TeamStandingsSnapshot {
    guard let snapshot = standings.first(where: { $0.team.id == teamID }) else {
        throw TestFixtureError.missingStandingsSnapshot(
            teamID: teamID,
            availableTeamIDs: standings.map(\.team.id),
            count: standings.count
        )
    }
    return snapshot
}

// fixtureData 메서드는 이 타입의 주요 동작을 수행합니다.
private func fixtureData(named name: String) throws -> Data {
    let fixturesDirectory = testFixturesDirectory()
    let fixtureURL = fixturesDirectory.appendingPathComponent("\(name).json")
    guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
        throw TestFixtureError.missingFixture(name: "\(name).json", searchedPath: fixtureURL.path)
    }
    do {
        return try Data(contentsOf: fixtureURL)
    } catch {
        throw TestFixtureError.unreadableFixture(name: "\(name).json", searchedPath: fixtureURL.path, underlying: error)
    }
}

// saveFixtureData 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
private func saveFixtureData(_ data: Data, named name: String) throws {
    let fixturesDirectory = testFixturesDirectory()
    try FileManager.default.createDirectory(at: fixturesDirectory, withIntermediateDirectories: true, attributes: nil)
    try data.write(to: fixturesDirectory.appendingPathComponent("\(name).json"), options: .atomic)
}

// testFixturesDirectory 메서드는 테스트 fixture 탐색 경로를 한 곳에서 정의합니다.
private func testFixturesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
}

private func projectFileContents(_ relativePath: String) throws -> String {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
}

// makeTemporaryDirectory 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
    return directory
}

// makeTemporaryUserDefaults 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeTemporaryUserDefaults() -> UserDefaults {
    let suiteName = "kboScoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

// localBootstrapFixtureData 메서드는 앱 fallback bootstrap과 같은 형태의 테스트 fixture를 읽습니다.
private func localBootstrapFixtureData() throws -> Data {
    try fixtureData(named: "local-bootstrap-data")
}

// makeBootstrapJSON 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeBootstrapJSON(
    teamName: String? = nil,
    firstGameAwayScore: Int? = nil
) throws -> Data {
    guard var root = try JSONSerialization.jsonObject(with: localBootstrapFixtureData()) as? [String: Any] else {
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

// makeBootstrapAPIResponseJSON 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// makeBackendMonthPayloadJSON 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeBackendMonthPayloadJSON() throws -> Data {
    // team 메서드는 이 타입의 주요 동작을 수행합니다.
    func team(_ code: String, _ nameKo: String, _ shortName: String, _ themeColor: String) -> [String: Any] {
        [
            "code": code,
            "nameKo": nameKo,
            "shortName": shortName,
            "themeColor": themeColor
        ]
    }

    let games: [[String: Any]] = [
        ["id": "bdd3ec7a-69aa-400d-9929-7b27e4f4cde7", "gameDate": "2026-03-28", "gameTime": "14:00", "status": "scheduled", "stadium": "문학", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SSG", "SSG 랜더스", "SSG", "#CE0E2D"), "awayTeam": team("KIA", "KIA 타이거즈", "KIA", "#EA0029")],
        ["id": "19458f95-24ee-4de1-af30-ecc8152c24ee", "gameDate": "2026-03-28", "gameTime": "14:00", "status": "scheduled", "stadium": "잠실", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("LG", "LG 트윈스", "LG", "#C30452"), "awayTeam": team("KT", "KT 위즈", "KT", "#000000")],
        ["id": "3d17cfd0-358d-4e2c-b40c-35671ca041b2", "gameDate": "2026-03-28", "gameTime": "14:00", "status": "scheduled", "stadium": "창원", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("NC", "NC 다이노스", "NC", "#315288"), "awayTeam": team("DOOSAN", "두산 베어스", "두산", "#131230")],
        ["id": "d3a57c14-2ad5-4baf-b2cf-a5ea4eb26c3b", "gameDate": "2026-03-28", "gameTime": "14:00", "status": "scheduled", "stadium": "대구", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SAMSUNG", "삼성 라이온즈", "삼성", "#0066B3"), "awayTeam": team("LOTTE", "롯데 자이언츠", "롯데", "#041E42")],
        ["id": "ba878f3f-ebe8-40b7-bc72-3f113801b71f", "gameDate": "2026-03-28", "gameTime": "14:00", "status": "scheduled", "stadium": "대전", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("HANWHA", "한화 이글스", "한화", "#FF6600"), "awayTeam": team("KIWOOM", "키움 히어로즈", "키움", "#570514")],
        ["id": "8eb61818-1148-4f64-9176-eb08cd9e0371", "gameDate": "2026-03-29", "gameTime": "14:00", "status": "scheduled", "stadium": "문학", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SSG", "SSG 랜더스", "SSG", "#CE0E2D"), "awayTeam": team("KIA", "KIA 타이거즈", "KIA", "#EA0029")],
        ["id": "ed85a6ff-d525-4fba-938c-1957da4b76c5", "gameDate": "2026-03-29", "gameTime": "14:00", "status": "scheduled", "stadium": "잠실", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("LG", "LG 트윈스", "LG", "#C30452"), "awayTeam": team("KT", "KT 위즈", "KT", "#000000")],
        ["id": "c08a2da6-8b3e-4182-a36b-8039c68cbf78", "gameDate": "2026-03-29", "gameTime": "14:00", "status": "scheduled", "stadium": "창원", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("NC", "NC 다이노스", "NC", "#315288"), "awayTeam": team("DOOSAN", "두산 베어스", "두산", "#131230")],
        ["id": "347710af-708a-423e-807a-7805c2a32782", "gameDate": "2026-03-29", "gameTime": "14:00", "status": "scheduled", "stadium": "대구", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SAMSUNG", "삼성 라이온즈", "삼성", "#0066B3"), "awayTeam": team("LOTTE", "롯데 자이언츠", "롯데", "#041E42")],
        ["id": "1697aa01-16cb-41dc-8189-770415b6528b", "gameDate": "2026-03-29", "gameTime": "14:00", "status": "scheduled", "stadium": "대전", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("HANWHA", "한화 이글스", "한화", "#FF6600"), "awayTeam": team("KIWOOM", "키움 히어로즈", "키움", "#570514")],
        ["id": "5cae24b4-c3b9-46fd-80dc-8072a84c8353", "gameDate": "2026-03-31", "gameTime": "18:30", "status": "scheduled", "stadium": "잠실", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("LG", "LG 트윈스", "LG", "#C30452"), "awayTeam": team("KIA", "KIA 타이거즈", "KIA", "#EA0029")],
        ["id": "32ac800e-88d6-4ad0-9c0c-312ccf71e0b8", "gameDate": "2026-03-31", "gameTime": "18:30", "status": "scheduled", "stadium": "대전", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("HANWHA", "한화 이글스", "한화", "#FF6600"), "awayTeam": team("KT", "KT 위즈", "KT", "#000000")],
        ["id": "558438b2-a0ed-4f8c-a766-27f332e4f69a", "gameDate": "2026-03-31", "gameTime": "18:30", "status": "scheduled", "stadium": "대구", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SAMSUNG", "삼성 라이온즈", "삼성", "#0066B3"), "awayTeam": team("DOOSAN", "두산 베어스", "두산", "#131230")],
        ["id": "7d91e0ac-642b-447f-a25b-18865a7a5719", "gameDate": "2026-03-31", "gameTime": "18:30", "status": "scheduled", "stadium": "창원", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("NC", "NC 다이노스", "NC", "#315288"), "awayTeam": team("LOTTE", "롯데 자이언츠", "롯데", "#041E42")],
        ["id": "8428cc15-4999-4b38-9f3d-c02ee97c61d9", "gameDate": "2026-03-31", "gameTime": "18:30", "status": "scheduled", "stadium": "문학", "homeScore": 0, "awayScore": 0, "inningState": NSNull(), "homeTeam": team("SSG", "SSG 랜더스", "SSG", "#CE0E2D"), "awayTeam": team("KIWOOM", "키움 히어로즈", "키움", "#570514")]
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

    // increment 메서드는 이 타입의 주요 동작을 수행합니다.
    func increment() {
        count += 1
    }

    // incrementAndReturn 메서드는 이 타입의 주요 동작을 수행합니다.
    func incrementAndReturn() -> Int {
        count += 1
        return count
    }

    var value: Int { count }
}

private actor ScheduleMonthFetchSequence {
    private let responses: [[GameDetail]]
    private var index = 0

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(responses: [[GameDetail]]) {
        self.responses = responses
    }

    // next 메서드는 이 타입의 주요 동작을 수행합니다.
    func next() -> [GameDetail] {
        defer { index += 1 }
        guard responses.isEmpty == false else { return [] }
        return responses[min(index, responses.count - 1)]
    }

    var count: Int { index }
}

private actor ScheduleFetchGate {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var didRelease = false

    // wait 메서드는 이 타입의 주요 동작을 수행합니다.
    func wait() async {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil
        guard didRelease == false else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    // waitUntilStarted 메서드는 이 타입의 주요 동작을 수행합니다.
    func waitUntilStarted() async {
        guard didStart == false else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    // release 메서드는 이 타입의 주요 동작을 수행합니다.
    func release() {
        didRelease = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ScheduleDateFetchRecorder {
    private let responses: [String: [GameDetail]]
    private let delayNanoseconds: UInt64
    private(set) var calls: [(dayKey: String, bypassingCache: Bool)] = []

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(responses: [String: [GameDetail]], delayNanoseconds: UInt64 = 0) {
        self.responses = responses
        self.delayNanoseconds = delayNanoseconds
    }

    // fetch 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetch(date: Date, bypassingCache: Bool) async -> [GameDetail] {
        let dayKey = scheduleTestDayKey(for: date)
        calls.append((dayKey, bypassingCache))
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return responses[dayKey] ?? []
    }
}

// scheduleTestDayKey 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
private func scheduleTestDayKey(for date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
        format: "%04d-%02d-%02d",
        components.year ?? 1970,
        components.month ?? 1,
        components.day ?? 1
    )
}

// standingsMovementCalendar 메서드는 이 타입의 주요 동작을 수행합니다.
private func standingsMovementCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}

// makeStandingsMovementFixture 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeStandingsMovementFixture() throws -> (
    teams: [Team],
    leader: Team,
    falling: Team,
    rising: Team,
    games: [GameDetail],
    previousRanks: [String: Int]
) {
    let teams = MockKBOData.makeBootstrap().teams
    let leader = try #require(teams.first(where: { $0.id == "lotte" }))
    let falling = try #require(teams.first(where: { $0.id == "doosan" }))
    let rising = try #require(teams.first(where: { $0.id == "kiwoom" }))
    let fixtureTeams = [leader, falling, rising]
    let games = [
        makeStandingsMovementGame(
            index: 1,
            day: "2026-05-20",
            awayTeam: falling,
            homeTeam: leader,
            awayScore: 2,
            homeScore: 5
        ),
        makeStandingsMovementGame(
            index: 2,
            day: "2026-05-21",
            awayTeam: rising,
            homeTeam: leader,
            awayScore: 1,
            homeScore: 4
        ),
        makeStandingsMovementGame(
            index: 3,
            day: "2026-05-22",
            awayTeam: rising,
            homeTeam: falling,
            awayScore: 2,
            homeScore: 6
        ),
        makeStandingsMovementGame(
            index: 4,
            day: "2026-05-24",
            awayTeam: falling,
            homeTeam: rising,
            awayScore: 1,
            homeScore: 7
        ),
        makeStandingsMovementGame(
            index: 5,
            day: "2026-05-24",
            awayTeam: falling,
            homeTeam: rising,
            awayScore: 3,
            homeScore: 5
        )
    ]
    return (
        teams: fixtureTeams,
        leader: leader,
        falling: falling,
        rising: rising,
        games: games,
        previousRanks: [leader.id: 1, falling.id: 2, rising.id: 3]
    )
}

// makeDoosanSSGStandingsMovementFixture 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeDoosanSSGStandingsMovementFixture() throws -> (
    teams: [Team],
    leader: Team,
    falling: Team,
    rising: Team,
    games: [GameDetail],
    previousRanks: [String: Int]
) {
    let teams = MockKBOData.makeBootstrap().teams
    let leader = try #require(teams.first(where: { $0.id == "lotte" }))
    let falling = try #require(teams.first(where: { $0.id == "ssg" }))
    let rising = try #require(teams.first(where: { $0.id == "doosan" }))
    let fixtureTeams = [leader, falling, rising]
    let fillerGames = (0..<240).map { index in
        let awayTeam: Team
        let homeTeam: Team
        switch index % 3 {
        case 0:
            awayTeam = leader
            homeTeam = falling
        case 1:
            awayTeam = falling
            homeTeam = rising
        default:
            awayTeam = rising
            homeTeam = leader
        }
        return makeStandingsMovementGame(
            index: 1000 + index,
            day: String(format: "2026-05-%02d", (index % 18) + 1),
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: 2,
            homeScore: 2
        )
    }
    let rankChangingGames = [
        makeStandingsMovementGame(
            index: 2001,
            day: "2026-05-20",
            awayTeam: falling,
            homeTeam: leader,
            awayScore: 2,
            homeScore: 5
        ),
        makeStandingsMovementGame(
            index: 2002,
            day: "2026-05-21",
            awayTeam: rising,
            homeTeam: leader,
            awayScore: 1,
            homeScore: 4
        ),
        makeStandingsMovementGame(
            index: 2003,
            day: "2026-05-22",
            awayTeam: rising,
            homeTeam: falling,
            awayScore: 2,
            homeScore: 6
        ),
        makeStandingsMovementGame(
            index: 2004,
            day: "2026-05-27",
            awayTeam: falling,
            homeTeam: rising,
            awayScore: 1,
            homeScore: 7
        ),
        makeStandingsMovementGame(
            index: 2005,
            day: "2026-05-27",
            awayTeam: falling,
            homeTeam: rising,
            awayScore: 3,
            homeScore: 5
        )
    ]
    return (
        teams: fixtureTeams,
        leader: leader,
        falling: falling,
        rising: rising,
        games: fillerGames + rankChangingGames,
        previousRanks: [leader.id: 1, falling.id: 2, rising.id: 3]
    )
}

// makeStandingsMovementGame 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeStandingsMovementGame(
    index: Int,
    day: String,
    awayTeam: Team,
    homeTeam: Team,
    awayScore: Int,
    homeScore: Int
) -> GameDetail {
    makeGameDetail(
        id: UUID(uuidString: String(format: "97000000-0000-0000-0000-%012d", index))!,
        scheduledStart: isoDate("\(day)T18:30:00+09:00"),
        venue: "잠실",
        awayTeam: awayTeam,
        homeTeam: homeTeam,
        awayScore: awayScore,
        homeScore: homeScore,
        status: .final,
        seasonClassification: .regularSeason
    )
}

// currentStandingsRanks 메서드는 이 타입의 주요 동작을 수행합니다.
private func currentStandingsRanks(
    teams: [Team],
    games: [GameDetail],
    previousRanks: [String: Int]
) -> [String: Int] {
    let regularSeasonGames = games.filter(\.isRegularSeason)
    let rankedSnapshots = teams
        .map { team in
            StandingsCalculator.makeSnapshot(
                for: team,
                completedGames: regularSeasonGames.filter {
                    $0.hasCompleteFinalScore && $0.involves(teamID: team.id)
                },
                seasonGames: regularSeasonGames
            )
        }
        .sorted {
            StandingsSorter.compare($0, $1, previousRankProvider: { previousRanks[$0.id] })
        }

    return Dictionary(uniqueKeysWithValues: rankedSnapshots.enumerated().map { index, snapshot in
        (snapshot.team.id, index + 1)
    })
}

// scheduleTestCalendar 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
private func scheduleTestCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}

// makeScheduleMonthGames 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeScheduleMonthGames(
    count: Int = 135,
    year: Int = 2026,
    month: Int = 5
) throws -> [GameDetail] {
    let teams = MockKBOData.makeBootstrap().teams
    let lg = try #require(teams.first(where: { $0.id == "lg" }))
    let doosan = try #require(teams.first(where: { $0.id == "doosan" }))
    let samsung = try #require(teams.first(where: { $0.id == "samsung" }))
    let lotte = try #require(teams.first(where: { $0.id == "lotte" }))
    let kia = try #require(teams.first(where: { $0.id == "kia" }))
    let ssg = try #require(teams.first(where: { $0.id == "ssg" }))
    let kiwoom = try #require(teams.first(where: { $0.id == "kiwoom" }))
    let hanwha = try #require(teams.first(where: { $0.id == "hanwha" }))
    let nc = try #require(teams.first(where: { $0.id == "nc" }))
    let kt = try #require(teams.first(where: { $0.id == "kt" }))
    let fixtures: [(away: Team, home: Team, venue: String)] = [
        (lg, doosan, "잠실"),
        (samsung, lotte, "대구"),
        (kia, ssg, "문학"),
        (kiwoom, hanwha, "대전"),
        (nc, kt, "창원")
    ]

    return (0..<count).map { index in
        let day = index % 27 + 1
        let slot = index / 27
        let fixture = fixtures[index % fixtures.count]
        let scheduledStart = isoDate(String(format: "%04d-%02d-%02dT%02d:00:00+09:00", year, month, day, 13 + slot))
        let status: GameStatus = day < 26 ? .final : .upcoming
        return makeGameDetail(
            id: UUID(uuidString: String(format: "96000000-0000-0000-0000-%012d", index + 1))!,
            scheduledStart: scheduledStart,
            venue: fixture.venue,
            awayTeam: fixture.away,
            homeTeam: fixture.home,
            awayScore: status == .final ? index % 10 : nil,
            homeScore: status == .final ? (index + 3) % 10 : nil,
            status: status,
            seasonClassification: .regularSeason,
            providerGameID: String(format: "%04d%02d%02d%03d", year, month, day, index)
        )
    }
}

// makeScheduleTodayRefreshGames 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeScheduleTodayRefreshGames(
    from fullMonthGames: [GameDetail],
    dayKey: String = "2026-05-26"
) -> [GameDetail] {
    fullMonthGames
        .filter { scheduleTestDayKey(for: $0.scheduledStart) == dayKey }
        .map { game in
            makeGameDetail(
                id: game.id,
                scheduledStart: game.scheduledStart,
                venue: game.venue,
                awayTeam: game.awayTeam,
                homeTeam: game.homeTeam,
                awayScore: 4,
                homeScore: 2,
                status: .final,
                seasonClassification: .regularSeason,
                providerGameID: game.providerGameID
            )
        }
}

// makeSchedulePartialSyncModel 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
@MainActor
private func makeSchedulePartialSyncModel(
    fullMonthGames: [GameDetail],
    todayRefreshGames: [GameDetail],
    currentDate: Date,
    otherMonthGames: [GameDetail] = []
) throws -> AppModel {
    let teams = MockKBOData.makeBootstrap().teams
    let mayKey = KBOMonthScheduleKey(year: 2026, month: 5)
    let otherMonthLookup = Dictionary(grouping: otherMonthGames) {
        KBOMonthScheduleKey(date: $0.scheduledStart, calendar: scheduleTestCalendar())
    }
    let repository = StubRepository(fetchMonthlySchedule: { key in
        if key == mayKey {
            return fullMonthGames
        }
        return otherMonthLookup[key] ?? []
    }, fetchScheduleBypassingCache: { date, _ in
        scheduleTestDayKey(for: date) == "2026-05-26" ? todayRefreshGames : []
    })
    return AppModel(
        repository: repository,
        scheduleStaleGameReconciliationClient: RecordingScheduleStaleGameReconciliationClient(),
        bootstrap: KBOBootstrapData(teams: teams, games: [], notifications: [], settings: .default),
        usePersistedSettings: false,
        currentDateProvider: { currentDate }
    )
}

private actor RecordingScheduleStaleGameReconciliationClient: ScheduleStaleGameReconciliationClient {
    private(set) var calls: [[String]] = []
    private let delayNanoseconds: UInt64
    private let error: Error?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(delayNanoseconds: UInt64 = 0, error: Error? = nil) {
        self.delayNanoseconds = delayNanoseconds
        self.error = error
    }

    // reconcileStaleGames 메서드는 이 타입의 주요 동작을 수행합니다.
    func reconcileStaleGames(dates: [String]) async throws {
        calls.append(dates)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let error {
            throw error
        }
    }
}

@MainActor
private final class TestLiveActivityController: FavoriteTeamLiveActivityControlling {
    let isSupported: Bool

    private(set) var activeGameID: UUID?
    private(set) var snapshots: [FavoriteTeamLiveActivitySnapshot] = []

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(isSupported: Bool) {
        self.isSupported = isSupported
    }

    // startOrUpdate 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func startOrUpdate(using snapshot: FavoriteTeamLiveActivitySnapshot) async throws {
        activeGameID = snapshot.gameID
        snapshots.append(snapshot)
    }

    // endCurrent 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func endCurrent() async {
        activeGameID = nil
    }
}

@MainActor
private final class NotificationRequestCollector {
    private(set) var requests: [UNNotificationRequest] = []

    // append 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func append(_ request: UNNotificationRequest) {
        requests.append(request)
    }
}

// StubRepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
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
    var fetchScheduleBypassingCacheHandler: (@Sendable (Date, Bool) async throws -> [GameDetail])?
    var fetchStandingsHandler: @Sendable () async throws -> [TeamStandingsSnapshot] = {
        []
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        fetchBootstrapData: @escaping @Sendable () async throws -> KBOBootstrapData = { stubBootstrap() },
        fetchGames: @escaping @Sendable () async throws -> [GameDetail] = { stubGames() },
        fetchNotifications: @escaping @Sendable () async throws -> [NotificationItem] = { stubNotifications() },
        fetchMonthlySchedule: @escaping @Sendable (KBOMonthScheduleKey) async throws -> [GameDetail] = { _ in stubGames() },
        fetchSchedule: @escaping @Sendable (Date) async throws -> [GameDetail] = { _ in stubGames() },
        fetchScheduleBypassingCache: (@Sendable (Date, Bool) async throws -> [GameDetail])? = nil,
        fetchStandings: @escaping @Sendable () async throws -> [TeamStandingsSnapshot] = { [] }
    ) {
        self.fetchBootstrapDataHandler = fetchBootstrapData
        self.fetchGamesHandler = fetchGames
        self.fetchNotificationsHandler = fetchNotifications
        self.fetchMonthlyScheduleHandler = fetchMonthlySchedule
        self.fetchScheduleHandler = fetchSchedule
        self.fetchScheduleBypassingCacheHandler = fetchScheduleBypassingCache
        self.fetchStandingsHandler = fetchStandings
    }

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        try await fetchBootstrapDataHandler()
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await fetchGamesHandler()
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await fetchNotificationsHandler()
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await fetchMonthlyScheduleHandler(month)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await fetchScheduleHandler(date)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        if let fetchScheduleBypassingCacheHandler {
            return try await fetchScheduleBypassingCacheHandler(date, bypassingCache)
        }
        return try await fetchScheduleHandler(date)
    }

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await fetchStandingsHandler()
    }
}

// DetailSnapshotStubRepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
private struct DetailSnapshotStubRepository: KBORepository, KBOGameDetailSnapshotDataSource {
    let base: StubRepository
    let fetchGameDetailSnapshotHandler: @Sendable (GameDetail, String, [Team]) async throws -> GameDetail?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        base: StubRepository,
        fetchGameDetailSnapshot: @escaping @Sendable (GameDetail, String, [Team]) async throws -> GameDetail?
    ) {
        self.base = base
        self.fetchGameDetailSnapshotHandler = fetchGameDetailSnapshot
    }

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        try await base.fetchBootstrapData()
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await base.fetchGames()
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await base.fetchNotifications()
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await base.fetchMonthlySchedule(for: month)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
    }

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

    // fetchGameDetailSnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailSnapshot(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        try await fetchGameDetailSnapshotHandler(game, identity, cachedTeams)
    }
}

// stubBootstrap 메서드는 이 타입의 주요 동작을 수행합니다.
private func stubBootstrap() -> KBOBootstrapData {
    MockKBOData.makeBootstrap()
}

// stubGames 메서드는 이 타입의 주요 동작을 수행합니다.
private func stubGames() -> [GameDetail] {
    stubBootstrap().games
}

// stubNotifications 메서드는 이 타입의 주요 동작을 수행합니다.
private func stubNotifications() -> [NotificationItem] {
    stubBootstrap().notifications
}

// isoDate 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
private func isoDate(_ rawValue: String) -> Date {
    ISO8601DateFormatter().date(from: rawValue)!
}

// homeFallbackTestCalendar 메서드는 이 타입의 주요 동작을 수행합니다.
private func homeFallbackTestCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 1
    return calendar
}

// previousKBOWeekStart 메서드는 이 타입의 주요 동작을 수행합니다.
private func previousKBOWeekStart(referenceDate: Date = Date()) -> Date {
    let calendar = homeFallbackTestCalendar()
    let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)!.start
    return calendar.date(byAdding: .day, value: -7, to: currentWeekStart)!
}

// dateInKBOWeek 메서드는 이 타입의 주요 동작을 수행합니다.
private func dateInKBOWeek(start weekStart: Date, dayOffset: Int) -> Date {
    let calendar = homeFallbackTestCalendar()
    return calendar.date(
        byAdding: DateComponents(day: dayOffset, hour: 18, minute: 30),
        to: weekStart
    )!
}

// makeStaleScheduleFixture 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeStaleScheduleFixture(
    status: GameStatus,
    day: String,
    id: UUID = UUID(uuidString: "99000000-0000-0000-0000-000000000001")!
) throws -> (game: GameDetail, today: Date, calendar: Calendar) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let teams = MockKBOData.makeBootstrap().teams
    let awayTeam = try #require(teams.first(where: { $0.id == "lg" }))
    let homeTeam = try #require(teams.first(where: { $0.id == "doosan" }))
    let game = makeGameDetail(
        id: id,
        scheduledStart: ISO8601DateFormatter().date(from: "\(day)T18:30:00+09:00")!,
        venue: "잠실",
        awayTeam: awayTeam,
        homeTeam: homeTeam,
        awayScore: status == .final ? 4 : nil,
        homeScore: status == .final ? 2 : nil,
        status: status
    )
    return (
        game: game,
        today: isoDate("2026-03-13T09:00:00+09:00"),
        calendar: calendar
    )
}

// makeGameDetail 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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
    events: [GameEvent] = [],
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
        events: events,
        note: note,
        providerGameID: providerGameID,
        awayStartingPitcherName: awayStartingPitcherName,
        homeStartingPitcherName: homeStartingPitcherName,
        currentPitcherName: currentPitcherName,
        currentBatterName: currentBatterName
	    )
}

// attendanceFixtureTeams 메서드는 이 타입의 주요 동작을 수행합니다.
private func attendanceFixtureTeams() throws -> (
    lg: Team,
    doosan: Team,
    samsung: Team,
    lotte: Team
) {
    let teams = MockKBOData.makeBootstrap().teams
    return (
        lg: try #require(teams.first(where: { $0.id == "lg" })),
        doosan: try #require(teams.first(where: { $0.id == "doosan" })),
        samsung: try #require(teams.first(where: { $0.id == "samsung" })),
        lotte: try #require(teams.first(where: { $0.id == "lotte" }))
    )
}

// makeAttendanceFixtureGame 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeAttendanceFixtureGame(
    index: Int,
    venue: String = "잠실",
    awayTeam: Team,
    homeTeam: Team,
    awayScore: Int,
    homeScore: Int
) -> GameDetail {
    makeGameDetail(
        id: UUID(uuidString: String(format: "95000000-0000-0000-0000-%012d", index))!,
        scheduledStart: isoDate(String(format: "2026-04-%02dT18:30:00+09:00", index)),
        venue: venue,
        awayTeam: awayTeam,
        homeTeam: homeTeam,
        awayScore: awayScore,
        homeScore: homeScore,
        status: .final,
        seasonClassification: .regularSeason,
        note: "provider_game_id=202604\(String(format: "%02d", index))\(awayTeam.markText)\(homeTeam.markText)0"
    )
}

// makeBaseRunnerDisplayGame 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// makeBaseRunnerLineupSections 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeBaseRunnerLineupSections(
    away: [(order: Int, name: String)],
    home: [(order: Int, name: String)]
) -> [GameCenterBattingSection] {
    [
        GameCenterBattingSection(lines: away.map(makeBaseRunnerLineupLine), totals: nil),
        GameCenterBattingSection(lines: home.map(makeBaseRunnerLineupLine), totals: nil)
    ]
}

// makeBaseRunnerLineupLine 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
private func makeBaseRunnerLineupLine(order: Int, name: String) -> GameCenterBattingLine {
    GameCenterBattingLine(
        battingOrder: "\(order)번",
        position: "타자",
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

// makeSupabaseGameRow 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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
    inningState: String?
) throws -> SupabaseGameRow {
    let resolvedOfficialProviderGameID = officialProviderGameID ?? providerGameID
    let inningValue = inningState.map { "\"\($0)\"" } ?? "null"
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
        "inning_state": \(inningValue),
        "is_cancelled": false,
        "is_postponed": false,
        "source_updated_at": "2026-04-28T20:00:00+09:00",
        "updated_at": "2026-04-28T20:00:00+09:00"
      }
    ]
    """
    return try JSONDecoder().decode([SupabaseGameRow].self, from: Data(payload.utf8))[0]
}

private func makeSupabaseLatestSnapshotRow(
    gameID: UUID,
    inningLabel: String,
    currentPitcherName: String? = nil,
    currentBatterName: String? = nil,
    balls: Int? = 0,
    strikes: Int? = 0,
    outs: Int? = 0,
    awayScore: Int? = nil,
    homeScore: Int? = nil,
    runnerOnFirst: Bool = false,
    runnerOnSecond: Bool = false,
    runnerOnThird: Bool = false,
    firstRunnerName: String? = nil,
    secondRunnerName: String? = nil,
    thirdRunnerName: String? = nil,
    createdAt: String? = nil,
    updatedAt: String? = nil
) throws -> SupabaseLatestGameSnapshotRow {
    let payload: [String: Any?] = [
        "game_id": gameID.uuidString,
        "inning_label": inningLabel,
        "balls": balls,
        "strikes": strikes,
        "outs": outs,
        "runner_on_first": runnerOnFirst,
        "runner_on_second": runnerOnSecond,
        "runner_on_third": runnerOnThird,
        "first_base_runner_name": firstRunnerName,
        "second_base_runner_name": secondRunnerName,
        "third_base_runner_name": thirdRunnerName,
        "current_pitcher_name": currentPitcherName,
        "current_batter_name": currentBatterName,
        "away_score": awayScore,
        "home_score": homeScore,
        "created_at": createdAt,
        "updated_at": updatedAt
    ]
    let data = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 })
    return try JSONDecoder().decode(SupabaseLatestGameSnapshotRow.self, from: data)
}

// makeStandingsSnapshot 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// makeProbabilityTestTeams 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// makeProbabilityThresholdSchedule 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// makePairDeficitRegularSeasonSchedule 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// completedProbabilityGame 메서드는 이 타입의 주요 동작을 수행합니다.
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

// makeConservativeEarlySeasonProbabilitySchedule 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// makeRoundRobinProbabilitySchedule 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// liveActivityContentStateKey 메서드는 이 타입의 주요 동작을 수행합니다.
private func liveActivityContentStateKey(
    isPreGame: Bool = false,
    favoriteScoreText: String = "4",
    opponentScoreText: String = "3",
    inningText: String = "7회 말",
    summaryText: String = "LIVE",
    favoriteStartingPitcherName: String? = "임찬규",
    opponentStartingPitcherName: String? = "문동주",
    balls: Int? = 1,
    strikes: Int? = 1,
    outs: Int? = 0,
    runnerOnFirst: Bool? = false,
    runnerOnSecond: Bool? = false,
    runnerOnThird: Bool? = false,
    currentBatterName: String? = "홍길동",
    currentPitcherName: String? = "김투수"
) -> FavoriteTeamLiveActivityContentStateKey {
    FavoriteTeamLiveActivityContentStateKey(
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

// roundRobinPairings 메서드는 이 타입의 주요 동작을 수행합니다.
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
