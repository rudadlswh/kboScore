from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from app.api.routes import games as games_route
from app.api.routes import schedule as schedule_route
from app.api.routes import standings as standings_route
from app.api.routes import teams as teams_route
from app.schemas.game import (
    GameDetailResponse,
    GameSnapshotsResponse,
    GameSeasonClassification,
    GamesResponse,
    GameStatus,
    ScoreSummary,
    SnapshotResponse,
    StadiumSummary,
)
from app.schemas.team import TeamSummary
from app.schemas.weather import GameWeatherResponse, WeatherCurrent
from app.services.game_query_service import GameQueryService
from app.schemas.schedule import ScheduleMonthResponse
from app.schemas.standings import (
    PostseasonProbabilityUnavailableReason,
    StandingsItem,
    StandingsRankingResolution,
    StandingsRecentResult,
    StandingsResponse,
)


KST = timezone(timedelta(hours=9))


def test_health_endpoint_returns_ok(client):
    response = client.get("/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_teams_endpoint_returns_expected_shape(client, monkeypatch):
    monkeypatch.setattr(
        teams_route.team_repository,
        "list_teams",
        lambda db: [
            {
                "team_id": "LG",
                "name_ko": "LG 트윈스",
                "name_en": "LG Twins",
                "short_name": "LG",
            }
        ],
    )

    response = client.get("/v1/teams")

    assert response.status_code == 200
    assert response.json() == {
        "teams": [
            {
                "teamId": "LG",
                "nameKo": "LG 트윈스",
                "nameEn": "LG Twins",
                "shortName": "LG",
            }
        ]
    }


def test_games_endpoint_defaults_to_current_kst_date(client, monkeypatch):
    captured: dict[str, object] = {}

    def fake_list_games(db, *, game_date, team_id, status):
        captured["game_date"] = game_date
        return GamesResponse(date=game_date, games=[])

    monkeypatch.setattr(games_route.game_query_service, "list_games", fake_list_games)

    response = client.get("/v1/games")

    assert response.status_code == 200
    assert isinstance(captured["game_date"], date)


def test_games_endpoint_filters_by_team_id_correctly(client, monkeypatch):
    captured: dict[str, object] = {}

    def fake_list_games(db, *, game_date, team_id, status):
        captured["game_date"] = game_date
        captured["team_id"] = team_id
        captured["status"] = status
        return GamesResponse(date=game_date, games=[])

    monkeypatch.setattr(games_route.game_query_service, "list_games", fake_list_games)

    response = client.get("/v1/games", params={"date": "2026-03-28", "teamId": "LG"})

    assert response.status_code == 200
    assert response.json() == {"date": "2026-03-28", "games": []}
    assert captured == {
        "game_date": date(2026, 3, 28),
        "team_id": "LG",
        "status": None,
    }


def test_schedule_month_endpoint_returns_expected_shape(client, monkeypatch):
    monkeypatch.setattr(
        schedule_route.game_repository,
        "list_games_in_range",
        lambda db, *, date_from, date_to, season_classification=None: [
            {
                "game_id": "game-1",
                "scheduled_at": datetime(2026, 3, 28, 14, 0, tzinfo=KST),
                "status": "scheduled",
                "season_classification": "regular_season",
                "stadium_name_ko": "잠실",
                "home_team_id": "LG",
                "home_team_name_ko": "LG 트윈스",
                "home_team_short_name": "LG",
                "away_team_id": "KT",
                "away_team_name_ko": "KT 위즈",
                "away_team_short_name": "KT",
                "home_score": 0,
                "away_score": 0,
                "inning_state": None,
                "is_postponed": False,
                "is_cancelled": False,
            }
        ],
    )

    response = client.get("/v1/schedule/month", params={"year": 2026, "month": 3})

    assert response.status_code == 200
    assert response.json() == {
        "year": 2026,
        "month": 3,
        "totalCount": 1,
        "games": [
            {
                "gameId": "game-1",
                "scheduledAt": "2026-03-28T14:00:00+09:00",
                "status": "scheduled",
                "seasonClassification": "regular_season",
                "stadium": "잠실",
                "homeTeam": {"teamId": "LG", "nameKo": "LG 트윈스", "shortName": "LG"},
                "awayTeam": {"teamId": "KT", "nameKo": "KT 위즈", "shortName": "KT"},
                "homeScore": 0,
                "awayScore": 0,
                "inningState": None,
            }
        ],
    }


def test_standings_endpoint_returns_expected_shape(client, monkeypatch):
    monkeypatch.setattr(
        standings_route.standings_query_service,
        "get_regular_season_standings",
        lambda db, season_id: StandingsResponse(
            season_id=season_id,
            generated_at=datetime(2026, 4, 2, 9, 0, tzinfo=KST),
            has_unknown_classification_games=False,
            standings=[
                StandingsItem(
                    team=TeamSummary(team_id="LG", name_ko="LG 트윈스"),
                    rank=1,
                    wins=5,
                    losses=1,
                    ties=0,
                    games_played=6,
                    remaining_regular_season_games=138,
                    win_percentage=0.833,
                    recent_results=[StandingsRecentResult.WIN, StandingsRecentResult.WIN],
                    unknown_classification_games=0,
                    ranking_resolution=StandingsRankingResolution.RESOLVED,
                    ranking_resolution_position=None,
                    postseason_qualification_probability=0.84,
                    postseason_probability_unavailable_reason=None,
                )
            ],
        ),
    )

    response = client.get("/v1/standings", params={"seasonId": 2026})

    assert response.status_code == 200
    payload = response.json()
    assert payload["seasonId"] == 2026
    assert payload["hasUnknownClassificationGames"] is False
    assert payload["standings"][0]["team"]["teamId"] == "LG"
    assert payload["standings"][0]["rankingResolution"] == "resolved"
    assert payload["standings"][0]["postseasonQualificationProbability"] == 0.84


def test_standings_endpoint_can_surface_probability_unavailable_state(client, monkeypatch):
    monkeypatch.setattr(
        standings_route.standings_query_service,
        "get_regular_season_standings",
        lambda db, season_id: StandingsResponse(
            season_id=season_id,
            generated_at=datetime(2026, 4, 2, 9, 0, tzinfo=KST),
            has_unknown_classification_games=True,
            standings=[
                StandingsItem(
                    team=TeamSummary(team_id="LG", name_ko="LG 트윈스"),
                    rank=1,
                    wins=5,
                    losses=1,
                    ties=0,
                    games_played=6,
                    remaining_regular_season_games=138,
                    win_percentage=0.833,
                    recent_results=[StandingsRecentResult.WIN],
                    unknown_classification_games=1,
                    ranking_resolution=StandingsRankingResolution.RESOLVED,
                    ranking_resolution_position=None,
                    postseason_qualification_probability=None,
                    postseason_probability_unavailable_reason=PostseasonProbabilityUnavailableReason.UNKNOWN_CLASSIFICATION_GAMES,
                )
            ],
        ),
    )

    response = client.get("/v1/standings", params={"seasonId": 2026})

    assert response.status_code == 200
    payload = response.json()
    assert payload["standings"][0]["postseasonQualificationProbability"] is None
    assert payload["standings"][0]["postseasonProbabilityUnavailableReason"] == "unknown_classification_games"


def test_games_endpoint_filters_by_status_correctly(client, monkeypatch):
    captured: dict[str, object] = {}

    def fake_list_games(db, *, game_date, team_id, status):
        captured["status"] = status
        return GamesResponse(date=game_date, games=[])

    monkeypatch.setattr(games_route.game_query_service, "list_games", fake_list_games)

    response = client.get("/v1/games", params={"date": "2026-03-28", "status": "live"})

    assert response.status_code == 200
    assert captured["status"] == GameStatus.LIVE


def test_game_detail_returns_404_with_error_shape_when_game_does_not_exist(client, monkeypatch):
    monkeypatch.setattr(games_route.game_query_service, "get_game_detail", lambda db, game_id: None)

    response = client.get("/v1/games/missing-game")

    assert response.status_code == 404
    assert response.json() == {
        "error": {
            "code": "GAME_NOT_FOUND",
            "message": "Game not found",
            "details": None,
        }
    }


def test_game_detail_aggregates_latest_weather_and_latest_snapshot_timestamp_correctly():
    class FakeGameRepository:
        def get_game_detail_base(self, db, game_id):
            assert game_id == "game-1"
            return {
                "game_id": "game-1",
                "provider_game_id": "20260328LGDOO0",
                "official_provider_game_id": "20260328LGDOO1",
                "scheduled_at": datetime(2026, 3, 28, 14, 0, tzinfo=KST),
                "home_team_id": "DOO",
                "home_team_name_ko": "두산 베어스",
                "away_team_id": "LG",
                "away_team_name_ko": "LG 트윈스",
                "stadium_id": "JS",
                "stadium_name_ko": "잠실",
                "status": "live",
                "season_classification": "regular_season",
                "home_score": 3,
                "away_score": 5,
                "inning_state": "7회초",
                "is_double_header": False,
                "is_postponed": False,
                "is_cancelled": False,
                "latest_snapshot_at": datetime(2026, 3, 28, 16, 11, 20, tzinfo=KST),
            }

    class FakeSnapshotRepository:
        pass

    class FakeWeatherRepository:
        def get_latest_weather_for_stadium(self, db, stadium_id):
            assert stadium_id == "JS"
            return {
                "stadium_id": "JS",
                "observed_at": datetime(2026, 3, 28, 16, 0, tzinfo=KST),
                "temperature_c": 12.4,
                "condition": "흐림",
                "precipitation_mm": 0.2,
            }

    service = GameQueryService(
        game_repository=FakeGameRepository(),
        snapshot_repository=FakeSnapshotRepository(),
        weather_repository=FakeWeatherRepository(),
    )

    response = service.get_game_detail(db=None, game_id="game-1")

    assert response == GameDetailResponse(
        game_id="game-1",
        provider_game_id="20260328LGDOO0",
        official_provider_game_id="20260328LGDOO1",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        home_team=TeamSummary(team_id="DOO", name_ko="두산 베어스"),
        away_team=TeamSummary(team_id="LG", name_ko="LG 트윈스"),
        stadium=StadiumSummary(stadium_id="JS", name_ko="잠실"),
        status=GameStatus.LIVE,
        season_classification=GameSeasonClassification.REGULAR_SEASON,
        score=ScoreSummary(home=3, away=5),
        inning_state="7회초",
        latest_snapshot_at=datetime(2026, 3, 28, 16, 11, 20, tzinfo=KST),
        weather=WeatherCurrent(
            temperature_c=12.4,
            condition="흐림",
            precipitation_mm=0.2,
            observed_at=datetime(2026, 3, 28, 16, 0, tzinfo=KST),
        ),
    )


def test_snapshots_endpoint_respects_limit_and_ordering():
    captured: dict[str, object] = {}

    class FakeGameRepository:
        def get_game_lookup(self, db, game_id):
            assert game_id == "game-1"
            return {"game_id": "game-1", "stadium_id": "JS"}

    class FakeSnapshotRepository:
        def list_game_snapshots(self, db, game_id, *, limit):
            captured["limit"] = limit
            return [
                {
                    "snapshot_at": datetime(2026, 3, 28, 16, 11, 20, tzinfo=KST),
                    "status": "finished",
                    "home_score": 3,
                    "away_score": 7,
                    "inning_state": "9회말",
                },
                {
                    "snapshot_at": datetime(2026, 3, 28, 15, 10, 0, tzinfo=KST),
                    "status": "live",
                    "home_score": 0,
                    "away_score": 1,
                    "inning_state": "2회초",
                },
            ]

    class FakeWeatherRepository:
        pass

    service = GameQueryService(
        game_repository=FakeGameRepository(),
        snapshot_repository=FakeSnapshotRepository(),
        weather_repository=FakeWeatherRepository(),
    )

    response = service.get_game_snapshots(db=None, game_id="game-1", limit=2)

    assert captured["limit"] == 2
    assert response == GameSnapshotsResponse(
        game_id="game-1",
        snapshots=[
            SnapshotResponse(
                snapshot_at=datetime(2026, 3, 28, 16, 11, 20, tzinfo=KST),
                status=GameStatus.FINISHED,
                score=ScoreSummary(home=3, away=7),
                inning_state="9회말",
            ),
            SnapshotResponse(
                snapshot_at=datetime(2026, 3, 28, 15, 10, 0, tzinfo=KST),
                status=GameStatus.LIVE,
                score=ScoreSummary(home=0, away=1),
                inning_state="2회초",
            ),
        ],
    )
    assert response.snapshots[0].snapshot_at > response.snapshots[1].snapshot_at


def test_weather_endpoint_returns_404_when_game_does_not_exist(client, monkeypatch):
    monkeypatch.setattr(games_route.game_query_service, "get_game_weather", lambda db, game_id: None)

    response = client.get("/v1/games/missing-game/weather")

    assert response.status_code == 404
    assert response.json() == {
        "error": {
            "code": "GAME_NOT_FOUND",
            "message": "Game not found",
            "details": None,
        }
    }


def test_status_normalization_maps_raw_db_values_into_public_enum_correctly():
    normalize = GameQueryService._normalize_status

    assert normalize("scheduled") == GameStatus.SCHEDULED
    assert normalize("live") == GameStatus.LIVE
    assert normalize("finished") == GameStatus.FINISHED
    assert normalize("suspended") == GameStatus.SUSPENDED
    assert normalize("live", is_cancelled=True) == GameStatus.CANCELLED
    assert normalize("scheduled", is_postponed=True) == GameStatus.POSTPONED
    assert normalize("mystery") == GameStatus.UNKNOWN
    assert normalize(None) == GameStatus.UNKNOWN
