from __future__ import annotations

from datetime import date, datetime

from collector.services.game_event_service import GameEventService
from collector.services.game_upsert_service import GameUpsertService
from collector.utils.time import KST
from tests.helpers.db_seed import insert_game, seed_default_teams


def test_game_schedule_events_table_exists(db_connection_factory):
    with db_connection_factory() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT to_regclass('public.game_schedule_events') AS table_name")
            row = cur.fetchone()

    assert row is not None
    assert row["table_name"] == "game_schedule_events"


def test_game_event_service_dedupes_identical_effective_event(db_connection_factory):
    observed_at = datetime(2026, 3, 28, 13, 20, tzinfo=KST)

    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        game_id = insert_game(
            conn,
            provider_game_id="20260328KTLG0",
            official_provider_game_id="20260328KTLG0",
            provider_game_id_kind="official",
            game_date=date(2026, 3, 28),
            scheduled_at=datetime(2026, 3, 28, 18, 30, tzinfo=KST),
            stadium="잠실",
            stadium_code="JS",
            home_team_id=team_ids["LG"],
            away_team_id=team_ids["KT"],
            status="scheduled",
        )

        service = GameEventService(conn)
        first = service.record_event(
            game_id=game_id,
            event_type="postponed_confirmed",
            confirmed=True,
            reason="rain",
            source="weather_official_status",
            recorded_at=observed_at,
            payload_json={"official_game_sc": "4"},
        )
        second = service.record_event(
            game_id=game_id,
            event_type="postponed_confirmed",
            confirmed=True,
            reason="rain",
            source="weather_official_status",
            recorded_at=observed_at.replace(minute=25),
            payload_json={"official_game_sc": "4"},
        )
        conn.commit()

        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT COUNT(*) AS count
                FROM game_schedule_events
                WHERE game_id = %s::uuid
                """,
                (game_id,),
            )
            row = cur.fetchone()

    assert first.inserted is True
    assert second.inserted is False
    assert row is not None
    assert int(row["count"]) == 1


def test_postponed_candidate_and_confirmed_events_are_distinct(db_connection_factory):
    observed_at = datetime(2026, 3, 28, 12, 50, tzinfo=KST)

    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        game_id = insert_game(
            conn,
            provider_game_id="20260328KTLG0",
            official_provider_game_id="20260328KTLG0",
            provider_game_id_kind="official",
            game_date=date(2026, 3, 28),
            scheduled_at=datetime(2026, 3, 28, 18, 30, tzinfo=KST),
            stadium="잠실",
            stadium_code="JS",
            home_team_id=team_ids["LG"],
            away_team_id=team_ids["KT"],
            status="scheduled",
        )

        service = GameEventService(conn)
        service.record_event(
            game_id=game_id,
            event_type="postponed_candidate",
            confirmed=False,
            reason="rain",
            source="weather_watch",
            recorded_at=observed_at,
            payload_json={"signal": "forecast_rain"},
        )
        service.record_event(
            game_id=game_id,
            event_type="postponed_confirmed",
            confirmed=True,
            reason="rain",
            source="weather_official_status",
            recorded_at=observed_at.replace(hour=13, minute=20),
            payload_json={"official_game_sc": "4"},
        )
        conn.commit()

        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT event_type, confirmed, reason
                FROM game_schedule_events
                WHERE game_id = %s::uuid
                ORDER BY recorded_at ASC, id ASC
                """,
                (game_id,),
            )
            rows = list(cur.fetchall())

    assert rows == [
        {"event_type": "postponed_candidate", "confirmed": False, "reason": "rain"},
        {"event_type": "postponed_confirmed", "confirmed": True, "reason": "rain"},
    ]


def test_mark_game_postponed_records_single_confirmed_event(db_connection_factory):
    observed_at = datetime(2026, 3, 28, 13, 20, tzinfo=KST)

    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        game_id = insert_game(
            conn,
            provider_game_id="20260328KTLG0",
            official_provider_game_id="20260328KTLG0",
            provider_game_id_kind="official",
            game_date=date(2026, 3, 28),
            scheduled_at=datetime(2026, 3, 28, 18, 30, tzinfo=KST),
            stadium="잠실",
            stadium_code="JS",
            home_team_id=team_ids["LG"],
            away_team_id=team_ids["KT"],
            status="scheduled",
        )

        service = GameUpsertService(conn)
        first = service.mark_game_postponed(
            game_id,
            observed_at,
            source="weather_official_status",
            reason="rain",
            payload_json={"official_game_sc": "4"},
        )
        second = service.mark_game_postponed(
            game_id,
            observed_at,
            source="weather_official_status",
            reason="rain",
            payload_json={"official_game_sc": "4"},
        )
        conn.commit()

        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT event_type, confirmed, reason, source
                FROM game_schedule_events
                WHERE game_id = %s::uuid
                ORDER BY recorded_at DESC, id DESC
                """,
                (game_id,),
            )
            rows = list(cur.fetchall())

    assert first is True
    assert second is False
    assert rows == [
        {
            "event_type": "postponed_confirmed",
            "confirmed": True,
            "reason": "rain",
            "source": "weather_official_status",
        }
    ]
