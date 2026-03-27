from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

import psycopg

from collector.utils.time import recent_kst_window_start, to_kst


@dataclass(frozen=True, slots=True)
class ConfirmedRainoutNotificationSummary:
    candidate_games: int
    target_devices: int
    inserted_notification_events: int
    skipped_duplicates: int


@dataclass(slots=True)
class NotificationService:
    conn: psycopg.Connection

    def create_confirmed_rainout_notification_events(
        self,
        observed_at: datetime,
        recent_hours: int = 6,
    ) -> ConfirmedRainoutNotificationSummary:
        """
        Insert queued notification_events for canonically confirmed rainout games only.

        The candidate scan is bounded to:
        - today's games in KST, or
        - games source-updated within the recent_hours window
        This keeps the MVP job from rescanning the full season every minute.
        """
        observed_at = to_kst(observed_at)
        game_date = observed_at.date()
        recent_window_start = recent_kst_window_start(observed_at, hours=recent_hours)

        with self.conn.cursor() as cur:
            cur.execute(
                """
                WITH candidate_games AS (
                    SELECT
                        g.id,
                        g.provider_game_id,
                        g.game_date,
                        g.status,
                        g.home_team_id,
                        g.away_team_id,
                        g.stadium,
                        g.scheduled_at,
                        g.source_updated_at,
                        home.short_name AS home_short_name,
                        away.short_name AS away_short_name
                    FROM games g
                    JOIN teams home ON home.id = g.home_team_id
                    JOIN teams away ON away.id = g.away_team_id
                    WHERE g.status = 'postponed'
                      AND g.is_postponed = TRUE
                      AND g.is_cancelled = FALSE
                      AND (
                        g.game_date = %(game_date)s
                        OR g.source_updated_at >= %(recent_window_start)s
                      )
                ),
                target_devices AS (
                    SELECT DISTINCT
                        cg.id AS game_id,
                        cg.provider_game_id,
                        cg.game_date,
                        cg.status,
                        cg.home_team_id,
                        cg.away_team_id,
                        cg.stadium,
                        cg.scheduled_at,
                        cg.source_updated_at,
                        cg.home_short_name,
                        cg.away_short_name,
                        dr.id AS device_registration_id
                    FROM candidate_games cg
                    JOIN device_registrations dr
                      ON dr.favorite_team_id IN (cg.home_team_id, cg.away_team_id)
                    WHERE dr.notifications_enabled = TRUE
                      AND NULLIF(BTRIM(dr.device_token), '') IS NOT NULL
                ),
                inserted_events AS (
                    INSERT INTO notification_events (
                        device_registration_id,
                        game_id,
                        event_type,
                        event_key,
                        title,
                        body,
                        payload_json,
                        delivery_status
                    )
                    SELECT
                        td.device_registration_id,
                        td.game_id,
                        'rainout_confirmed',
                        'kbo:rainout:' || td.game_id::text || ':confirmed:' || td.game_date::text || ':v1',
                        '경기 우천 취소',
                        td.away_short_name || ' vs ' || td.home_short_name || ' 경기가 우천으로 취소되었습니다.',
                        jsonb_build_object(
                            'game_id', td.game_id,
                            'provider_game_id', td.provider_game_id,
                            'game_date', td.game_date,
                            'status', td.status,
                            'home_team_id', td.home_team_id,
                            'away_team_id', td.away_team_id,
                            'stadium', td.stadium,
                            'scheduled_at', td.scheduled_at,
                            'source_updated_at', td.source_updated_at,
                            'notification_type', 'rainout_confirmed'
                        ),
                        'queued'
                    FROM target_devices td
                    ON CONFLICT (event_key, device_registration_id) DO NOTHING
                    RETURNING 1
                )
                SELECT
                    (SELECT COUNT(*)::int FROM candidate_games) AS candidate_games,
                    (SELECT COUNT(*)::int FROM target_devices) AS target_devices,
                    (SELECT COUNT(*)::int FROM inserted_events) AS inserted_notification_events
                """,
                {
                    "game_date": game_date,
                    "recent_window_start": recent_window_start,
                },
            )
            row = cur.fetchone()

        candidate_games = int(row["candidate_games"]) if row is not None else 0
        target_devices = int(row["target_devices"]) if row is not None else 0
        inserted_notification_events = int(row["inserted_notification_events"]) if row is not None else 0

        return ConfirmedRainoutNotificationSummary(
            candidate_games=candidate_games,
            target_devices=target_devices,
            inserted_notification_events=inserted_notification_events,
            skipped_duplicates=max(target_devices - inserted_notification_events, 0),
        )
