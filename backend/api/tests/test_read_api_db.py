from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import text
from sqlalchemy.orm import Session


KST = timezone(timedelta(hours=9))
UTC = timezone.utc


def _insert_team(
    db_session: Session,
    *,
    code: str,
    name_ko: str,
    short_name: str,
    sort_order: int,
    previous_regular_season_rank: int | None = None,
    name_en: str | None = None,
) -> str:
    row = db_session.execute(
        text(
            """
            INSERT INTO teams (code, name_ko, name_en, short_name, sort_order, previous_regular_season_rank)
            VALUES (:code, :name_ko, :name_en, :short_name, :sort_order, :previous_regular_season_rank)
            RETURNING id::text AS id
            """
        ),
        {
            "code": code,
            "name_ko": name_ko,
            "name_en": name_en,
            "short_name": short_name,
            "sort_order": sort_order,
            "previous_regular_season_rank": previous_regular_season_rank,
        },
    ).mappings().one()
    db_session.commit()
    return row["id"]


def _insert_game(
    db_session: Session,
    *,
    provider_game_id: str,
    game_date: str,
    scheduled_at: datetime,
    stadium: str,
    stadium_code: str,
    home_team_id: str,
    away_team_id: str,
    status: str = "scheduled",
    home_score: int = 0,
    away_score: int = 0,
    inning_state: str | None = None,
    is_postponed: bool = False,
    is_cancelled: bool = False,
    official_provider_game_id: str | None = None,
    season_classification: str = "unknown",
) -> str:
    row = db_session.execute(
        text(
            """
            INSERT INTO games (
                provider,
                provider_game_id,
                official_provider_game_id,
                game_date,
                scheduled_at,
                stadium,
                stadium_code,
                home_team_id,
                away_team_id,
                status,
                season_classification,
                home_score,
                away_score,
                inning_state,
                is_postponed,
                is_cancelled
            ) VALUES (
                'kbo',
                :provider_game_id,
                :official_provider_game_id,
                :game_date,
                :scheduled_at,
                :stadium,
                :stadium_code,
                CAST(:home_team_id AS uuid),
                CAST(:away_team_id AS uuid),
                :status,
                :season_classification,
                :home_score,
                :away_score,
                :inning_state,
                :is_postponed,
                :is_cancelled
            )
            RETURNING id::text AS id
            """
        ),
        {
            "provider_game_id": provider_game_id,
            "official_provider_game_id": official_provider_game_id,
            "game_date": game_date,
            "scheduled_at": scheduled_at,
            "stadium": stadium,
            "stadium_code": stadium_code,
            "home_team_id": home_team_id,
            "away_team_id": away_team_id,
            "status": status,
            "season_classification": season_classification,
            "home_score": home_score,
            "away_score": away_score,
            "inning_state": inning_state,
            "is_postponed": is_postponed,
            "is_cancelled": is_cancelled,
        },
    ).mappings().one()
    db_session.commit()
    return row["id"]


def _insert_snapshot(
    db_session: Session,
    *,
    game_id: str,
    snapshot_at: datetime,
    status: str,
    home_score: int,
    away_score: int,
    inning_state: str | None,
) -> None:
    db_session.execute(
        text(
            """
            INSERT INTO game_snapshots (game_id, snapshot_at, status, home_score, away_score, inning_state)
            VALUES (CAST(:game_id AS uuid), :snapshot_at, :status, :home_score, :away_score, :inning_state)
            """
        ),
        {
            "game_id": game_id,
            "snapshot_at": snapshot_at,
            "status": status,
            "home_score": home_score,
            "away_score": away_score,
            "inning_state": inning_state,
        },
    )
    db_session.commit()


def _insert_weather(
    db_session: Session,
    *,
    game_id: str,
    stadium_code: str,
    observed_at: datetime,
    current_icon_name: str,
    current_temp_c: float,
    current_rain_mm: float | None,
) -> None:
    db_session.execute(
        text(
            """
            INSERT INTO weather_snapshots (
                game_id,
                observed_at,
                source_name,
                stadium_code,
                current_icon_name,
                current_temp_c,
                current_rain_mm
            ) VALUES (
                CAST(:game_id AS uuid),
                :observed_at,
                'weather_ajax',
                :stadium_code,
                :current_icon_name,
                :current_temp_c,
                :current_rain_mm
            )
            """
        ),
        {
            "game_id": game_id,
            "observed_at": observed_at,
            "stadium_code": stadium_code,
            "current_icon_name": current_icon_name,
            "current_temp_c": current_temp_c,
            "current_rain_mm": current_rain_mm,
        },
    )
    db_session.commit()


def _insert_game_event(
    db_session: Session,
    *,
    game_id: str,
    event_type: str,
    confirmed: bool,
    reason: str | None,
    source: str,
    recorded_at: datetime,
    event_key: str,
) -> None:
    db_session.execute(
        text(
            """
            INSERT INTO game_schedule_events (
                game_id,
                event_type,
                confirmed,
                reason,
                source,
                recorded_at,
                event_key
            ) VALUES (
                CAST(:game_id AS uuid),
                :event_type,
                :confirmed,
                :reason,
                :source,
                :recorded_at,
                :event_key
            )
            """
        ),
        {
            "game_id": game_id,
            "event_type": event_type,
            "confirmed": confirmed,
            "reason": reason,
            "source": source,
            "recorded_at": recorded_at,
            "event_key": event_key,
        },
    )
    db_session.commit()


def test_games_filters_by_kst_calendar_date_correctly(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)

    included_game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 0, 30, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
    )
    _insert_game(
        db_session,
        provider_game_id="20260327LGDOO0",
        game_date="2026-03-27",
        scheduled_at=datetime(2026, 3, 27, 23, 30, tzinfo=UTC),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
    )

    response = db_client.get("/v1/games", params={"date": "2026-03-28"})

    assert response.status_code == 200
    payload = response.json()
    assert payload["date"] == "2026-03-28"
    assert [game["gameId"] for game in payload["games"]] == [included_game_id]


def test_games_team_id_filter_matches_home_and_away_teams(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)
    kt_id = _insert_team(db_session, code="KT", name_ko="KT 위즈", short_name="KT", sort_order=3)

    away_match = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
    )
    home_match = _insert_game(
        db_session,
        provider_game_id="20260328KTLG0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 18, 30, tzinfo=KST),
        stadium="수원",
        stadium_code="SW",
        home_team_id=lg_id,
        away_team_id=kt_id,
    )
    _insert_game(
        db_session,
        provider_game_id="20260328KTDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 19, 0, tzinfo=KST),
        stadium="수원",
        stadium_code="SW",
        home_team_id=doo_id,
        away_team_id=kt_id,
    )

    response = db_client.get("/v1/games", params={"date": "2026-03-28", "teamId": "LG"})

    assert response.status_code == 200
    assert {game["gameId"] for game in response.json()["games"]} == {away_match, home_match}


def test_games_status_filter_uses_canonical_game_status(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)

    live_game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="live",
        home_score=3,
        away_score=5,
        inning_state="7회초",
    )
    _insert_game(
        db_session,
        provider_game_id="20260328LGDOO1",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 18, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="scheduled",
    )

    response = db_client.get("/v1/games", params={"date": "2026-03-28", "status": "live"})

    assert response.status_code == 200
    games = response.json()["games"]
    assert [game["gameId"] for game in games] == [live_game_id]
    assert games[0]["status"] == "live"


def test_games_and_detail_promote_live_status_from_latest_snapshot(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)

    game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO2",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 18, 30, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="scheduled",
        season_classification="regular_season",
        home_score=0,
        away_score=0,
        inning_state=None,
    )
    _insert_snapshot(
        db_session,
        game_id=game_id,
        snapshot_at=datetime(2026, 3, 28, 18, 35, 0, tzinfo=KST),
        status="live",
        home_score=1,
        away_score=2,
        inning_state="1회초",
    )

    games_response = db_client.get("/v1/games", params={"date": "2026-03-28"})
    detail_response = db_client.get(f"/v1/games/{game_id}")

    assert games_response.status_code == 200
    listed = next(game for game in games_response.json()["games"] if game["gameId"] == game_id)
    assert listed["status"] == "live"
    assert listed["seasonClassification"] == "regular_season"
    assert listed["inningState"] == "1회초"
    assert listed["score"] == {"home": 1, "away": 2}

    assert detail_response.status_code == 200
    detail = detail_response.json()
    assert detail["status"] == "live"
    assert detail["seasonClassification"] == "regular_season"
    assert detail["inningState"] == "1회초"
    assert detail["score"] == {"home": 1, "away": 2}


def test_snapshot_live_does_not_override_terminal_or_scheduled_semantics(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)

    scheduled_game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO3",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 12, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="scheduled",
    )
    postponed_game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO4",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="postponed",
        is_postponed=True,
    )
    finished_game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO5",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 16, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="finished",
    )

    for game_id in (postponed_game_id, finished_game_id):
        _insert_snapshot(
            db_session,
            game_id=game_id,
            snapshot_at=datetime(2026, 3, 28, 18, 35, 0, tzinfo=KST),
            status="live",
            home_score=1,
            away_score=2,
            inning_state="1회초",
        )

    response = db_client.get("/v1/games", params={"date": "2026-03-28"})

    assert response.status_code == 200
    statuses = {game["gameId"]: game["status"] for game in response.json()["games"]}
    assert statuses[scheduled_game_id] == "scheduled"
    assert statuses[postponed_game_id] == "postponed"
    assert statuses[finished_game_id] == "finished"


def test_status_filter_includes_snapshot_promoted_live_games(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)

    promoted_game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO6",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 18, 30, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="scheduled",
    )
    _insert_snapshot(
        db_session,
        game_id=promoted_game_id,
        snapshot_at=datetime(2026, 3, 28, 18, 35, 0, tzinfo=KST),
        status="live",
        home_score=0,
        away_score=1,
        inning_state="1회초",
    )

    response = db_client.get("/v1/games", params={"date": "2026-03-28", "status": "live"})

    assert response.status_code == 200
    assert [game["gameId"] for game in response.json()["games"]] == [promoted_game_id]


def test_game_detail_returns_latest_snapshot_timestamp_correctly(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)
    game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        official_provider_game_id="20260328LGDOO1",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="live",
        home_score=3,
        away_score=5,
        inning_state="7회초",
    )
    _insert_snapshot(
        db_session,
        game_id=game_id,
        snapshot_at=datetime(2026, 3, 28, 15, 10, 0, tzinfo=KST),
        status="live",
        home_score=0,
        away_score=1,
        inning_state="2회초",
    )
    _insert_snapshot(
        db_session,
        game_id=game_id,
        snapshot_at=datetime(2026, 3, 28, 16, 11, 20, tzinfo=KST),
        status="live",
        home_score=3,
        away_score=5,
        inning_state="7회초",
    )

    response = db_client.get(f"/v1/games/{game_id}")

    assert response.status_code == 200
    assert response.json()["latestSnapshotAt"] == "2026-03-28T16:11:20+09:00"


def test_game_weather_returns_latest_weather_row_correctly(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)
    game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
    )
    _insert_weather(
        db_session,
        game_id=game_id,
        stadium_code="JS",
        observed_at=datetime(2026, 3, 28, 15, 0, tzinfo=KST),
        current_icon_name="맑음",
        current_temp_c=14.1,
        current_rain_mm=0.0,
    )
    _insert_weather(
        db_session,
        game_id=game_id,
        stadium_code="JS",
        observed_at=datetime(2026, 3, 28, 16, 0, tzinfo=KST),
        current_icon_name="흐림",
        current_temp_c=12.4,
        current_rain_mm=0.2,
    )

    response = db_client.get(f"/v1/games/{game_id}/weather")

    assert response.status_code == 200
    assert response.json() == {
        "gameId": game_id,
        "stadiumId": "JS",
        "current": {
            "temperatureC": 12.4,
            "condition": "흐림",
            "precipitationMm": 0.2,
            "observedAt": "2026-03-28T16:00:00+09:00",
        },
    }


def test_game_snapshots_returns_rows_in_desc_order(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)
    game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="live",
    )
    _insert_snapshot(
        db_session,
        game_id=game_id,
        snapshot_at=datetime(2026, 3, 28, 15, 10, 0, tzinfo=KST),
        status="live",
        home_score=0,
        away_score=1,
        inning_state="2회초",
    )
    _insert_snapshot(
        db_session,
        game_id=game_id,
        snapshot_at=datetime(2026, 3, 28, 16, 11, 20, tzinfo=KST),
        status="finished",
        home_score=3,
        away_score=7,
        inning_state="9회말",
    )

    response = db_client.get(f"/v1/games/{game_id}/snapshots", params={"limit": 2})

    assert response.status_code == 200
    snapshots = response.json()["snapshots"]
    assert [snapshot["snapshotAt"] for snapshot in snapshots] == [
        "2026-03-28T16:11:20+09:00",
        "2026-03-28T15:10:00+09:00",
    ]


def test_missing_game_returns_agreed_404_payload_for_all_game_specific_routes(db_client):
    expected = {
        "error": {
            "code": "GAME_NOT_FOUND",
            "message": "Game not found",
            "details": None,
        }
    }

    detail_response = db_client.get("/v1/games/missing")
    weather_response = db_client.get("/v1/games/missing/weather")
    snapshots_response = db_client.get("/v1/games/missing/snapshots")

    assert detail_response.status_code == 404
    assert weather_response.status_code == 404
    assert snapshots_response.status_code == 404
    assert detail_response.json() == expected
    assert weather_response.json() == expected
    assert snapshots_response.json() == expected


def test_pregame_rows_are_null_safe_for_inning_and_weather(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)
    game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="scheduled",
        inning_state=None,
        home_score=0,
        away_score=0,
    )

    detail_response = db_client.get(f"/v1/games/{game_id}")
    weather_response = db_client.get(f"/v1/games/{game_id}/weather")

    assert detail_response.status_code == 200
    assert weather_response.status_code == 200
    assert detail_response.json()["inningState"] is None
    assert detail_response.json()["weather"] is None
    assert detail_response.json()["score"] == {"home": 0, "away": 0}
    assert weather_response.json() == {
        "gameId": game_id,
        "stadiumId": "JS",
        "current": None,
    }


def test_team_games_returns_both_home_and_away_games_for_team(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)
    kt_id = _insert_team(db_session, code="KT", name_ko="KT 위즈", short_name="KT", sort_order=3)

    away_game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="live",
        season_classification="regular_season",
        home_score=3,
        away_score=5,
        inning_state="7회초",
    )
    home_game_id = _insert_game(
        db_session,
        provider_game_id="20260329KTLG0",
        game_date="2026-03-29",
        scheduled_at=datetime(2026, 3, 29, 18, 30, tzinfo=KST),
        stadium="수원",
        stadium_code="SW",
        home_team_id=lg_id,
        away_team_id=kt_id,
        status="scheduled",
    )

    response = db_client.get(
        "/v1/teams/LG/games",
        params={"dateFrom": "2026-03-28", "dateTo": "2026-03-30"},
    )

    assert response.status_code == 200
    games = response.json()["games"]
    assert [game["gameId"] for game in games] == [away_game_id, home_game_id]
    assert games[0]["isHome"] is False
    assert games[0]["seasonClassification"] == "regular_season"
    assert games[1]["isHome"] is True
    assert games[1]["seasonClassification"] == "unknown"


def test_team_games_respects_date_range(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)

    included_game_id = _insert_game(
        db_session,
        provider_game_id="20260329LGDOO0",
        game_date="2026-03-29",
        scheduled_at=datetime(2026, 3, 29, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
    )
    _insert_game(
        db_session,
        provider_game_id="20260331LGDOO0",
        game_date="2026-03-31",
        scheduled_at=datetime(2026, 3, 31, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
    )

    response = db_client.get(
        "/v1/teams/LG/games",
        params={"dateFrom": "2026-03-28", "dateTo": "2026-03-30"},
    )

    assert response.status_code == 200
    assert [game["gameId"] for game in response.json()["games"]] == [included_game_id]


def test_team_games_respects_optional_status_filter(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)

    live_game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="live",
    )
    _insert_game(
        db_session,
        provider_game_id="20260329LGDOO0",
        game_date="2026-03-29",
        scheduled_at=datetime(2026, 3, 29, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="scheduled",
    )

    response = db_client.get(
        "/v1/teams/LG/games",
        params={"dateFrom": "2026-03-28", "dateTo": "2026-03-30", "status": "live"},
    )

    assert response.status_code == 200
    games = response.json()["games"]
    assert [game["gameId"] for game in games] == [live_game_id]
    assert games[0]["status"] == "live"


def test_team_games_score_projection_flips_by_home_away_role(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)
    kt_id = _insert_team(db_session, code="KT", name_ko="KT 위즈", short_name="KT", sort_order=3)

    _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="live",
        home_score=3,
        away_score=5,
    )
    _insert_game(
        db_session,
        provider_game_id="20260329KTLG0",
        game_date="2026-03-29",
        scheduled_at=datetime(2026, 3, 29, 18, 30, tzinfo=KST),
        stadium="수원",
        stadium_code="SW",
        home_team_id=lg_id,
        away_team_id=kt_id,
        status="finished",
        home_score=4,
        away_score=2,
    )

    response = db_client.get(
        "/v1/teams/LG/games",
        params={"dateFrom": "2026-03-28", "dateTo": "2026-03-30"},
    )

    assert response.status_code == 200
    games = response.json()["games"]
    assert games[0]["score"] == {"myTeam": 5, "opponent": 3}
    assert games[1]["score"] == {"myTeam": 4, "opponent": 2}


def test_team_games_returns_team_not_found_when_team_is_missing(db_client):
    response = db_client.get(
        "/v1/teams/MISSING/games",
        params={"dateFrom": "2026-03-28", "dateTo": "2026-03-30"},
    )

    assert response.status_code == 404
    assert response.json() == {
        "error": {
            "code": "TEAM_NOT_FOUND",
            "message": "Team not found",
            "details": None,
        }
    }


def test_team_games_is_null_safe_for_pregame_rows(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)

    _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
        status="scheduled",
        inning_state=None,
        home_score=0,
        away_score=0,
    )

    response = db_client.get(
        "/v1/teams/LG/games",
        params={"dateFrom": "2026-03-28", "dateTo": "2026-03-30"},
    )

    assert response.status_code == 200
    game = response.json()["games"][0]
    assert game["inningState"] is None
    assert game["score"] == {"myTeam": 0, "opponent": 0}


def test_game_events_returns_ordered_event_history_when_data_exists(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)
    game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
    )
    _insert_game_event(
        db_session,
        game_id=game_id,
        event_type="postponed_candidate",
        confirmed=False,
        reason="rain",
        source="weather_watch",
        recorded_at=datetime(2026, 3, 28, 12, 50, tzinfo=KST),
        event_key="candidate-1",
    )
    _insert_game_event(
        db_session,
        game_id=game_id,
        event_type="postponed_confirmed",
        confirmed=True,
        reason="rain",
        source="weather_official_status",
        recorded_at=datetime(2026, 3, 28, 13, 20, tzinfo=KST),
        event_key="confirmed-1",
    )

    response = db_client.get(f"/v1/games/{game_id}/events")

    assert response.status_code == 200
    assert response.json() == {
        "gameId": game_id,
        "events": [
            {
                "eventType": "postponed_confirmed",
                "confirmed": True,
                "reason": "rain",
                "recordedAt": "2026-03-28T13:20:00+09:00",
            },
            {
                "eventType": "postponed_candidate",
                "confirmed": False,
                "reason": "rain",
                "recordedAt": "2026-03-28T12:50:00+09:00",
            },
        ],
    }


def test_game_events_returns_404_when_game_does_not_exist(db_client):
    response = db_client.get("/v1/games/missing/events")

    assert response.status_code == 404
    assert response.json() == {
        "error": {
            "code": "GAME_NOT_FOUND",
            "message": "Game not found",
            "details": None,
        }
    }


def test_events_feed_filters_by_date(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)
    game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
    )
    _insert_game_event(
        db_session,
        game_id=game_id,
        event_type="time_changed",
        confirmed=True,
        reason=None,
        source="schedule_bootstrap",
        recorded_at=datetime(2026, 3, 28, 11, 0, tzinfo=KST),
        event_key="date-filter-hit",
    )
    _insert_game_event(
        db_session,
        game_id=game_id,
        event_type="venue_changed",
        confirmed=True,
        reason=None,
        source="schedule_bootstrap",
        recorded_at=datetime(2026, 3, 29, 11, 0, tzinfo=KST),
        event_key="date-filter-miss",
    )

    response = db_client.get("/v1/events", params={"date": "2026-03-28"})

    assert response.status_code == 200
    assert response.json() == {
        "date": "2026-03-28",
        "events": [
            {
                "gameId": game_id,
                "eventType": "time_changed",
                "confirmed": True,
                "reason": None,
                "recordedAt": "2026-03-28T11:00:00+09:00",
            }
        ],
    }


def test_events_feed_filters_by_team_id_for_home_and_away_games(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)
    kt_id = _insert_team(db_session, code="KT", name_ko="KT 위즈", short_name="KT", sort_order=3)

    away_game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
    )
    home_game_id = _insert_game(
        db_session,
        provider_game_id="20260328KTLG0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 18, 30, tzinfo=KST),
        stadium="수원",
        stadium_code="SW",
        home_team_id=lg_id,
        away_team_id=kt_id,
    )
    other_game_id = _insert_game(
        db_session,
        provider_game_id="20260328KTDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 19, 0, tzinfo=KST),
        stadium="수원",
        stadium_code="SW",
        home_team_id=doo_id,
        away_team_id=kt_id,
    )

    _insert_game_event(
        db_session,
        game_id=away_game_id,
        event_type="time_changed",
        confirmed=True,
        reason=None,
        source="schedule_bootstrap",
        recorded_at=datetime(2026, 3, 28, 10, 0, tzinfo=KST),
        event_key="away-home-hit",
    )
    _insert_game_event(
        db_session,
        game_id=home_game_id,
        event_type="venue_changed",
        confirmed=True,
        reason=None,
        source="schedule_bootstrap",
        recorded_at=datetime(2026, 3, 28, 11, 0, tzinfo=KST),
        event_key="home-home-hit",
    )
    _insert_game_event(
        db_session,
        game_id=other_game_id,
        event_type="status_corrected",
        confirmed=True,
        reason=None,
        source="schedule_bootstrap",
        recorded_at=datetime(2026, 3, 28, 12, 0, tzinfo=KST),
        event_key="team-filter-miss",
    )

    response = db_client.get("/v1/events", params={"date": "2026-03-28", "teamId": "LG"})

    assert response.status_code == 200
    assert {event["gameId"] for event in response.json()["events"]} == {away_game_id, home_game_id}


def test_events_feed_filters_by_event_type(db_client, db_session: Session):
    lg_id = _insert_team(db_session, code="LG", name_ko="LG 트윈스", short_name="LG", sort_order=1)
    doo_id = _insert_team(db_session, code="DOO", name_ko="두산 베어스", short_name="두산", sort_order=2)
    game_id = _insert_game(
        db_session,
        provider_game_id="20260328LGDOO0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=doo_id,
        away_team_id=lg_id,
    )
    _insert_game_event(
        db_session,
        game_id=game_id,
        event_type="time_changed",
        confirmed=True,
        reason=None,
        source="schedule_bootstrap",
        recorded_at=datetime(2026, 3, 28, 10, 0, tzinfo=KST),
        event_key="event-type-hit",
    )
    _insert_game_event(
        db_session,
        game_id=game_id,
        event_type="venue_changed",
        confirmed=True,
        reason=None,
        source="schedule_bootstrap",
        recorded_at=datetime(2026, 3, 28, 11, 0, tzinfo=KST),
        event_key="event-type-miss",
    )

    response = db_client.get("/v1/events", params={"date": "2026-03-28", "eventType": "time_changed"})

    assert response.status_code == 200
    assert response.json() == {
        "date": "2026-03-28",
        "events": [
            {
                "gameId": game_id,
                "eventType": "time_changed",
                "confirmed": True,
                "reason": None,
                "recordedAt": "2026-03-28T10:00:00+09:00",
            }
        ],
    }


def test_schedule_month_endpoint_returns_month_games_for_backend_runtime(db_client, db_session: Session):
    lg_id = _insert_team(
        db_session,
        code="LG",
        name_ko="LG 트윈스",
        short_name="LG",
        sort_order=1,
        previous_regular_season_rank=1,
    )
    kt_id = _insert_team(
        db_session,
        code="KT",
        name_ko="KT 위즈",
        short_name="KT",
        sort_order=2,
        previous_regular_season_rank=6,
    )
    _insert_game(
        db_session,
        provider_game_id="20260328KTLG0",
        game_date="2026-03-28",
        scheduled_at=datetime(2026, 3, 28, 14, 0, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=lg_id,
        away_team_id=kt_id,
        season_classification="regular_season",
    )
    _insert_game(
        db_session,
        provider_game_id="20260401KTLG0",
        game_date="2026-04-01",
        scheduled_at=datetime(2026, 4, 1, 18, 30, tzinfo=KST),
        stadium="잠실",
        stadium_code="JS",
        home_team_id=lg_id,
        away_team_id=kt_id,
        season_classification="regular_season",
    )

    response = db_client.get("/v1/schedule/month", params={"year": 2026, "month": 3})

    assert response.status_code == 200
    payload = response.json()
    assert payload["year"] == 2026
    assert payload["month"] == 3
    assert payload["totalCount"] == 1
    assert payload["games"][0]["seasonClassification"] == "regular_season"
    assert payload["games"][0]["homeTeam"]["teamId"] == "LG"


def test_standings_endpoint_uses_kbo_tiebreak_resolution_metadata(db_client, db_session: Session):
    lg_id = _insert_team(
        db_session,
        code="LG",
        name_ko="LG 트윈스",
        short_name="LG",
        sort_order=1,
        previous_regular_season_rank=1,
    )
    hanwha_id = _insert_team(
        db_session,
        code="HANWHA",
        name_ko="한화 이글스",
        short_name="한화",
        sort_order=2,
        previous_regular_season_rank=2,
    )
    ssg_id = _insert_team(
        db_session,
        code="SSG",
        name_ko="SSG 랜더스",
        short_name="SSG",
        sort_order=3,
        previous_regular_season_rank=3,
    )
    samsung_id = _insert_team(
        db_session,
        code="SAMSUNG",
        name_ko="삼성 라이온즈",
        short_name="삼성",
        sort_order=4,
        previous_regular_season_rank=4,
    )
    nc_id = _insert_team(
        db_session,
        code="NC",
        name_ko="NC 다이노스",
        short_name="NC",
        sort_order=5,
        previous_regular_season_rank=5,
    )
    kt_id = _insert_team(
        db_session,
        code="KT",
        name_ko="KT 위즈",
        short_name="KT",
        sort_order=6,
        previous_regular_season_rank=6,
    )

    seed_games = [
        ("20260328HHLG0", lg_id, hanwha_id, 5, 3),
        ("20260328SSGLG0", lg_id, ssg_id, 4, 2),
        ("20260328NCLG0", lg_id, nc_id, 6, 1),
        ("20260328KTLG0", lg_id, kt_id, 2, 7),
        ("20260329SSLG0", samsung_id, lg_id, 4, 3),
        ("20260329HHSSG0", hanwha_id, ssg_id, 5, 2),
        ("20260329HHSS0", hanwha_id, samsung_id, 4, 1),
        ("20260329HHNC0", hanwha_id, nc_id, 6, 2),
        ("20260329HHKT0", hanwha_id, kt_id, 5, 1),
        ("20260330SSGSS0", ssg_id, samsung_id, 5, 4),
        ("20260330SSGNC0", ssg_id, nc_id, 3, 1),
        ("20260330SSGKT0", ssg_id, kt_id, 4, 2),
        ("20260331SSNC0", samsung_id, nc_id, 5, 2),
        ("20260331SSKT0", samsung_id, kt_id, 7, 4),
        ("20260331NCKT0", nc_id, kt_id, 3, 1),
    ]
    for provider_game_id, home_team_id, away_team_id, home_score, away_score in seed_games:
        _insert_game(
            db_session,
            provider_game_id=provider_game_id,
            game_date=provider_game_id[0:4] + "-" + provider_game_id[4:6] + "-" + provider_game_id[6:8],
            scheduled_at=datetime(
                int(provider_game_id[0:4]),
                int(provider_game_id[4:6]),
                int(provider_game_id[6:8]),
                18,
                30,
                tzinfo=KST,
            ),
            stadium="잠실",
            stadium_code="JS",
            home_team_id=home_team_id,
            away_team_id=away_team_id,
            status="finished",
            home_score=home_score,
            away_score=away_score,
            season_classification="regular_season",
        )

    response = db_client.get("/v1/standings", params={"seasonId": 2026})

    assert response.status_code == 200
    payload = response.json()
    assert payload["seasonId"] == 2026
    assert payload["standings"][4]["rankingResolution"] == "tiebreak_game_required"
    assert payload["standings"][4]["rankingResolutionPosition"] == 5
    assert payload["standings"][4]["team"]["teamId"] == "NC"
    assert payload["standings"][5]["team"]["teamId"] == "KT"
    assert payload["standings"][0]["postseasonQualificationProbability"] is None
    assert payload["standings"][0]["postseasonProbabilityUnavailableReason"] == "incomplete_regular_season_schedule"
