WITH home_team AS (
    SELECT id FROM teams WHERE code = 'LG'
),
away_team AS (
    SELECT id FROM teams WHERE code = 'KT'
),
seed_game AS (
    INSERT INTO games (
        provider,
        provider_game_id,
        game_date,
        scheduled_at,
        stadium,
        stadium_code,
        home_team_id,
        away_team_id,
        status,
        is_postponed,
        is_cancelled,
        source_updated_at,
        official_provider_game_id,
        provider_game_id_kind
    )
    SELECT
        'kbo',
        '20260327KTLG0',
        DATE '2026-03-27',
        TIMESTAMPTZ '2026-03-27 18:30:00+09',
        '잠실',
        'JS',
        home_team.id,
        away_team.id,
        'postponed',
        TRUE,
        FALSE,
        TIMESTAMPTZ '2026-03-27 16:00:00+09',
        '20260327KTLG0',
        'official'
    FROM home_team, away_team
    RETURNING id, home_team_id, away_team_id
)
INSERT INTO device_registrations (device_token, platform, app_version, favorite_team_id, notifications_enabled)
SELECT 'seed-home-token', 'ios', '1.0.0', home_team_id, TRUE FROM seed_game
UNION ALL
SELECT 'seed-away-token', 'ios', '1.0.0', away_team_id, TRUE FROM seed_game;
